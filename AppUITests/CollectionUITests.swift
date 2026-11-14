import XCTest

@MainActor final class CollectionUITests: XCTestCase {
    func testManualCardSurvivesAppRestart() async throws {
        let app = XCUIApplication()
        app.launchEnvironment["CARD_LEDGER_UI_TEST_STORE"] = UUID().uuidString
        app.launch()
        XCTAssertTrue(app.buttons["collection.add"].waitForExistence(timeout: 20))
        app.buttons["collection.add"].tap()
        let player = app.textFields["card.player"]
        // Identity fields follow the photo section; scroll until the field is reachable.
        for _ in 0..<4 where !player.isHittable { app.swipeUp() }
        XCTAssertTrue(player.waitForExistence(timeout: 5))
        player.tap(); player.typeText("UI Rookie")
        app.buttons["card.save"].tap()
        let saved = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "UI Rookie")).firstMatch
        XCTAssertTrue(saved.waitForExistence(timeout: 10))
        app.terminate(); app.launch()
        XCTAssertTrue(saved.waitForExistence(timeout: 20))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Saved Card Ledger collection"; screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
