import Foundation

struct PricerCard: Codable, Identifiable, Equatable {
    var id: String
    var player: String?
    var year: Int?
    var set: String?
    var cardNumber: String?
    var sport: String?
    var manufacturer: String?
    var grade: String?
    var price: Double?
    var updatedAt: String?
    var variant: String?
    var title: String { [year.map(String.init),player,set,cardNumber,grade].compactMap { $0 }.joined(separator:" · ") }
}
struct CardPricing: Codable, Equatable {
    enum Status: String, Codable { case priced, noMatch, review, noPrice }
    var status: Status
    var checkedAt: Date = Date()
    var cardID: String?
    var value: Double?
    var updatedAt: String?
    var confidence: String?
    var compCount: Int?
    var warnings: [String] = []
    var candidates: [PricerCard] = []
    var userConfirmedMatch = false
    var summary: String {
        switch status {
        case .priced: return "CardPricer estimate"
        case .noMatch: return "No matching card on CardPricer"
        case .review: return "Review the CardPricer match"
        case .noPrice: return "No CardPricer price available"
        }
    }
    var usableValue: Double? { guard status == .priced, let value, value.isFinite, value > 0 else { return nil }; return value }
}

/// Direct anonymous read-only API. No account, API key, photo upload or private worker.
actor CardPricerClient {
    static let shared = CardPricerClient()
    static let website = URL(string:"https://cardpricer.co")!
    typealias Transport = (URLRequest) async throws -> (Data, HTTPURLResponse)
    private let transport: Transport
    private var nextRequest = Date.distantPast
    private var blockedUntil = Date.distantPast
    private let spacing: TimeInterval
    init(spacing: TimeInterval = 1.05, transport: Transport? = nil) {
        self.spacing = spacing
        self.transport = transport ?? { request in
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 15
            configuration.timeoutIntervalForResource = 20
            let session = URLSession(configuration:configuration)
            defer { session.finishTasksAndInvalidate() }
            let (data,response) = try await session.data(for:request)
            guard let http = response as? HTTPURLResponse else { throw PricingError.invalidResponse }
            return (data,http)
        }
    }
    struct Envelope<T: Decodable>: Decodable {
        var ok: Bool
        var apiVersion: String
        var data: T
        var meta: Meta?
        struct Meta: Decodable { var pagination: Pagination? }
        struct Pagination: Decodable { var nextOffset: Int? }
    }
    struct Detail: Decodable {
        var id: String; var player: String?; var year: Int?; var set: String?; var cardNumber: String?
        var sport: String?; var manufacturer: String?; var grade: String?; var price: Double?
        var updatedAt: String?; var variant: String?
        var record: PricerCard { PricerCard(id:id,player:player,year:year,set:set,cardNumber:cardNumber,sport:sport,manufacturer:manufacturer,grade:grade,price:price,updatedAt:updatedAt,variant:variant) }
    }
    struct Provenance: Decodable {
        struct CardRef: Decodable { var id: String }
        struct Comp: Decodable { var title: String?; var grade: String? }
        struct Comps: Decodable { var total: Int?; var recent: [Comp]? }
        struct Confidence: Decodable { var label: String?; var warnings: [String]? }
        var card: CardRef
        var comps: Comps?
        var confidence: Confidence?
    }
    private func get<T: Decodable>(_ path: String, query: [URLQueryItem] = []) async throws -> Envelope<T> {
        try Task.checkCancellation()
        guard Date() >= blockedUntil else { throw PricingError.rateLimited }
        let slot = max(Date(),nextRequest); nextRequest = slot.addingTimeInterval(spacing)
        let delay = slot.timeIntervalSinceNow
        if delay > 0 { try await Task.sleep(for:.seconds(delay)) }
        try Task.checkCancellation()
        guard Date() >= blockedUntil else { throw PricingError.rateLimited }
        var components = URLComponents(string:"https://cardpricer.co/api/v1/" + path)!
        if !query.isEmpty { components.queryItems = query }
        var request = URLRequest(url:components.url!); request.timeoutInterval = 15
        request.setValue("application/json",forHTTPHeaderField:"Accept")
        request.setValue("CardLedger/0.1",forHTTPHeaderField:"User-Agent")
        let (data,response) = try await transport(request)
        try Task.checkCancellation()
        if response.statusCode == 429 {
            let seconds = Double(response.value(forHTTPHeaderField:"Retry-After") ?? "") ?? 60
            blockedUntil = Date().addingTimeInterval(min(max(seconds,1),3600))
            throw PricingError.rateLimited
        }
        guard response.statusCode == 200 else { throw PricingError.unavailable }
        guard data.count <= 2_000_000 else { throw PricingError.invalidResponse }
        do {
            let result = try JSONDecoder().decode(Envelope<T>.self,from:data)
            guard result.ok, result.apiVersion.hasPrefix("1.") else { throw PricingError.invalidResponse }
            return result
        } catch { throw PricingError.invalidResponse }
    }
    func checkConnection() async throws {
        struct Status: Decodable { var now: String }
        let _: Envelope<Status> = try await get("status")
    }
    func lookup(_ identity: Identity) async throws -> CardPricing {
        guard Self.complete(identity) else { return CardPricing(status:.review,warnings:["Complete the player, year, set, card number and grade in Edit to look up a price."]) }
        var candidates: [PricerCard] = []; var offset = 0; var truncated = false
        // Search player/year rather than concatenating all fields into an undocumented search grammar.
        for page in 0..<3 {
            let response: Envelope<[PricerCard]> = try await get("cards",query:[
                URLQueryItem(name:"player",value:identity.player.trimmingCharacters(in:.whitespacesAndNewlines)),
                URLQueryItem(name:"year",value:identity.year.trimmingCharacters(in:.whitespacesAndNewlines)),
                URLQueryItem(name:"sport",value:Self.normalized(identity.sport)),
                URLQueryItem(name:"limit",value:"100"),URLQueryItem(name:"offset",value:String(offset))])
            candidates += response.data.filter { Self.possibleMatch($0,identity) }
            guard let next = response.meta?.pagination?.nextOffset else { break }
            guard next > offset else { throw PricingError.invalidResponse }
            if page == 2 { truncated = true }; offset = next
        }
        var seen = Set<String>(); candidates = candidates.filter { seen.insert($0.id).inserted }
        guard !candidates.isEmpty else { return CardPricing(status:.noMatch,warnings:truncated ? ["Search limit reached. Try a more specific player name in Edit."] : []) }
        if candidates.count == 1 && !truncated {
            return try await price(identity, candidate:candidates[0],confirmed:false)
        }
        return CardPricing(status:.review,warnings:[truncated ? "Search limit reached; review the candidate before using a value." : "Several catalog records match. Choose and verify the exact card."],candidates:candidates)
    }
    func price(_ identity: Identity, candidate: PricerCard, confirmed: Bool) async throws -> CardPricing {
        guard UUID(uuidString:candidate.id) != nil, Self.possibleMatch(candidate,identity) else { throw PricingError.changedMatch }
        let detail: Envelope<Detail> = try await get("cards/" + candidate.id)
        let record = detail.data.record
        guard record.id == candidate.id, Self.possibleMatch(record,identity) else { throw PricingError.changedMatch }
        let evidence: Envelope<Provenance> = try await get("cards/" + candidate.id + "/provenance")
        guard evidence.data.card.id == record.id else { throw PricingError.invalidResponse }
        let comps = evidence.data.comps?.recent ?? []
        let variantConfirmed = Self.variantConfirmed(record,identity,comps:comps)
        if !confirmed && !variantConfirmed {
            return CardPricing(status:.review,warnings:["CardPricer does not fully identify this variation. Verify the set, parallel, autograph and grade before using its price."],candidates:[record])
        }
        var warnings = evidence.data.confidence?.warnings ?? []
        if confirmed && !variantConfirmed { warnings.insert("Card match confirmed by you; CardPricer’s variation information is incomplete.",at:0) }
        let count = max(0,evidence.data.comps?.total ?? 0)
        if count == 0 { warnings.append("No recent comparable sales supplied. This is a provider estimate, not a verified sale price.") }
        if let updated = record.updatedAt, let date = Self.date(updated), Date().timeIntervalSince(date) > 30*86400 {
            warnings.append("CardPricer last updated this value more than 30 days ago.")
        }
        let value = record.price.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
        return CardPricing(status:value == nil ? .noPrice:.priced,cardID:record.id,value:value,updatedAt:record.updatedAt,
                           confidence:evidence.data.confidence?.label,compCount:count,warnings:warnings,userConfirmedMatch:confirmed)
    }
    static func normalized(_ text: String) -> String {
        text.folding(options:[.caseInsensitive,.diacriticInsensitive],locale:Locale(identifier:"en_US_POSIX"))
            .components(separatedBy:CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator:" ")
    }
    static func grade(_ text: String?) -> String {
        let value = normalized(text ?? "")
        return ["raw","ungraded"].contains(value) ? "raw" : value
    }
    static func complete(_ i: Identity) -> Bool {
        [i.player,i.year,i.set,i.number,i.grade,i.sport].allSatisfy { !normalized($0).isEmpty } && Int(i.year.trimmingCharacters(in:.whitespacesAndNewlines)) != nil
    }
    static func possibleMatch(_ card: PricerCard,_ i: Identity) -> Bool {
        guard complete(i),UUID(uuidString:card.id) != nil,
              normalized(card.player ?? "") == normalized(i.player),card.year == Int(i.year.trimmingCharacters(in:.whitespacesAndNewlines)),
              normalized(card.sport ?? "") == normalized(i.sport),grade(card.grade) == grade(i.grade),
              normalized(card.cardNumber ?? "") == normalized(i.number) else { return false }
        let brand = normalized(i.manufacturer), sourceBrand = normalized(card.manufacturer ?? "")
        if !brand.isEmpty && !sourceBrand.isEmpty && brand != sourceBrand { return false }
        let set = normalized(i.set), variant = normalized(i.variant), sourceSet = normalized(card.set ?? "")
        let sets = Set([set,normalized(i.manufacturer+" "+i.set)])
        if sets.contains(sourceSet) { return true }
        return !variant.isEmpty && variant != "base" && sets.contains(where:{ $0+" "+variant == sourceSet })
    }
    static func variantConfirmed(_ card: PricerCard,_ i: Identity,comps:[Provenance.Comp]) -> Bool {
        let variant = normalized(i.variant)
        guard !["","unknown","unspecified","na","n a"].contains(variant) else { return false }
        if let explicit = card.variant, normalized(explicit) != variant { return false }
        // A catalog row may silently merge a base card with a parallel. Require every
        // returned comp title to resolve to this identity, not just the catalog fields.
        guard !comps.isEmpty else { return card.variant.map { normalized($0) == variant } ?? false }
        return comps.allSatisfy { comp in
            guard grade(comp.grade) == grade(i.grade), let title = comp.title else { return false }
            var remaining = " " + normalized(title) + " "
            for part in [i.player,i.year,card.set ?? i.set,i.number,i.grade] {
                let needle = " " + normalized(part) + " "
                guard remaining.contains(needle) else { return false }
                remaining = remaining.replacingOccurrences(of:needle,with:" ")
            }
            if variant != "base" {
                let needle = " " + variant + " "
                if remaining.contains(needle) { remaining = remaining.replacingOccurrences(of:needle,with:" ") }
                else if !normalized(card.set ?? "").hasSuffix(" " + variant) { return false }
            }
            let allowed: Set<String> = ["rc","rookie","card","base","mint","gem","mt","nm"]
            return remaining.split(separator:" ").allSatisfy { allowed.contains(String($0)) }
        }
    }
    static func date(_ text: String) -> Date? {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime,.withFractionalSeconds]
        if let date = f.date(from:text) { return date }; f.formatOptions = [.withInternetDateTime]; return f.date(from:text)
    }
}
enum PricingError: LocalizedError {
    case rateLimited, unavailable, invalidResponse, changedMatch
    var errorDescription: String? {
        switch self {
        case .rateLimited: return "CardPricer’s free request limit was reached. Try again later; your saved value is unchanged."
        case .unavailable: return "CardPricer is unavailable. Try again later; your saved value is unchanged."
        case .invalidResponse: return "CardPricer returned an unreadable response. Your saved value is unchanged."
        case .changedMatch: return "This CardPricer record no longer matches. Refresh the search before choosing a price."
        }
    }
}
