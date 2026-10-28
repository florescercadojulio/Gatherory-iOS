import XCTest

final class DecisionCardLayoutUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLongIdeaFitsAboveTabsAndFullTextRemainsAvailableInLightAndDark() throws {
        for appearance in ["Light", "Dark"] {
            let app = XCUIApplication()
            app.launchArguments = [
                "-DisableProductionFlowSimulation", "-SkipAuthentication",
                "-SeedDevelopmentData", "-UseEphemeralDataStore",
                "-UseProductionOnboarding", "-LongDecisionCardUITest",
                "-hasSeenDecideTimelinePrimer", "YES", "-AppleLanguages", "(en)",
                "-AppleInterfaceStyle", appearance, "-appAppearance", appearance.lowercased()
            ]
            app.launch()
            defer { app.terminate() }
            let workspace = app.buttons.matching(
                NSPredicate(format: "label CONTAINS %@", "IBM TechXchange 2026")
            ).firstMatch
            XCTAssertTrue(workspace.waitForExistence(timeout: 8))
            workspace.tap()
            let tabs = app.tabBars.firstMatch
            XCTAssertTrue(tabs.buttons["Decide"].waitForExistence(timeout: 5))
            tabs.buttons["Decide"].tap()
            let card = app.buttons["decision-card-11111111-1111-4111-8111-111111111111"]
            XCTAssertTrue(card.waitForExistence(timeout: 5))
            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.name = "Long decision card — \(appearance)"
            attachment.lifetime = .keepAlways
            add(attachment)
            XCTAssertTrue(card.isHittable)
            XCTAssertGreaterThan(card.frame.height, 100)
            XCTAssertGreaterThanOrEqual(card.frame.minY, app.navigationBars.firstMatch.frame.maxY - 1,
                                        "The resting card must stay below the navigation toolbar.")
            XCTAssertLessThanOrEqual(card.frame.maxY, tabs.frame.minY + 1,
                                     "Long content must not push the resting card behind the tabs.")

            card.tap()
            XCTAssertTrue(app.buttons["Edit idea"].waitForExistence(timeout: 5),
                          "The bounded preview must still open the existing idea detail screen.")
            let fullNote = app.staticTexts.matching(NSPredicate(
                format: "label CONTAINS %@", "not a claim about its ERP or application architecture."
            )).firstMatch
            XCTAssertTrue(fullNote.waitForExistence(timeout: 5),
                          "The complete note must remain available beyond the deck preview.")

            app.navigationBars.buttons.firstMatch.tap()
            XCTAssertTrue(card.waitForExistence(timeout: 5))
            card.swipeRight()
            let undo = app.buttons["Undo last decision"]
            XCTAssertTrue(undo.waitForExistence(timeout: 5),
                          "Bounding the preview must preserve the native deck's swipe decision.")
            XCTAssertTrue(card.waitForNonExistence(timeout: 3))
            undo.tap()
            XCTAssertTrue(card.waitForExistence(timeout: 5),
                          "Undo must restore the same long card within the deck.")
        }
    }
}
