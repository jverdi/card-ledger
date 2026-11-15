import XCTest

@MainActor final class PricingUITests: XCTestCase {
    func reveal(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        let element = app.buttons[identifier]
        for _ in 0..<5 { if element.exists && element.isHittable { return element }; app.swipeUp() }
        return element
    }
    func testReviewPriceAndIndependentReferencePersist() {
        continueAfterFailure = false; executionTimeAllowance = 120
        let app = XCUIApplication()
        app.launchEnvironment["CARD_LEDGER_UI_TEST_STORE"] = UUID().uuidString
        app.launchEnvironment["CARD_LEDGER_PRICING_FIXTURE"] = "1"
        app.launch()
        let rows = app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH %@","card.row."))
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout:20)); rows.firstMatch.tap()
        let refresh = reveal(app,"pricing.refresh"); XCTAssertTrue(refresh.isHittable); refresh.tap()
        let review = reveal(app,"pricing.review"); XCTAssertTrue(review.waitForExistence(timeout:5)); review.tap()
        XCTAssertTrue(app.buttons["pricing.confirmMatch"].waitForExistence(timeout:5)); app.buttons["pricing.confirmMatch"].tap()
        app.alerts.buttons["Confirm match"].tap()
        XCTAssertTrue(app.buttons["card.detail.close"].waitForExistence(timeout:5))
        reveal(app,"pricing.crossCheck").tap()
        let field = app.textFields["pricing.referenceValue"]
        XCTAssertTrue(field.waitForExistence(timeout:5)); field.tap(); field.typeText("20")
        let done = app.buttons["money.done"]
        XCTAssertTrue(done.waitForExistence(timeout:5)); done.tap()
        let verified = app.switches["pricing.referenceVerified"]
        for _ in 0..<3 { if verified.isHittable { break }; app.swipeUp() }
        verified.tap()
        XCTAssertEqual(verified.value as? String,"1")
        XCTAssertTrue(app.buttons["pricing.referenceSave"].isEnabled); app.buttons["pricing.referenceSave"].tap()
        XCTAssertTrue(app.staticTexts["11% below CardPricer"].waitForExistence(timeout:5))
        let shot = XCTAttachment(screenshot:app.screenshot()); shot.name = "CardPricer estimate and separate 130 Point reference"; shot.lifetime = .keepAlways; add(shot)
        app.buttons["card.detail.close"].tap()
        XCTAssertTrue(rows.firstMatch.label.contains("22.50"))
        app.terminate(); app.launch()
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout:20)); XCTAssertTrue(rows.firstMatch.label.contains("22.50")); rows.firstMatch.tap()
        _ = reveal(app,"pricing.crossCheck")
        XCTAssertTrue(app.staticTexts["11% below CardPricer"].exists)
    }
}
