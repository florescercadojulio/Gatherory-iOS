//
//  GatheroryUITests.swift
//  GatheroryUITests
//
//  Created by Julio C on 10/7/26.
//

import XCTest

final class GatheroryUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testSeededWorkspaceCanOpen() throws {
        let app = fixtureApplication()
        app.launchArguments += ["-UseProductionOnboarding", "-AppleLanguages", "(en)"]
        app.launch()

        XCTAssertTrue(
            app.buttons["Filter events"].waitForExistence(timeout: 8),
            "The seeded development flow should reach the workspace library."
        )

        let seededWorkspace = app.buttons
            .matching(NSPredicate(format: "label CONTAINS %@", "Maya & Theo"))
            .firstMatch
        XCTAssertTrue(
            seededWorkspace.waitForExistence(timeout: 3),
            "The deterministic workspace fixture should be visible."
        )

        seededWorkspace.tap()

        XCTAssertTrue(
            app.tabBars.buttons["Home"].waitForExistence(timeout: 5),
            "Opening a workspace should present the workspace tab interface."
        )
    }

    @MainActor
    func testEventsLongPressOffersLifecycleActionsInLightAndDark() throws {
        for appearance in ["Light", "Dark"] {
            let app = fixtureApplication()
            app.launchArguments += [
                "-UseProductionOnboarding", "-AppleLanguages", "(en)",
                "-AppleInterfaceStyle", appearance, "-appAppearance", appearance.lowercased()
            ]
            app.launch()
            let event = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Alex & Jordan")).firstMatch
            XCTAssertTrue(event.waitForExistence(timeout: 8))
            XCTAssertFalse(app.staticTexts["Draft"].exists, "The Events list should not show a lifecycle badge.")
            event.press(forDuration: 1)
            XCTAssertTrue(app.buttons["Cancel Event"].waitForExistence(timeout: 3))
            XCTAssertTrue(app.buttons["Delete Event"].exists)
            XCTAssertTrue(app.buttons["Duplicate Event"].exists)
            XCTAssertFalse(app.buttons["Pause Replies"].exists)
            let menuShot = XCTAttachment(screenshot: app.screenshot())
            menuShot.name = "Events management long press — \(appearance)"
            menuShot.lifetime = .keepAlways
            add(menuShot)
            app.buttons["Cancel Event"].tap()
            let confirmation = app.alerts.firstMatch
            XCTAssertTrue(confirmation.waitForExistence(timeout: 3))
            confirmation.buttons["Cancel"].tap()
            XCTAssertTrue(event.waitForExistence(timeout: 3))
            event.press(forDuration: 1)
            app.buttons["Delete Event"].tap()
            XCTAssertTrue(confirmation.waitForExistence(timeout: 3))
            confirmation.buttons["Cancel"].tap()
            XCTAssertTrue(event.waitForExistence(timeout: 3), "Cancelling deletion must retain the event.")
            event.tap()
            XCTAssertTrue(app.buttons["home.event.main"].waitForExistence(timeout: 5))
            XCTAssertFalse(app.staticTexts["Draft"].exists)
            XCTAssertFalse(app.staticTexts["Main event"].exists)
            let homeShot = XCTAttachment(screenshot: app.screenshot())
            homeShot.name = "Event Home without badges — \(appearance)"
            homeShot.lifetime = .keepAlways
            add(homeShot)
            app.terminate()
        }
    }

    @MainActor
    func testEventsLongPressDoesNotExposeLifecycleActionsToReadOnlyParticipants() throws {
        let app = fixtureApplication()
        app.launchArguments += [
            "-UseProductionOnboarding", "-ReadOnlyCollaboratorsUITest", "-AppleLanguages", "(en)"
        ]
        app.launch()
        defer { app.terminate() }
        let event = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Alex & Jordan")).firstMatch
        XCTAssertTrue(event.waitForExistence(timeout: 8))
        event.press(forDuration: 1)
        XCTAssertFalse(app.buttons["Cancel Event"].exists)
        XCTAssertFalse(app.buttons["Delete Event"].exists)
        XCTAssertFalse(app.buttons["Duplicate Event"].exists)
    }

    @MainActor
    func testDuplicateFromEventsLongPressCreatesIndependentEventInLightAndDark() throws {
        for appearance in ["Light", "Dark"] {
            let app = fixtureApplication()
            app.launchArguments += [
                "-UseProductionOnboarding", "-AppleLanguages", "(en)",
                "-AppleInterfaceStyle", appearance, "-appAppearance", appearance.lowercased()
            ]
            app.launch()
            let source = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Alex & Jordan")).firstMatch
            XCTAssertTrue(source.waitForExistence(timeout: 8))
            source.press(forDuration: 1)
            let menuShot = XCTAttachment(screenshot: app.screenshot())
            menuShot.name = "Events long-press menu — \(appearance)"
            menuShot.lifetime = .keepAlways
            add(menuShot)
            app.buttons["Duplicate Event"].tap()
            let name = app.textFields["workspace.duplicateEvent.name"]
            XCTAssertTrue(name.waitForExistence(timeout: 5))
            XCTAssertTrue((name.value as? String ?? "").hasPrefix("Copy of "))
            XCTAssertFalse(app.switches["workspace.duplicateEvent.includePlanningContent"].exists,
                           "Schedule and ideas are part of the confirmed copy without another choice.")
            let sheetShot = XCTAttachment(screenshot: app.screenshot())
            sheetShot.name = "Duplicate event sheet — \(appearance)"
            sheetShot.lifetime = .keepAlways
            add(sheetShot)
            app.navigationBars.buttons["Cancel"].tap()
            XCTAssertTrue(source.waitForExistence(timeout: 3))
            source.press(forDuration: 1)
            app.buttons["Duplicate Event"].tap()
            XCTAssertTrue(name.waitForExistence(timeout: 5))
            let oldName = name.value as? String ?? ""
            name.tap()
            name.typeText(" revised")
            let editedName = name.value as? String ?? ""
            XCTAssertNotEqual(editedName, oldName, "The native text field should accept an edit.")
            let confirm = app.buttons["workspace.duplicateEvent.confirm"]
            XCTAssertTrue(confirm.isEnabled)
            confirm.tap()
            let copiedEvent = app.buttons["home.event.main"]
            XCTAssertTrue(copiedEvent.waitForExistence(timeout: 8))
            XCTAssertTrue(copiedEvent.label.contains(editedName))
            XCTAssertFalse(app.staticTexts["Draft"].exists)
            let shot = XCTAttachment(screenshot: app.screenshot())
            shot.name = "Duplicated event Home — \(appearance)"
            shot.lifetime = .keepAlways
            add(shot)
            app.terminate()
        }
    }

    @MainActor
    func testHomeKeepsMainAndChildEventContextVisibleInLightAndDark() throws {
        for appearance in ["Light", "Dark"] {
            let app = fixtureApplication()
            app.launchArguments += [
                "-UseProductionOnboarding", "-AppleLanguages", "(en)",
                "-AppleInterfaceStyle", appearance, "-appAppearance", appearance.lowercased()
            ]
            app.launch()
            let workspace = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Alex & Jordan")).firstMatch
            XCTAssertTrue(workspace.waitForExistence(timeout: 8))
            workspace.tap()
            let main = app.buttons["home.event.main"]
            XCTAssertTrue(main.waitForExistence(timeout: 5))
            XCTAssertTrue(main.label.contains("Main event"))
            XCTAssertTrue(main.label.contains("Draft"))
            let mainTitle = "Alex & Jordan’s Wedding"
            let homeNavigationBar = app.navigationBars.firstMatch
            let mainNavigationBar = app.navigationBars[mainTitle]
            XCTAssertTrue(mainNavigationBar.waitForExistence(timeout: 5),
                          "Home should name its selected main event in native navigation.")
            let mainShot = XCTAttachment(screenshot: app.screenshot())
            mainShot.name = "Home main event context — \(appearance)"
            mainShot.lifetime = .keepAlways
            add(mainShot)

            let scroll = app.scrollViews.firstMatch
            for _ in 0..<8 where mainNavigationBar.exists {
                scroll.swipeDown()
            }
            let selectedChildTitle = homeNavigationBar.identifier.isEmpty
                ? homeNavigationBar.staticTexts.firstMatch.label
                : homeNavigationBar.identifier
            let navigationBarDescription = homeNavigationBar.debugDescription
            XCTAssertNotEqual(selectedChildTitle, mainTitle,
                              "Paging from the main event should select a scheduled child.")
            let childCards = app.buttons.matching(NSPredicate(
                format: "identifier == %@", "home.event.child"
            ))
            let titleMatchedChild = childCards.matching(NSPredicate(
                format: "identifier == %@ AND label CONTAINS %@", "home.event.child", selectedChildTitle
            )).firstMatch
            let child: XCUIElement
            if titleMatchedChild.isHittable {
                child = titleMatchedChild
            } else {
                let activeChildCard = (0..<childCards.count).map { childCards.element(boundBy: $0) }
                    .first { candidate in
                        guard candidate.isHittable else { return false }
                        let candidateTitle = candidate.label.components(separatedBy: ",").first ?? ""
                        return app.navigationBars[candidateTitle].exists
                    }
                child = activeChildCard ?? titleMatchedChild
            }
            XCTAssertTrue(child.isHittable, "The selected child card should be visible on Home.")
            let selectedChildCardTitle = child.label.components(separatedBy: ",").first ?? ""
            XCTAssertTrue(app.navigationBars[selectedChildCardTitle].exists,
                          "The active navigation title should identify the visible child. Bar: \(navigationBarDescription)")
            XCTAssertTrue(child.label.contains("Subevent"))
            XCTAssertTrue(child.label.contains("Part of \(mainTitle)"))
            let childShot = XCTAttachment(screenshot: app.screenshot())
            childShot.name = "Home child event context — \(appearance)"
            childShot.lifetime = .keepAlways
            add(childShot)
            app.terminate()
        }
    }

    @MainActor
    func testHomeOverviewModeAndSelectionPersistInLightAndDark() throws {
        for appearance in ["Light", "Dark"] {
            let app = fixtureApplication()
            addTeardownBlock {
                if app.state == .notRunning {
                    app.launch()
                }
                if app.navigationBars["Invitation"].exists,
                   app.navigationBars.buttons.firstMatch.exists {
                    app.navigationBars.buttons.firstMatch.tap()
                }
                if !app.buttons["Account and settings"].waitForExistence(timeout: 2) {
                    let workspace = app.buttons.matching(
                        NSPredicate(format: "label BEGINSWITH %@", "Alex & Jordan")
                    ).firstMatch
                    if workspace.waitForExistence(timeout: 2) { workspace.tap() }
                }
                if app.buttons["Account and settings"].waitForExistence(timeout: 2) {
                    HomeLayoutUITestSupport.select("Cards", in: app)
                }
                app.terminate()
            }
            app.launchArguments += [
                "-UseProductionOnboarding", "-AppleLanguages", "(en)",
                "-AppleInterfaceStyle", appearance, "-appAppearance", appearance.lowercased()
            ]
            app.launch()

            let workspace = app.buttons.matching(
                NSPredicate(format: "label BEGINSWITH %@", "Alex & Jordan")
            ).firstMatch
            XCTAssertTrue(workspace.waitForExistence(timeout: 8))
            workspace.tap()

            let cardsMain = app.buttons["home.event.main"]
            XCTAssertTrue(cardsMain.waitForExistence(timeout: 5), "Cards should be the initial Home layout.")
            XCTAssertFalse(app.descendants(matching: .any)["home.overview.mainEvent"].exists)

            HomeLayoutUITestSupport.select("Overview", in: app)

            let overviewMain = app.descendants(matching: .any)["home.overview.mainEvent"]
            XCTAssertTrue(overviewMain.waitForExistence(timeout: 5))
            let mainShot = XCTAttachment(screenshot: app.screenshot())
            mainShot.name = "Home Overview main event — \(appearance)"
            mainShot.lifetime = .keepAlways
            add(mainShot)
            let ceremonyRow = app.buttons.matching(
                NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@",
                            "home.overview.event.", "Ceremony")
            ).firstMatch
            XCTAssertTrue(ceremonyRow.waitForExistence(timeout: 5), "Overview should include a scheduled child event.")
            let overviewScroll = app.scrollViews["home.overview"]
            for _ in 0..<8 where !ceremonyRow.isHittable { overviewScroll.swipeUp() }
            XCTAssertTrue(ceremonyRow.isHittable, "Vertical scrolling should reach the event's date group.")
            let ceremonyDay = app.scrollViews.matching(
                NSPredicate(format: "identifier BEGINSWITH %@", "home.overview.day.")
            ).containing(.button, identifier: ceremonyRow.identifier).firstMatch
            XCTAssertTrue(ceremonyDay.exists, "The child event should belong to a dated horizontal collection.")
            let cocktailCard = ceremonyDay.buttons.matching(
                NSPredicate(format: "label CONTAINS %@", "Cocktail Hour")
            ).firstMatch
            XCTAssertTrue(cocktailCard.exists, "Events on the same day should share one collection.")
            ceremonyDay.swipeLeft()
            XCTAssertTrue(cocktailCard.isHittable, "Horizontal scrolling should reveal the next event on this date.")
            cocktailCard.tap()
            XCTAssertTrue(app.navigationBars["Invitation"].waitForExistence(timeout: 5))
            app.navigationBars.buttons.firstMatch.tap()
            XCTAssertTrue(app.navigationBars["Cocktail Hour"].waitForExistence(timeout: 5),
                          "Opening a horizontally revealed card must select that exact event.")
            for _ in 0..<3 where !ceremonyRow.isHittable { ceremonyDay.swipeRight() }
            XCTAssertTrue(ceremonyRow.isHittable)
            let rowsShot = XCTAttachment(screenshot: app.screenshot())
            rowsShot.name = "Home Overview date-grouped image cards — \(appearance)"
            rowsShot.lifetime = .keepAlways
            add(rowsShot)
            XCTAssertFalse(app.staticTexts["Alex & Jordan’s Wedding Playlist"].exists,
                           "Overview must not show event ideas as schedule rows.")

            ceremonyRow.tap()
            XCTAssertTrue(app.navigationBars["Invitation"].waitForExistence(timeout: 5),
                          "A child row should open the existing invitation detail.")
            app.navigationBars.buttons.firstMatch.tap()
            XCTAssertTrue(app.navigationBars["Ceremony"].waitForExistence(timeout: 5),
                          "Returning from the invitation should retain the selected child context.")

            HomeLayoutUITestSupport.select("Cards", in: app)
            XCTAssertTrue(app.navigationBars["Ceremony"].waitForExistence(timeout: 5),
                          "Switching to Cards should preserve the selected child context.")
            XCTAssertTrue(app.buttons.matching(
                NSPredicate(format: "identifier == %@ AND label CONTAINS %@", "home.event.child", "Ceremony")
            ).firstMatch.waitForExistence(timeout: 5))

            // A fresh app process verifies the choice lives in the display preference.
            HomeLayoutUITestSupport.select("Overview", in: app)
            app.terminate()
            app.launch()
            let relaunchedWorkspace = app.buttons.matching(
                NSPredicate(format: "label BEGINSWITH %@", "Alex & Jordan")
            ).firstMatch
            XCTAssertTrue(relaunchedWorkspace.waitForExistence(timeout: 8))
            relaunchedWorkspace.tap()
            XCTAssertTrue(
                app.descendants(matching: .any)["home.overview.mainEvent"].waitForExistence(timeout: 5),
                "Overview should remain selected after reopening the app."
            )

            HomeLayoutUITestSupport.select("Cards", in: app)
            XCTAssertTrue(app.buttons["home.event.main"].waitForExistence(timeout: 5),
                          "Restore Cards after checking persisted Overview mode.")
            app.terminate()
        }
    }

    @MainActor
    func testNewWorkspaceDateStaysSelectedWhenDateEditorReopensInLightAndDarkMode() throws {
        for appearance in ["Light", "Dark"] {
            let app = fixtureApplication()
            app.launchArguments += [
                "-UseProductionOnboarding", "-AppleLanguages", "(en)",
                "-AppleInterfaceStyle", appearance, "-appAppearance", appearance.lowercased()
            ]
            app.launch()

            let addWorkspace = app.buttons["workspace.add"]
            XCTAssertTrue(addWorkspace.waitForExistence(timeout: 8))
            addWorkspace.tap()
            app.buttons["workspace.startFromScratch"].tap()
            XCTAssertTrue(app.navigationBars["New Event"].waitForExistence(timeout: 5))

            let editDate = app.buttons["workspace.new.dateTime"]
            XCTAssertTrue(editDate.waitForExistence(timeout: 5))
            editDate.tap()
            XCTAssertTrue(app.navigationBars["Date and Time"].waitForExistence(timeout: 5))
            XCTAssertFalse(app.buttons["Time Zone"].exists,
                           "A new event should use the device timezone automatically.")

            var calendar = Calendar.autoupdatingCurrent
            calendar.timeZone = .autoupdatingCurrent
            let today = Date.now
            let dayOfMonth = calendar.component(.day, from: today)
            let selectedDate = calendar.date(byAdding: .day, value: dayOfMonth == 1 ? 1 : -1, to: today)!
            let dateLabel = DateFormatter()
            dateLabel.locale = Locale(identifier: "en_US")
            dateLabel.timeZone = .autoupdatingCurrent
            // Native calendar day cells omit the year; the compact control's
            // saved value below verifies the complete date including its year.
            dateLabel.setLocalizedDateFormatFromTemplate("EEEE MMMM d")

            let datePicker = app.descendants(matching: .any)
                .matching(identifier: "event.dateTime.starts.date")
                .firstMatch
            XCTAssertTrue(datePicker.waitForExistence(timeout: 5))
            // The inner Date Picker becomes a non-button accessibility element
            // while its calendar popup is open; its date value stays available.
            let dateValue = datePicker.descendants(matching: .any)
                .matching(NSPredicate(format: "label == %@", "Date Picker")).firstMatch
            let dateButton = datePicker.buttons.firstMatch
            XCTAssertTrue(dateButton.waitForExistence(timeout: 5))
            let initialPickerValue = dateValue.value as? String ?? ""
            let todayLabels = [DateFormatter.Style.short, .medium, .long, .full].map { style in
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "en_US")
                formatter.timeZone = .autoupdatingCurrent
                formatter.dateStyle = style
                formatter.timeStyle = .none
                return formatter.string(from: today)
            }
            XCTAssertTrue(todayLabels.contains { initialPickerValue.contains($0) },
                          "A new event date should default to today in the device timezone. Value: \(initialPickerValue)")
            dateButton.tap()
            let targetDay = app.buttons.matching(
                NSPredicate(format: "label CONTAINS %@", dateLabel.string(from: selectedDate))
            ).firstMatch
            XCTAssertTrue(targetDay.waitForExistence(timeout: 5),
                          "The native calendar should expose the selected day by its date label.")
            targetDay.tap()

            let savedPickerValue = dateValue.value as? String
            XCTAssertNotNil(savedPickerValue, "The selected date should remain readable from the native date control.")
            XCTAssertNotEqual(savedPickerValue, initialPickerValue,
                              "Choosing a different calendar day should change the full date control value.")
            let expectedDate = DateFormatter()
            expectedDate.locale = Locale(identifier: "en_US")
            expectedDate.timeZone = .autoupdatingCurrent
            expectedDate.dateStyle = .medium
            expectedDate.timeStyle = .none
            XCTAssertEqual(savedPickerValue, expectedDate.string(from: selectedDate))
            let done = app.navigationBars["Date and Time"].buttons["Done"]
            done.tap()
            // A compact calendar popup can consume the first outside tap.
            if done.waitForNonExistence(timeout: 1) == false { done.tap() }
            XCTAssertTrue(app.navigationBars["New Event"].waitForExistence(timeout: 5))
            editDate.tap()
            XCTAssertTrue(app.navigationBars["Date and Time"].waitForExistence(timeout: 5))
            XCTAssertEqual(dateValue.value as? String, savedPickerValue,
                           "Reopening the date editor should preserve the selected day.")
            XCTAssertFalse(app.buttons["Time Zone"].exists)

            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "New event date selection — \(appearance)"
            screenshot.lifetime = .keepAlways
            add(screenshot)
            app.terminate()
        }
    }

    @MainActor
    func testReadOnlyCollaboratorIdentityAndAccessStayReadableInLightAndDarkMode() throws {
        for appearance in ["Light", "Dark"] {
            let app = fixtureApplication()
            app.launchArguments += [
                "-UseProductionOnboarding", "-AppleLanguages", "(en)",
                "-AppleInterfaceStyle", appearance, "-appAppearance", appearance.lowercased(),
                "-ReadOnlyCollaboratorsUITest"
            ]
            app.launch()

            let workspace = app.buttons
                .matching(NSPredicate(format: "label CONTAINS %@", "Alex & Jordan"))
                .firstMatch
            XCTAssertTrue(workspace.waitForExistence(timeout: 8))
            workspace.tap()

            XCTAssertFalse(app.tabBars.buttons["Manage"].exists,
                           "Workspace navigation should no longer include a Manage tab.")
            HomeLayoutUITestSupport.select("Cards", in: app)
            let manageButton = app.buttons["home.manage.main"]
            XCTAssertTrue(manageButton.waitForExistence(timeout: 5))
            manageButton.tap()
            let dashboard = app.scrollViews["event.management.dashboard"]
            XCTAssertTrue(dashboard.waitForExistence(timeout: 5),
                          "A read-only collaborator should open the event dashboard directly.")
            XCTAssertFalse(app.buttons["event.management.people"].exists,
                           "The dashboard should not show a People menu entry.")
            let collaborators = app.buttons.matching(
                NSPredicate(format: "label CONTAINS[c] %@", "Collaborators")
            ).firstMatch
            XCTAssertTrue(collaborators.waitForExistence(timeout: 5))
            collaborators.tap()

            let alexRow = app.descendants(matching: .any).matching(
                NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", "Alex (You)", "View only")
            ).firstMatch
            XCTAssertTrue(alexRow.waitForExistence(timeout: 5), "The read-only viewer's name and access should remain visible.")
            XCTAssertTrue(app.navigationBars.staticTexts["Alex & Jordan’s Wedding"].exists,
                          "The management sheet keeps the selected event name in its navigation bar.")
            XCTAssertFalse(alexRow.elementType == .button, "A read-only participant row must not be exposed as an edit button.")
            XCTAssertTrue(alexRow.isHittable, "The read-only row should remain available to VoiceOver and touch exploration.")

            alexRow.tap()
            XCTAssertFalse(app.navigationBars["Participant"].exists, "Tapping a read-only row must not open the edit sheet.")
            app.terminate()
        }
    }

    @MainActor
    func testLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            fixtureApplication().launch()
        }
    }

    @MainActor
    func testHomeShareButtonOpensInvitation() throws {
        let app = fixtureApplication()
        app.launchArguments += ["-UseProductionOnboarding", "-AppleLanguages", "(en)"]
        app.launch()
        let workspace = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Maya & Theo")).firstMatch
        XCTAssertTrue(workspace.waitForExistence(timeout: 8))
        workspace.tap()

        let share = app.buttons["Share Invitation"]
        XCTAssertTrue(share.waitForExistence(timeout: 5))
        XCTAssertTrue(share.isHittable)
        // Tap the physical center, not an accessibility activation fallback.
        share.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(app.navigationBars["Invite"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testInvitationSharingLayoutAndEmailFlow() throws {
        for (appearance, largeText) in [("Dark", false), ("Light", false)] {
            let app = fixtureApplication()
            app.launchArguments += ["-UseProductionOnboarding", "-AppleLanguages", "(en)", "-AppleInterfaceStyle", appearance]
            if largeText {
                app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
            }
            app.launch()
            let workspace = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Maya & Theo")).firstMatch
            XCTAssertTrue(workspace.waitForExistence(timeout: 8))
            workspace.tap()

            let share = app.buttons["Share Invitation"]
            XCTAssertTrue(share.waitForExistence(timeout: 5))
            share.tap()

            XCTAssertTrue(app.navigationBars["Invite"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.buttons["Create Invitation Link"].exists)
            XCTAssertTrue(app.buttons["Invite by Email"].exists)
            XCTAssertFalse(app.navigationBars["Invite"].buttons["Share Invitation"].exists, "Do not repeat sharing in the invite toolbar.")
            XCTAssertFalse(app.switches["Approve Collaborators"].exists)
            XCTAssertFalse(app.buttons["Sharing Settings"].exists)
            XCTAssertFalse(app.buttons["Choose a Person"].exists)

            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "Invite — \(appearance)\(largeText ? " — Large Text" : "")"
            screenshot.lifetime = .keepAlways
            add(screenshot)

            let emailInvite = app.buttons["Invite by Email"]
            for _ in 0..<5 where !emailInvite.isHittable { app.swipeUp() }
            emailInvite.tap()
            XCTAssertTrue(app.navigationBars["Invite by Email"].waitForExistence(timeout: 3))
            XCTAssertTrue(app.textFields["Email"].exists)
            XCTAssertTrue(app.buttons["Create Invitation Link"].exists)
            app.navigationBars["Invite by Email"].buttons["Close"].tap()
            XCTAssertTrue(app.navigationBars["Invite"].waitForExistence(timeout: 3))
            app.terminate()
        }
    }

    @MainActor
    func testDraftEventRemovalFromMoreMenu() throws {
        for appearance in ["Light", "Dark"] {
            let app = fixtureApplication()
            app.launchArguments += ["-UseProductionOnboarding", "-AppleLanguages", "(en)", "-AppleInterfaceStyle", appearance]
            app.launch()
            let workspace = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Maya & Theo")).firstMatch
            XCTAssertTrue(workspace.waitForExistence(timeout: 8))
            workspace.tap()
            let mainCard = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Maya & Theo")).firstMatch
            XCTAssertTrue(mainCard.waitForExistence(timeout: 5))
            XCTAssertFalse(app.buttons["Event Actions"].exists, "Home must not show event actions.")
            mainCard.press(forDuration: 1)
            XCTAssertTrue(app.buttons["Edit Event"].waitForExistence(timeout: 3),
                          "Home should retain its non-destructive native shortcuts.")
            XCTAssertFalse(app.buttons["Delete Event"].exists,
                           "Deletion belongs in the invitation detail where its confirmation is presented.")
            XCTAssertFalse(app.buttons["Cancel Event"].exists,
                           "Home must not expose a cancellation action without its detail confirmation.")
            app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1)).tap()
            mainCard.tap()
            let actions = app.buttons["Event Actions"]
            XCTAssertTrue(actions.waitForExistence(timeout: 5))
            actions.tap()
            app.buttons["Delete Event"].tap()
            XCTAssertTrue(app.buttons["Cancel"].waitForExistence(timeout: 3))
            app.buttons["Cancel"].tap()
            XCTAssertTrue(actions.waitForExistence(timeout: 3), "Cancel must leave the event unchanged.")
            actions.tap()
            app.buttons["Delete Event"].tap()
            app.buttons["Delete Event"].tap()
            XCTAssertTrue(app.staticTexts["No Main Event"].waitForExistence(timeout: 5))
            app.terminate()
        }
    }

    @MainActor
    func testEventEditorDoesNotDuplicateAccountSyncStatus() throws {
        for appearance in ["Light", "Dark"] {
            let app = fixtureApplication()
            app.launchArguments += ["-UseProductionOnboarding", "-AppleLanguages", "(en)", "-AppleInterfaceStyle", appearance]
            app.launch()
            let workspace = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Maya & Theo")).firstMatch
            XCTAssertTrue(workspace.waitForExistence(timeout: 8))
            workspace.tap()
            XCTAssertTrue(app.tabBars.buttons["Home"].waitForExistence(timeout: 5))
            let card = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Maya & Theo")).firstMatch
            XCTAssertTrue(card.waitForExistence(timeout: 5))
            card.tap()
            let actions = app.buttons["Event Actions"]
            XCTAssertTrue(actions.waitForExistence(timeout: 5))
            actions.tap()
            let edit = app.buttons["Edit Event"]
            XCTAssertTrue(edit.waitForExistence(timeout: 5))
            edit.tap()
            XCTAssertTrue(app.navigationBars["Edit Event"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.textFields["Name your event"].isHittable)
            for copy in ["Sync status applies to saved changes, not unsaved edits in this form.", "Saved on this device", "Up to date", "Cloud sync needs attention"] {
                XCTAssertFalse(app.staticTexts[copy].exists)
            }
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "Event Editor Without Sync UI — \(appearance)"
            screenshot.lifetime = .keepAlways
            add(screenshot)
            app.terminate()
        }
    }

    @MainActor
    func testCancellationKeepsInvitationButClosesEditing() throws {
        for appearance in ["Light", "Dark"] {
            let app = fixtureApplication()
            app.launchArguments += [
                "-UseProductionOnboarding", "-home.layout", "overview",
                "-AppleLanguages", "(en)", "-AppleInterfaceStyle", appearance,
                "-appAppearance", appearance.lowercased()
            ]
            app.launch()
            addTeardownBlock {
                guard app.state == .runningForeground else { return }
                let tree = XCTAttachment(data: Data(app.debugDescription.utf8), uniformTypeIdentifier: "public.plain-text")
                tree.name = "Cancellation accessibility — \(appearance)"
                tree.lifetime = .deleteOnSuccess
                self.add(tree)
                let shot = XCTAttachment(screenshot: app.screenshot())
                shot.name = "Cancellation — \(appearance)"
                shot.lifetime = .deleteOnSuccess
                self.add(shot)
                app.terminate()
            }
            let workspace = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Maya & Theo")).firstMatch
            XCTAssertTrue(workspace.waitForExistence(timeout: 8))
            workspace.tap()
            let card = app.buttons["home.overview.mainEvent"]
            XCTAssertTrue(card.waitForExistence(timeout: 5))
            card.tap()
            XCTAssertTrue(app.navigationBars["Invitation"].waitForExistence(timeout: 5))
            let actions = app.descendants(matching: .any).matching(identifier: "invitation.actions").firstMatch
            XCTAssertTrue(actions.waitForExistence(timeout: 5))
            actions.tap()
            app.buttons["Cancel Event"].tap()
            let confirmation = app.alerts.firstMatch
            XCTAssertTrue(confirmation.waitForExistence(timeout: 3))
            confirmation.buttons["Cancel"].tap()
            XCTAssertTrue(app.buttons["invitation.edit.title"].waitForExistence(timeout: 5),
                          "Dismissing cancellation must leave the invitation editable.")
            actions.tap()
            app.buttons["Cancel Event"].tap()
            XCTAssertTrue(confirmation.waitForExistence(timeout: 3))
            confirmation.buttons["Cancel Event"].tap()
            XCTAssertTrue(card.waitForExistence(timeout: 5), "Cancellation retains the event instead of deleting it.")
            card.tap()
            XCTAssertTrue(app.navigationBars["Invitation"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.staticTexts["Cancelled"].waitForExistence(timeout: 5))
            XCTAssertFalse(app.buttons["invitation.edit.title"].exists)
            XCTAssertFalse(app.buttons["invitation.edit.date"].exists)
            XCTAssertFalse(app.buttons["invitation.edit.location"].exists)
            XCTAssertFalse(app.buttons["Going"].isEnabled)
            XCTAssertFalse(app.buttons["Not Sure"].isEnabled)
            XCTAssertFalse(app.buttons["Not Going"].isEnabled)
            // Cancellation can remove the entire conditional menu when no
            // permitted actions remain. If retained for exports, it must still
            // omit all planning/lifecycle edits.
            if actions.exists { actions.tap() }
            XCTAssertFalse(app.buttons["Edit Event"].exists)
            XCTAssertFalse(app.buttons["Cancel Event"].exists)
            app.terminate()
        }
    }

    @MainActor
    func testArchiveSubeventFromEventDetailsMoreMenu() throws {
        let app = fixtureApplication()
        app.launchArguments += ["-UseProductionOnboarding", "-AppleLanguages", "(en)"]
        app.launch()
        let workspace = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Alex & Jordan")).firstMatch
        XCTAssertTrue(workspace.waitForExistence(timeout: 8))
        workspace.tap()
        let card = app.buttons.matching(NSPredicate(
            format: "identifier == %@ AND label CONTAINS %@", "home.event.child", "Ceremony"
        )).firstMatch
        let homeScroll = app.scrollViews.firstMatch
        XCTAssertTrue(homeScroll.waitForExistence(timeout: 5))
        // The sample ceremony is at 16:00 while the main event keeps the current
        // clock time, so chronological order can put it above or below Home's focus.
        for _ in 0..<4 where !card.isHittable { homeScroll.swipeDown() }
        for _ in 0..<8 where !card.isHittable { homeScroll.swipeUp() }
        XCTAssertTrue(card.isHittable)
        XCTAssertFalse(app.buttons["Event Actions"].exists, "Home must not show event actions.")
        card.tap()
        let actions = app.buttons["Event Actions"]
        XCTAssertTrue(actions.waitForExistence(timeout: 5))
        actions.tap()
        app.buttons["Archive Event"].tap()
        let confirmation = app.alerts.firstMatch
        XCTAssertTrue(confirmation.waitForExistence(timeout: 3))
        confirmation.buttons["Cancel"].tap()
        XCTAssertTrue(actions.exists, "Cancel must keep the sub-event open.")
        actions.tap()
        app.buttons["Archive Event"].tap()
        XCTAssertTrue(confirmation.waitForExistence(timeout: 3))
        confirmation.buttons["Archive Event"].tap()
        XCTAssertTrue(app.buttons["Share Invitation"].waitForExistence(timeout: 5), "Archiving must return to Home.")
        XCTAssertTrue(card.waitForNonExistence(timeout: 5), "Archived sub-events must leave Home.")
        app.terminate()
    }

    @MainActor
    func testDecidePrimerSimpleLayoutAndDismissal() throws {
        continueAfterFailure = false
        let app = fixtureApplication()
        app.launchArguments += [
            "-UseProductionOnboarding", "-AppleLanguages", "(en)",
            "-hasSeenDecideTimelinePrimer", "NO"
        ]
        app.launch()
        defer { app.terminate() }
        let workspace = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Alex & Jordan")).firstMatch
        XCTAssertTrue(workspace.waitForExistence(timeout: 8))
        workspace.tap()
        let tab = app.tabBars.buttons["Decide"]
        let decide = tab.exists ? tab : app.buttons["Decide"].firstMatch
        XCTAssertTrue(decide.waitForExistence(timeout: 8))
        decide.tap()

        let action = app.buttons["decide-primer-continue"]
        XCTAssertTrue(action.waitForExistence(timeout: 5))
        XCTAssertEqual(action.label, "Continue")
        XCTAssertTrue(action.isHittable)
        XCTAssertGreaterThanOrEqual(action.frame.height, 44)
        XCTAssertTrue(app.windows.firstMatch.frame.contains(action.frame))
        let heading = app.staticTexts["primer.heading"]
        XCTAssertTrue(heading.exists)
        XCTAssertEqual(heading.label, "Help your team choose")
        XCTAssertTrue(app.descendants(matching: .any)["primer.brandHeader"].firstMatch.exists)
        XCTAssertFalse(app.sheets.firstMatch.exists, "Education should use the welcome screen's edge-to-edge presentation.")
        XCTAssertLessThan(action.frame.width, app.windows.firstMatch.frame.width * 0.7,
                          "Continue should be a centered, content-sized action.")
        for (identifier, text) in [
            ("pass", "Swipe left if it’s not for you."),
            ("maybe", "Swipe up if you’re not sure."),
            ("love", "Swipe right if you love it. Your input helps the host choose.")
        ] {
            let row = app.descendants(matching: .any)["decide.primer.feature.\(identifier)"].firstMatch
            XCTAssertTrue(row.exists)
            XCTAssertTrue(row.label.contains(text))
        }
        XCTAssertFalse(app.descendants(matching: .any)["decide-primer-preview"].exists)
        XCTAssertFalse(app.staticTexts["decide-primer-feedback"].exists)
        XCTAssertFalse(app.buttons["decide-primer-love"].exists)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "practice")).firstMatch.exists)
        let loveRow = app.descendants(matching: .any)["decide.primer.feature.love"].firstMatch
        if loveRow.frame.maxY > action.frame.minY - 8 { app.scrollViews.firstMatch.swipeUp() }
        XCTAssertLessThanOrEqual(loveRow.frame.maxY, action.frame.minY - 8)
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = "Simple welcome-style swipe primer"
        image.lifetime = .keepAlways
        add(image)
        action.tap()
        XCTAssertTrue(action.waitForNonExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Undo last decision"].exists, "Reading the primer must not record a decision.")
        XCTAssertTrue(app.buttons["decision-event-filter"].exists)
        let ideasTab = app.tabBars.buttons["Ideas"]
        (ideasTab.exists ? ideasTab : app.buttons["Ideas"].firstMatch).tap()
        decide.tap()
        XCTAssertFalse(action.exists, "The completed primer should stay dismissed on another Decide visit.")
    }

    @MainActor
    private func fixtureApplication() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += [
            "-DisableProductionFlowSimulation",
            "-SkipAuthentication",
            "-SeedDevelopmentData",
            "-UseEphemeralDataStore"
        ]
        return app
    }
}
