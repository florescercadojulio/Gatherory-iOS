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
        app.launch()

        XCTAssertTrue(
            app.navigationBars["Workspaces"].waitForExistence(timeout: 8),
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
        for (appearance, largeText) in [("Dark", false), ("Light", false), ("Dark", true)] {
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
            XCTAssertFalse(app.buttons["Delete Event"].exists, "Home must not expose removal through a context menu.")
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
            app.launchArguments += ["-UseProductionOnboarding", "-AppleLanguages", "(en)", "-AppleInterfaceStyle", appearance]
            app.launch()
            let workspace = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Maya & Theo")).firstMatch
            XCTAssertTrue(workspace.waitForExistence(timeout: 8))
            workspace.tap()
            let card = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Maya & Theo")).firstMatch
            XCTAssertTrue(card.waitForExistence(timeout: 5))
            card.tap()
            let actions = app.buttons["Event Actions"]
            XCTAssertTrue(actions.waitForExistence(timeout: 5))
            actions.tap()
            app.buttons["Cancel Event"].tap()
            let confirmation = app.alerts.firstMatch
            XCTAssertTrue(confirmation.waitForExistence(timeout: 3))
            confirmation.buttons["Cancel"].tap()
            XCTAssertTrue(actions.exists)
            actions.tap()
            app.buttons["Cancel Event"].tap()
            XCTAssertTrue(confirmation.waitForExistence(timeout: 3))
            confirmation.buttons["Cancel Event"].tap()
            XCTAssertTrue(card.waitForExistence(timeout: 5), "Cancellation retains the invitation instead of deleting it.")
            card.tap()
            XCTAssertFalse(app.buttons["Edit Event"].exists)
            XCTAssertFalse(app.buttons["Cancel Event"].exists)
            XCTAssertTrue(app.staticTexts["Cancelled"].waitForExistence(timeout: 3))
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "Cancelled Invitation — \(appearance)"
            screenshot.lifetime = .keepAlways
            add(screenshot)
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
        let card = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Ceremony,")).firstMatch
        for _ in 0..<8 where !card.isHittable { app.swipeUp() }
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
    func testDecidePrimerPracticeAndLayout() throws {
        for (appearance, largeText, language) in [
            ("Light", false, "en"), ("Dark", false, "en"),
            ("Light", true, "en"), ("Dark", false, "es")
        ] {
            let app = fixtureApplication()
            app.launchArguments += [
                "-UseProductionOnboarding", "-AppleLanguages", "(\(language))",
                "-AppleInterfaceStyle", appearance, "-appAppearance", appearance.lowercased(),
                "-hasSeenDecideTimelinePrimer", "NO"
            ]
            if largeText {
                app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
            }
            app.launch()
            let workspace = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Alex & Jordan")).firstMatch
            XCTAssertTrue(workspace.waitForExistence(timeout: 8))
            workspace.tap()
            app.tabBars.buttons[language == "es" ? "Decidir" : "Decide"].tap()

            let start = app.buttons[language == "es" ? "Empezar a decidir" : "Start Deciding"]
            XCTAssertTrue(start.waitForExistence(timeout: 5))
            XCTAssertTrue(start.isHittable, "Continue must stay reachable even at accessibility text sizes.")
            let initial = XCTAttachment(screenshot: app.screenshot())
            initial.name = "Decide primer — \(appearance) — \(language)\(largeText ? " — Large Text" : "")"
            initial.lifetime = .keepAlways
            add(initial)

            if appearance == "Light", !largeText, language == "en" {
                let preview = app.descendants(matching: .any)["decide-primer-preview"]
                XCTAssertTrue(preview.exists)
                preview.swipeLeft()
                XCTAssertEqual(app.staticTexts["decide-primer-feedback"].label, "Not for you. Teammates can still weigh in.")
                preview.swipeUp()
                XCTAssertEqual(app.staticTexts["decide-primer-feedback"].label, "Undecided. You can change your response in Ideas.")
                preview.swipeRight()
                XCTAssertEqual(app.staticTexts["decide-primer-feedback"].label, "You love it. Approval is still a separate team decision.")
            }

            for (choice, english, spanish) in [
                ("pass", "Not for you. Teammates can still weigh in.", "No es para ti. Los demás pueden seguir opinando."),
                ("maybe", "Undecided. You can change your response in Ideas.", "Aún no te decides. Puedes cambiar tu respuesta en Ideas."),
                ("love", "You love it. Approval is still a separate team decision.", "Te encanta. La aprobación sigue siendo una decisión aparte del equipo.")
            ] {
                let button = app.buttons["decide-primer-\(choice)"]
                for _ in 0..<5 where !button.isHittable { app.swipeUp() }
                XCTAssertTrue(button.isHittable)
                XCTAssertGreaterThanOrEqual(button.frame.height, 44)
                button.tap()
                let feedback = app.staticTexts["decide-primer-feedback"]
                XCTAssertTrue(feedback.waitForExistence(timeout: 3))
                XCTAssertEqual(feedback.label, language == "es" ? spanish : english)
            }
            // The date explanation must remain reachable below the illustration.
            let dated = app.staticTexts[language == "es" ? "Ya tiene una fecha" : "Already has a date"]
            for _ in 0..<5 where !dated.isHittable { app.swipeUp() }
            XCTAssertTrue(dated.exists)
            let details = XCTAttachment(screenshot: app.screenshot())
            details.name = "Decide primer details — \(appearance) — \(language)\(largeText ? " — Large Text" : "")"
            details.lifetime = .keepAlways
            add(details)
            start.tap()
            XCTAssertTrue(start.waitForNonExistence(timeout: 3))
            XCTAssertFalse(app.buttons["Undo last decision"].exists, "Practice must not create real decisions.")
            XCTAssertTrue(app.buttons["decision-event-filter"].exists)
            app.terminate()
        }
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
