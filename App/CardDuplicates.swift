import Foundation

/// Exact catalog identity only. Missing set/parallel information must never turn
/// two merely similar cards into an asserted exact match.
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
    static func matches(for scanned: Card,in collection: [Card]) -> [Card] {
        collection.filter { $0.batchState == nil && $0.id != scanned.id && exactMatch(scanned,$0) }
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
        existing.research = scanned.research; existing.pricing = scanned.pricing; existing.scanNote = scanned.scanNote
        return existing
    }

}

extension CollectionStore {
    /// Replacement retains the existing entry's identity, collection history and
    /// owner-entered fields, while refreshing only its scan-derived content.
    func saveScan(_ scanned: Card,replacing id: UUID? = nil) throws -> Card {
        guard let id else { try save(scanned); return scanned }
        guard var existing = cards.first(where:{ $0.id == id }), CardDuplicates.exactMatch(scanned,existing) else {
            throw ScanSaveError.matchChanged
        }
        existing = CardDuplicates.replacing(existing, with: scanned)
        try save(existing)
        return existing
    }
}
enum ScanSaveError: LocalizedError {
    case matchChanged
    var errorDescription: String? { "The existing card changed or was removed. Review the save options again." }
}

