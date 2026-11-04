import XCTest

final class BudgetConflictRecoveryUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testCancelKeepsConflictAndUsingSharedBudgetPreservesTitle() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-DisableProductionFlowSimulation",
            "-SkipAuthentication",
            "-UseEphemeralDataStore",
            "-BudgetConflictUITest",
            "-UseProductionOnboarding",
            "-AppleLanguages", "(en)",
            "-AppleInterfaceStyle", "dark", "-appAppearance", "dark",
            "-home.layout", "overview"
        ]
        app.launch()
        defer { app.terminate() }

        let workspace = app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "Local event title")
        ).firstMatch
        XCTAssertTrue(workspace.waitForExistence(timeout: 10), "The synthetic budget workspace should open in the library.")
        workspace.tap()

        let manage = app.buttons["home.manage.main"]
        XCTAssertTrue(manage.waitForExistence(timeout: 6), "The overview should expose management for this workspace.")
        manage.tap()
        XCTAssertTrue(app.scrollViews["event.management.dashboard"].waitForExistence(timeout: 6))
        app.buttons["manage.budget.open"].tap()

        let budget = app.scrollViews["budget.detail"]
        XCTAssertTrue(budget.waitForExistence(timeout: 6))
        XCTAssertEqual(budget.value as? String, "Local event title")
        let accountButton = app.navigationBars["Budget"].buttons["Account and settings"]
        XCTAssertTrue(accountButton.waitForExistence(timeout: 5))
        accountButton.tap()
        XCTAssertTrue(app.navigationBars["Account"].waitForExistence(timeout: 6))

        let useShared = app.buttons["account.budget.useShared"]
        for _ in 0..<8 where !useShared.isHittable { app.swipeUp() }
        XCTAssertTrue(useShared.waitForExistence(timeout: 6), "Account should list the unresolved budget conflict.")
        XCTAssertTrue(useShared.isEnabled, "The shared vector should be available: \(app.debugDescription)")
        useShared.tap()
        let confirmation = app.alerts["Use the shared budget?"]
        XCTAssertTrue(confirmation.waitForExistence(timeout: 4), app.debugDescription)
        let cancel = confirmation.buttons["Cancel"]
        XCTAssertTrue(cancel.exists, app.debugDescription)
        cancel.tap()
        XCTAssertTrue(useShared.waitForExistence(timeout: 4), "Cancel should leave the conflict available for review.")

        useShared.tap()
        let confirm = confirmation.buttons["Use shared budget"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 4))
        confirm.tap()
        let conflictRow = app.buttons["account.budget.useShared"]
        let cleared = NSPredicate(format: "exists == false")
        expectation(for: cleared, evaluatedWith: conflictRow)
        waitForExpectations(timeout: 6)

        app.buttons["Done"].tap()
        XCTAssertTrue(budget.waitForExistence(timeout: 5))
        XCTAssertEqual(budget.value as? String, "Local event title",
                       "Resolving the budget conflict must preserve the local event title edit.")
        let overview = app.buttons["budget.scope.toggle"]
        for _ in 0..<8 where !overview.isHittable { budget.swipeUp() }
        XCTAssertTrue(overview.isHittable)
        overview.tap()
        XCTAssertEqual(budget.value as? String, "All event budgets")

        let rootAllocation = app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", "Local event title", "$600")
        ).firstMatch
        let childAllocation = app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", "Dinner", "$400")
        ).firstMatch
        for _ in 0..<8 where (!rootAllocation.isHittable || !childAllocation.isHittable) { budget.swipeUp() }
        XCTAssertTrue(rootAllocation.exists, "The shared root allocation should be restored to $600.")
        XCTAssertTrue(childAllocation.exists, "The shared child allocation should be restored to $400.")
    }
}
