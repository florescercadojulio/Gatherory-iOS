import XCTest

final class ExploreAdChannelsUITests: XCTestCase {
    @MainActor
    func testAllChannelsAndTypedSearchInLightAppearance() throws {
        try verifyChannels(appearance: "light")
    }

    @MainActor
    func testAllChannelsAndTypedSearchInDarkAppearance() throws {
        try verifyChannels(appearance: "dark")
    }

    @MainActor
    private func verifyChannels(appearance: String) throws {
        continueAfterFailure = false
        for channel in ["All", "Blueprints", "Ideas"] {
            let app = XCUIApplication()
            app.launchArguments = [
                "-DisableProductionFlowSimulation", "-SkipAuthentication",
                "-SeedDevelopmentData", "-UseEphemeralDataStore", "-UseProductionOnboarding",
                "-BlueprintAdsScrollVerification", "-IdeaDiscoveryPagingFixture",
                "-AppleLanguages", "(en)", "-appAppearance", appearance,
            ]
            app.launch()
            defer { app.terminate() }
            let explore = app.tabBars.buttons["Explore"]
            XCTAssertTrue(explore.waitForExistence(timeout: 8))
            explore.tap()
            if channel != "All" {
                let filter = app.buttons["explore.content.filter"]
                XCTAssertTrue(filter.waitForExistence(timeout: 5))
                filter.tap()
                app.collectionViews.buttons[channel].firstMatch.tap()
            }

            let scroll = app.scrollViews[channel == "Ideas" ? "idea.discovery.scroll" : "blueprint.catalog.scroll"]
            XCTAssertTrue(scroll.waitForExistence(timeout: 8))
            verifySampleAd(in: app, scroll: scroll, context: "\(channel) browse / \(appearance)")

            let search = app.searchFields.firstMatch
            for _ in 0..<14 {
                if search.isHittable { break }
                scroll.swipeDown()
            }
            XCTAssertTrue(search.isHittable)
            search.tap()
            let query = channel == "Ideas" ? "Paging" : "wedding"
            search.typeText(query + "\n")
            let firstResult = app.buttons[channel == "Ideas"
                ? "idea.discovery.card.paging-idea-001"
                : "blueprint.catalog.card.wedding-visual-1"]
            XCTAssertTrue(firstResult.waitForExistence(timeout: 10), "Typed search must preserve organic relevance.")
            verifySampleAd(in: app, scroll: scroll, context: "\(channel) typed search / \(appearance)")
        }
    }

    @MainActor
    private func verifySampleAd(in app: XCUIApplication, scroll: XCUIElement, context: String) {
        let ads = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "explore.ad.explore-ad-")
        )
        // Only Google's sample inventory is used. Never tap an ad or its CTA.
        for _ in 0..<10 {
            dismissValidator(in: app)
            if ads.firstMatch.waitForExistence(timeout: 3) { break }
            scroll.swipeUp()
        }
        XCTAssertTrue(ads.firstMatch.exists, "No sample native ad rendered: \(context)")
        for _ in 0..<8 {
            dismissValidator(in: app)
            if ads.allElementsBoundByIndex.contains(where: \.isHittable) { break }
            if ads.firstMatch.exists, ads.firstMatch.frame.maxY < scroll.frame.minY {
                scroll.swipeDown()
            } else { scroll.swipeUp() }
        }
        let visible = ads.allElementsBoundByIndex.first(where: \.isHittable)
        XCTAssertNotNil(visible, "A sample native ad must become visible while browsing: \(context)")
        if let visible {
            XCTAssertGreaterThan(visible.frame.height, 100, context)
            XCTAssertLessThanOrEqual(visible.frame.width, scroll.frame.width + 1, context)
        }
    }

    @MainActor
    private func dismissValidator(in app: XCUIApplication) {
        if app.staticTexts["AdMob native ad validator"].exists, app.buttons["Dismiss"].isHittable {
            app.buttons["Dismiss"].tap()
        }
    }
}
