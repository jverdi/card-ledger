import Foundation
import SwiftUI

struct Identity: Codable, Equatable {
    var player = ""
    var team = ""
    var sport = "Baseball"
    var year = ""
    var manufacturer = ""
    var set = ""
    var number = ""
    var variant = ""
    var grade = "Raw"
    var certificate = ""
    var confirmed = false
    var title: String { [year, player, set, number].filter { !$0.isEmpty }.joined(separator: " · ") }
}
struct Observation: Codable, Identifiable {
    var id: String { source_url + (sale_date ?? "") + String(amount ?? 0) }
    var source_name: String
    var source_url: String
    var source_record_id: String?
    var evidence_type: String
    var page_opened: Bool
    var exact_match: Bool
    var observed_card_description: String
    var sale_date: String?
    var source_as_of_date: String?
    var amount: Double?
    var currency: String?
    var shipping_amount: Double?
    var buyer_premium_amount: Double?
    var price_basis: String
    var included: Bool
    var exclusion_reason: String?
}
struct Research: Codable {
    var searched_at: String
    var identity_status: String
    var unresolved_fields: [String]
    var queries_used: [String]
    var observations: [Observation]
    var valuation_basis: String
    var limitations: [String]
    var estimate: Double?
    var low: Double?
    var high: Double?
    var sample_count: Int
}
struct Card: Codable, Identifiable {
    var id = UUID()
    var identity = Identity()
    var notes = ""
    var tags = ""
    var location = ""
    var status = "Owned"
    var added = Date()
    var dispositionDate: Date?
    var front: Data?
    var back: Data?
    var thumbnail: Data?
    var ocr = ""
    var research: Research?
}
struct Archive: Codable { var version = 1; var cards: [Card] }

@MainActor final class CollectionStore: ObservableObject {
    @Published private(set) var cards: [Card] = []
    @Published var error: String?
    private var loaded = false
    private let file: URL
    init(file: URL? = nil) {
        self.file = file ?? URL.applicationSupportDirectory.appending(path: "CardLedger/collection.json")
        do {
            if FileManager.default.fileExists(atPath: self.file.path) {
                let archive = try JSONDecoder().decode(Archive.self, from: Data(contentsOf: self.file))
                try Self.validate(archive)
                cards = archive.cards
            }
            loaded = true
        } catch { self.error = "Collection could not be opened. Existing data has been preserved. \(error.localizedDescription)" }
    }
    static func validate(_ archive: Archive) throws {
        guard archive.version == 1, Set(archive.cards.map(\.id)).count == archive.cards.count else {
            throw CocoaError(.fileReadCorruptFile)
        }
    }
    private func commit(_ next: [Card]) throws {
        guard loaded else { throw CocoaError(.fileReadCorruptFile) }
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let bytes = try JSONEncoder().encode(Archive(cards: next))
        try bytes.write(to: file, options: [.atomic, .completeFileProtection])
        cards = next
    }
    func save(_ card: Card) throws {
        var next = cards
        if let index = next.firstIndex(where: { $0.id == card.id }) { next[index] = card }
        else { next.insert(card, at: 0) }
        try commit(next)
    }
    func delete(_ id: UUID) throws { try commit(cards.filter { $0.id != id }) }
    func export() throws -> URL {
        let url = URL.temporaryDirectory.appending(path: "CardLedger-backup.json")
        try JSONEncoder().encode(Archive(cards: cards)).write(to: url, options: .atomic)
        return url
    }
    func restore(_ data: Data) throws {
        let archive = try JSONDecoder().decode(Archive.self, from: data)
        try Self.validate(archive)
        // Merge only new UUIDs. An imported backup cannot overwrite newer local edits.
        let ids = Set(cards.map(\.id))
        try commit(cards + archive.cards.filter { !ids.contains($0.id) })
    }
    func csv() throws -> URL {
        func cell(_ value: String) -> String {
            let safe = ["=", "+", "-", "@"].contains(String(value.prefix(1))) ? "'" + value : value
            return "\"" + safe.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        let rows = [["Player", "Team", "Sport", "Year", "Set", "Number", "Variant", "Grade", "Status", "Tags", "Location", "Notes"]] + cards.map {
            [$0.identity.player, $0.identity.team, $0.identity.sport, $0.identity.year, $0.identity.set, $0.identity.number, $0.identity.variant, $0.identity.grade, $0.status, $0.tags, $0.location, $0.notes]
        }
        let url = URL.temporaryDirectory.appending(path: "CardLedger.csv")
        try rows.map { $0.map(cell).joined(separator: ",") }.joined(separator: "\r\n").write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}
