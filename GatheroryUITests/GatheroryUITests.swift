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
