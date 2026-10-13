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
