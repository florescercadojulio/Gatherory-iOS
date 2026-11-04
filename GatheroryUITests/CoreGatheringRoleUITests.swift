import XCTest

final class CoreGatheringRoleUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testGuestFixtureRemainsGuestThroughHomeAndInvitation() throws {
        let app = launch(roleFixture: "-MainInvitationGuestUITest")
        defer {
            attachDiagnostics(from: app, label: "Guest role fixture")
            app.terminate()
        }

        openSeededWorkspace(in: app)
        let main = rootEventButton(in: app)
        XCTAssertTrue(main.waitForExistence(timeout: 6), app.debugDescription)
        XCTAssertEqual(homeManagementButtons(in: app).count, 0,
                       "The guest fixture should not expose Home event management.\n\(app.debugDescription)")
        main.tap()
        XCTAssertTrue(app.navigationBars["Invitation"].waitForExistence(timeout: 6), app.debugDescription)
        assertInvitationIsReadOnly(in: app)
    }

    @MainActor
    func testReadOnlyFixtureRemainsReadOnlyThroughHomeAndInvitation() throws {
        let app = launch(roleFixture: "-ReadOnlyCollaboratorsUITest")
        defer {
            attachDiagnostics(from: app, label: "Read-only role fixture")
            app.terminate()
        }

        openSeededWorkspace(in: app)
        let main = rootEventButton(in: app)
        XCTAssertTrue(main.waitForExistence(timeout: 6), app.debugDescription)
        XCTAssertTrue(app.buttons["home.manage.main"].exists,
                      "Read-only collaborators retain access to view the event dashboard.")
        main.tap()
        XCTAssertTrue(app.navigationBars["Invitation"].waitForExistence(timeout: 6), app.debugDescription)
        assertInvitationIsReadOnly(in: app)
    }

    @MainActor
    private func openSeededWorkspace(in app: XCUIApplication) {
        XCTAssertTrue(app.buttons["Filter events"].waitForExistence(timeout: 10), app.debugDescription)
        let workspace = app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "Alex & Jordan")
        ).firstMatch
        XCTAssertTrue(workspace.waitForExistence(timeout: 8), app.debugDescription)
        workspace.tap()
        XCTAssertTrue(app.scrollViews["home.overview"].waitForExistence(timeout: 8), app.debugDescription)
    }

    @MainActor
    private func rootEventButton(in app: XCUIApplication) -> XCUIElement {
        let overviewMain = app.buttons["home.overview.mainEvent"]
        if overviewMain.waitForExistence(timeout: 3) { return overviewMain }
        return app.buttons["home.event.main"]
    }

    @MainActor
    private func homeManagementButtons(in app: XCUIApplication) -> XCUIElementQuery {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "home.manage."))
    }

    @MainActor
    private func assertInvitationIsReadOnly(in app: XCUIApplication) {
        XCTAssertFalse(app.buttons["invitation.edit.title"].exists, app.debugDescription)
        XCTAssertFalse(app.buttons["invitation.edit.date"].exists, app.debugDescription)
        XCTAssertFalse(app.buttons["invitation.edit.location"].exists, app.debugDescription)
        XCTAssertFalse(app.buttons["invitation-share-invitation"].exists, app.debugDescription)
        XCTAssertFalse(app.buttons["invitation.manage"].exists, app.debugDescription)
        XCTAssertFalse(app.tabBars.buttons["Manage"].exists, app.debugDescription)
    }

    @MainActor
    private func launch(roleFixture: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-DisableProductionFlowSimulation",
            "-SkipAuthentication",
            "-SeedDevelopmentData",
            "-UseEphemeralDataStore",
            "-UseProductionOnboarding",
            "-home.layout", "overview",
            "-AppleLanguages", "(en)"
        ]
        app.launchArguments.append(roleFixture)
        app.launch()
        return app
    }

    @MainActor
    private func attachDiagnostics(from app: XCUIApplication, label: String) {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "\(label) screenshot"
        screenshot.lifetime = .deleteOnSuccess
        add(screenshot)

        let accessibilityTree = XCTAttachment(
            data: Data(app.debugDescription.utf8),
            uniformTypeIdentifier: "public.plain-text"
        )
        accessibilityTree.name = "\(label) accessibility tree"
        accessibilityTree.lifetime = .deleteOnSuccess
        add(accessibilityTree)
    }
}
