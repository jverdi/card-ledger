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
    func testFlipDuringConfirmationIsRememberedAndBackNeedsFreshHold() {
        var gate = CaptureGate(); let r = rectangle()
        gate.reset(requireDeparture:true)
        XCTAssertFalse(gate.observe(nil,at:0,captureAllowed:false))
        XCTAssertFalse(gate.observe(nil,at:0.2,captureAllowed:false))
        XCTAssertFalse(gate.requiresDeparture)
        for i in 3..<25 { XCTAssertFalse(gate.observe(r,at:Double(i)*0.1,captureAllowed:false)) }
        gate.restartHold() // background/foreground or confirmation ending must not re-arm the flip
        XCTAssertFalse(gate.requiresDeparture)
        XCTAssertFalse(gate.observe(r,at:3))
        var count = 0
        for i in 31..<50 { if gate.observe(r,at:Double(i)*0.1) { count += 1 } }
        XCTAssertEqual(count,1)
    }
    func testSingleMissingFrameCannotRearmTheFront() {
        var gate = CaptureGate(); gate.reset(requireDeparture:true)
        _ = gate.observe(nil,at:0)
        for i in 1..<20 { XCTAssertFalse(gate.observe(rectangle(),at:Double(i)*0.1)) }
        XCTAssertTrue(gate.requiresDeparture)
    }
    func testFocusLossResetsHoldAndPortraitFocusCoordinates() {
        var gate = CaptureGate(); let r = rectangle()
        for i in 0..<5 { XCTAssertFalse(gate.observe(r,at:Double(i)*0.1)) }
        XCTAssertGreaterThan(gate.progress,0.7)
        XCTAssertFalse(gate.observe(r,at:0.5,focused:false)); XCTAssertEqual(gate.progress,0)
        for i in 6..<11 { XCTAssertFalse(gate.observe(r,at:Double(i)*0.1)) }
        XCTAssertTrue(gate.observe(r,at:1.2))
        XCTAssertEqual(AutoScanCamera.deviceFocusPoint(portraitPoint:CGPoint(x:0.2,y:0.7)),CGPoint(x:0.7,y:0.8))
    }
    func testGentleHandDriftCapturesWithinHalfASecond() {
        var gate = CaptureGate(); let base = rectangle()
        var captured = false
        for i in 0...5 {
            var moved = base
            moved.points = base.points.map { CGPoint(x:$0.x + Double(i)*0.009,y:$0.y + (i%2 == 0 ? 0.004 : 0)) }
            captured = gate.observe(moved,at:Double(i)*0.1)
            if i < 5 { XCTAssertFalse(captured) }
        }
        XCTAssertTrue(captured,"Normal drift should not restart the hold indefinitely")
    }
    func testStaleFrameCannotCompleteCapture() {
        var gate = CaptureGate()
        for i in 0..<5 { XCTAssertFalse(gate.observe(rectangle(),at:Double(i)*0.1)) }
        XCTAssertFalse(gate.observe(rectangle(),at:2))
        XCTAssertEqual(gate.progress,0)
    }
    func testFocusMustSettle() {
        var gate = CaptureGate()
        for i in 0..<20 { XCTAssertFalse(gate.observe(rectangle(),at:Double(i)*0.1,focused:false)) }
    }
}
@MainActor final class ScanFlowTests: XCTestCase {
    func services(lookup: @escaping (Identity) async throws -> CardPricing) -> ScanServices {
        ScanServices(process:{ PhotoResult(original:$0.original,corrected:$0.original,text:$0.original == Data([1]) ? "Front OCR":"Back OCR") },identify:{ text in
            XCTAssertTrue(text.contains("Front OCR")); XCTAssertTrue(text.contains("Back OCR"))
            return Identity(player:"Rookie",team:"Team",year:"2026",set:"Set",number:"1",variant:"Base")
        },lookup:lookup,canLookup:true,revealDuration:0.02,spinnerDelay:0.05,minimumReveal:0.04,collapseDuration:0.01,confirmationDuration:0.03)
    }
    func feed(_ model:ScanFlowModel) async throws {
        model.receive(CapturedFace(original:Data([1]),crop:CropSelection()))
        XCTAssertEqual(model.stage,.frontCaptured)
        XCTAssertFalse(model.scanning); XCTAssertTrue(model.capturing)
        try await waitUntil { model.stage == .back }
        model.receive(CapturedFace(original:Data([2]),crop:CropSelection()))
    }
    func waitUntil(_ predicate: @escaping () -> Bool) async throws {
        for _ in 0..<100 { if predicate() { return }; try await Task.sleep(for:.milliseconds(10)) }
        XCTFail("Flow did not reach expected state")
    }
    func testSlowPricingShowsDelayedSpinnerThenWaitsForContinueWithoutPrice() async throws {
        let model = ScanFlowModel(services:services { identity in
            XCTAssertFalse(identity.confirmed)
            try await Task.sleep(for:.milliseconds(250)); throw ScanFailure.timeout
        })
        try await feed(model)
        try await waitUntil { model.stage == .revealing }
        XCTAssertFalse(model.showPriceSpinner)
        try await waitUntil { model.showPriceSpinner }
        model.continueToCollection()
        XCTAssertEqual(model.stage,.revealing)
        try await waitUntil { model.canContinue }
        XCTAssertEqual(model.stage,.review)
        XCTAssertFalse(model.showPriceSpinner)
        XCTAssertNotNil(model.card.front); XCTAssertNotNil(model.card.backCorrected)
        XCTAssertNil(model.card.pricing); XCTAssertNotNil(model.card.scanNote)
    }
    func testCancellationCannotFinishOrInsertAnIncompleteCard() async throws {
        let model = ScanFlowModel(services:services { _ in try await Task.sleep(for:.seconds(10)); throw ScanFailure.timeout })
        try await feed(model); try await waitUntil { model.pricePending }; model.cancel()
        try await Task.sleep(for:.milliseconds(100))
        XCTAssertNotEqual(model.stage,.ready)
    }
    func testConfirmationIgnoresExtraFramesAndCancellationStopsTransition() async throws {
        let model = ScanFlowModel(services:services { _ in throw ScanFailure.timeout })
        let front = CapturedFace(original:Data([1]),crop:CropSelection())
        model.receive(front)
        XCTAssertEqual(model.stage,.frontCaptured)
        model.receive(front)
        XCTAssertNil(model.card.back)
        model.cancel()
        try await Task.sleep(for:.milliseconds(80))
        XCTAssertEqual(model.stage,.frontCaptured)
        XCTAssertNil(model.card.back)
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
            CardPricing(status:.priced,value:25)
        })
        try await feed(model); try await waitUntil { model.canContinue }
        XCTAssertFalse(model.showPriceSpinner); XCTAssertEqual(model.card.pricing?.usableValue,25)
        try await Task.sleep(for:.milliseconds(150))
        XCTAssertEqual(model.stage,.review)
        model.continueToCollection(); model.continueToCollection()
        XCTAssertEqual(model.stage,.compact)
        XCTAssertFalse(model.canContinue)
        try await waitUntil { model.stage == .ready }
    }
    func testUnavailablePricingStillOffersContinueAndCancellationPreventsInsertion() async throws {
        var configuration = services { _ in XCTFail("Unconfigured pricing should not run"); throw ScanFailure.timeout }
        configuration.canLookup = false
        let model = ScanFlowModel(services:configuration)
        try await feed(model); try await waitUntil { model.canContinue }
        XCTAssertNotNil(model.card.scanNote)
        XCTAssertFalse(model.pricePending)
        model.cancel(); model.continueToCollection()
        try await Task.sleep(for:.milliseconds(60))
        XCTAssertEqual(model.stage,.review)
        XCTAssertFalse(model.canContinue)
    }
    func testCancellationDuringContinueAnimationPreventsInsertion() async throws {
        var configuration = services { _ in throw ScanFailure.timeout }
        configuration.collapseDuration = 0.1
        let model = ScanFlowModel(services:configuration)
        try await feed(model); try await waitUntil { model.canContinue }
        model.continueToCollection(); model.cancel()
        try await Task.sleep(for:.milliseconds(150))
        XCTAssertNotEqual(model.stage,.ready)
    }

}

