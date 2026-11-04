import XCTest

final class MainInvitationEditingUITests: XCTestCase {
    private let originalTitle = "Alex & Jordan’s Wedding"

    @MainActor
    func testHostCanSaveAndCancelMainInvitationTitleAndLocationInBothAppearances() throws {
        continueAfterFailure = false

        for appearance in ["light", "dark"] {
            let app = launch(appearance: appearance)
            openMainInvitation(in: app)

            let title = app.buttons["invitation.edit.title"]
            XCTAssertTrue(title.waitForExistence(timeout: 8))
            XCTAssertTrue(app.buttons["invitation.edit.date"].exists)
            XCTAssertTrue(app.buttons["invitation.edit.location"].exists)

            title.tap()
            let titleField = app.textFields["invitation.edit.title.field"]
            XCTAssertTrue(titleField.waitForExistence(timeout: 5))
            replaceText(in: titleField, with: "A discarded invitation title")
            app.buttons["invitation.edit.title.cancel"].tap()
            XCTAssertTrue(app.buttons["invitation.edit.title"].waitForExistence(timeout: 5))
            XCTAssertEqual(app.buttons["invitation.edit.title"].label, originalTitle,
                           "Cancel should discard the title draft.")

            title.tap()
            let editableTitle = app.textFields["invitation.edit.title.field"]
            XCTAssertTrue(editableTitle.waitForExistence(timeout: 5))
            replaceText(in: editableTitle, with: "A saved invitation title")
            app.buttons["invitation.edit.title.save"].tap()
            XCTAssertTrue(app.buttons["invitation.edit.title"].waitForExistence(timeout: 5))
            XCTAssertEqual(app.buttons["invitation.edit.title"].label, "A saved invitation title",
                           "Saving should update the visible invitation title.")

            let date = app.buttons["invitation.edit.date"]
            date.tap()
            XCTAssertTrue(app.navigationBars["Date and Time"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.datePickers["invitation.edit.date.starts.date"].exists)
            app.buttons["invitation.edit.date.cancel"].tap()
            XCTAssertTrue(date.waitForExistence(timeout: 5), "Cancel should return to the invitation.")

            date.tap()
            let allDay = app.switches["invitation.edit.date.allDay"]
            XCTAssertTrue(allDay.waitForExistence(timeout: 5))
            let originalAllDayValue = allDay.value as? String
            XCTAssertNotNil(originalAllDayValue, "The all-day switch should expose its current value.")
            allDay.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
            XCTAssertNotEqual(allDay.value as? String, originalAllDayValue,
                               "Tapping the all-day switch should change its draft value before saving.")
            app.buttons["invitation.edit.date.save"].tap()
            XCTAssertTrue(date.waitForExistence(timeout: 5), "Saving should return to the invitation.")

            date.tap()
            let savedAllDay = app.switches["invitation.edit.date.allDay"]
            XCTAssertTrue(savedAllDay.waitForExistence(timeout: 5))
            XCTAssertNotEqual(savedAllDay.value as? String, originalAllDayValue,
                               "Saving the date sheet should persist its all-day setting.")
            savedAllDay.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
            XCTAssertEqual(savedAllDay.value as? String, originalAllDayValue,
                           "The all-day switch should change back before restoring the original setting.")
            app.buttons["invitation.edit.date.save"].tap()
            XCTAssertTrue(date.waitForExistence(timeout: 5))

            let location = app.buttons["invitation.edit.location"]
            location.tap()
            XCTAssertTrue(app.navigationBars["Location"].waitForExistence(timeout: 5))
            app.buttons["invitation.edit.location.clear"].tap()
            app.buttons["invitation.edit.location.cancel"].tap()
            XCTAssertEqual(app.buttons["invitation.edit.location"].label, "Willow & Stone Estate",
                           "Cancel should discard clearing the location.")

            location.tap()
            XCTAssertTrue(app.navigationBars["Location"].waitForExistence(timeout: 5))
            app.buttons["invitation.edit.location.clear"].tap()
            app.buttons["invitation.edit.location.save"].tap()
            XCTAssertTrue(app.buttons["invitation.edit.location"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.buttons["invitation.edit.location"].label.localizedCaseInsensitiveContains("add location"),
                          "Saving should remove the visible event location.")

            attach(app, name: "Main invitation editing — \(appearance)")
            app.terminate()
        }
    }

    @MainActor
    func testViewOnlyCollaboratorCannotEditOrShareMainInvitation() throws {
        continueAfterFailure = false
        let app = launch(appearance: "light", readOnly: true)
        defer { app.terminate() }
        openMainInvitation(in: app)

        XCTAssertFalse(app.buttons["invitation.edit.title"].exists)
        XCTAssertFalse(app.buttons["invitation.edit.date"].exists)
        XCTAssertFalse(app.buttons["invitation.edit.location"].exists)
        XCTAssertFalse(app.buttons["invitation-share-invitation"].exists)
        assertPlainReadOnlyDetails(in: app)
    }

    @MainActor
    func testInvitationInformationTilesOpenTheirFocusedEditors() throws {
        continueAfterFailure = false
        let app = launch(appearance: "dark", withMapCoordinates: true)
        defer { app.terminate() }
        openMainInvitation(in: app)

        let dateInfo = app.buttons["invitation.edit.date.info"]
        reveal(dateInfo, in: app)
        XCTAssertTrue(dateInfo.isHittable)
        XCTAssertTrue(app.buttons["Add to Calendar"].exists,
                      "The calendar action should remain separate from the editable date information tile.")
        dateInfo.tap()
        XCTAssertTrue(app.navigationBars["Date and Time"].waitForExistence(timeout: 5))
        app.buttons["invitation.edit.date.cancel"].tap()
        XCTAssertTrue(dateInfo.waitForExistence(timeout: 5))

        let locationInfo = app.buttons["invitation.edit.location.info"]
        reveal(locationInfo, in: app)
        XCTAssertTrue(locationInfo.isHittable)
        locationInfo.tap()
        XCTAssertTrue(app.navigationBars["Location"].waitForExistence(timeout: 5))
        app.buttons["invitation.edit.location.cancel"].tap()
        XCTAssertTrue(locationInfo.waitForExistence(timeout: 5))

        // The map sits below the address and can be outside the viewport.
        let mapsLink = app.descendants(matching: .any)
            .matching(identifier: "invitation.location.maps").firstMatch
        reveal(mapsLink, in: app)
        XCTAssertTrue(mapsLink.isHittable,
                      "Maps should remain a separate action below the editable address.")
        XCTAssertTrue(mapsLink.label.contains("Willow & Stone Estate"))
        attach(app, name: "Invitation information tiles — dark")
    }

    @MainActor
    func testGuestRoleCannotEditOrShareMainInvitation() throws {
        continueAfterFailure = false
        let app = launch(appearance: "light", guest: true)
        defer { app.terminate() }
        openMainInvitation(in: app)

        XCTAssertFalse(app.buttons["invitation.edit.title"].exists)
        XCTAssertFalse(app.buttons["invitation.edit.date"].exists)
        XCTAssertFalse(app.buttons["invitation.edit.location"].exists)
        XCTAssertFalse(app.buttons["invitation-share-invitation"].exists)
        assertPlainReadOnlyDetails(in: app)
    }

    @MainActor
    func testGuestAndViewOnlyStayReadOnlyAfterSwitchingHomeLayout() throws {
        continueAfterFailure = false

        for (readOnly, guest) in [(true, false), (false, true)] {
            let app = launch(appearance: "light", readOnly: readOnly, guest: guest,
                             pinsHomeLayout: false)
            addTeardownBlock {
                guard app.state == .runningForeground else { return }
                self.attach(app, name: "Role after Account layout switch")
                app.terminate()
            }
            openSeededWorkspace(in: app)

            // Select both layouts through the actual preference UI. A launch
            // argument for home.layout would override the saved preference and
            // make this an invalid test of the Account flow.
            HomeLayoutUITestSupport.select("Overview", in: app)
            XCTAssertTrue(app.scrollViews["home.overview"].waitForExistence(timeout: 5),
                          app.debugDescription)

            HomeLayoutUITestSupport.select("Cards", in: app)
            XCTAssertTrue(app.buttons["home.event.main"].waitForExistence(timeout: 5),
                          app.debugDescription)
            let managementButtons = app.buttons.matching(
                NSPredicate(format: "identifier BEGINSWITH %@", "home.manage.")
            )
            if guest {
                XCTAssertEqual(managementButtons.count, 0,
                               "Switching to Cards must not grant guest management entry points.")
            } else {
                XCTAssertTrue(app.buttons["home.manage.main"].exists,
                              "View-only collaborators may still open the read-only management dashboard.")
            }

            let main = app.buttons["home.event.main"]
            XCTAssertTrue(main.waitForExistence(timeout: 6))
            main.tap()
            XCTAssertTrue(app.navigationBars["Invitation"].waitForExistence(timeout: 6))
            XCTAssertFalse(app.buttons["invitation.edit.title"].exists)
            XCTAssertFalse(app.buttons["invitation.edit.date"].exists)
            XCTAssertFalse(app.buttons["invitation.edit.location"].exists)
            XCTAssertFalse(app.buttons["invitation-share-invitation"].exists)
            assertPlainReadOnlyDetails(in: app)
        }
    }

    @MainActor
    func testDetailShareUsesOpenedChildAndNativeBackReturnsHome() throws {
        continueAfterFailure = false
        let app = launch(appearance: "light")
        defer { app.terminate() }
        openSeededWorkspace(in: app)
        let homeScroll = app.scrollViews.firstMatch
        XCTAssertTrue(homeScroll.waitForExistence(timeout: 5))
        let child = app.buttons.matching(
            NSPredicate(format: "identifier == %@ AND label CONTAINS %@", "home.event.child", "Ceremony")
        ).firstMatch
        for _ in 0..<4 where !child.isHittable { homeScroll.swipeDown() }
        for _ in 0..<8 where !child.isHittable { homeScroll.swipeUp() }
        XCTAssertTrue(child.waitForExistence(timeout: 8))
        XCTAssertTrue(child.isHittable)
        let childTitle = child.label.components(separatedBy: ",").first ?? ""
        XCTAssertFalse(childTitle.isEmpty, "The child card should expose its event title.")
        child.tap()

        let share = app.buttons["invitation-share-invitation"]
        XCTAssertTrue(share.waitForExistence(timeout: 8))
        XCTAssertTrue(share.isHittable)
        XCTAssertLessThan(share.frame.midX, app.windows.firstMatch.frame.midX,
                          "Detail sharing should appear on the leading side of the invitation toolbar.")
        XCTAssertTrue(app.buttons["invitation.edit.title"].exists,
                      "Authorized planners can edit the opened child from its invitation content.")
        XCTAssertTrue(app.buttons["invitation.edit.date"].exists)
        XCTAssertTrue(app.buttons["invitation.edit.location"].exists)
        share.tap()

        XCTAssertTrue(app.navigationBars["Invite"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts[childTitle].waitForExistence(timeout: 5),
                      "The invitation share screen should stay pinned to the opened child event.")
        app.buttons["Close"].tap()

        let back = app.navigationBars.buttons["Back"]
        XCTAssertTrue(back.waitForExistence(timeout: 5))
        back.tap()
        XCTAssertTrue(app.buttons["home.event.main"].waitForExistence(timeout: 8),
                      "Native back should return from the invitation detail to Home.")
    }

    @MainActor
    private func openMainInvitation(in app: XCUIApplication) {
        openSeededWorkspace(in: app)
        let main = app.buttons["home.event.main"]
        XCTAssertTrue(main.waitForExistence(timeout: 10))
        main.tap()
        XCTAssertTrue(app.navigationBars["Invitation"].waitForExistence(timeout: 8))
    }

    @MainActor
    private func openSeededWorkspace(in app: XCUIApplication) {
        XCTAssertTrue(app.buttons["Filter events"].waitForExistence(timeout: 10))
        let seededWorkspace = app.buttons
            .matching(NSPredicate(format: "label CONTAINS %@", "Alex & Jordan"))
            .firstMatch
        XCTAssertTrue(seededWorkspace.waitForExistence(timeout: 8))
        seededWorkspace.tap()
        if app.scrollViews["home.overview"].exists {
            XCTAssertTrue(app.scrollViews["home.overview"].waitForExistence(timeout: 8),
                          "The selected workspace should open in Overview.")
        } else {
            XCTAssertTrue(app.buttons["home.event.main"].waitForExistence(timeout: 8),
                          "Both planner and guest-role workspaces should open the main invitation.")
        }
    }

    @MainActor
    private func assertPlainReadOnlyDetails(in app: XCUIApplication) {
        let visibleTitle = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", originalTitle)
        ).firstMatch
        XCTAssertTrue(visibleTitle.waitForExistence(timeout: 5))
        visibleTitle.tap()
        XCTAssertFalse(app.navigationBars["Edit Event"].exists,
                       "Tapping the visible title should not open an editor for a read-only participant.")

        let visibleDate = app.staticTexts.matching(
            NSPredicate(format: "label MATCHES %@", ".*\\b[0-9]{4}\\b.*")
        ).firstMatch
        XCTAssertTrue(visibleDate.waitForExistence(timeout: 5))
        visibleDate.tap()
        XCTAssertFalse(app.navigationBars["Date and Time"].exists,
                       "Tapping the visible date should not open an editor for a read-only participant.")
    }

    @MainActor
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        let scroll = app.scrollViews.firstMatch
        for _ in 0..<12 where !element.isHittable { scroll.swipeUp() }
        XCTAssertTrue(element.isHittable, "The invitation information tile should be reachable by scrolling.")
    }

    @MainActor
    private func replaceText(in field: XCUIElement, with replacement: String) {
        let current = field.value as? String ?? ""
        XCTAssertFalse(current.isEmpty, "The invitation title field should have its current title.")
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.99, dy: 0.5)).tap()
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count) + replacement)
    }

    @MainActor
    private func launch(appearance: String, readOnly: Bool = false, guest: Bool = false,
                        homeLayout: String? = nil, pinsHomeLayout: Bool = true,
                        withMapCoordinates: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += [
            "-DisableProductionFlowSimulation", "-SkipAuthentication",
            "-SeedDevelopmentData", "-UseEphemeralDataStore",
            "-AppleLanguages", "(en)", "-AppleInterfaceStyle", appearance,
            "-appAppearance", appearance,
        ]
        if readOnly || guest || homeLayout != nil {
            app.launchArguments.append("-UseProductionOnboarding")
        }
        if pinsHomeLayout, let homeLayout {
            // Pin the role checks to the alternate Cards route instead of
            // inheriting a layout preference left by another UI test.
            app.launchArguments += ["-home.layout", homeLayout]
        } else if pinsHomeLayout && (readOnly || guest) {
            app.launchArguments += ["-home.layout", "cards"]
        }
        if readOnly { app.launchArguments.append("-ReadOnlyCollaboratorsUITest") }
        if guest { app.launchArguments.append("-MainInvitationGuestUITest") }
        if withMapCoordinates { app.launchArguments.append("-MainInvitationMapUITest") }
        app.launch()
        return app
    }

    @MainActor
    private func attach(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
