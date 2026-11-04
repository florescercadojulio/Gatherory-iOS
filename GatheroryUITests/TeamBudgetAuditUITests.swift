import XCTest

final class TeamBudgetAuditUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor
    func testHostCanOpenWorkspaceBudgetAndAllocationEditorThenReturnToManage() throws {
        let app = launch(appearance: "Light")
        defer {
            attachFailureDiagnostics(from: app)
            app.terminate()
        }
        openMainManage(in: app)
        app.buttons["manage.budget.open"].tap()

        let budget = app.scrollViews["budget.detail"]
        XCTAssertTrue(budget.waitForExistence(timeout: 6))
        XCTAssertTrue(app.staticTexts["Tracked cost"].exists)
        XCTAssertFalse(app.staticTexts["Total Spent"].exists)
        let scope = app.buttons["budget.scope.toggle"]
        for _ in 0..<10 where !scope.isHittable { budget.swipeUp() }
        XCTAssertTrue(scope.isHittable)
        scope.tap()
        XCTAssertEqual(budget.value as? String, "All event budgets")

        // The allocation rows are user-facing buttons in the workspace rollup.
        let rootBudget = budget.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "Alex & Jordan’s Wedding")
        ).firstMatch
        for _ in 0..<8 where !rootBudget.isHittable { budget.swipeUp() }
        XCTAssertTrue(rootBudget.isHittable, "The workspace root allocation should be available to its manager.")
        rootBudget.tap()
        XCTAssertTrue(app.navigationBars["Event Budget"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Current Allocation"].exists)
        let allocationField = allocationAmountField(in: app)
        XCTAssertTrue(allocationField.waitForExistence(timeout: 3), "New Allocation field missing from the sheet AX tree:\n\(app.debugDescription)")
        let originalAllocation = allocationField.value as? String ?? ""
        XCTAssertFalse(originalAllocation.isEmpty)
        allocationField.tap()
        allocationField.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: originalAllocation.count) + "1234")
        app.buttons["Cancel"].tap()
        XCTAssertTrue(budget.waitForExistence(timeout: 5))
        rootBudget.tap()
        let reopenedAllocation = allocationAmountField(in: app)
        XCTAssertTrue(reopenedAllocation.waitForExistence(timeout: 5), "New Allocation field missing after reopening:\n\(app.debugDescription)")
        XCTAssertEqual(reopenedAllocation.value as? String, originalAllocation,
                       "Cancel should discard the unsaved allocation draft.")
        app.buttons["Cancel"].tap()
        XCTAssertTrue(budget.waitForExistence(timeout: 5))

        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.scrollViews["event.management.dashboard"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.navigationBars.staticTexts["Alex & Jordan’s Wedding"].exists)
    }

    @MainActor
    func testReadOnlyCollaboratorCanViewBudgetButCannotOpenAllocationEditing() throws {
        let app = launch(appearance: "Dark", readOnly: true)
        defer {
            attachFailureDiagnostics(from: app)
            app.terminate()
        }
        openMainManage(in: app)
        app.buttons["manage.budget.open"].tap()

        let budget = app.scrollViews["budget.detail"]
        XCTAssertTrue(budget.waitForExistence(timeout: 6))
        XCTAssertTrue(app.staticTexts["Spending Status"].waitForExistence(timeout: 5))
        let scope = app.buttons["budget.scope.toggle"]
        for _ in 0..<10 where !scope.isHittable { budget.swipeUp() }
        XCTAssertTrue(scope.isHittable)
        scope.tap()
        XCTAssertEqual(budget.value as? String, "All event budgets")

        let rootBudget = budget.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "Alex & Jordan’s Wedding")
        ).firstMatch
        for _ in 0..<10 where !rootBudget.isHittable { budget.swipeUp() }
        XCTAssertTrue(rootBudget.exists, "A read-only planner should still see team budget allocation data.")
        XCTAssertFalse(rootBudget.isEnabled, "A read-only planner must not be able to edit an allocation.")
        XCTAssertFalse(app.navigationBars["Event Budget"].exists)
    }

    @MainActor
    private func openMainManage(in app: XCUIApplication) {
        XCTAssertTrue(app.buttons["Filter events"].waitForExistence(timeout: 10))
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Alex & Jordan")).firstMatch.tap()
        XCTAssertTrue(app.buttons["home.manage.main"].waitForExistence(timeout: 8))
        app.buttons["home.manage.main"].tap()
        XCTAssertTrue(app.scrollViews["event.management.dashboard"].waitForExistence(timeout: 6))
    }

    @MainActor
    private func allocationAmountField(in app: XCUIApplication) -> XCUIElement {
        let field = app.textFields.matching(
            NSPredicate(format: "label CONTAINS %@ OR placeholderValue == %@", "New Allocation", "Amount")
        ).firstMatch
        for _ in 0..<4 where !field.exists { app.swipeUp() }
        return field
    }

    @MainActor
    private func launch(appearance: String, readOnly: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-DisableProductionFlowSimulation", "-SkipAuthentication", "-SeedDevelopmentData",
            "-UseEphemeralDataStore", "-UseProductionOnboarding", "-AppleLanguages", "(en)",
            "-AppleInterfaceStyle", appearance.lowercased(), "-appAppearance", appearance.lowercased(),
            "-home.layout", "overview"
        ]
        if readOnly { app.launchArguments.append("-ReadOnlyCollaboratorsUITest") }
        app.launch()
        return app
    }

    @MainActor
    private func attachFailureDiagnostics(from app: XCUIApplication) {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Team budget audit final UI"
        screenshot.lifetime = .deleteOnSuccess
        add(screenshot)

        let accessibilityTree = XCTAttachment(string: app.debugDescription)
        accessibilityTree.name = "Team budget audit final accessibility tree"
        accessibilityTree.lifetime = .deleteOnSuccess
        add(accessibilityTree)
    }
}
