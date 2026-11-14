import XCTest
@testable import CardLedger

final class CaptureGateTests: XCTestCase {
    func rectangle() -> CardRectangle { CardRectangle(points:[CGPoint(x:0.2,y:0.2),CGPoint(x:0.8,y:0.2),CGPoint(x:0.8,y:0.8),CGPoint(x:0.2,y:0.8)],confidence:0.95,pixelSize:CGSize(width:700,height:1000)) }
    func testRejectsSquareClippedAndUnstableObjects() {
        var gate = CaptureGate(); var r = rectangle(); r.pixelSize = CGSize(width:1000,height:1000)
        XCTAssertFalse(r.likelyCard)
        for i in 0..<20 { XCTAssertFalse(gate.observe(r,at:Double(i)*0.2)) }
        r = rectangle(); r.points[0].x = 0
        XCTAssertFalse(r.likelyCard)
        r = rectangle()
        for i in 0..<20 { var moving = r; moving.points = r.points.map { CGPoint(x:$0.x + (i%2 == 0 ? 0.03:0),y:$0.y) }; XCTAssertFalse(gate.observe(moving,at:Double(i)*0.2)) }
    }
    func testStableCaptureLatchesAndRequiresDepartureBeforeBack() {
        var gate = CaptureGate(); let r = rectangle()
        var captures = 0
        for i in 0..<30 { if gate.observe(r,at:Double(i)*0.1) { captures += 1 } }
        XCTAssertEqual(captures,1)
        gate.reset(requireDeparture:true)
        for i in 30..<50 { XCTAssertFalse(gate.observe(r,at:Double(i)*0.1)) }
        for i in 50..<56 { XCTAssertFalse(gate.observe(nil,at:Double(i)*0.1)) }
        for i in 56..<76 { if gate.observe(r,at:Double(i)*0.1) { captures += 1 } }
        XCTAssertEqual(captures,2)
    }
    func testFocusMustSettle() {
        var gate = CaptureGate()
        for i in 0..<20 { XCTAssertFalse(gate.observe(rectangle(),at:Double(i)*0.1,focused:false)) }
    }
}
@MainActor final class ScanFlowTests: XCTestCase {
    func services(lookup: @escaping (Identity) async throws -> Research) -> ScanServices {
        ScanServices(process:{ PhotoResult(original:$0.original,corrected:$0.original,text:$0.original == Data([1]) ? "Front OCR":"Back OCR") },identify:{ text in
            XCTAssertTrue(text.contains("Front OCR")); XCTAssertTrue(text.contains("Back OCR"))
            return Identity(player:"Rookie",team:"Team",year:"2026",set:"Set",number:"1",variant:"Base")
        },lookup:lookup,canLookup:true,revealDuration:0.02,spinnerDelay:0.05,minimumReveal:0.04,collapseDuration:0.01)
    }
    func feed(_ model:ScanFlowModel) { model.receive(CapturedFace(original:Data([1]),crop:CropSelection())); XCTAssertEqual(model.stage,.back); model.receive(CapturedFace(original:Data([2]),crop:CropSelection())) }
    func waitUntil(_ predicate: @escaping () -> Bool) async throws {
        for _ in 0..<100 { if predicate() { return }; try await Task.sleep(for:.milliseconds(10)) }
        XCTFail("Flow did not reach expected state")
    }
    func testSlowPricingShowsDelayedSpinnerThenCompletesWithoutPrice() async throws {
        let model = ScanFlowModel(services:services { identity in
            XCTAssertFalse(identity.confirmed)
            try await Task.sleep(for:.milliseconds(250)); throw ScanFailure.timeout
        })
        feed(model)
        try await waitUntil { model.stage == .revealing }
        XCTAssertFalse(model.showPriceSpinner)
        try await waitUntil { model.showPriceSpinner }
        try await waitUntil { model.stage == .ready }
        XCTAssertFalse(model.showPriceSpinner)
        XCTAssertNotNil(model.card.front); XCTAssertNotNil(model.card.backCorrected)
        XCTAssertNil(model.card.research); XCTAssertNotNil(model.card.scanNote)
    }
    func testCancellationCannotFinishOrInsertAnIncompleteCard() async throws {
        let model = ScanFlowModel(services:services { _ in try await Task.sleep(for:.seconds(10)); throw ScanFailure.timeout })
        feed(model); try await waitUntil { model.pricePending }; model.cancel()
        try await Task.sleep(for:.milliseconds(100))
        XCTAssertNotEqual(model.stage,.ready)
    }
    func testCancelledScanRejectsLateCapture() {
        let model = ScanFlowModel(services:services { _ in throw ScanFailure.timeout })
        model.cancel()
        model.receive(CapturedFace(original:Data([1]),crop:CropSelection()))
        XCTAssertEqual(model.stage,.front)
        XCTAssertNil(model.card.front)
    }
    func testFastPriceSkipsSpinner() async throws {
        let model = ScanFlowModel(services:services { _ in
            Research(searched_at:"2026-11-14",identity_status:"confirmed",unresolved_fields:[],queries_used:[],observations:[],valuation_basis:"sold_comps",limitations:[],estimate:25,low:20,high:30,sample_count:5)
        })
        feed(model); try await waitUntil { model.stage == .ready }
        XCTAssertFalse(model.showPriceSpinner); XCTAssertEqual(model.card.research?.estimate,25)
    }
}
