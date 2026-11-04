import XCTest

final class ManageBudgetNavigationUITests: XCTestCase {
    private let mainTitle = "Alex & Jordan’s Wedding"
    private let childTitle = "Ceremony"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testBudgetBackReturnsToTheSameEventDashboardFromOverviewManagement() throws {
        for isChild in [false, true] {
            let app = launch()
            defer { attachFailureDiagnostics(from: app) }
            openWorkspace(in: app)
            HomeLayoutUITestSupport.select("Overview", in: app)

            let eventTitle = isChild ? childTitle : mainTitle
            let managementButton: XCUIElement
            let budgetScope: String
            if isChild {
                let child = app.buttons.matching(
                    NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@",
                                "home.overview.event.", childTitle)
                ).firstMatch
                XCTAssertTrue(child.waitForExistence(timeout: 6))
                let eventID = String(child.identifier.dropFirst("home.overview.event.".count))
                managementButton = app.buttons["home.manage.subevent-\(eventID)"]
                budgetScope = childTitle
            } else {
                managementButton = app.buttons["home.manage.main"]
                budgetScope = mainTitle
            }

            XCTAssertTrue(managementButton.waitForExistence(timeout: 6),
                          "Overview should offer management for the selected event.")
            for _ in 0..<8 where !managementButton.isHittable { app.swipeUp() }
            XCTAssertTrue(managementButton.isHittable,
                          "The selected event's Overview management footer should be reachable.")
            managementButton.tap()

            let dashboard = app.scrollViews["event.management.dashboard"]
            XCTAssertTrue(dashboard.waitForExistence(timeout: 6),
                          "Management should open on the selected event dashboard.")
            XCTAssertTrue(app.navigationBars.staticTexts[eventTitle].exists)

            let budgetButton = app.buttons["manage.budget.open"]
            let budgetDetail = app.scrollViews["budget.detail"]
            for iteration in 0..<2 {
                XCTAssertTrue(budgetButton.waitForExistence(timeout: 5),
                              "The dashboard should expose its Budget card as a single destination.")
                budgetButton.tap()

                XCTAssertTrue(budgetDetail.waitForExistence(timeout: 5),
                              "Opening Budget should show its detail screen.")
                XCTAssertEqual(budgetDetail.value as? String, budgetScope,
                               "Budget should retain the managed event's exact scope.")

                if iteration == 1 {
                    let scopeToggle = app.buttons["budget.scope.toggle"]
                    for _ in 0..<8 where !scopeToggle.isHittable { budgetDetail.swipeUp() }
                    XCTAssertTrue(scopeToggle.isHittable,
                                  "The Budget screen should offer its workspace scope toggle.")
                    scopeToggle.tap()
                    XCTAssertEqual(budgetDetail.value as? String, "All event budgets",
                                   "The scope toggle should show the workspace budget in place.")

                    XCTAssertTrue(scopeToggle.waitForExistence(timeout: 5),
                                  "The scope toggle should keep a stable identifier as its label changes.")
                    for _ in 0..<12 where !scopeToggle.isHittable { budgetDetail.swipeUp() }
                    scopeToggle.tap()
                    XCTAssertEqual(budgetDetail.value as? String, budgetScope,
                                   "Toggling back should restore this event's budget in place.")
                }

                let back = app.navigationBars.buttons.firstMatch
                XCTAssertTrue(back.waitForExistence(timeout: 5))
                back.tap()

                XCTAssertTrue(dashboard.waitForExistence(timeout: 5),
                              "One native back step from Budget should return to the management dashboard.")
                XCTAssertTrue(app.navigationBars.staticTexts[eventTitle].exists)
                XCTAssertFalse(budgetDetail.exists,
                               "The Budget screen should no longer be present after one back step.")
            }

            let homeBack = app.navigationBars.buttons.firstMatch
            XCTAssertTrue(homeBack.waitForExistence(timeout: 5))
            homeBack.tap()
            XCTAssertTrue(app.tabBars.buttons["Home"].waitForExistence(timeout: 5),
                          "Leaving management should return to Home.")
            XCTAssertFalse(dashboard.exists)
        }
    }

    @MainActor
    func testBackFromWorkspaceOverviewReturnsDirectlyToManage() throws {
        let app = launch()
        defer {
            attachFailureDiagnostics(from: app)
            app.terminate()
        }
        openWorkspace(in: app)
        HomeLayoutUITestSupport.select("Overview", in: app)
        let manage = app.buttons["home.manage.main"]
        XCTAssertTrue(manage.waitForExistence(timeout: 6))
        manage.tap()
        let dashboard = app.scrollViews["event.management.dashboard"]
        XCTAssertTrue(dashboard.waitForExistence(timeout: 6))
        app.buttons["manage.budget.open"].tap()
        let budget = app.scrollViews["budget.detail"]
        XCTAssertTrue(budget.waitForExistence(timeout: 6))
        let overview = app.buttons["budget.scope.toggle"]
        for _ in 0..<8 where !overview.isHittable { budget.swipeUp() }
        XCTAssertTrue(overview.isHittable)
        overview.tap()
        XCTAssertEqual(budget.value as? String, "All event budgets")
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(dashboard.waitForExistence(timeout: 5),
                      "Back from the aggregate budget must return directly to Manage, without another Budget screen.")
        XCTAssertFalse(budget.exists)
        XCTAssertTrue(app.navigationBars.staticTexts[mainTitle].exists)
    }

    @MainActor
    private func openWorkspace(in app: XCUIApplication) {
        XCTAssertTrue(app.buttons["Filter events"].waitForExistence(timeout: 10),
                      "The seeded workspace library should open.")
        let workspace = app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "Alex & Jordan")
        ).firstMatch
        XCTAssertTrue(workspace.waitForExistence(timeout: 8))
        workspace.tap()
        XCTAssertTrue(app.tabBars.buttons["Home"].waitForExistence(timeout: 6))
    }

    @MainActor
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-DisableProductionFlowSimulation",
            "-SkipAuthentication",
            "-SeedDevelopmentData",
            "-UseEphemeralDataStore",
            "-UseProductionOnboarding",
            "-AppleLanguages", "(en)"
        ]
        app.launch()
        return app
    }

    @MainActor
    private func attachFailureDiagnostics(from app: XCUIApplication) {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Manage budget navigation final UI"
        screenshot.lifetime = .deleteOnSuccess
        add(screenshot)

        let accessibilityTree = XCTAttachment(string: app.debugDescription)
        accessibilityTree.name = "Manage budget navigation final accessibility tree"
        accessibilityTree.lifetime = .deleteOnSuccess
        add(accessibilityTree)
        app.terminate()
    }
}
