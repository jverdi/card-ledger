import XCTest

@MainActor final class CardInteractionUITests: XCTestCase {
    func waitForValue(_ element:XCUIElement,_ text:String,file:StaticString = #filePath,line:UInt = #line) {
        let predicate = NSPredicate(format:"value CONTAINS %@",text)
        let expectation = XCTNSPredicateExpectation(predicate:predicate,object:element)
        XCTAssertEqual(XCTWaiter.wait(for:[expectation],timeout:5),.completed,file:file,line:line)
    }
    func testPauseSwipeDragAndFlatZoomRoundTrip() {
        continueAfterFailure = false; executionTimeAllowance = 180
        let app = XCUIApplication()
        app.launchEnvironment["CARD_LEDGER_UI_TEST_STORE"] = UUID().uuidString
        app.launchEnvironment["CARD_LEDGER_VIEWER_FIXTURE"] = "1"
        app.launch()
        let row = app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH %@","card.row.")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout:20)); row.tap()
        let card = app.descendants(matching:.any).matching(identifier:"card.detail.reveal").firstMatch
        XCTAssertTrue(card.waitForExistence(timeout:10)); card.tap(); waitForValue(card,"paused")
        let before = card.value as? String
        card.swipeLeft(velocity:.fast); waitForValue(card,"paused")
        XCTAssertNotEqual(card.value as? String,before,"A swipe must change the paused face")
        card.swipeRight(velocity:.fast); waitForValue(card,"paused")
        XCTAssertEqual(card.value as? String,before)
        let design = XCTAttachment(screenshot:app.screenshot()); design.name = "Refined viewer and paused card"; design.lifetime = .keepAlways; add(design)
        card.coordinate(withNormalizedOffset:CGVector(dx:0.35,dy:0.45)).press(forDuration:0.1,
            thenDragTo:card.coordinate(withNormalizedOffset:CGVector(dx:0.7,dy:0.6)),withVelocity:.slow,thenHoldForDuration:0.3)
        waitForValue(card,"spinning")
        card.tap(); waitForValue(card,"paused")
        card.pinch(withScale:1.7,velocity:1)
        let canvas = app.scrollViews["card.zoom.canvas"]
        XCTAssertTrue(canvas.waitForExistence(timeout:10))
        canvas.pinch(withScale:2.5,velocity:1)
        let percent = Double((canvas.value as? String ?? "").components(separatedBy:" ").first ?? "") ?? 0
        XCTAssertGreaterThan(percent,200,"The flat photo must zoom beyond its fit size")
        let zoomed = XCTAttachment(screenshot:app.screenshot()); zoomed.name = "Flat face zoomed beyond fit"; zoomed.lifetime = .keepAlways; add(zoomed)
        canvas.pinch(withScale:0.25,velocity:-1)
        if canvas.exists { canvas.pinch(withScale:0.5,velocity:-1) }
        XCTAssertTrue(card.waitForExistence(timeout:10)); waitForValue(card,"spinning")
        XCTAssertFalse(canvas.exists)
        card.tap(); waitForValue(card,"paused"); card.pinch(withScale:1.4,velocity:1)
        XCTAssertTrue(app.buttons["card.zoom.close"].waitForExistence(timeout:10))
        app.buttons["card.zoom.close"].tap(); waitForValue(card,"spinning")
    }
    func testBatchRevealWaitsWhileUserInspectsThenContinues() {
        continueAfterFailure = false; executionTimeAllowance = 120
        let app = XCUIApplication()
        app.launchEnvironment["CARD_LEDGER_UI_TEST_STORE"] = UUID().uuidString
        app.launchEnvironment["CARD_LEDGER_BATCH_FIXTURE"] = "1"
        app.launch(); app.buttons["collection.batch"].tap()
        let card = app.descendants(matching:.any).matching(identifier:"batch.reveal").firstMatch
        XCTAssertTrue(card.waitForExistence(timeout:20)); card.tap(); waitForValue(card,"paused")
        let returned = XCTNSPredicateExpectation(predicate:NSPredicate(format:"label == %@","Scan front of card"),object:app.staticTexts["batch.instruction"])
        returned.isInverted = true
        XCTAssertEqual(XCTWaiter.wait(for:[returned],timeout:3),.completed)
        XCTAssertTrue(card.exists); card.tap()
        let next = XCTNSPredicateExpectation(predicate:NSPredicate(format:"label == %@","Scan front of card"),object:app.staticTexts["batch.instruction"])
        XCTAssertEqual(XCTWaiter.wait(for:[next],timeout:10),.completed)
    }
}
