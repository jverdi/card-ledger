import XCTest
@testable import CardLedger
@MainActor final class StoreTests: XCTestCase {
    func temporary() -> URL { URL.temporaryDirectory.appending(path: UUID().uuidString + "/collection.json") }
    func testRoundTripPhotosAndStatus() async throws {
        let path = temporary(); let store = CollectionStore(file: path)
        var card = Card(); card.identity.player = "Test"; card.front = Data([1,2,3]); card.status = "Sold"
        try store.save(card)
        let reopened = CollectionStore(file: path)
        XCTAssertEqual(reopened.cards.first?.front, card.front)
        XCTAssertEqual(reopened.cards.first?.status, "Sold")
    }
    func testImportDoesNotOverwriteExistingCopy() async throws {
        let store = CollectionStore(file: temporary()); var card = Card(); card.notes = "newer"
        try store.save(card); card.notes = "older"
        try store.restore(JSONEncoder().encode(Archive(cards: [card])))
        XCTAssertEqual(store.cards.count,1); XCTAssertEqual(store.cards[0].notes,"newer")
    }
    func testCorruptStoreIsNeverOverwritten() async throws {
        let path = temporary(); try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
        let bytes = Data("invalid".utf8); try bytes.write(to: path)
        let store = CollectionStore(file: path)
        XCTAssertThrowsError(try store.save(Card()))
        XCTAssertEqual(try Data(contentsOf: path),bytes)
    }
    func testRejectDuplicateUUIDs() async throws {
        let card = Card()
        XCTAssertThrowsError(try CollectionStore.validate(Archive(cards:[card,card])))
    }
    func testRetakingPhotoReplacesOnlyThatSidesText() async {
        var card = Card()
        card.replaceOCR("Old front", front: true)
        card.replaceOCR("Back label", front: false)
        card.identity.confirmed = true
        card.replaceOCR("New front", front: true)
        XCTAssertFalse(card.ocr.contains("Old front"))
        XCTAssertTrue(card.ocr.contains("New front"))
        XCTAssertTrue(card.ocr.contains("Back label"))
        XCTAssertFalse(card.identity.confirmed)
    }
    func testMoneyAndCropSurviveBackupRestore() async throws {
        let store = CollectionStore(file: temporary())
        var card = Card(); card.manualValue = Decimal(string: "12.34"); card.acquisitionCost = Decimal(string: "1.99"); card.frontCrop = CropSelection()
        try store.save(card)
        let restored = CollectionStore(file: temporary())
        try restored.restore(Data(contentsOf: store.export()))
        XCTAssertEqual(restored.cards[0].manualValue, Decimal(string: "12.34"))
        XCTAssertEqual(restored.cards[0].acquisitionCost, Decimal(string: "1.99"))
        XCTAssertEqual(restored.cards[0].frontCrop, card.frontCrop)
        XCTAssertEqual(restored.cards[0].collectionValue, 12.34)
    }
    func testCropRejectsCrossedOrTinyQuadrilaterals() async {
        XCTAssertTrue(CropSelection().valid)
        var crop = CropSelection(); crop.points.swapAt(1, 2)
        XCTAssertFalse(crop.valid)
        crop = CropSelection(); crop.points = crop.points.map { CropPoint(x: $0.x / 100, y: $0.y / 100) }
        XCTAssertFalse(crop.valid)
    }
}
