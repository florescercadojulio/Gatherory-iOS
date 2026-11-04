import XCTest

final class EventManagementUITests: XCTestCase {
    private let mainTitle = "Alex & Jordan’s Wedding"
    private let childTitle = "Ceremony"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testMainAndChildUpdatesUseTheManagedEvent() throws {
        let app = launch()
        openWorkspace(in: app)
        let childManageID = childManagementButtonID(in: app)
        for manageID in ["home.manage.main", childManageID] {
            let manage = app.buttons[manageID]
            for _ in 0..<8 where !manage.isHittable { app.swipeUp() }
            XCTAssertTrue(manage.isHittable)
            let homeTitle = app.navigationBars.firstMatch.identifier
            manage.tap()
            let dashboard = app.scrollViews["event.management.dashboard"]
            XCTAssertTrue(dashboard.waitForExistence(timeout: 6))
            let expectedUpdatesID = manageID.replacingOccurrences(of: "home.manage.", with: "manage.updates.")
            let updates = dashboard.buttons[expectedUpdatesID]
            for _ in 0..<8 where !updates.isHittable { dashboard.swipeUp() }
            XCTAssertTrue(updates.isHittable,
                          "Updates must use the managed event, independently of Home's selection.")
            XCTAssertEqual(dashboard.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "manage.updates.")).count, 1)
            updates.tap()
            XCTAssertTrue(app.navigationBars["Updates"].waitForExistence(timeout: 6))
            app.navigationBars.buttons.firstMatch.tap()
            XCTAssertTrue(dashboard.waitForExistence(timeout: 6))
            returnFromManagement(in: app)
            XCTAssertEqual(app.navigationBars.firstMatch.identifier, homeTitle)
        }
        app.terminate()
    }

    @MainActor
    func testOverviewUpdatesOpensThroughManagementInsteadOfHomeToolbar() throws {
        let app = launch()
        openWorkspace(in: app)
        HomeLayoutUITestSupport.select("Cards", in: app)
        XCTAssertTrue(app.buttons["home.updates"].exists)

        HomeLayoutUITestSupport.select("Overview", in: app)
        XCTAssertFalse(app.buttons["home.updates"].exists,
                       "Overview should route updates through the event's Manage dashboard.")
        let manage = app.buttons["home.manage.main"]
        XCTAssertTrue(manage.waitForExistence(timeout: 6))
        for _ in 0..<8 where !manage.isHittable { app.swipeUp() }
        XCTAssertTrue(manage.isHittable)
        manage.tap()

        let dashboard = app.scrollViews["event.management.dashboard"]
        XCTAssertTrue(dashboard.waitForExistence(timeout: 6))
        let updates = dashboard.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "Updates")
        ).firstMatch
        for _ in 0..<8 where !updates.isHittable { dashboard.swipeUp() }
        XCTAssertTrue(updates.isHittable)
        updates.tap()
        XCTAssertTrue(app.navigationBars["Updates"].waitForExistence(timeout: 6))
        app.terminate()
    }

    @MainActor
    func testMainAndChildManagementFromCardsAndOverviewKeepsHomeSelected() throws {
        for layout in ["Cards", "Overview"] {
            for isChild in [false, true] {
                let app = launch()
                openWorkspace(in: app)
                XCTAssertFalse(app.tabBars.buttons["Manage"].exists,
                               "The workspace tab bar should not contain a Manage tab.")

                let childManageID = childManagementButtonID(in: app)
                HomeLayoutUITestSupport.select(layout, in: app)
                let identifier = isChild ? childManageID : "home.manage.main"
                let manage = app.buttons[identifier]
                XCTAssertTrue(manage.waitForExistence(timeout: 6),
                              "The \(layout) Home view should offer management for the selected event.")
                for _ in 0..<8 where !manage.isHittable { app.swipeUp() }
                XCTAssertTrue(manage.isHittable)
                let eventButton: XCUIElement
                if layout == "Cards" {
                    eventButton = isChild
                        ? app.buttons.matching(NSPredicate(format: "identifier == %@ AND label CONTAINS %@", "home.event.child", childTitle)).firstMatch
                        : app.buttons["home.event.main"]
                } else {
                    eventButton = isChild
                        ? app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "home.overview.event.", childTitle)).firstMatch
                        : app.buttons["home.overview.mainEvent"]
                }
                XCTAssertTrue(eventButton.exists)
                XCTAssertGreaterThanOrEqual(manage.frame.minY, eventButton.frame.maxY - 1,
                                            "Manage must be below the card details, not over the artwork.")
                XCTAssertGreaterThanOrEqual(manage.frame.height, 44)
                let homeTitleBefore = app.navigationBars.firstMatch.identifier
                manage.tap()

                assertManagementView(for: isChild ? childTitle : mainTitle, in: app)
                returnFromManagement(in: app)
                XCTAssertTrue(app.tabBars.buttons["Home"].isSelected,
                              "Closing event management should leave the Home tab selected.")
                XCTAssertEqual(app.navigationBars.firstMatch.identifier, homeTitleBefore,
                               "Managing a different card should not change Home's selected event.")
                app.terminate()
            }
        }
    }

    @MainActor
    func testInvitationsOmitManageWhileHomeCardsRetainManagementInBothAppearances() throws {
        for (appearance, isChild) in [("Light", false), ("Dark", true)] {
            let app = launch(appearance: appearance)
            openWorkspace(in: app)
            let manageID = isChild ? childManagementButtonID(in: app) : "home.manage.main"
            HomeLayoutUITestSupport.select("Cards", in: app)
            let invitation = isChild
                ? app.buttons.matching(NSPredicate(format: "identifier == %@ AND label CONTAINS %@",
                                                    "home.event.child", childTitle)).firstMatch
                : app.buttons["home.event.main"]
            XCTAssertTrue(invitation.waitForExistence(timeout: 6))
            for _ in 0..<8 where !invitation.isHittable { app.swipeUp() }
            invitation.tap()
            XCTAssertTrue(app.navigationBars["Invitation"].waitForExistence(timeout: 6))

            XCTAssertFalse(app.buttons["invitation.manage"].exists,
                           "Management belongs on the preceding Home card, not the invitation toolbar.")
            XCTAssertFalse(app.buttons["Manage Event"].exists)
            XCTAssertTrue(app.buttons["invitation-share-invitation"].exists)
            XCTAssertTrue(app.buttons["invitation.actions"].exists)
            let backToHome = app.navigationBars["Invitation"].buttons.firstMatch
            XCTAssertTrue(backToHome.waitForExistence(timeout: 5))
            backToHome.tap()
            XCTAssertTrue(app.tabBars.buttons["Home"].isSelected,
                          "Returning from the invitation should preserve Home tab selection.")
            XCTAssertFalse(app.tabBars.buttons["Manage"].exists)

            let manage = app.buttons[manageID]
            for _ in 0..<8 where !manage.isHittable { app.swipeUp() }
            XCTAssertTrue(manage.isHittable,
                          "The original Home card's Manage footer must remain available.")
            manage.tap()
            assertManagementView(for: isChild ? childTitle : mainTitle, in: app)
            returnFromManagement(in: app)
            XCTAssertTrue(app.tabBars.buttons["Home"].isSelected)
            app.terminate()
        }
    }

    @MainActor
    func testInvitationGuestDoesNotSeeEventManagementEntryPoints() throws {
        let app = launch(guest: true)
        openWorkspace(in: app, expectsHomeTabs: false)
        let homeManagementButtons = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "home.manage.")
        )
        XCTAssertEqual(homeManagementButtons.count, 0,
                       "A guest should not see event management on Home cards.")

        let main = app.buttons["home.event.main"]
        XCTAssertTrue(main.waitForExistence(timeout: 6))
        main.tap()
        XCTAssertTrue(app.navigationBars["Invitation"].waitForExistence(timeout: 6))
        XCTAssertFalse(app.buttons["invitation.manage"].exists,
                       "A guest should not see event management in the invitation toolbar.")
        XCTAssertFalse(app.tabBars.buttons["Manage"].exists)
    }

    @MainActor
    private func assertManagementView(for eventTitle: String, in app: XCUIApplication,
                                       file: StaticString = #filePath, line: UInt = #line) {
        let title = app.navigationBars.staticTexts[eventTitle]
        XCTAssertTrue(title.waitForExistence(timeout: 6),
                      "The management view should display the exact selected event title.", file: file, line: line)
        let dashboard = app.scrollViews["event.management.dashboard"]
        XCTAssertTrue(dashboard.waitForExistence(timeout: 6),
                      "Management should open directly to the event dashboard.", file: file, line: line)
        XCTAssertFalse(app.buttons["event.management.people"].exists,
                       "The dashboard should not show a People menu entry.", file: file, line: line)
        let guests = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Guests")).firstMatch
        XCTAssertTrue(guests.exists, "The event dashboard should show its Guests card.", file: file, line: line)
        let collaborators = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "Collaborators")
        ).firstMatch
        XCTAssertTrue(collaborators.waitForExistence(timeout: 6), file: file, line: line)
        collaborators.tap()
        let alex = app.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS[c] %@", "Alex")
        ).firstMatch
        XCTAssertTrue(alex.waitForExistence(timeout: 6), "People should show the event's collaborators.",
                      file: file, line: line)

        let backToDashboard = app.navigationBars.buttons.firstMatch
        XCTAssertTrue(backToDashboard.waitForExistence(timeout: 5), file: file, line: line)
        backToDashboard.tap()
        XCTAssertTrue(dashboard.waitForExistence(timeout: 5),
                      "One native back step should return from Collaborators to the dashboard.", file: file, line: line)
        XCTAssertTrue(app.navigationBars.staticTexts[eventTitle].exists,
                      "The event title should remain pinned on the dashboard.", file: file, line: line)
    }

    @MainActor
    private func returnFromManagement(in app: XCUIApplication,
                                      file: StaticString = #filePath, line: UInt = #line) {
        let back = app.navigationBars.buttons.firstMatch
        XCTAssertTrue(back.waitForExistence(timeout: 5), file: file, line: line)
        XCTAssertFalse(app.buttons["Done"].exists, "Management should use native back navigation, not a sheet's Done action.", file: file, line: line)
        back.tap()
    }

    @MainActor
    private func childManagementButtonID(in app: XCUIApplication) -> String {
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
        XCTAssertTrue(app.buttons["Filter events"].waitForExistence(timeout: 10),
                      "The seeded workspace library should open.")
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
    private func launch(guest: Bool = false, appearance: String = "Light") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-DisableProductionFlowSimulation",
            "-SkipAuthentication",
            "-SeedDevelopmentData",
            "-UseEphemeralDataStore",
            "-UseProductionOnboarding",
            "-AppleLanguages", "(en)",
            "-AppleInterfaceStyle", appearance.lowercased(), "-appAppearance", appearance.lowercased()
        ]
        if guest {
            app.launchArguments += ["-UseProductionOnboarding", "-home.layout", "cards",
                                   "-MainInvitationGuestUITest"]
        }
        app.launch()
        return app
    }
}
