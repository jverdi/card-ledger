import XCTest

@MainActor final class CollectionUITests: XCTestCase {
    func testAutomaticScanAddsCardAndFormOnlyEdits() async throws {
        let app = XCUIApplication()
        app.launchEnvironment["CARD_LEDGER_UI_TEST_STORE"] = UUID().uuidString
        app.launchEnvironment["CARD_LEDGER_SCAN_FIXTURE"] = "1"
        app.launch()
        XCTAssertTrue(app.buttons["collection.add"].waitForExistence(timeout:20))
        app.buttons["collection.add"].tap()
        XCTAssertTrue(app.staticTexts["Scan front of card"].waitForExistence(timeout:5))
        let guide = XCTAttachment(screenshot:app.screenshot()); guide.name = "Vibrant vector scanning guide"; guide.lifetime = .keepAlways; add(guide)
        XCTAssertFalse(app.textFields["card.player"].exists)
        XCTAssertTrue(app.staticTexts["scan.frontConfirmation"].waitForExistence(timeout:15))
        let confirmation = XCTAttachment(screenshot:app.screenshot()); confirmation.name = "Obvious front captured confirmation"; confirmation.lifetime = .keepAlways; add(confirmation)
        XCTAssertTrue(app.staticTexts["Scan back of card"].waitForExistence(timeout:10))
        XCTAssertTrue(app.staticTexts["Front captured"].exists)
        let backGuide = XCTAttachment(screenshot:app.screenshot()); backGuide.name = "Back scan with persistent front confirmation"; backGuide.lifetime = .keepAlways; add(backGuide)
        XCTAssertTrue(app.staticTexts["UI Rookie"].waitForExistence(timeout:20))
        XCTAssertTrue(app.otherElements["scan.cardReveal"].exists || app.images["scan.cardReveal"].exists || app.descendants(matching:.any)["scan.cardReveal"].exists)
        let reveal = XCTAttachment(screenshot:app.screenshot()); reveal.name = "Two-sided holographic reveal"; reveal.lifetime = .keepAlways; add(reveal)
        let row = app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH %@","card.row.")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout:30))
        row.tap()
        let player = app.textFields["card.player"]
        for _ in 0..<5 where !player.isHittable { app.swipeUp() }
        XCTAssertEqual(player.value as? String,"UI Rookie")
        player.tap(); player.typeText(" Edited")
        app.buttons["card.save"].tap()
        app.terminate(); app.launch()
        XCTAssertTrue(row.waitForExistence(timeout:20))
        XCTAssertTrue(row.label.contains("UI Rookie Edited"))
        let shot = XCTAttachment(screenshot:app.screenshot()); shot.name = "Automatic scan collection"; shot.lifetime = .keepAlways; add(shot)
    }
}
