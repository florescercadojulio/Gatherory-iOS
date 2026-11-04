import XCTest

final class EventSimplificationUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testOverviewFallbackAndStatusFreeEventEditorsInLightAndDark() throws {
        for appearance in ["Light", "Dark"] {
            let app = XCUIApplication()
            app.launchArguments = [
                "-DisableProductionFlowSimulation", "-SkipAuthentication",
                "-SeedDevelopmentData", "-UseEphemeralDataStore",
                "-UseProductionOnboarding", "-AppleLanguages", "(en)",
                "-AppleInterfaceStyle", appearance, "-appAppearance", appearance.lowercased(),
                "-home.layout", "unrecognized-layout"
            ]
            app.launch()
            let workspace = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Alex & Jordan")).firstMatch
            XCTAssertTrue(workspace.waitForExistence(timeout: 10))
            workspace.tap()
            XCTAssertTrue(app.scrollViews["home.overview"].waitForExistence(timeout: 6))
            XCTAssertFalse(app.buttons["home.event.main"].exists)

            for isChild in [false, true] {
                let event = isChild
                    ? app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "home.overview.event.", "Ceremony")).firstMatch
                    : app.buttons["home.overview.mainEvent"]
                reveal(event, in: app)
                event.tap()
                XCTAssertTrue(app.navigationBars["Invitation"].waitForExistence(timeout: 6))
                app.buttons["invitation.actions"].tap()
                app.buttons["Edit Event"].tap()
                let field = app.textFields["event.editor.title"]
                XCTAssertTrue(field.waitForExistence(timeout: 6))
                XCTAssertEqual(field.value as? String, isChild ? "Ceremony" : "Alex & Jordan’s Wedding")
                for title in ["Status", "Planning Status"] {
                    XCTAssertFalse(app.buttons[title].exists)
                    XCTAssertFalse(app.pickers[title].exists)
                    XCTAssertFalse(app.staticTexts[title].exists)
                }
                app.buttons["Cancel"].tap()
                XCTAssertTrue(app.navigationBars["Invitation"].waitForExistence(timeout: 6))

                if !isChild {
                    let schedule = app.buttons["invitation.edit.date.info"]
                    reveal(schedule, in: app)
                    XCTAssertTrue(app.buttons["invitation.add-to-calendar"].exists)
                    for zone in ["EDT", "EST", "America/Detroit"] {
                        XCTAssertFalse(app.staticTexts[zone].exists)
                    }
                    schedule.tap()
                    XCTAssertTrue(app.navigationBars["Date and Time"].waitForExistence(timeout: 6))
                    XCTAssertFalse(app.buttons["Time Zone"].exists)
                    XCTAssertFalse(app.pickers["Time Zone"].exists)
                    app.buttons["invitation.edit.date.cancel"].tap()
                    XCTAssertTrue(app.navigationBars["Invitation"].waitForExistence(timeout: 6))
                }
                app.navigationBars.buttons.firstMatch.tap()
                XCTAssertTrue(app.scrollViews["home.overview"].waitForExistence(timeout: 6))
            }
            app.terminate()
        }
    }

    @MainActor
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<10 where !element.isHittable { app.swipeUp() }
        XCTAssertTrue(element.waitForExistence(timeout: 6))
        XCTAssertTrue(element.isHittable)
    }
}
