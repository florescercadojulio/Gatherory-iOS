import XCTest

final class IdeasApprovalUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testPersonalLoveAppearsInLikedAndApprovalRequiresConfirmation() throws {
        for appearance in ["Light", "Dark"] {
            let app = birthdayFixture(appearance: appearance)
            app.launch()
            openBirthdayWorkspace(in: app)

            app.tabBars.buttons["Decide"].tap()
            let candlelit = app.buttons.matching(
                NSPredicate(format: "label CONTAINS[c] %@", "Candlelit birthday table")
            ).firstMatch
            XCTAssertTrue(candlelit.waitForExistence(timeout: 8),
                          "The unresponded idea should be available to the current viewer in Decide.")
            swipeRight(on: candlelit)
            XCTAssertTrue(app.buttons["Undo last decision"].waitForExistence(timeout: 5),
                          "Loving the idea should record the viewer's personal response.")

            app.tabBars.buttons["Ideas"].tap()
            let filter = app.buttons["Filter ideas"]
            XCTAssertTrue(filter.waitForExistence(timeout: 6))
            filter.tap()
            let likedOption = app.buttons["Liked"]
            XCTAssertTrue(likedOption.waitForExistence(timeout: 4))
            likedOption.tap()
            XCTAssertTrue(app.buttons.matching(
                NSPredicate(format: "label CONTAINS[c] %@", "Candlelit birthday table")
            ).firstMatch.waitForExistence(timeout: 6),
                          "The viewer-loved idea should appear in Liked.")
            XCTAssertFalse(app.buttons.matching(
                NSPredicate(format: "label CONTAINS[c] %@", "Family-style pasta dinner")
            ).firstMatch.exists,
                           "An idea with no love response from this viewer should not appear in Liked.")

            // Approve directly from the viewer's Liked collection.
            let idea = app.buttons.matching(
                NSPredicate(format: "label CONTAINS[c] %@", "Candlelit birthday table")
            ).firstMatch
            XCTAssertTrue(idea.waitForExistence(timeout: 6))
            for _ in 0..<8 where !idea.isHittable { app.scrollViews.firstMatch.swipeUp() }
            idea.press(forDuration: 1.0)
            let approve = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Approve")).firstMatch
            XCTAssertTrue(approve.waitForExistence(timeout: 5),
                          "Long-press should expose the explicit Approve action.")
            approve.tap()
            XCTAssertTrue(app.staticTexts["idea.approval.title"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.descendants(matching: .any)["idea.approval.event"].exists,
                          "The approval sheet should identify the parent event.")
            XCTAssertTrue(app.descendants(matching: .any)["idea.approval.cost"].exists,
                          "The approval sheet should show the idea's estimated cost.")
            app.buttons["idea.approval.cancel"].tap()
            XCTAssertFalse(app.staticTexts["idea.approval.title"].exists,
                           "Cancel should close the sheet without approving the idea.")
            XCTAssertFalse(app.buttons.matching(
                NSPredicate(format: "label CONTAINS[c] %@", "Family-style pasta dinner")
            ).firstMatch.exists, "Cancelling preserves the personal Liked collection.")

            idea.press(forDuration: 1.0)
            let retryApprove = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Approve")).firstMatch
            XCTAssertTrue(retryApprove.waitForExistence(timeout: 5),
                          "Cancel should leave the idea available for approval.")
            retryApprove.tap()
            let confirm = app.buttons["idea.approval.confirm"]
            XCTAssertTrue(confirm.waitForExistence(timeout: 5))
            confirm.tap()
            XCTAssertTrue(app.staticTexts["idea.approval.title"].waitForNonExistence(timeout: 5))
            XCTAssertFalse(app.buttons.matching(
                NSPredicate(format: "label CONTAINS[c] %@", "Family-style pasta dinner")
            ).firstMatch.exists, "Approval preserves the personal Liked collection.")
            XCTAssertTrue(idea.exists, "An accepted idea retains the viewer's personal Love It response.")

            filter.tap()
            let approvedOption = app.buttons["Approved"]
            XCTAssertTrue(approvedOption.waitForExistence(timeout: 4))
            approvedOption.tap()
            XCTAssertTrue(app.buttons.matching(
                NSPredicate(format: "label CONTAINS[c] %@", "Candlelit birthday table")
            ).firstMatch.waitForExistence(timeout: 6),
                          "Confirmation should move the idea into Approved.")
            XCTAssertEqual(app.buttons.matching(
                NSPredicate(format: "label CONTAINS[c] %@", "Candlelit birthday table")
            ).count, 1, "Approval should not duplicate the idea.")
            app.terminate()
        }
    }

    @MainActor
    func testEventIdeaLongPressRetainsScheduleFlow() throws {
        for appearance in ["Light", "Dark"] {
            let app = standardFixture(appearance: appearance)
            app.launch()
            XCTAssertTrue(app.buttons["Filter events"].waitForExistence(timeout: 10))
            let workspace = app.buttons.matching(
                NSPredicate(format: "label CONTAINS %@", "Alex & Jordan")
            ).firstMatch
            XCTAssertTrue(workspace.waitForExistence(timeout: 8))
            workspace.tap()
            app.tabBars.buttons["Ideas"].tap()
            let reception = app.buttons.matching(
                NSPredicate(format: "label CONTAINS[c] %@", "Reception")
            ).firstMatch
            XCTAssertTrue(reception.waitForExistence(timeout: 8))
            for _ in 0..<8 where !reception.isHittable { app.scrollViews.firstMatch.swipeUp() }
            reception.press(forDuration: 1.0)
            let schedule = app.buttons["Schedule"]
            XCTAssertTrue(schedule.waitForExistence(timeout: 5),
                          "Long-pressing an event idea should retain Schedule.")
            schedule.tap()
            XCTAssertTrue(app.navigationBars["Schedule Event"].waitForExistence(timeout: 5),
                          "Event ideas should open the existing schedule editor.")
            XCTAssertTrue(app.buttons["idea.schedule.date"].waitForExistence(timeout: 5))
            app.buttons["idea.schedule.cancel"].tap()
            XCTAssertFalse(app.navigationBars["Schedule Event"].exists,
                           "Cancelling should leave the event idea unscheduled.")
            app.terminate()
        }
    }

    @MainActor
    private func openBirthdayWorkspace(in app: XCUIApplication) {
        let workspace = app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "Maya’s Birthday Dinner")
        ).firstMatch
        XCTAssertTrue(workspace.waitForExistence(timeout: 8))
        workspace.tap()
    }

    @MainActor
    private func swipeRight(on element: XCUIElement) {
        let start = element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let end = element.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: end)
    }

    @MainActor
    private func birthdayFixture(appearance: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = baseArguments(appearance: appearance) + ["-UseBirthdayMarketingFixture"]
        return app
    }

    @MainActor
    private func standardFixture(appearance: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = baseArguments(appearance: appearance)
        return app
    }

    private func baseArguments(appearance: String) -> [String] {
        [
            "-DisableProductionFlowSimulation",
            "-SkipAuthentication",
            "-SeedDevelopmentData",
            "-UseEphemeralDataStore",
            "-UseProductionOnboarding",
            "-hasSeenDecideTimelinePrimer", "YES",
            "-home.layout", "cards",
            "-AppleLanguages", "(en)",
            "-AppleInterfaceStyle", appearance,
            "-appAppearance", appearance.lowercased()
        ]
    }
}
