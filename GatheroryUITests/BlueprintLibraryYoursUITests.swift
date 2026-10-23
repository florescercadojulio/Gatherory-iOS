import XCTest

final class BlueprintLibraryYoursUITests: XCTestCase {
    private let personalID = "10000000-0000-4000-8000-000000000001"
    private let recoveryID = "20000000-0000-4000-8000-000000000002"
    private let installationID = "30000000-0000-4000-8000-000000000003"

    @MainActor
    func testEmptyYoursHasTopAlignedPrimaryCollectionAndActionsInBothAppearances() throws {
        continueAfterFailure = false
        for appearance in ["light", "dark"] {
            let app = launch(state: "empty", appearance: appearance)
            let blueprints = app.tabBars.buttons["Blueprints"]
            XCTAssertTrue(blueprints.waitForExistence(timeout: 10))
            blueprints.tap()

            let collections = app.segmentedControls["blueprint.library.collections"]
            XCTAssertTrue(collections.waitForExistence(timeout: 10))
            XCTAssertLessThan(collections.frame.minY, 220, "Yours, Saved, and Liked should start near the top of the library.")
            XCTAssertEqual(app.segmentedControls.count, 1, "Yours should not contain a secondary collection picker.")
            XCTAssertFalse(app.staticTexts["Drafts"].exists)
            XCTAssertFalse(app.staticTexts["Installed"].exists)

            let create = app.buttons["blueprint.library.create"]
            let explore = app.buttons["blueprint.library.explore"]
            XCTAssertTrue(create.waitForExistence(timeout: 8))
            XCTAssertTrue(explore.waitForExistence(timeout: 8))
            XCTAssertTrue(create.isHittable)
            XCTAssertTrue(explore.isHittable)
            attach(app, name: "Yours empty — \(appearance)")

            create.tap()
            XCTAssertTrue(app.navigationBars["Choose an event"].waitForExistence(timeout: 8))
            attach(app, name: "Yours create — \(appearance) — event chooser")
            app.navigationBars.buttons["Cancel"].tap()
            XCTAssertTrue(create.waitForExistence(timeout: 8))

            explore.tap()
            XCTAssertTrue(app.searchFields["Search blueprints"].waitForExistence(timeout: 8))
            app.terminate()
        }
    }

    @MainActor
    func testMixedYoursShowsPersonalRecoveryAndUsedCardsAndOpensRecovery() throws {
        continueAfterFailure = false
        let app = launch(state: "mixed", appearance: "light")
        defer { app.terminate() }
        openLibrary(in: app)

        let personal = app.buttons["blueprint.library.card.personal.\(personalID)"]
        let recovery = app.buttons["blueprint.library.card.recovery.\(recoveryID)"]
        let used = app.buttons["blueprint.library.card.used.\(installationID)"]
        XCTAssertTrue(personal.waitForExistence(timeout: 10))
        XCTAssertTrue(recovery.waitForExistence(timeout: 10))
        XCTAssertTrue(used.waitForExistence(timeout: 10))
        XCTAssertTrue(recovery.label.contains("Garden celebration"),
                      "The recovery card should use its saved event name.")
        XCTAssertTrue(recovery.label.contains("Wedding"),
                      "The recovery card should retain the source Blueprint's title alongside its cover.")
        attach(app, name: "Yours mixed — all card types")

        recovery.tap()
        let closePreview = app.buttons["blueprint.preview.close"]
        XCTAssertTrue(closePreview.waitForExistence(timeout: 10), "Continue setup should reopen the saved recovery customization.")
        XCTAssertEqual(closePreview.label, "Back")
        let recoveryScroll = app.scrollViews["blueprint.preview.singleScroll"]
        XCTAssertTrue(recoveryScroll.waitForExistence(timeout: 8))
        XCTAssertGreaterThan(recoveryScroll.frame.height, app.windows.firstMatch.frame.height * 0.8,
                             "Recovery setup should fill the screen like other Yours previews.")
        XCTAssertTrue(app.staticTexts["A recovery edit"].waitForExistence(timeout: 5),
                      "The opened recovery Blueprint should show its saved customization.")
        attach(app, name: "Yours recovery customization")
        closePreview.tap()
        XCTAssertTrue(closePreview.waitForNonExistence(timeout: 8), "Back should return from recovery to Yours.")
        XCTAssertTrue(recovery.waitForExistence(timeout: 8), "The recovery entry should remain in Yours after returning.")
        XCTAssertTrue(recovery.isHittable)

        let scroll = app.scrollViews["blueprint.library.scroll"]
        XCTAssertTrue(scroll.exists)
        for _ in 0..<6 where !used.isHittable { scroll.swipeUp() }
        XCTAssertTrue(used.isHittable, "The used receipt should remain in the unified Yours feed while scrolling.")
    }

    @MainActor
    func testPendingInstallationKeepsRecoverySetupVisible() throws {
        continueAfterFailure = false
        let app = launch(state: "pending", appearance: "light")
        defer { app.terminate() }
        openLibrary(in: app)

        let recovery = app.buttons["blueprint.library.card.recovery.\(recoveryID)"]
        XCTAssertTrue(recovery.waitForExistence(timeout: 10), "A pending installation must not hide Continue setup recovery.")
        XCTAssertTrue(recovery.label.localizedCaseInsensitiveContains("setup"))
        XCTAssertTrue(app.buttons["blueprint.library.pending.continue"].exists)
        attach(app, name: "Yours pending setup recovery")
    }

    @MainActor
    private func openLibrary(in app: XCUIApplication) {
        XCTAssertTrue(app.buttons["Filter events"].waitForExistence(timeout: 10))
        let tab = app.tabBars.buttons["Blueprints"]
        XCTAssertTrue(tab.waitForExistence(timeout: 5))
        tab.tap()
        XCTAssertTrue(app.segmentedControls["blueprint.library.collections"].waitForExistence(timeout: 8))
    }

    @MainActor
    private func launch(state: String, appearance: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += [
            "-DisableProductionFlowSimulation", "-SkipAuthentication",
            "-SeedDevelopmentData", "-UseEphemeralDataStore",
            "-BlueprintLibraryVisualFixture", "-BlueprintLibraryFixtureState", state,
            "-BlueprintSearchVisualFixture",
            "-AppleLanguages", "(en)", "-appAppearance", appearance,
        ]
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
