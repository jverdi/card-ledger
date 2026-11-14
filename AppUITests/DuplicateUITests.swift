import XCTest

@MainActor final class DuplicateUITests: XCTestCase {
    func scanDuplicate() throws -> XCUIApplication {
        executionTimeAllowance = 120
        let app = XCUIApplication()
        app.launchEnvironment["CARD_LEDGER_UI_TEST_STORE"] = UUID().uuidString
        app.launchEnvironment["CARD_LEDGER_SCAN_FIXTURE"] = "1"
        app.launchEnvironment["CARD_LEDGER_DUPLICATE_FIXTURE"] = "1"
        app.launch()
        XCTAssertTrue(app.buttons["collection.add"].waitForExistence(timeout:20))
        XCTAssertEqual(rows(app).count,1)
        app.buttons["collection.add"].tap()
        XCTAssertTrue(app.buttons["scan.continue"].waitForExistence(timeout:50))
        XCTAssertTrue(app.staticTexts["scan.duplicate.notice"].exists || app.descendants(matching:.any)["scan.duplicate.notice"].exists)
        app.buttons["scan.continue"].tap()
        XCTAssertTrue(app.buttons["scan.duplicate.add"].waitForExistence(timeout:5))
        XCTAssertTrue(app.buttons["scan.duplicate.overwrite"].isEnabled)
        XCTAssertTrue(app.buttons["scan.duplicate.discard"].exists)
        return app
    }
    func rows(_ app: XCUIApplication) -> XCUIElementQuery { app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH %@","card.row.")) }
    func testAddDuplicateCreatesSecondCopy() throws {
        let app = try scanDuplicate()
        let screenshot = XCTAttachment(screenshot:app.screenshot()); screenshot.name = "Exact match with three explicit choices"; screenshot.lifetime = .keepAlways; add(screenshot)
        app.buttons["scan.duplicate.add"].tap()
        XCTAssertTrue(app.buttons["collection.add"].waitForExistence(timeout:10))
        XCTAssertEqual(rows(app).count,2)
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["collection.add"].waitForExistence(timeout:20)); XCTAssertEqual(rows(app).count,2)
    }
    func testOverwriteKeepsOneCopyAndOwnerValue() throws {
        let app = try scanDuplicate()
        app.buttons["scan.duplicate.overwrite"].tap()
        XCTAssertTrue(app.buttons["collection.add"].waitForExistence(timeout:10))
        XCTAssertEqual(rows(app).count,1)
        XCTAssertTrue(rows(app).firstMatch.label.contains("12.34"))
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["collection.add"].waitForExistence(timeout:20)); XCTAssertEqual(rows(app).count,1)
        XCTAssertTrue(rows(app).firstMatch.label.contains("12.34"))
    }
    func testDiscardLeavesExistingCopyUntouched() throws {
        let app = try scanDuplicate()
        app.buttons["scan.duplicate.discard"].tap()
        XCTAssertTrue(app.buttons["collection.add"].waitForExistence(timeout:10))
        XCTAssertEqual(rows(app).count,1)
        XCTAssertTrue(rows(app).firstMatch.label.contains("12.34"))
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["collection.add"].waitForExistence(timeout:20)); XCTAssertEqual(rows(app).count,1)
    }
}
