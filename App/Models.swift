import Foundation
import CryptoKit
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
    var sourceYear: String? // Original season notation retained for review.
    var confirmed = false
    var title: String { [year, player, set, number].filter { !$0.isEmpty }.joined(separator: " · ") }
    var details: Identity { var result = normalized; result.confirmed = false; result.sourceYear = nil; return result }
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
    var acquisitionDate: Date?
    var acquisitionCost: Decimal?
    var dispositionProceeds: Decimal?
    var manualValue: Decimal?
    var manualValueDate: Date?
    var manualValueSource: String?
    var backCorrected: Data?
    var frontCrop: CropSelection?
    var backCrop: CropSelection?
    var batchState: String? // queued / duplicate; nil means part of the collection
    var scanNote: String?
    var frontOrientationUncertain: Bool?
    var backOrientationUncertain: Bool?
    var collectionValue: Double? { manualValue.map { NSDecimalNumber(decimal: $0).doubleValue } ?? pricing?.usableValue }
    var valueLabel: String { manualValue != nil ? "Your value" : "CardPricer estimate" }
    var front: Data?
    var back: Data?
    var thumbnail: Data?
    var ocr = ""
    var research: Research? // Legacy backup compatibility; no longer used for pricing.
    var pricing: CardPricing?
    var priceCrossCheck: PriceCrossCheck?
    var frontOCR: String?
    var backOCR: String?
    mutating func replaceOCR(_ text: String, front: Bool) {
        if front { frontOCR = text } else { backOCR = text }
        ocr = "Front:\n" + (frontOCR ?? "") + "\nBack:\n" + (backOCR ?? "")
        identity.confirmed = false
        research = nil; pricing = nil; priceCrossCheck = nil
    }
}
struct Archive: Codable {
    var version = 1
    var cards: [Card]
    var photoHashes: [String: [String: String]]?
}
extension Card {
    var photoData: [String: Data] {
        ["front": front, "back": back, "thumbnail": thumbnail, "backCorrected": backCorrected].compactMapValues { $0 }
    }
    mutating func setPhoto(_ data: Data?, role: String) {
        switch role {
        case "front": front = data
        case "back": back = data
        case "thumbnail": thumbnail = data
        case "backCorrected": backCorrected = data
        default: break
        }
    }
}


@MainActor final class CollectionStore: ObservableObject {
    @Published private(set) var cards: [Card] = []
    @Published var error: String?
    private var loaded = false
    private let file: URL
    private var assets: URL { file.deletingLastPathComponent().appending(path: "Photos", directoryHint: .isDirectory) }
    static func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    static func safeHash(_ value: String) -> Bool { value.count == 64 && value.allSatisfy { "0123456789abcdef".contains($0) } }
    var storageBytes: Int { cards.reduce(0) { total, card in total + card.photoData.values.reduce(0) { $0 + $1.count } } }
    init(file: URL? = nil) {
        self.file = file ?? URL.applicationSupportDirectory.appending(path: "CardLedger/collection.json")
        var needsNormalization = false
        do {
            if FileManager.default.fileExists(atPath: self.file.path) {
                var archive = try JSONDecoder().decode(Archive.self, from: Data(contentsOf: self.file))
                if let hashes = archive.photoHashes {
                    for index in archive.cards.indices {
                        for (role, hash) in hashes[archive.cards[index].id.uuidString] ?? [:] {
                            guard Self.safeHash(hash) else { throw CocoaError(.fileReadCorruptFile) }
                            let bytes = try Data(contentsOf: assets.appending(path: hash))
                            archive.cards[index].setPhoto(bytes, role: role)
                        }
                    }
                }
                try Self.validate(archive)
                cards = archive.cards.map(\.normalizedMetadata)
                needsNormalization = zip(cards,archive.cards).contains { $0.identity != $1.identity || $0.priceCrossCheck != $1.priceCrossCheck }
            }
            loaded = true
            if needsNormalization {
                do { try commit(cards) }
                catch { self.error = "Metadata cleanup could not be saved. Your original collection is preserved. " + error.localizedDescription }
            }
        } catch { self.error = "Collection could not be opened. Existing data has been preserved. \(error.localizedDescription)" }
    }
    static func validate(_ archive: Archive) throws {
        guard [1, 2].contains(archive.version), archive.cards.count <= 10000, Set(archive.cards.map(\.id)).count == archive.cards.count else {
            throw CocoaError(.fileReadCorruptFile)
        }
        if archive.version == 2 && archive.photoHashes == nil { throw CocoaError(.fileReadCorruptFile) }
        let ids = Set(archive.cards.map { $0.id.uuidString })
        if let hashes = archive.photoHashes, !Set(hashes.keys).isSubset(of: ids) { throw CocoaError(.fileReadCorruptFile) }
        for card in archive.cards {
            guard ["Owned", "Sold", "Gifted"].contains(card.status),
                  [card.manualValue, card.acquisitionCost, card.dispositionProceeds].allSatisfy({ $0 == nil || ($0! >= 0 && !$0!.isNaN) }),
                  (card.priceCrossCheck.map { !$0.value.isNaN && $0.value > 0 } ?? true),
                  card.frontCrop?.valid != false, card.backCrop?.valid != false else { throw CocoaError(.fileReadCorruptFile) }
            let photos = card.photoData
            guard photos.values.allSatisfy({ $0.count <= 50 * 1024 * 1024 }) else { throw CocoaError(.fileReadTooLarge) }
            if let hashes = archive.photoHashes {
                let expected = hashes[card.id.uuidString] ?? [:]
                guard Set(expected.keys) == Set(photos.keys) else { throw CocoaError(.fileReadCorruptFile) }
                for (role, bytes) in photos {
                    guard let hash = expected[role], safeHash(hash), hash == digest(bytes) else { throw CocoaError(.fileReadCorruptFile) }
                }
            }
        }
    }
    private func archive(_ cards: [Card]) -> Archive {
        let hashes = Dictionary(uniqueKeysWithValues: cards.map { card in
            (card.id.uuidString, card.photoData.mapValues(Self.digest))
        })
        return Archive(version: 2, cards: cards, photoHashes: hashes)
    }
    private func commit(_ next: [Card]) throws {
        guard loaded else { throw CocoaError(.fileReadCorruptFile) }
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let next = next.map(\.normalizedMetadata)
        var index = archive(next)
        try Self.validate(index)
        try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
        for position in index.cards.indices {
            for (role, data) in index.cards[position].photoData {
                let hash = index.photoHashes![index.cards[position].id.uuidString]![role]!
                let target = assets.appending(path: hash)
                if !FileManager.default.fileExists(atPath: target.path) { try data.write(to: target, options: [.atomic, .completeFileProtection]) }
                index.cards[position].setPhoto(nil, role: role)
            }
        }
        // Photos are committed first. An interrupted index write leaves the previous index and its photos intact.
        let bytes = try JSONEncoder().encode(index)
        try bytes.write(to: file, options: [.atomic, .completeFileProtection])
        cards = next
        let referenced = Set(index.photoHashes!.values.flatMap { $0.values })
        if let files = try? FileManager.default.contentsOfDirectory(at: assets, includingPropertiesForKeys: nil) {
            for url in files where Self.safeHash(url.lastPathComponent) && !referenced.contains(url.lastPathComponent) { try? FileManager.default.removeItem(at: url) }
        }
    }
    func save(_ card: Card) throws {
        var next = cards
        if let index = next.firstIndex(where: { $0.id == card.id }) { next[index] = card }
        else { next.insert(card, at: 0) }
        try commit(next)
    }
    func resolveBatch(_ scanned: Card, replacing id: UUID? = nil) throws {
        var next = cards.filter { $0.id != scanned.id }
        var result = scanned; result.batchState = nil
        if let id {
            guard let existing = next.first(where: { $0.id == id }), CardDuplicates.needsReview(scanned, existing) else { throw ScanSaveError.matchChanged }
            result = CardDuplicates.replacing(existing, with: result)
            next.removeAll { $0.id == id }
        }
        next.insert(result, at: 0)
        try commit(next)
    }
    func delete(_ id: UUID) throws { try commit(cards.filter { $0.id != id }) }
    func export() throws -> URL {
        let url = URL.temporaryDirectory.appending(path: "CardLedger-backup.json")
        try JSONEncoder().encode(archive(cards)).write(to: url, options: [.atomic, .completeFileProtection])
        return url
    }
    func restore(_ data: Data) throws {
        guard data.count <= 512 * 1024 * 1024 else { throw CocoaError(.fileReadTooLarge) }
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
        let rows = [["Player", "Team", "Card type", "Year", "Set", "Number", "Variant", "Grade", "Status", "Tags", "Location", "Notes", "Manual value USD", "Value source", "Acquisition cost USD", "Disposition proceeds USD"]] + cards.filter { $0.batchState == nil }.map {
            [$0.identity.player, $0.identity.team, $0.identity.sport, $0.identity.year, $0.identity.set, $0.identity.number, $0.identity.variant, $0.identity.grade, $0.status, $0.tags, $0.location, $0.notes, $0.manualValue.map { NSDecimalNumber(decimal: $0).stringValue } ?? "", $0.manualValueSource ?? "", $0.acquisitionCost.map { NSDecimalNumber(decimal: $0).stringValue } ?? "", $0.dispositionProceeds.map { NSDecimalNumber(decimal: $0).stringValue } ?? ""]
        }
        let url = URL.temporaryDirectory.appending(path: "CardLedger.csv")
        try rows.map { $0.map(cell).joined(separator: ",") }.joined(separator: "\r\n").write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}

