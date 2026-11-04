import XCTest

final class IdeaSchedulingUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testEventIdeaScheduleCancellationAndConfirmationInBothAppearances() throws {
        for appearance in ["Light", "Dark"] {
            let app = fixtureApplication(appearance: appearance)
            app.launch()
            addTeardownBlock {
                guard app.state == .runningForeground else { return }
                let tree = XCTAttachment(data: Data(app.debugDescription.utf8), uniformTypeIdentifier: "public.plain-text")
                tree.name = "Idea scheduling accessibility — \(appearance)"
                tree.lifetime = .deleteOnSuccess
                self.add(tree)
                let shot = XCTAttachment(screenshot: app.screenshot())
                shot.name = "Idea scheduling — \(appearance)"
                shot.lifetime = .deleteOnSuccess
                self.add(shot)
                app.terminate()
            }
            openSeededEventIdea(in: app)

            let schedule = app.buttons["idea.schedule.action"]
            XCTAssertTrue(schedule.waitForExistence(timeout: 5),
                          "A dated event idea should offer Schedule in \(appearance) appearance.")
            schedule.tap()

            let date = app.buttons["idea.schedule.date"]
            let location = app.buttons["idea.schedule.location"]
            XCTAssertTrue(app.navigationBars["Schedule Event"].waitForExistence(timeout: 5))
            XCTAssertTrue(date.waitForExistence(timeout: 5))
            XCTAssertTrue(location.exists)
            let teamSummary = app.descendants(matching: .any)["idea.schedule.teamInput"]
            XCTAssertTrue(teamSummary.waitForExistence(timeout: 5),
                          "Schedule should show the compact team response summary.")
            XCTAssertNotEqual(teamSummary.elementType, .button,
                              "The compact team summary should be informational, not a voting control.")
            let teamSummaryLabel = teamSummary.label.lowercased()
            XCTAssertTrue(teamSummaryLabel.contains("response") || teamSummaryLabel.contains("unanswered"),
                          "The compact summary should communicate team response state. Label: \(teamSummary.label)")
            XCTAssertTrue(date.label.contains(":"), "The proposal should carry its time into Schedule.")
            XCTAssertTrue(location.label.contains("Willow & Stone Estate"),
                          "The proposal location should be carried into Schedule. Label: \(location.label)")
            let proposedDate = date.label
            let proposedLocation = location.label

            date.tap()
            XCTAssertTrue(app.navigationBars["Date and Time"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.buttons["idea.schedule.dateTime.cancel"].exists)
            app.buttons["idea.schedule.dateTime.cancel"].tap()
            XCTAssertTrue(app.navigationBars["Schedule Event"].waitForExistence(timeout: 5))
            XCTAssertEqual(date.label, proposedDate,
                           "Cancelling the nested date editor should preserve the proposal in the Schedule draft.")

            date.tap()
            XCTAssertTrue(app.navigationBars["Date and Time"].waitForExistence(timeout: 5))
            let allDay = app.switches["idea.schedule.dateTime.allDay"]
            XCTAssertTrue(allDay.waitForExistence(timeout: 5))
            let originalAllDayValue = allDay.value as? String
            XCTAssertNotNil(originalAllDayValue)
            allDay.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
            XCTAssertNotEqual(allDay.value as? String, originalAllDayValue,
                              "The nested date editor should accept an all-day draft before saving.")
            app.buttons["idea.schedule.dateTime.save"].tap()
            XCTAssertTrue(app.navigationBars["Schedule Event"].waitForExistence(timeout: 5))

            location.tap()
            XCTAssertTrue(app.navigationBars["Location"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.buttons["idea.schedule.locationPicker.save"].exists)
            app.buttons["idea.schedule.locationPicker.save"].tap()
            XCTAssertTrue(app.navigationBars["Schedule Event"].waitForExistence(timeout: 5))
            XCTAssertEqual(location.label, proposedLocation,
                           "Confirming the nested location editor should preserve the selected place.")
            app.buttons["idea.schedule.removeLocation"].tap()
            XCTAssertTrue(location.label.contains("Add Location"),
                          "Removing the selected place should edit only the Schedule draft.")

            app.buttons["idea.schedule.cancel"].tap()
            XCTAssertTrue(schedule.waitForExistence(timeout: 5),
                           "Cancelling the outer Schedule sheet should return to the editable idea.")
            XCTAssertEqual(linkedHomeEventCount(in: app), 0,
                           "Cancelling Schedule must not add an event to Home.")

            openReceptionIdeaFromCurrentWorkspace(in: app)
            let reopenedSchedule = app.buttons["idea.schedule.action"]
            XCTAssertTrue(reopenedSchedule.waitForExistence(timeout: 5),
                          "Cancelling Schedule should leave the idea available to schedule.")
            reopenedSchedule.tap()
            XCTAssertTrue(app.navigationBars["Schedule Event"].waitForExistence(timeout: 5))
            XCTAssertEqual(app.buttons["idea.schedule.date"].label, proposedDate,
                           "Cancelling Schedule should discard the all-day draft and retain the proposed date and time.")
            XCTAssertEqual(app.buttons["idea.schedule.location"].label, proposedLocation,
                           "Cancelling Schedule should discard location removal and retain the proposed location.")
            let confirm = app.buttons["idea.schedule.confirm"]
            XCTAssertTrue(confirm.isEnabled)
            confirm.tap()

            let viewEvent = app.buttons["idea.schedule.view-event"]
            XCTAssertTrue(viewEvent.waitForExistence(timeout: 6),
                          "Confirmation should expose the linked event from the idea.")
            XCTAssertEqual(viewEvent.label, "View Event",
                           "The scheduled idea should expose its linked event as the next action.")
            XCTAssertFalse(app.buttons["idea.schedule.scheduled"].exists,
                           "The old disabled Scheduled indicator should be replaced by View Event.")
            XCTAssertFalse(app.buttons["Edit idea"].exists,
                           "Scheduled content should be edited from its linked event, without reopening the old proposal editor.")
            XCTAssertFalse(app.staticTexts.matching(
                NSPredicate(format: "label BEGINSWITH[c] %@", "Proposed ")
            ).firstMatch.exists,
                           "A scheduled event idea should not retain the Proposed Event label.")
            XCTAssertFalse(app.buttons["idea.schedule.action"].exists,
                           "A scheduled idea should not expose a second Schedule action.")
            XCTAssertEqual(linkedHomeEventCount(in: app), 1,
                           "Home should show one event linked from this idea.")
            openReceptionIdeaFromCurrentWorkspace(in: app)
            XCTAssertTrue(viewEvent.waitForExistence(timeout: 5),
                          "Returning from Home should reopen the scheduled idea route.")

            viewEvent.tap()
            assertCanonicalLinkedReception(in: app, proposedDate: proposedDate)
            XCTAssertFalse(app.buttons["idea.schedule.action"].exists)
            let nativeBack = app.navigationBars.buttons.firstMatch
            XCTAssertTrue(nativeBack.waitForExistence(timeout: 5))
            nativeBack.tap()
            XCTAssertTrue(viewEvent.waitForExistence(timeout: 5),
                          "The system Back action should return to the same scheduled idea.")

            // The native interactive pop should preserve the same idea route too.
            viewEvent.tap()
            assertCanonicalLinkedReception(in: app, proposedDate: proposedDate)
            let edgeStart = app.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.5))
            let edgeEnd = app.coordinate(withNormalizedOffset: CGVector(dx: 0.82, dy: 0.5))
            edgeStart.press(forDuration: 0.05, thenDragTo: edgeEnd)
            XCTAssertTrue(viewEvent.waitForExistence(timeout: 5),
                          "The interactive Back gesture should return to the same scheduled idea.")

            // Reopening the scheduled idea must not create a duplicate Home event.
            XCTAssertEqual(linkedHomeEventCount(in: app), 1,
                           "Reopening the scheduled idea must not create a duplicate Home event.")
            app.terminate()
        }
    }

    @MainActor
    func testReadOnlyCollaboratorCannotScheduleEventIdea() throws {
        let app = fixtureApplication(appearance: "Light", readOnlyCollaborator: true)
        app.launch()
        openSeededEventIdea(in: app)

        XCTAssertFalse(app.buttons["idea.schedule.action"].exists,
                       "A view-only collaborator should not be offered the Schedule action.")
        XCTAssertFalse(app.buttons["idea.schedule.confirm"].exists,
                       "A view-only collaborator should not be able to open Schedule confirmation.")
        XCTAssertEqual(linkedHomeEventCount(in: app), 0)
        app.terminate()
    }

    @MainActor
    private func assertCanonicalLinkedReception(in app: XCUIApplication, proposedDate: String) {
        XCTAssertTrue(app.navigationBars["Invitation"].waitForExistence(timeout: 6))
        let eventRoute = app.descendants(matching: .any)["idea.schedule.linked-event.title"]
        XCTAssertTrue(eventRoute.waitForExistence(timeout: 5),
                      "View Event should open the canonical linked invitation.")
        let title = app.buttons["invitation.edit.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5),
                      "The linked event should expose its canonical hero title.")
        XCTAssertTrue(title.label.localizedCaseInsensitiveContains("Reception"),
                      "The linked event should retain the proposal title. Label: \(title.label)")
        XCTAssertFalse(title.label.localizedCaseInsensitiveContains("Proposed"),
                       "The scheduled event should use the canonical event title, without a Proposed label.")

        let date = app.buttons["invitation.edit.date"]
        XCTAssertTrue(date.waitForExistence(timeout: 5),
                      "The linked invitation should show its canonical event schedule.")
        XCTAssertTrue(date.label.contains("2027"),
                      "The linked event should preserve the proposal's 2027 date. Label: \(date.label)")
        let proposalYear = proposedDate.contains("2027")
        XCTAssertTrue(proposalYear,
                      "The seeded Reception proposal should carry its 2027 date into the Schedule draft. Label: \(proposedDate)")

        let location = app.buttons["invitation.edit.location"]
        XCTAssertTrue(location.waitForExistence(timeout: 5),
                      "The linked invitation should show its canonical event location.")
        XCTAssertTrue(location.label.contains("Willow & Stone Estate"),
                      "The selected proposal location should carry into the linked event. Label: \(location.label)")
        XCTAssertFalse(app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "Proposed Event")
        ).firstMatch.exists,
                       "The linked canonical invitation should not be presented as a proposal.")
    }

    @MainActor
    private func fixtureApplication(appearance: String, readOnlyCollaborator: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-DisableProductionFlowSimulation",
            "-SkipAuthentication",
            "-SeedDevelopmentData",
            "-UseEphemeralDataStore",
            "-UseProductionOnboarding",
            "-home.layout", "overview",
            "-AppleLanguages", "(en)",
            "-AppleInterfaceStyle", appearance,
            "-appAppearance", appearance.lowercased()
        ]
        if readOnlyCollaborator {
            app.launchArguments.append("-ReadOnlyCollaboratorsUITest")
        }
        return app
    }

    @MainActor
    private func openSeededEventIdea(in app: XCUIApplication) {
        XCTAssertTrue(app.buttons["Filter events"].waitForExistence(timeout: 10),
                      "The deterministic workspace library should open.")
        let workspace = app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "Alex & Jordan")
        ).firstMatch
        XCTAssertTrue(workspace.waitForExistence(timeout: 8))
        workspace.tap()

        openReceptionIdeaFromCurrentWorkspace(in: app)
    }

    @MainActor
    private func openReceptionIdeaFromCurrentWorkspace(in app: XCUIApplication) {
        let ideasTab = app.tabBars.buttons["Ideas"]
        XCTAssertTrue(ideasTab.waitForExistence(timeout: 8))
        ideasTab.tap()
        if app.buttons["idea.schedule.action"].exists || app.buttons["idea.schedule.view-event"].exists {
            app.navigationBars.buttons.firstMatch.tap()
        }
        let reception = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "Reception")
        ).firstMatch
        XCTAssertTrue(reception.waitForExistence(timeout: 8),
                      "The seeded Reception proposal should be available in Ideas.")
        let ideasScroll = app.scrollViews.firstMatch
        for _ in 0..<8 where !reception.isHittable { ideasScroll.swipeUp() }
        XCTAssertTrue(reception.isHittable)
        reception.tap()
    }

    @MainActor
    private func linkedHomeEventCount(in app: XCUIApplication) -> Int {
        let homeTab = app.tabBars.buttons["Home"]
        XCTAssertTrue(homeTab.waitForExistence(timeout: 5))
        homeTab.tap()
        let linkedEvents = app.buttons.matching(
            NSPredicate(
                format: "(identifier == %@ OR identifier BEGINSWITH %@) AND label BEGINSWITH[c] %@",
                "home.event.child", "home.overview.event.", "Reception"
            )
        )
        return linkedEvents.count
    }
}
