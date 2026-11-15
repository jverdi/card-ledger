import XCTest

final class BatchUITests: XCTestCase {
    func testTwoPairsAutomaticallyReturnToFrontAndDeferDuplicateReview() throws {
        executionTimeAllowance = 120
        let app = XCUIApplication()
        app.launchEnvironment["CARD_LEDGER_UI_TEST_STORE"] = UUID().uuidString
        app.launchEnvironment["CARD_LEDGER_BATCH_FIXTURE"] = "1"
        app.launch()
        app.buttons["collection.batch"].tap()
        XCTAssertTrue(app.staticTexts["batch.count"].waitForExistence(timeout:15))
        let two = NSPredicate(format:"label CONTAINS %@", "2 captured")
        expectation(for:two,evaluatedWith:app.staticTexts["batch.count"])
        waitForExpectations(timeout:40)
        let front = NSPredicate(format:"label == %@","Scan front of card")
        expectation(for:front,evaluatedWith:app.staticTexts["batch.instruction"])
        waitForExpectations(timeout:15)
        // No Continue or other taps were needed for either card.
        XCTAssertFalse(app.buttons["scan.continue"].exists)
        app.buttons["batch.done"].tap()
        XCTAssertTrue(app.buttons["batch.inbox"].waitForExistence(timeout:15))
        app.buttons["batch.inbox"].tap()
        app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH %@","batch.duplicate.")).firstMatch.tap()
        XCTAssertTrue(app.staticTexts["scan.duplicate.title"].waitForExistence(timeout:10))
        app.buttons["scan.duplicate.add"].tap()
        app.buttons["Done"].tap()
        app.terminate(); app.launch()
        XCTAssertFalse(app.buttons["batch.inbox"].exists)
        XCTAssertEqual(app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH %@","card.row.")).count,2)
    }
}
