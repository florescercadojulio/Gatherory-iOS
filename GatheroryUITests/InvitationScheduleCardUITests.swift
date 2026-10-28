import XCTest

final class InvitationScheduleCardUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testHostScheduleCardKeepsDateEditorSeparateFromCalendarExportInBothAppearances() throws {
        for appearance in ["Light", "Dark"] {
            let app = fixtureApplication(appearance: appearance)
            app.launch()
            defer { app.terminate() }
            openMainInvitation(in: app)

            let dateInfo = app.buttons["invitation.edit.date.info"]
            reveal(dateInfo, in: app)
            XCTAssertTrue(dateInfo.isHittable)

            let addToCalendar = app.buttons["invitation.add-to-calendar"]
            reveal(addToCalendar, in: app)
            XCTAssertTrue(addToCalendar.waitForExistence(timeout: 5),
                          "The scheduled host event should offer a separate native calendar action.")
            XCTAssertTrue(dateInfo.isHittable, "The date tile and calendar footer should be visible together in the schedule card.")
            XCTAssertNotEqual(dateInfo.identifier, addToCalendar.identifier,
                              "The date editor and calendar export must remain separate actions.")
            assertCopyFooterIsAbsent(in: app)

            let zone = TimeZone.autoupdatingCurrent
            let fixtureDate = Calendar.autoupdatingCurrent.date(byAdding: .day, value: 248, to: .now) ?? .now
            if let abbreviation = zone.abbreviation(for: fixtureDate) {
                XCTAssertTrue(dateInfo.label.contains(abbreviation),
                              "The schedule accessibility label should include its timezone. Label: \(dateInfo.label)")
            }
            XCTAssertTrue(
                dateInfo.label.contains(String(Calendar.autoupdatingCurrent.component(.year, from: fixtureDate))),
                "The detailed schedule tile should retain the full event year for accessibility. Label: \(dateInfo.label)"
            )
            XCTAssertNotNil(dateInfo.label.range(of: #"\b\d{1,2}:\d{2}\b"#, options: .regularExpression),
                            "The schedule label should expose the prominent event time. Label: \(dateInfo.label)")

            attach(app, name: "Host invitation schedule card — \(appearance)")

            dateInfo.tap()
            XCTAssertTrue(app.navigationBars["Date and Time"].waitForExistence(timeout: 5),
                          "The date card should still open the focused date editor.")
            app.buttons["invitation.edit.date.cancel"].tap()
            XCTAssertTrue(dateInfo.waitForExistence(timeout: 5))

            addToCalendar.tap()
            let calendarCancel = app.navigationBars.buttons.matching(identifier: "Cancel").firstMatch
            XCTAssertTrue(calendarCancel.waitForExistence(timeout: 8),
                          "Add to Calendar should open the native event editor. Accessibility tree: \(app.debugDescription)")
            calendarCancel.tap()

            let discardAlert = app.alerts.firstMatch
            if discardAlert.waitForExistence(timeout: 2) {
                let discard = discardAlert.buttons.matching(
                    NSPredicate(format: "label CONTAINS[c] %@", "Discard")
                ).firstMatch
                XCTAssertTrue(discard.waitForExistence(timeout: 3), "Cancelling a new calendar event should offer discard.")
                discard.tap()
            }
            XCTAssertTrue(dateInfo.waitForExistence(timeout: 5),
                          "Cancelling the native calendar editor should return to the invitation without saving.")
        }
    }

    @MainActor
    func testViewOnlyGuestKeepsCalendarExportWithoutDateEditingInBothAppearances() throws {
        for appearance in ["Light", "Dark"] {
            let app = fixtureApplication(appearance: appearance, isGuest: true)
            app.launch()
            defer { app.terminate() }
            openMainInvitation(in: app)

            let addToCalendar = app.buttons["invitation.add-to-calendar"]
            reveal(addToCalendar, in: app)
            XCTAssertTrue(addToCalendar.waitForExistence(timeout: 5),
                          "A view-only guest should still be able to add the scheduled event to their calendar.")
            XCTAssertTrue(addToCalendar.isHittable)
            assertCopyFooterIsAbsent(in: app)
            XCTAssertFalse(app.buttons["invitation.edit.date.info"].exists,
                           "The view-only guest should not receive the host date editor action.")

            let zone = TimeZone.autoupdatingCurrent
            let fixtureDate = Calendar.autoupdatingCurrent.date(byAdding: .day, value: 248, to: .now) ?? .now
            if let abbreviation = zone.abbreviation(for: fixtureDate) {
                let schedule = app.descendants(matching: .any).matching(
                    NSPredicate(format: "label CONTAINS %@", abbreviation)
                ).firstMatch
                XCTAssertTrue(schedule.exists,
                              "The guest should still see the scheduled date/time and timezone label.")
            }

            attach(app, name: "Guest invitation schedule card — \(appearance)")
        }
    }

    @MainActor
    private func fixtureApplication(appearance: String, isGuest: Bool = false) -> XCUIApplication {
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
        if isGuest { app.launchArguments.append("-MainInvitationGuestUITest") }
        return app
    }

    @MainActor
    private func openMainInvitation(in app: XCUIApplication) {
        XCTAssertTrue(app.buttons["Filter events"].waitForExistence(timeout: 10),
                      "The seeded workspace library should open.")
        let workspace = app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "Alex & Jordan")
        ).firstMatch
        XCTAssertTrue(workspace.waitForExistence(timeout: 8))
        workspace.tap()
        HomeLayoutUITestSupport.select("Cards", in: app)
        let main = app.buttons["home.event.main"]
        XCTAssertTrue(main.waitForExistence(timeout: 8))
        main.tap()
        XCTAssertTrue(app.navigationBars["Invitation"].waitForExistence(timeout: 8))
    }

    @MainActor
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        let scroll = app.scrollViews.firstMatch
        XCTAssertTrue(scroll.waitForExistence(timeout: 5))
        for _ in 0..<12 where !element.isHittable { scroll.swipeUp() }
        XCTAssertTrue(element.isHittable, "The invitation schedule card should be reachable by scrolling.")
    }

    @MainActor
    private func assertCopyFooterIsAbsent(in app: XCUIApplication) {
        let copyFooter = app.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS[c] %@", "Saves a copy")
        ).firstMatch
        XCTAssertFalse(
            copyFooter.exists,
            "The invitation should not show the outdated copy/sync footer. Accessibility tree: \(app.debugDescription)"
        )
    }

    @MainActor
    private func attach(_ app: XCUIApplication, name: String) {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
