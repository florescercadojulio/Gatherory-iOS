import XCTest

final class EventDateOrderingUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor
    func testEventsAndHomeStartWithUpcomingDatesInLightAndDark() throws {
        for appearance in ["light", "dark"] {
            let app = XCUIApplication()
            app.launchArguments = [
                "-DisableProductionFlowSimulation", "-SkipAuthentication", "-SeedDevelopmentData",
                "-UseEphemeralDataStore", "-UseProductionOnboarding", "-EventDateOrderingUITest",
                "-AppleLanguages", "(en)", "-AppleInterfaceStyle", appearance,
                "-appAppearance", appearance, "-home.layout", "overview"
            ]
            app.launch()
            let eventButtons = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "events.event."))
            let firstEvent = eventButtons.firstMatch
            XCTAssertTrue(firstEvent.waitForExistence(timeout: 10))
            XCTAssertTrue(firstEvent.label.contains("Next gathering"),
                          "The Events tab should lead with the nearest upcoming gathering, not insertion order.")
            firstEvent.tap()

            let overview = app.scrollViews["home.overview"]
            XCTAssertTrue(overview.waitForExistence(timeout: 6))
            let main = app.buttons["home.overview.mainEvent"]
            XCTAssertTrue(main.exists)
            XCTAssertTrue(main.label.contains("Next gathering"))
            let groups = overview.scrollViews.matching(NSPredicate(format: "identifier BEGINSWITH %@", "home.overview.day."))
            XCTAssertEqual(groups.count, 5)
            XCTAssertTrue(groups.element(boundBy: 0).buttons.firstMatch.label.contains("Today session"))
            XCTAssertTrue(groups.element(boundBy: 1).buttons.firstMatch.label.contains("Morning session"),
                          "Events on the same day should remain in time order.")
            XCTAssertTrue(groups.element(boundBy: 2).buttons.firstMatch.label.contains("Later session"))
            XCTAssertTrue(groups.element(boundBy: 3).buttons.firstMatch.label.contains("Yesterday session"))
            XCTAssertTrue(groups.element(boundBy: 4).buttons.firstMatch.label.contains("Old session"))
            XCTAssertLessThan(main.frame.minY, groups.element(boundBy: 0).frame.minY,
                              "The main event stays above the date-sorted schedule.")

            // Launch each layout independently: launch-argument preferences
            // intentionally override changes made through the settings picker.
            app.terminate()
            app.launchArguments = app.launchArguments.map { $0 == "overview" ? "cards" : $0 }
            app.launch()
            XCTAssertTrue(firstEvent.waitForExistence(timeout: 10))
            firstEvent.tap()
            XCTAssertTrue(app.buttons["home.event.main"].waitForExistence(timeout: 6))
            app.swipeUp()
            let firstChild = app.buttons.matching(identifier: "home.event.child").firstMatch
            XCTAssertTrue(firstChild.waitForExistence(timeout: 6))
            XCTAssertTrue(firstChild.label.contains("Today session"),
                          "The alternate Cards view should use the same date order.")
            app.terminate()
        }
    }
}
