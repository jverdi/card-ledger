import XCTest

@MainActor final class CollectionUITests: XCTestCase {
    func testGuidedScanAndSavedCardViewerEditRemove() throws {
        continueAfterFailure = false
        executionTimeAllowance = 180 // Includes cold simulator OCR, relaunch and UI animations.
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
        // Hosted simulators can take over 45 seconds for both faces and four orientations.
        // Stop here on failure instead of issuing invalid UI actions.
        guard app.staticTexts["UI Rookie"].waitForExistence(timeout:90) else {
            XCTFail("Both card faces did not finish recognition")
            return
        }
        XCTAssertTrue(app.otherElements["scan.cardReveal"].exists || app.images["scan.cardReveal"].exists || app.descendants(matching:.any)["scan.cardReveal"].exists)
        XCTAssertTrue(app.buttons["scan.continue"].waitForExistence(timeout:15))
        let reveal = XCTAttachment(screenshot:app.screenshot()); reveal.name = "Two-sided holographic reveal"; reveal.lifetime = .keepAlways; add(reveal)
        let row = app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH %@","card.row.")).firstMatch
        XCTAssertFalse(row.exists)
        app.buttons["scan.continue"].tap()
        XCTAssertTrue(row.waitForExistence(timeout:30))
        row.tap()
        XCTAssertTrue(app.buttons["card.detail.actions"].waitForExistence(timeout:5))
        XCTAssertFalse(app.textFields["card.player"].exists)
        XCTAssertTrue(app.descendants(matching:.any)["card.detail.reveal"].exists)
        let detail = XCTAttachment(screenshot:app.screenshot()); detail.name = "Saved card holographic viewer"; detail.lifetime = .keepAlways; add(detail)
        app.buttons["card.detail.actions"].tap()
        app.buttons["Edit"].tap()
        let player = app.textFields["card.player"]
        for _ in 0..<5 where !player.isHittable { app.swipeUp() }
        XCTAssertEqual(player.value as? String,"UI Rookie")
        player.tap(); player.typeText(" Edited")
        app.buttons["card.save"].tap()
        XCTAssertTrue(app.staticTexts["card.detail.player"].waitForExistence(timeout:5))
        XCTAssertEqual(app.staticTexts["card.detail.player"].label,"UI Rookie Edited")
        app.buttons["card.detail.close"].tap()
        app.terminate(); app.launch()
        XCTAssertTrue(row.waitForExistence(timeout:20))
        XCTAssertTrue(row.label.contains("UI Rookie Edited"))
        row.tap()
        XCTAssertTrue(app.buttons["card.detail.actions"].waitForExistence(timeout:5))
        app.buttons["card.detail.actions"].tap(); app.buttons["Remove"].tap()
        XCTAssertTrue(app.buttons["Remove card"].waitForExistence(timeout:5))
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["card.detail.actions"].exists)
        app.buttons["card.detail.actions"].tap(); app.buttons["Remove"].tap()
        app.buttons["Remove card"].tap()
        XCTAssertTrue(app.buttons["collection.add"].waitForExistence(timeout:5))
        XCTAssertFalse(row.exists)
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["collection.add"].waitForExistence(timeout:20))
        XCTAssertFalse(row.exists)
        let shot = XCTAttachment(screenshot:app.screenshot()); shot.name = "Collection after confirmed removal"; shot.lifetime = .keepAlways; add(shot)
    }
}
