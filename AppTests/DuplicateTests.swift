import XCTest
@testable import CardLedger

@MainActor final class DuplicateTests: XCTestCase {
    func card() -> Card {
        var card = Card()
        card.identity = Identity(player:"Anthony Volpe",team:"New York Yankees",year:"2023",manufacturer:"Topps",set:"Inception",number:"105",variant:"Base",grade:"Raw")
        card.front = Data([1]); card.back = Data([2]); card.thumbnail = Data([3])
        return card
    }
    func file() -> URL { URL.temporaryDirectory.appending(path:UUID().uuidString+"/collection.json") }
    func testExactIdentityNormalizesCaseWhitespaceButRejectsPartialOrDifferentCards() {
        let existing = card()
        var scanned = card(); scanned.identity.player = "  ANTHONY   VOLPE "; scanned.identity.manufacturer = "TOPPS"
        XCTAssertTrue(CardDuplicates.exactMatch(scanned,existing))
        for path in [\Identity.player,\.sport,\.year,\.manufacturer,\.set,\.number,\.variant,\.grade] {
            var incomplete = scanned; incomplete.identity[keyPath:path] = ""
            XCTAssertFalse(CardDuplicates.exactMatch(incomplete,existing))
            var different = scanned; different.identity[keyPath:path] = "Different"
            XCTAssertFalse(CardDuplicates.exactMatch(different,existing))
        }
        scanned.identity.variant = "Unknown"
        XCTAssertFalse(CardDuplicates.exactMatch(scanned,existing))
        scanned = card(); scanned.identity.certificate = "1234"
        XCTAssertFalse(CardDuplicates.exactMatch(scanned,existing))
        scanned = card(); scanned.identity.team = "Different team"
        XCTAssertFalse(CardDuplicates.exactMatch(scanned,existing))
        XCTAssertFalse(CardDuplicates.exactMatch(Card(),Card()))
    }
    func testFindsEveryMatchingCopyWithoutSelectingOneToOverwrite() {
        let a = card(), b = card(), scanned = card()
        var other = card(); other.identity.variant = "Gold"
        XCTAssertEqual(Set(CardDuplicates.matches(for:scanned,in:[a,other,b]).map(\.id)),Set([a.id,b.id]))
    }
    func testAddDuplicatePreservesBothIndependentEntries() throws {
        let path = file(), existing = card(), scanned = card()
        let store = CollectionStore(file:path); try store.save(existing)
        let added = try store.saveScan(scanned)
        XCTAssertEqual(added.id,scanned.id)
        XCTAssertEqual(Set(CollectionStore(file:path).cards.map(\.id)),Set([existing.id,scanned.id]))
    }
    func testOverwriteRefreshesScanAndPreservesChosenRecordsHistory() throws {
        let path = file(); let store = CollectionStore(file:path)
        var existing = card(); existing.notes = "Notes"; existing.tags = "Emmett"; existing.location = "Binder A"
        existing.manualValue = 50; existing.manualValueSource = "Owner"; existing.manualValueDate = Date(timeIntervalSince1970:100)
        existing.acquisitionCost = 5; existing.acquisitionDate = Date(timeIntervalSince1970:10)
        existing.status = "Sold"; existing.dispositionProceeds = 65; existing.dispositionDate = Date(timeIntervalSince1970:200)
        let other = card(); try store.save(existing); try store.save(other)
        var scanned = card(); scanned.front = Data([9]); scanned.back = Data([8]); scanned.thumbnail = Data([7]); scanned.backCorrected = Data([6])
        scanned.frontCrop = CropSelection(); scanned.backCrop = CropSelection(); scanned.ocr = "New OCR"
        let result = try store.saveScan(scanned,replacing:existing.id)
        XCTAssertEqual(result.id,existing.id); XCTAssertEqual(result.added,existing.added)
        let reopened = CollectionStore(file:path)
        XCTAssertEqual(reopened.cards.count,2)
        let updated = try XCTUnwrap(reopened.cards.first { $0.id == existing.id })
        XCTAssertEqual(updated.photoData,scanned.photoData); XCTAssertEqual(updated.ocr,"New OCR")
        XCTAssertEqual(updated.frontCrop,scanned.frontCrop); XCTAssertEqual(updated.backCrop,scanned.backCrop)
        XCTAssertEqual(updated.notes,existing.notes); XCTAssertEqual(updated.tags,existing.tags); XCTAssertEqual(updated.location,existing.location)
        XCTAssertEqual(updated.manualValue,existing.manualValue); XCTAssertEqual(updated.manualValueSource,existing.manualValueSource); XCTAssertEqual(updated.manualValueDate,existing.manualValueDate)
        XCTAssertEqual(updated.acquisitionCost,existing.acquisitionCost); XCTAssertEqual(updated.acquisitionDate,existing.acquisitionDate)
        XCTAssertEqual(updated.status,existing.status); XCTAssertEqual(updated.dispositionDate,existing.dispositionDate); XCTAssertEqual(updated.dispositionProceeds,existing.dispositionProceeds)
        XCTAssertEqual(reopened.cards.first { $0.id == other.id }?.front,other.front)
    }
    func testChangedOrDeletedMatchCannotBeOverwritten() throws {
        let store = CollectionStore(file:file()); var existing = card(); let scanned = card()
        try store.save(existing); existing.identity.variant = "Gold"; try store.save(existing)
        XCTAssertThrowsError(try store.saveScan(scanned,replacing:existing.id))
        XCTAssertEqual(store.cards[0].identity.variant,"Gold")
        try store.delete(existing.id)
        XCTAssertThrowsError(try store.saveScan(scanned,replacing:existing.id))
        XCTAssertTrue(store.cards.isEmpty)
    }
}
