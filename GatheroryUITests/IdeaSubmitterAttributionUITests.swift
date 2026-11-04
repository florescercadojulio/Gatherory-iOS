import XCTest

final class IdeaSubmitterAttributionUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testSeededAuthorAttributionRemainsVisibleFromIdeasAndDecide() throws {
        for appearance in ["Light", "Dark"] {
            for entryPoint in ["Ideas", "Decide"] {
                let app = fixtureApplication(appearance: appearance)
                app.launch()
                defer { app.terminate() }

                let workspace = app.buttons.matching(
                    NSPredicate(format: "label CONTAINS %@", "Maya’s Birthday Dinner")
                ).firstMatch
                XCTAssertTrue(workspace.waitForExistence(timeout: 8),
                              "The birthday workspace fixture should be available.")
                workspace.tap()

                let entryControl = app.buttons[entryPoint]
                XCTAssertTrue(entryControl.waitForExistence(timeout: 5),
                              "The \(entryPoint) workspace control should be available.")
                entryControl.tap()

                let idea = app.buttons.matching(
                    NSPredicate(format: "label CONTAINS %@", "Candlelit birthday table")
                ).firstMatch
                XCTAssertTrue(idea.waitForExistence(timeout: 8),
                              "The seeded idea authored by Riley should be visible in \(entryPoint).")
                if entryPoint == "Ideas" {
                    let ideasScroll = app.scrollViews.firstMatch
                    for _ in 0..<8 where !idea.isHittable { ideasScroll.swipeUp() }
                }
                XCTAssertTrue(idea.isHittable,
                              "The seeded idea should be reachable without changing its decision state.")
                idea.tap()

                let attribution = app.staticTexts["Suggested by Riley Kim"]
                XCTAssertTrue(attribution.waitForExistence(timeout: 8),
                              "The idea detail should attribute the idea to the account recorded by its stable author ID.")
                XCTAssertTrue(app.buttons["Edit idea"].waitForExistence(timeout: 5),
                              "Author attribution should leave the existing idea detail action available.")
            }
        }
    }

    @MainActor
    private func fixtureApplication(appearance: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-DisableProductionFlowSimulation",
            "-SkipAuthentication",
            "-SeedDevelopmentData",
            "-UseEphemeralDataStore",
            "-UseBirthdayMarketingFixture",
            "-UseProductionOnboarding",
            "-hasSeenDecideTimelinePrimer", "YES",
            "-AppleLanguages", "(en)",
            "-AppleInterfaceStyle", appearance,
            "-appAppearance", appearance.lowercased()
        ]
        return app
    }
}
