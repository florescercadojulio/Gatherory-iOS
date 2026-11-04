import XCTest

final class CoreGatheringCoordinationUITests: XCTestCase {
    private let mainTitle = "Alex & Jordan’s Wedding"
    private let childTitle = "Ceremony"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testTasksCreateEditCompleteAndReopenInExactMainAndChildEvents() throws {
        let app = launch()
        defer {
            attachFailureDiagnostics(from: app)
            app.terminate()
        }
        openWorkspace(in: app)

        let mainTask = "Main task for coordination audit"
        let editedMainTask = "Updated main task for coordination audit"
        openManage(reference: "home.manage.main", in: app)
        openTasks(in: app)
        addTask(mainTask, eventTitle: mainTitle, in: app)
        editTask(mainTask, as: editedMainTask, in: app)
        completeAndReopen(editedMainTask, in: app)

        returnToHome(in: app)
        let childReference = childManagementReference(in: app)
        openManage(reference: childReference, in: app)
        openTasks(in: app)
        XCTAssertFalse(taskTitleExists(mainTask, in: app),
                       "A main-event task must not appear in the child event's list.")
        XCTAssertFalse(taskTitleExists(editedMainTask, in: app),
                       "Editing a main-event task must not copy it into a child event.")

        let childTask = "Child task for coordination audit"
        let editedChildTask = "Updated child task for coordination audit"
        addTask(childTask, eventTitle: childTitle, in: app)
        editTask(childTask, as: editedChildTask, in: app)
        completeAndReopen(editedChildTask, in: app)

        returnToHome(in: app)
        openManage(reference: "home.manage.main", in: app)
        openTasks(in: app)
        XCTAssertTrue(taskTitleExists(editedMainTask, in: app),
                      "The edited and reopened main task should remain with its root event.")
        XCTAssertFalse(taskTitleExists(editedChildTask, in: app),
                       "A child-event task must not appear in the root event's list.")
    }

    @MainActor
    private func addTask(_ title: String, eventTitle: String, in app: XCUIApplication,
                         file: StaticString = #filePath, line: UInt = #line) {
        app.buttons["Add a To-do"].tap()
        XCTAssertTrue(app.navigationBars["New To-do"].waitForExistence(timeout: 5), file: file, line: line)
        let destination = app.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", "Adding this to-do to", eventTitle)
        ).firstMatch
        XCTAssertTrue(destination.waitForExistence(timeout: 5),
                      "The editor should identify its exact event destination.", file: file, line: line)
        let titleField = todoTitleField(in: app)
        XCTAssertTrue(titleField.waitForExistence(timeout: 5), file: file, line: line)
        titleField.tap()
        titleField.typeText(title)
        app.navigationBars.buttons["Add"].tap()
        XCTAssertTrue(app.buttons[title].waitForExistence(timeout: 5),
                      "The saved task should appear in Upcoming.", file: file, line: line)
    }

    @MainActor
    private func editTask(_ original: String, as edited: String, in app: XCUIApplication,
                          file: StaticString = #filePath, line: UInt = #line) {
        let row = app.buttons.matching(NSPredicate(format: "label == %@", original)).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), "The task row should open its editor.", file: file, line: line)
        row.tap()
        XCTAssertTrue(app.navigationBars["Edit To-do"].waitForExistence(timeout: 5), file: file, line: line)
        let titleField = todoTitleField(in: app, currentTitle: original)
        XCTAssertTrue(titleField.waitForExistence(timeout: 5), file: file, line: line)
        replaceText(in: titleField, with: edited)
        app.navigationBars.buttons["Save"].tap()
        XCTAssertTrue(app.buttons[edited].waitForExistence(timeout: 5),
                      "The edited task title should be visible after saving.", file: file, line: line)
        XCTAssertFalse(app.buttons[original].exists, file: file, line: line)
    }

    @MainActor
    private func completeAndReopen(_ title: String, in app: XCUIApplication,
                                   file: StaticString = #filePath, line: UInt = #line) {
        let markComplete = app.buttons["Mark Complete: \(title)"]
        XCTAssertTrue(markComplete.waitForExistence(timeout: 5), file: file, line: line)
        markComplete.tap()

        app.buttons["Completed"].tap()
        let markIncomplete = app.buttons["Mark Incomplete: \(title)"]
        XCTAssertTrue(markIncomplete.waitForExistence(timeout: 5),
                      "Completed should contain the task and offer reopening it.", file: file, line: line)
        XCTAssertEqual(markIncomplete.value as? String, "Completed", file: file, line: line)
        markIncomplete.tap()

        app.buttons["Upcoming"].tap()
        XCTAssertTrue(app.buttons[title].waitForExistence(timeout: 5),
                      "Reopening the task should return it to Upcoming.", file: file, line: line)
        app.buttons["Completed"].tap()
        XCTAssertFalse(app.buttons["Mark Incomplete: \(title)"].exists,
                       "The reopened task should no longer appear in Completed.", file: file, line: line)
        app.buttons["Upcoming"].tap()
    }

    @MainActor
    private func openTasks(in app: XCUIApplication,
                           file: StaticString = #filePath, line: UInt = #line) {
        let dashboard = app.scrollViews["event.management.dashboard"]
        let tasks = dashboard.buttons.matching(NSPredicate(format: "label CONTAINS %@", "To-dos")).firstMatch
        for _ in 0..<10 where !tasks.isHittable { dashboard.swipeUp() }
        XCTAssertTrue(tasks.isHittable, "The current event's To-dos card should be reachable.", file: file, line: line)
        tasks.tap()
        XCTAssertTrue(app.navigationBars["To-dos"].waitForExistence(timeout: 5), file: file, line: line)
    }

    @MainActor
    private func openManage(reference: String, in app: XCUIApplication,
                            file: StaticString = #filePath, line: UInt = #line) {
        let manage = app.buttons[reference]
        for _ in 0..<10 where !manage.isHittable { app.scrollViews["home.overview"].swipeUp() }
        XCTAssertTrue(manage.isHittable, "The event's Manage action should be reachable.", file: file, line: line)
        manage.tap()
        XCTAssertTrue(app.scrollViews["event.management.dashboard"].waitForExistence(timeout: 5),
                      file: file, line: line)
    }

    @MainActor
    private func childManagementReference(in app: XCUIApplication,
                                          file: StaticString = #filePath, line: UInt = #line) -> String {
        let child = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@",
                        "home.overview.event.", childTitle)
        ).firstMatch
        XCTAssertTrue(child.waitForExistence(timeout: 6), file: file, line: line)
        return "home.manage.subevent-\(child.identifier.dropFirst("home.overview.event.".count))"
    }

    @MainActor
    private func returnToHome(in app: XCUIApplication,
                              file: StaticString = #filePath, line: UInt = #line) {
        let tasksBack = app.navigationBars.buttons.firstMatch
        XCTAssertTrue(tasksBack.waitForExistence(timeout: 5), file: file, line: line)
        tasksBack.tap()
        XCTAssertTrue(app.scrollViews["event.management.dashboard"].waitForExistence(timeout: 5),
                      file: file, line: line)
        let dashboardBack = app.navigationBars.buttons.firstMatch
        XCTAssertTrue(dashboardBack.waitForExistence(timeout: 5), file: file, line: line)
        dashboardBack.tap()
        XCTAssertTrue(app.scrollViews["home.overview"].waitForExistence(timeout: 5), file: file, line: line)
    }

    @MainActor
    private func taskTitleExists(_ title: String, in app: XCUIApplication) -> Bool {
        app.buttons.matching(NSPredicate(format: "label == %@", title)).firstMatch.exists
    }

    @MainActor
    private func todoTitleField(in app: XCUIApplication, currentTitle: String? = nil) -> XCUIElement {
        if let currentTitle {
            let matchingValue = app.textFields.matching(NSPredicate(format: "value == %@", currentTitle)).firstMatch
            return matchingValue.exists ? matchingValue : app.textFields.firstMatch
        }
        return app.textFields["What needs doing?"]
    }

    @MainActor
    private func replaceText(in field: XCUIElement, with replacement: String) {
        let current = field.value as? String ?? ""
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.99, dy: 0.5)).tap()
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count) + replacement)
    }

    @MainActor
    private func openWorkspace(in app: XCUIApplication,
                               file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(app.buttons["Filter events"].waitForExistence(timeout: 10), file: file, line: line)
        let workspace = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Alex & Jordan")).firstMatch
        XCTAssertTrue(workspace.waitForExistence(timeout: 8), file: file, line: line)
        workspace.tap()
        XCTAssertTrue(app.tabBars.buttons["Home"].waitForExistence(timeout: 6), file: file, line: line)
        XCTAssertTrue(app.scrollViews["home.overview"].waitForExistence(timeout: 6), file: file, line: line)
    }

    @MainActor
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-DisableProductionFlowSimulation", "-SkipAuthentication", "-SeedDevelopmentData",
            "-UseEphemeralDataStore", "-UseProductionOnboarding", "-AppleLanguages", "(en)",
            "-home.layout", "overview"
        ]
        app.launch()
        return app
    }

    @MainActor
    private func attachFailureDiagnostics(from app: XCUIApplication) {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Core gathering task coordination final screen"
        screenshot.lifetime = .deleteOnSuccess
        add(screenshot)

        let accessibilityTree = XCTAttachment(
            data: Data(app.debugDescription.utf8),
            uniformTypeIdentifier: "public.plain-text"
        )
        accessibilityTree.name = "Core gathering task coordination accessibility tree"
        accessibilityTree.lifetime = .deleteOnSuccess
        add(accessibilityTree)
    }
}
