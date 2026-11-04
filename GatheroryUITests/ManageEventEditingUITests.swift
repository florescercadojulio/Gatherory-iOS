import XCTest

final class ManageEventEditingUITests: XCTestCase {
    private let mainTitle = "Alex & Jordan’s Wedding"
    private let childTitle = "Ceremony"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testManageHasNoEditorGearAndInvitationContentOpensEventEditorInBothAppearances() throws {
        for appearance in ["Light", "Dark"] {
            for isChild in [false, true] {
                let app = launch(appearance: appearance)
                openWorkspace(in: app)

                let manageID = isChild ? childManageID(in: app) : "home.manage.main"
                let manage = app.buttons[manageID]
                XCTAssertTrue(manage.waitForExistence(timeout: 6))
                for _ in 0..<8 where !manage.isHittable { app.swipeUp() }
                XCTAssertTrue(manage.isHittable)
                manage.tap()

                let dashboard = app.scrollViews["event.management.dashboard"]
                XCTAssertTrue(dashboard.waitForExistence(timeout: 6))
                XCTAssertFalse(app.buttons["event.management.settings"].exists,
                               "Event editing should be opened from its detail, not a Manage toolbar gear.")
                app.navigationBars.buttons.firstMatch.tap()
                XCTAssertTrue(app.tabBars.buttons["Home"].isSelected)
                HomeLayoutUITestSupport.select("Cards", in: app)

                let eventCard = isChild
                    ? app.buttons.matching(NSPredicate(format: "identifier == %@ AND label CONTAINS %@",
                                                       "home.event.child", childTitle)).firstMatch
                    : app.buttons["home.event.main"]
                XCTAssertTrue(eventCard.waitForExistence(timeout: 6))
                for _ in 0..<8 where !eventCard.isHittable { app.swipeUp() }
                eventCard.tap()
                XCTAssertTrue(app.navigationBars["Invitation"].waitForExistence(timeout: 6))

                let editableTitle = app.buttons["invitation.edit.title"]
                XCTAssertTrue(editableTitle.waitForExistence(timeout: 6),
                              "The event detail title should be the entry point to editing.")
                editableTitle.tap()
                XCTAssertTrue(app.navigationBars["Edit Event"].waitForExistence(timeout: 6))
                let titleField = isChild
                    ? app.textFields["event.editor.title"]
                    : app.textFields["invitation.edit.title.field"]
                XCTAssertTrue(titleField.waitForExistence(timeout: 6))
                XCTAssertEqual(titleField.value as? String, isChild ? childTitle : mainTitle,
                               "The native editor should be initialized with the event shown in detail.")

                app.buttons[isChild ? "Cancel" : "invitation.edit.title.cancel"].tap()
                XCTAssertTrue(app.navigationBars["Invitation"].waitForExistence(timeout: 6),
                              "Cancel should return to the same event detail.")
                XCTAssertEqual(app.buttons["invitation.edit.title"].label,
                               isChild ? childTitle : mainTitle,
                               "Cancel should leave the event title unchanged.")
                app.navigationBars.buttons.firstMatch.tap()
                XCTAssertTrue(app.tabBars.buttons["Home"].isSelected,
                              "Back from event detail should return directly to Home.")
                XCTAssertFalse(app.scrollViews["event.management.dashboard"].exists)
                app.terminate()
            }
        }
    }

    @MainActor
    func testGuestCannotEditInvitationContentOrOpenManage() throws {
        let app = launch(appearance: "Light", guest: true)
        openWorkspace(in: app, expectsHomeTabs: false)
        HomeLayoutUITestSupport.select("Cards", in: app)
        XCTAssertEqual(app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "home.manage.")
        ).count, 0)

        let main = app.buttons["home.event.main"]
        XCTAssertTrue(main.waitForExistence(timeout: 6))
        for _ in 0..<8 where !main.isHittable { app.swipeUp() }
        XCTAssertTrue(main.isHittable)
        main.tap()
        XCTAssertTrue(app.navigationBars["Invitation"].waitForExistence(timeout: 6))
        XCTAssertFalse(app.buttons["invitation.edit.title"].exists)
        XCTAssertFalse(app.buttons["invitation.edit.date"].exists)
        XCTAssertFalse(app.buttons["invitation.edit.location"].exists)
        app.terminate()
    }

    @MainActor
    private func childManageID(in app: XCUIApplication) -> String {
        HomeLayoutUITestSupport.select("Overview", in: app)
        let child = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@",
                        "home.overview.event.", childTitle)
        ).firstMatch
        XCTAssertTrue(child.waitForExistence(timeout: 6))
        let eventUUID = String(child.identifier.dropFirst("home.overview.event.".count))
        return "home.manage.subevent-\(eventUUID)"
    }

    @MainActor
    private func openWorkspace(in app: XCUIApplication, expectsHomeTabs: Bool = true) {
        XCTAssertTrue(app.buttons["Filter events"].waitForExistence(timeout: 10))
        let workspace = app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "Alex & Jordan")
        ).firstMatch
        XCTAssertTrue(workspace.waitForExistence(timeout: 8))
        workspace.tap()
        if expectsHomeTabs {
            XCTAssertTrue(app.tabBars.buttons["Home"].waitForExistence(timeout: 6))
        } else {
            XCTAssertTrue(app.buttons["Account and settings"].waitForExistence(timeout: 6))
        }
    }

    @MainActor
    private func launch(appearance: String, guest: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-DisableProductionFlowSimulation",
            "-SkipAuthentication",
            "-SeedDevelopmentData",
            "-UseEphemeralDataStore",
            "-UseProductionOnboarding",
            "-AppleLanguages", "(en)",
            "-AppleInterfaceStyle", appearance,
            "-appAppearance", appearance.lowercased()
        ]
        if guest { app.launchArguments.append("-MainInvitationGuestUITest") }
        app.launch()
        return app
    }
}
