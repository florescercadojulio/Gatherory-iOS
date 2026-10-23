import XCTest

final class BlueprintExploreHeaderUITests: XCTestCase {
    @MainActor
    func testNativeHeaderAlignmentTypingAndScrolling() throws {
        continueAfterFailure = false
        for appearance in ["light", "dark"] {
            let app = XCUIApplication()
            app.launchArguments += [
                "-DisableProductionFlowSimulation", "-SkipAuthentication",
                "-SeedDevelopmentData", "-UseEphemeralDataStore",
                "-BlueprintSearchVisualFixture", "-AppleLanguages", "(en)",
                "-appAppearance", appearance,
            ]
            app.launch()
            defer { app.terminate() }
            let explore = app.tabBars.buttons["Explore"]
            XCTAssertTrue(explore.waitForExistence(timeout: 8))
            explore.tap()

            let title = app.navigationBars.staticTexts["Search"].firstMatch
            let profile = app.buttons["Account and settings"]
            let search = app.searchFields["Search blueprints"]
            XCTAssertTrue(title.waitForExistence(timeout: 8))
            XCTAssertTrue(profile.isHittable)
            XCTAssertTrue(search.exists)
            assertAligned(title: title, profile: profile)
            attach(app, name: "Explore header — \(appearance) — aligned")

            search.tap()
            search.typeText("wedding")
            XCTAssertEqual(search.value as? String, "wedding")
            // The system uses Close on iOS 27; earlier presentations say Cancel.
            let dismissSearch = app.navigationBars.buttons.matching(NSPredicate(
                format: "label == %@ OR label == %@", "Close", "Cancel"
            )).firstMatch
            XCTAssertTrue(dismissSearch.waitForExistence(timeout: 5))
            attach(app, name: "Explore header — \(appearance) — typing")
            search.typeText("\n")
            let scroll = app.scrollViews["blueprint.catalog.scroll"]
            XCTAssertTrue(scroll.waitForExistence(timeout: 5))
            scroll.swipeUp()
            XCTAssertEqual(search.value as? String, "wedding")
            attach(app, name: "Explore header — \(appearance) — results scrolled")
            dismissSearch.tap()
            XCTAssertTrue(dismissSearch.waitForNonExistence(timeout: 5))
            XCTAssertTrue(profile.waitForExistence(timeout: 5))
            assertAligned(title: title, profile: profile)
            scroll.swipeUp()
            attach(app, name: "Explore header — \(appearance) — browse scrolled")
            scroll.swipeDown()
            XCTAssertTrue(profile.isHittable)
            XCTAssertTrue(search.isHittable)
        }
    }

    @MainActor
    private func assertAligned(title: XCUIElement, profile: XCUIElement) {
        XCTAssertEqual(title.frame.midY, profile.frame.midY, accuracy: 8,
                       "The native title and profile action should occupy the same toolbar row.")
        XCTAssertLessThanOrEqual(title.frame.maxX, profile.frame.minX)
    }

    @MainActor
    private func attach(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
