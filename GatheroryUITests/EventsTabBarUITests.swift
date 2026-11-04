import XCTest

final class EventsTabBarUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor
    func testEventsKeepsAllMainTabsExpandedWhileScrollingInLightAndDark() throws {
        for appearance in ["light", "dark"] {
            let app = XCUIApplication()
            app.launchArguments = [
                "-DisableProductionFlowSimulation", "-SkipAuthentication", "-SeedDevelopmentData",
                "-UseEphemeralDataStore", "-UseProductionOnboarding", "-EventDateOrderingUITest",
                "-AppleLanguages", "(en)", "-AppleInterfaceStyle", appearance,
                "-appAppearance", appearance
            ]
            app.launch()
            let events = app.scrollViews["events.list"]
            XCTAssertTrue(events.waitForExistence(timeout: 10))
            let bar = app.tabBars.firstMatch
            XCTAssertTrue(bar.waitForExistence(timeout: 5))
            let expandedHeight = bar.frame.height
            XCTAssertGreaterThan(expandedHeight, 0)

            for _ in 0..<3 {
                events.swipeUp()
                assertExpanded(bar, expectedHeight: expandedHeight)
            }
            bar.buttons["Blueprints"].tap()
            XCTAssertTrue(bar.buttons["Blueprints"].isSelected)
            bar.buttons["Events"].tap()
            XCTAssertTrue(events.waitForExistence(timeout: 5))
            events.swipeDown()
            assertExpanded(bar, expectedHeight: expandedHeight)
            app.terminate()
        }
    }

    @MainActor
    private func assertExpanded(_ bar: XCUIElement, expectedHeight: CGFloat,
                                file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(bar.buttons["Events"].isSelected, file: file, line: line)
        for title in ["Events", "Blueprints", "Explore"] {
            XCTAssertTrue(bar.buttons[title].isHittable,
                          "Events scrolling must leave \(title) directly accessible.", file: file, line: line)
        }
        XCTAssertEqual(bar.frame.height, expectedHeight, accuracy: 2,
                       "The main tab bar should retain its expanded height.", file: file, line: line)
    }
}
