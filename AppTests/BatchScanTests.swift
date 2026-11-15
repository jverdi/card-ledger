import XCTest
@testable import CardLedger

@MainActor final class BatchScanTests: XCTestCase {
    func store() -> CollectionStore { CollectionStore(file:URL.temporaryDirectory.appending(path:UUID().uuidString+"/collection.json")) }
    func pair() -> Card {
        var card = Card(); card.front = Data([1]); card.back = Data([2]); card.frontCrop = CropSelection(); card.backCrop = CropSelection()
        return card
    }
    func services() -> ScanServices {
        ScanServices(process:{ PhotoResult(original:$0.original,corrected:$0.original,text:"Card") },identify:{ _ in
            Identity(player:"Rookie",team:"Team",year:"2026",manufacturer:"Brand",set:"Set",number:"1",variant:"Base")
        },lookup:{ _ in throw ScanFailure.timeout },canLookup:true,revealDuration:0,minimumReveal:0)
    }
    func wait(_ predicate: @escaping () -> Bool) async throws {
        for _ in 0..<200 { if predicate() { return }; try await Task.sleep(for:.milliseconds(10)) }
        XCTFail("Batch processing did not finish")
    }
    func testBackToBackPairsPersistAndDuplicatesWaitForChoice() async throws {
        let store = store(); let coordinator = BatchScanCoordinator(); coordinator.services = services()
        let first = pair(), second = pair()
        try coordinator.enqueue(first,store:store); try coordinator.enqueue(second,store:store)
        XCTAssertEqual(store.cards.count,2)
        XCTAssertEqual(coordinator.pendingCount(store),2)
        try await wait { coordinator.pendingCount(store) == 0 }
        XCTAssertEqual(store.cards.filter { $0.batchState == nil }.count,1)
        XCTAssertEqual(coordinator.duplicateCount(store),1)
        let duplicate = try XCTUnwrap(store.cards.first { $0.batchState == "duplicate" })
        XCTAssertNotNil(duplicate.scanNote) // Price failure does not lose either face.
        XCTAssertEqual(duplicate.back,Data([2]))
        try store.resolveBatch(duplicate)
        XCTAssertEqual(store.cards.filter { $0.batchState == nil }.count,2)
    }
    func testPersistedQueueResumesAndOverwriteIsAtomicPreservingOwnerFields() async throws {
        let file = URL.temporaryDirectory.appending(path:UUID().uuidString+"/collection.json")
        let initial = CollectionStore(file:file)
        var existing = pair(); existing.identity = try await services().identify(""); existing.notes = "Keep"; existing.manualValue = 7
        try initial.save(existing)
        var queued = pair(); queued.batchState = "queued"; try initial.save(queued)
        let restored = CollectionStore(file:file); let coordinator = BatchScanCoordinator(); coordinator.services = services()
        coordinator.resume(store:restored)
        try await wait { coordinator.duplicateCount(restored) == 1 }
        let duplicate = try XCTUnwrap(restored.cards.first { $0.id == queued.id })
        try restored.resolveBatch(duplicate,replacing:existing.id)
        let reopened = CollectionStore(file:file)
        XCTAssertEqual(reopened.cards.count,1)
        XCTAssertEqual(reopened.cards.first?.id,existing.id)
        XCTAssertEqual(reopened.cards.first?.notes,"Keep")
        XCTAssertEqual(reopened.cards.first?.manualValue,7)
        XCTAssertNil(reopened.cards.first?.batchState)
    }
    func testQueuedCardsAreNotDuplicateMatchesAndDiscardLeavesCollectionUntouched() throws {
        let store = store(); var a = pair(); a.identity = Identity(player:"A",year:"1",manufacturer:"B",set:"C",number:"1",variant:"Base")
        var b = a; b.id = UUID(); b.batchState = "duplicate"
        try store.save(a); try store.save(b)
        XCTAssertEqual(CardDuplicates.matches(for:b,in:store.cards).map(\.id),[a.id])
        XCTAssertTrue(CardDuplicates.matches(for:a,in:store.cards).isEmpty)
        try store.delete(b.id); XCTAssertEqual(store.cards.map(\.id),[a.id])
    }
}

final class BatchCaptureGateTests: XCTestCase {
    func testChangedFaceRearmsWithoutMissingRectangleAndOldFaceCannotRepeat() {
        let r = CardRectangle(points:[CGPoint(x:0.2,y:0.2),CGPoint(x:0.8,y:0.2),CGPoint(x:0.8,y:0.8),CGPoint(x:0.2,y:0.8)],confidence:0.95,pixelSize:CGSize(width:700,height:1000))
        let front: [UInt8] = [0,255,0,255], back: [UInt8] = [255,0,255,0]
        var gate = CaptureGate(); var count = 0
        for i in 0..<20 { if gate.observe(r,at:Double(i)*0.1,appearance:front) { count += 1 } }
        XCTAssertEqual(count,1)
        gate.reset(requireDeparture:true)
        for i in 20..<30 { XCTAssertFalse(gate.observe(r,at:Double(i)*0.1,appearance:front)) }
        // Flip during confirmation; do not capture until armed.
        for i in 30..<40 { XCTAssertFalse(gate.observe(r,at:Double(i)*0.1,captureAllowed:false,appearance:back)) }
        XCTAssertFalse(gate.requiresDeparture)
        for i in 40..<60 { if gate.observe(r,at:Double(i)*0.1,appearance:back) { count += 1 } }
        XCTAssertEqual(count,2)
        gate.reset(requireDeparture:true)
        _ = gate.observe(nil,at:6); _ = gate.observe(nil,at:6.3)
        for i in 64..<80 { XCTAssertFalse(gate.observe(r,at:Double(i)*0.1,appearance:back)) }
        for i in 80..<100 { if gate.observe(r,at:Double(i)*0.1,appearance:front) { count += 1 } }
        XCTAssertEqual(count,3)
    }
    func testDeliberateClearPermitsVisuallyIdenticalNextCard() {
        let r = CardRectangle(points:[CGPoint(x:0.2,y:0.2),CGPoint(x:0.8,y:0.2),CGPoint(x:0.8,y:0.8),CGPoint(x:0.2,y:0.8)],confidence:0.95,pixelSize:CGSize(width:700,height:1000))
        var gate = CaptureGate(); let face: [UInt8] = [10,100,200,40]
        var captures = 0
        for i in 0..<20 { if gate.observe(r,at:Double(i)*0.1,appearance:face) { captures += 1 } }
        gate.reset(requireDeparture:true)
        for i in 20..<30 { _ = gate.observe(nil,at:Double(i)*0.1) }
        for i in 30..<50 { if gate.observe(r,at:Double(i)*0.1,appearance:face) { captures += 1 } }
        XCTAssertEqual(captures,2)
    }
    func testBrightnessChangeIsNotAFlip() {
        XCTAssertEqual(CaptureGate.difference([20,60,100,140],[40,80,120,160]),0,accuracy:0.001)
    }
}
