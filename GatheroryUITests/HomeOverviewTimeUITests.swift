import XCTest

final class HomeOverviewTimeUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testOverviewShowsMainAndChildTimeRangesInLightAndDark() throws {
        for appearance in ["Light", "Dark"] {
            let app = XCUIApplication()
            app.launchArguments += [
                "-DisableProductionFlowSimulation", "-SkipAuthentication",
                "-SeedDevelopmentData", "-UseEphemeralDataStore",
                "-UseProductionOnboarding", "-AppleLanguages", "(en)",
                "-AppleInterfaceStyle", appearance, "-appAppearance", appearance.lowercased()
            ]
            app.launch()
            defer { app.terminate() }

            let workspace = app.buttons.matching(
                NSPredicate(format: "label BEGINSWITH %@", "Alex & Jordan")
            ).firstMatch
            XCTAssertTrue(workspace.waitForExistence(timeout: 8))
            workspace.tap()

            HomeLayoutUITestSupport.select("Overview", in: app)

            let mainCard = app.descendants(matching: .any)["home.overview.mainEvent"]
            XCTAssertTrue(mainCard.waitForExistence(timeout: 5))
            XCTAssertTrue(mainCard.label.contains("AM") || mainCard.label.contains("PM"),
                          "The main event accessibility label should include its scheduled time: \(mainCard.label)")
            attach(app, name: "Overview main schedule — \(appearance)")
            mainCard.tap()
            XCTAssertTrue(app.navigationBars["Invitation"].waitForExistence(timeout: 5))
            app.navigationBars.buttons.firstMatch.tap()

            let ceremonyCard = app.buttons.matching(
                NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@",
                            "home.overview.event.", "Ceremony")
            ).firstMatch
            XCTAssertTrue(ceremonyCard.waitForExistence(timeout: 5))
            XCTAssertTrue(ceremonyCard.label.contains("4:00") && ceremonyCard.label.contains("4:30"),
                          "The child event accessibility label should include its complete time range: \(ceremonyCard.label)")

            let overview = app.scrollViews["home.overview"]
            for _ in 0..<8 where !ceremonyCard.isHittable { overview.swipeUp() }
            XCTAssertTrue(ceremonyCard.isHittable)
            let tabs = app.tabBars.firstMatch
            for _ in 0..<4 where ceremonyCard.frame.maxY > tabs.frame.minY - 12 {
                overview.swipeUp()
            }
            XCTAssertLessThanOrEqual(ceremonyCard.frame.maxY, tabs.frame.minY,
                                     "The full card including the visible time range should be above the tabs.")
            attach(app, name: "Overview child time range — \(appearance)")
            ceremonyCard.tap()
            XCTAssertTrue(app.navigationBars["Invitation"].waitForExistence(timeout: 5))
        }
    }

    @MainActor
    func testTimedMainOverviewKeepsBothEndpointsInLightAndDark() throws {
        for appearance in ["Light", "Dark"] {
            let app = XCUIApplication()
            app.launchArguments = [
                "-DisableProductionFlowSimulation", "-SkipAuthentication",
                "-SeedDevelopmentData", "-UseEphemeralDataStore",
                "-UseBirthdayMarketingFixture", "-UseProductionOnboarding",
                "-AppleLanguages", "(en)", "-AppleInterfaceStyle", appearance,
                "-appAppearance", appearance.lowercased()
            ]
            app.launch()
            defer { app.terminate() }
            let workspace = app.buttons.matching(
                NSPredicate(format: "label CONTAINS %@", "Maya’s Birthday Dinner")
            ).firstMatch
            XCTAssertTrue(workspace.waitForExistence(timeout: 10))
            workspace.tap()
            HomeLayoutUITestSupport.select("Overview", in: app)
            let main = app.buttons["home.overview.mainEvent"]
            XCTAssertTrue(main.waitForExistence(timeout: 5))
            XCTAssertTrue(main.label.contains("6:30") && main.label.contains("10:00"),
                          "The main card should retain both scheduled endpoints: \(main.label)")
            attach(app, name: "Overview main time range — \(appearance)")
        }
    }

    @MainActor
    private func attach(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
