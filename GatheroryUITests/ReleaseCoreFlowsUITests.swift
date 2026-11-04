import XCTest

final class ReleaseCoreFlowsUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testCreateEventFromScratchOpensHomeAndInvitationShowsTitleAndToday() throws {
        for appearance in ["Light", "Dark"] {
            let app = fixtureApplication(appearance: appearance)
            app.launch()
            defer { app.terminate() }

            XCTAssertTrue(app.buttons["Filter events"].waitForExistence(timeout: 8))
            let title = "Release Event \(UUID().uuidString.prefix(8))"
            let creationMoment = Date.now

            app.buttons["workspace.add"].tap()
            app.buttons["workspace.startFromScratch"].tap()
            let name = app.textFields["Event name"]
            XCTAssertTrue(name.waitForExistence(timeout: 5))
            name.tap()
            name.typeText(title)
            app.navigationBars.buttons["Create"].tap()

            XCTAssertTrue(app.tabBars.buttons["Home"].waitForExistence(timeout: 8),
                          "Creating should automatically open the new workspace Home tab.")
            let homeEvent = mainEventCard(in: app)
            XCTAssertTrue(homeEvent.waitForExistence(timeout: 5))
            XCTAssertTrue(homeEvent.label.contains(title), "Home should show the newly created event title.")

            let expectedHomeDate = formattedDate(creationMoment, style: .long)
            XCTAssertTrue(homeEvent.label.contains(expectedHomeDate), "Home should retain the new event's default date.")
            homeEvent.tap()

            let invitationTitle = app.buttons["invitation.edit.title"]
            XCTAssertTrue(invitationTitle.waitForExistence(timeout: 8), "The event invitation detail should open.")
            XCTAssertTrue(invitationTitle.label.contains(title), "The invitation should display the new event title.")
            let invitationDate = app.buttons["invitation.edit.date"]
            XCTAssertTrue(invitationDate.waitForExistence(timeout: 5))
            let expectedInvitationDate = formattedDate(creationMoment, style: .full)
            XCTAssertTrue(invitationDate.label.contains(expectedInvitationDate), "The invitation should display today's event date.")

            app.terminate()
        }
    }

    @MainActor
    func testAddEditDecideAndUndoManualIdea() throws {
        for appearance in ["Light", "Dark"] {
            let app = fixtureApplication(appearance: appearance)
            app.launch()
            defer { app.terminate() }

            let eventTitle = "Idea Test Event \(UUID().uuidString.prefix(8))"
            createWorkspace(named: eventTitle, in: app)
            XCTAssertTrue(app.tabBars.buttons["Home"].waitForExistence(timeout: 8))

            app.tabBars.buttons["Ideas"].tap()
            let addIdea = app.buttons["Add idea"]
            XCTAssertTrue(addIdea.waitForExistence(timeout: 5))
            addIdea.tap()
            let otherCategory = app.buttons["Other"]
            XCTAssertTrue(otherCategory.waitForExistence(timeout: 5))
            for _ in 0..<4 where !otherCategory.isHittable { app.swipeUp() }
            XCTAssertTrue(otherCategory.isHittable, "Other remains reachable in the native category chooser sheet.")
            otherCategory.tap()
            XCTAssertTrue(app.navigationBars.staticTexts["New Idea"].waitForExistence(timeout: 5))

            let initialTitle = "Planning idea \(UUID().uuidString.prefix(8))"
            let titleField = app.textFields["Idea title (optional)"]
            XCTAssertTrue(titleField.waitForExistence(timeout: 5))
            titleField.tap()
            titleField.typeText(initialTitle)
            app.navigationBars.buttons["Add"].tap()

            let ideaCard = app.buttons.matching(
                NSPredicate(format: "label CONTAINS %@", initialTitle)
            ).firstMatch
            XCTAssertTrue(ideaCard.waitForExistence(timeout: 8), "The manually added idea should appear in Ideas.")
            ideaCard.tap()
            XCTAssertTrue(app.buttons["Edit idea"].waitForExistence(timeout: 5))
            app.buttons["Edit idea"].tap()

            let editTitle = app.textFields["Idea title (optional)"]
            XCTAssertTrue(editTitle.waitForExistence(timeout: 5))
            XCTAssertEqual(editTitle.value as? String, initialTitle)
            let savedTitle = "Edited idea \(UUID().uuidString.prefix(8))"
            editTitle.tap()
            editTitle.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: initialTitle.count) + savedTitle)
            app.navigationBars.buttons["Save"].tap()

            XCTAssertTrue(app.staticTexts[savedTitle].waitForExistence(timeout: 5), "The saved title should appear in the idea detail.")
            XCTAssertTrue(app.tabBars.buttons["Decide"].waitForExistence(timeout: 5))
            app.tabBars.buttons["Decide"].tap()

            let decisionCard = app.buttons.matching(
                NSPredicate(format: "label CONTAINS %@", savedTitle)
            ).firstMatch
            XCTAssertTrue(decisionCard.waitForExistence(timeout: 8), "The saved idea should be available for a real decision.")
            XCTAssertFalse(app.buttons["Undo last decision"].exists, "A new event should start without a prior decision to undo.")

            let swipeStart = decisionCard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            let swipeEnd = decisionCard.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5))
            swipeStart.press(forDuration: 0.05, thenDragTo: swipeEnd)

            let undo = app.buttons["Undo last decision"]
            XCTAssertTrue(undo.waitForExistence(timeout: 5), "A real swipe decision should expose Undo.")
            XCTAssertTrue(decisionCard.waitForNonExistence(timeout: 3), "The decided idea should leave the unanswered queue.")
            undo.tap()
            XCTAssertTrue(decisionCard.waitForExistence(timeout: 5), "Undo should restore the idea to the decision queue.")

            app.terminate()
        }
    }

    @MainActor
    private func mainEventCard(in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(
            format: "identifier == %@ OR identifier == %@",
            "home.overview.mainEvent", "home.event.main"
        )).firstMatch
    }

    @MainActor
    private func createWorkspace(named title: String, in app: XCUIApplication) {
        XCTAssertTrue(app.buttons["workspace.add"].waitForExistence(timeout: 8))
        app.buttons["workspace.add"].tap()
        app.buttons["workspace.startFromScratch"].tap()
        let name = app.textFields["Event name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText(title)
        app.navigationBars.buttons["Create"].tap()

        XCTAssertTrue(app.tabBars.buttons["Home"].waitForExistence(timeout: 8),
                      "Creating should automatically open the new workspace Home tab.")
        let homeEvent = mainEventCard(in: app)
        XCTAssertTrue(homeEvent.waitForExistence(timeout: 5))
        XCTAssertTrue(homeEvent.label.contains(title))
    }

    @MainActor
    private func fixtureApplication(appearance: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += [
            "-DisableProductionFlowSimulation",
            "-SkipAuthentication",
            "-SeedDevelopmentData",
            "-UseEphemeralDataStore",
            "-UseProductionOnboarding",
            "-hasSeenDecideTimelinePrimer", "YES",
            "-AppleLanguages", "(en)",
            "-AppleInterfaceStyle", appearance,
            "-appAppearance", appearance.lowercased()
        ]
        return app
    }

    private func formattedDate(_ date: Date, style: DateFormatter.Style) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateStyle = style
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}
