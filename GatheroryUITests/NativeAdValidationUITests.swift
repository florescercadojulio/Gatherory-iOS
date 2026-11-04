import XCTest

final class NativeAdValidationUITests: XCTestCase {
    @MainActor
    func testGoogleSampleAssetBoundsWhileScrolling() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = [
            "-DisableProductionFlowSimulation", "-SkipAuthentication",
            "-SeedDevelopmentData", "-UseEphemeralDataStore", "-UseProductionOnboarding",
            "-BlueprintAdsScrollVerification", "-AppleLanguages", "(en)"
        ]
        app.launch()
        defer { app.terminate() }
        let exploreTab = app.tabBars.buttons["Explore"]
        let explore = exploreTab.exists ? exploreTab : app.buttons["Explore"].firstMatch
        XCTAssertTrue(explore.waitForExistence(timeout: 10))
        explore.tap()
        let primer = app.buttons["search.primer.continue"]
        if primer.waitForExistence(timeout: 5) { primer.tap() }
        let scroll = app.scrollViews["blueprint.catalog.scroll"]
        XCTAssertTrue(scroll.waitForExistence(timeout: 10))
        let ad = app.descendants(matching: .any)["explore.ad.explore-ad-6"].firstMatch
        XCTAssertTrue(ad.waitForExistence(timeout: 40), "Google's real sample inventory must load for this check.")
        for _ in 0..<8 where !ad.isHittable { scroll.swipeUp() }
        XCTAssertTrue(ad.isHittable)
        assertRegisteredAndContained(ad)
        assertNoBoundsWarning(in: app)
        attach(app, name: "Google sample ad — settled bounds")
        // Scroll around the registered creative, without leaving its inventory
        // range or refreshing the feed. Inventory eviction is a separate policy.
        // Never tap the ad, its CTA, AdChoices or a live creative.
        scroll.swipeUp()
        assertNoBoundsWarning(in: app)
        scroll.swipeDown()
        assertNoBoundsWarning(in: app)
        for _ in 0..<4 {
            if ad.exists && ad.isHittable { break }
            if ad.exists && ad.frame.maxY < scroll.frame.minY { scroll.swipeDown() }
            else { scroll.swipeUp() }
        }
        XCTAssertTrue(ad.isHittable, "The sample creative should remain available around its scroll position.")
        assertRegisteredAndContained(ad)
        assertNoBoundsWarning(in: app)
        attach(app, name: "Google sample ad — bounds after scrolling")

    }

    @MainActor
    private func assertRegisteredAndContained(_ ad: XCUIElement) {
        let ready = XCTNSPredicateExpectation(
            predicate: NSPredicate { element, _ in
                (element as? XCUIElement)?.value as? String == "registered=true;assetsContained=true"
            }, object: ad)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 8), .completed,
                       "The real creative must be registered with the SDK and every asset must fit.")
    }

    @MainActor
    private func assertNoBoundsWarning(in app: XCUIApplication) {
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(
            format: "label CONTAINS[c] %@", "Advertiser assets outside native ad view"
        )).firstMatch.exists)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(
            format: "label CONTAINS[c] %@", "implementation issue found"
        )).firstMatch.exists)
    }

    @MainActor
    private func attach(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
