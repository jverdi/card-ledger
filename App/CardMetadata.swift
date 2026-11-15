import Foundation

/// One representation for recognition, saved cards, filters and catalog matching.
enum CardMetadata {
    static func clean(_ raw: String) -> String { raw.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ") }
    static func title(_ raw: String) -> String {
        let acronyms: Set<String> = ["UI", "TCG", "DJ", "AJ", "CJ", "TJ", "JD", "JP", "II", "III", "IV", "VI", "VII", "LA", "NY", "USA", "MLB", "NBA", "NFL", "NHL", "WNBA", "MLS", "UFC", "WWE", "NCAA", "RC", "RPA", "SP", "SSP", "MVP", "PSA", "BGS", "SGC", "CGC", "DNA"]
        let particles: Set<String> = ["de", "del", "da", "dos", "di", "du", "la", "van", "von", "der", "den"]
        let spellings = ["degrom":"deGrom", "lemahieu":"LeMahieu", "d'arnaud":"d’Arnaud", "d’arnaud":"d’Arnaud", "pokemon":"Pokémon", "pokémon":"Pokémon", "jr":"Jr.", "jr.":"Jr.", "sr":"Sr.", "sr.":"Sr."]
        return clean(raw).split(separator: " ").enumerated().map { index, word in
            let token = String(word), lower = token.lowercased()
            if let spelling = spellings[lower] { return spelling }
            if index > 1, lower == "la", particles.contains(String(clean(raw).split(separator:" ")[index - 1]).lowercased()) { return "la" }
            if acronyms.contains(token.uppercased()) { return token.uppercased() }
            if token.contains("."), token.filter({ $0.isLetter }).count <= 3 { return token.uppercased() }
            if index > 0, particles.contains(lower) { return lower }
            var result = lower.capitalized
            if lower.hasPrefix("mc"), lower.count > 2 {
                result = "Mc" + String(lower.dropFirst(2)).capitalized
            }
            return result
        }.joined(separator: " ")
    }
    static func manufacturer(_ raw: String) -> String {
        switch raw.lowercased().filter({ $0.isLetter || $0.isNumber }) {
        case "topps", "thetoppscompanyinc", "toppscompanyinc", "thetoppscompany": return "Topps"
        case "panini", "paniniamericainc", "paniniamerica", "paninigroup": return "Panini"
        case "upperdeck", "theupperdeckcompany", "theupperdeckcompanyllc", "upperdeckcompany": return "Upper Deck"
        default: return title(raw)
        }
    }
    static func year(_ raw: String) -> String {
        let text = clean(raw).replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "–", with: "-").replacingOccurrences(of: "—", with: "-")
        let parts = text.split(whereSeparator: { $0 == "/" || $0 == "-" })
        guard let first = parts.first, first.count == 4, let start = Int(first), (1800...2199).contains(start) else { return "" }
        if parts.count == 1 { return text == String(start) ? String(start) : "" }
        guard text.filter({ $0 == "/" || $0 == "-" }).count == 1, parts.count == 2, let end = Int(parts[1]),
              (parts[1].count == 2 && end == (start + 1) % 100) || (parts[1].count == 4 && end == start + 1) else { return "" }
        // Preserve the source season separately; collection years always use its first year.
        return String(start)
    }
    static func surname(_ raw: String) -> String {
        let suffixes: Set<String> = ["jr", "sr", "ii", "iii", "iv", "v", "vi"]
        let particles: Set<String> = ["de", "del", "da", "dos", "di", "du", "la", "van", "von", "der", "den"]
        var words = clean(raw).split(separator: " ").map(String.init)
        while words.count > 1, let last = words.last, suffixes.contains(last.lowercased().filter { $0 != "." && $0 != "," }) { words.removeLast() }
        guard !words.isEmpty else { return "" }
        var start = words.count - 1
        while start > 1 && particles.contains(words[start - 1].lowercased()) { start -= 1 }
        return words[start...].joined(separator: " ")
    }
}
extension Identity {
    var normalized: Identity {
        var result = self
        result.player = CardMetadata.title(player); result.team = CardMetadata.title(team)
        result.sport = CardMetadata.title(sport)
        result.year = CardMetadata.year(year)
        if result.year != year && !CardMetadata.clean(year).isEmpty { result.sourceYear = CardMetadata.clean(year) }
        result.manufacturer = CardMetadata.manufacturer(manufacturer)
        result.set = CardMetadata.title(set); result.variant = CardMetadata.title(variant)
        result.grade = CardMetadata.title(grade)
        result.number = CardMetadata.clean(number).uppercased(); result.certificate = CardMetadata.clean(certificate).uppercased()
        return result
    }
}
extension Card {
    var normalizedMetadata: Card {
        var result = self
        result.identity = identity.normalized
        if let reference = priceCrossCheck { result.priceCrossCheck?.identity = reference.identity.normalized }
        return result
    }
}

enum CollectionSort: String, CaseIterable {
    case added = "Date added", name = "Player name", year = "Year", value = "Value"
    func directionLabel(ascending: Bool) -> String {
        switch self {
        case .added: return ascending ? "Oldest added" : "Recently added"
        case .name: return ascending ? "A–Z" : "Z–A"
        case .year: return ascending ? "Earlier years" : "Later years"
        case .value: return ascending ? "Low to high" : "High to low"
        }
    }
    func sorted(_ cards: [Card], ascending: Bool) -> [Card] {
        func compare<T: Comparable>(_ a: T?, _ b: T?) -> ComparisonResult? {
            // Unknown values stay at the bottom in either direction.
            if a == nil && b != nil { return .orderedDescending }
            if a != nil && b == nil { return .orderedAscending }
            guard let a, let b, a != b else { return nil }
            return (ascending ? a < b : a > b) ? .orderedAscending : .orderedDescending
        }
        return cards.sorted { a, b in
            var order: ComparisonResult?
            switch self {
            case .added: order = compare(a.added, b.added)
            case .year: order = compare(Int(CardMetadata.year(a.identity.year)), Int(CardMetadata.year(b.identity.year)))
            case .value: order = compare(a.collectionValue, b.collectionValue)
            case .name:
                let nameA = CardMetadata.surname(a.identity.player), nameB = CardMetadata.surname(b.identity.player)
                if nameA.isEmpty != nameB.isEmpty { return !nameA.isEmpty }
                let result = nameA.localizedStandardCompare(nameB)
                if result != .orderedSame { return ascending ? result == .orderedAscending : result == .orderedDescending }
                let fullName = a.identity.player.localizedStandardCompare(b.identity.player)
                if fullName != .orderedSame { return ascending ? fullName == .orderedAscending : fullName == .orderedDescending }
            }
            if let order { return order == .orderedAscending }
            return a.added == b.added ? a.id.uuidString < b.id.uuidString : a.added > b.added
        }
    }
}
