import Foundation

/// Exact identities and possible duplicates are deliberately separate: uncertain
/// OCR or similar artwork asks for review without asserting a catalog match.
enum CardDuplicates {
    static func normalized(_ value: String) -> String {
        value.precomposedStringWithCanonicalMapping.lowercased()
            .split(whereSeparator:{ $0.isWhitespace }).joined(separator:" ")
    }
    static func key(_ identity: Identity) -> [String]? {
        let identity = identity.normalized
        let required = [identity.player,identity.sport,identity.year,identity.manufacturer,
                        identity.set,identity.number,identity.variant,identity.grade].map(normalized)
        let unknown: Set<String> = ["","unknown","n/a","na","?","unidentified","not available","unspecified"]
        guard required.allSatisfy({ !unknown.contains($0) }) else { return nil }
        return required + [normalized(identity.certificate)]
    }
    static func exactMatch(_ a: Card,_ b: Card) -> Bool {
        guard let signature = key(a.identity), let other = key(b.identity), signature == other else { return false }
        let teamA = normalized(a.identity.team), teamB = normalized(b.identity.team)
        return teamA.isEmpty || teamB.isEmpty || teamA == teamB
    }
    static func isKnown(_ value: String) -> Bool {
        !["", "unknown", "n/a", "na", "?", "unidentified", "not available", "unspecified"].contains(normalized(value))
    }
    static func sameKnown(_ a: String, _ b: String) -> Bool {
        isKnown(a) && isKnown(b) && normalized(a) == normalized(b)
    }
    /// Used by both scan flows and rechecked before an explicit overwrite.
    static func needsReview(_ a: Card, _ b: Card) -> Bool {
        if exactMatch(a,b) { return true }
        let x = a.identity.normalized, y = b.identity.normalized
        // Human-verified differing identities and certificate numbers are not
        // overridden by artwork, which can be shared by different parallels.
        if x.confirmed && y.confirmed && x.details != y.details { return false }
        if isKnown(x.certificate) && isKnown(y.certificate) && !sameKnown(x.certificate,y.certificate) { return false }
        let sameName = sameKnown(x.player,y.player)
        if sameName {
            let core = [(x.sport,y.sport),(x.year,y.year),(x.manufacturer,y.manufacturer),(x.set,y.set),(x.number,y.number)]
            let qualifiers = [(x.variant,y.variant),(x.grade,y.grade)]
            if core.allSatisfy({ sameKnown($0.0,$0.1) }) &&
                qualifiers.allSatisfy({ !isKnown($0.0) || !isKnown($0.1) || sameKnown($0.0,$0.1) }) { return true }
        }
        let front = CardVisualMatch.similarity(a.thumbnail ?? a.front,b.thumbnail ?? b.front)
        // Names may be missing or misread too; require both faces to strongly
        // agree in that case. A shared team, name, year or card back alone is insufficient.
        if sameName && front >= 0.86 { return true }
        guard front >= (sameName ? 0.78 : 0.94) else { return false }
        let back = CardVisualMatch.similarity(a.backCorrected ?? a.back,b.backCorrected ?? b.back)
        return back >= (sameName ? 0.88 : 0.94)
    }
    static func matches(for scanned: Card,in collection: [Card]) -> [Card] {
        collection.filter { $0.batchState == nil && $0.id != scanned.id && needsReview(scanned,$0) }
            .sorted { $0.added == $1.added ? $0.id.uuidString < $1.id.uuidString : $0.added > $1.added }
    }
    static func replacing(_ original: Card, with scanned: Card) -> Card {
        var existing = original
        existing.identity = scanned.identity
        existing.front = scanned.front; existing.back = scanned.back
        existing.thumbnail = scanned.thumbnail; existing.backCorrected = scanned.backCorrected
        existing.frontCrop = scanned.frontCrop; existing.backCrop = scanned.backCrop
        existing.frontOrientationUncertain = scanned.frontOrientationUncertain
        existing.backOrientationUncertain = scanned.backOrientationUncertain
        existing.ocr = scanned.ocr; existing.frontOCR = scanned.frontOCR; existing.backOCR = scanned.backOCR
        existing.research = scanned.research; existing.pricing = scanned.pricing; existing.priceCrossCheck = scanned.priceCrossCheck; existing.scanNote = scanned.scanNote
        return existing
    }

}

extension CollectionStore {
    /// Replacement retains the existing entry's identity, collection history and
    /// owner-entered fields, while refreshing only its scan-derived content.
    func saveScan(_ scanned: Card,replacing id: UUID? = nil,duplicateConfirmed: Bool = false) throws -> Card {
        guard let id else {
            guard duplicateConfirmed || CardDuplicates.matches(for:scanned,in:cards).isEmpty else { throw ScanSaveError.duplicateNeedsReview }
            try save(scanned); return scanned
        }
        guard var existing = cards.first(where:{ $0.id == id }), CardDuplicates.needsReview(scanned,existing) else {
            throw ScanSaveError.matchChanged
        }
        existing = CardDuplicates.replacing(existing, with: scanned)
        try save(existing)
        return existing
    }
}
enum ScanSaveError: LocalizedError {
    case matchChanged, duplicateNeedsReview
    var errorDescription: String? {
        switch self {
        case .matchChanged: return "The existing card changed or was removed. Review the save options again."
        case .duplicateNeedsReview: return "A possible duplicate is now in your collection. Review the save options before adding another copy."
        }
    }
}

