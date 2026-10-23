import XCTest

final class BlueprintAdsScrollUITests: XCTestCase {
    @MainActor
    func testPrefetchedAdDoesNotMoveVisibleBlueprints() throws {
        continueAfterFailure = false
        for appearance in ["Light", "Dark"] {
            let app = XCUIApplication()
            app.launchArguments += [
                "-DisableProductionFlowSimulation", "-SkipAuthentication",
                "-SeedDevelopmentData", "-UseEphemeralDataStore",
                "-BlueprintAdsScrollVerification", "-AppleLanguages", "(en)",
                "-appAppearance", appearance.lowercased(),
            ]
            app.launch()
            defer { app.terminate() }
            let explore = app.tabBars.buttons["Explore"]
            XCTAssertTrue(explore.waitForExistence(timeout: 8))
            explore.tap()
            let first = card(1, in: app)
            let third = card(3, in: app)
            XCTAssertTrue(first.waitForExistence(timeout: 10))
            XCTAssertTrue(third.waitForExistence(timeout: 5))
            let firstFrame = first.frame
            let thirdFrame = third.frame
            let ad = app.descendants(matching: .any)["explore.ad.explore-ad-6"]
            XCTAssertTrue(ad.waitForExistence(timeout: 30), "The real SDK sample should load before scrolling.")
            for (card, initial) in [(first, firstFrame), (third, thirdFrame)] {
                XCTAssertEqual(card.frame.minX, initial.minX, accuracy: 1)
                XCTAssertEqual(card.frame.minY, initial.minY, accuracy: 1)
                XCTAssertEqual(card.frame.width, initial.width, accuracy: 1)
                XCTAssertEqual(card.frame.height, initial.height, accuracy: 1)
            }
            attach(app, name: "Explore ads — \(appearance) — visible cards after ad arrival")
        }
    }

    @MainActor
    func testGoogleTestAdSettlesDuringBrowseScrollAndPreviewReturn() throws {
        continueAfterFailure = false

        for appearance in ["Light", "Dark"] {
            let app = XCUIApplication()
            app.launchArguments += [
                "-DisableProductionFlowSimulation", "-SkipAuthentication",
                "-SeedDevelopmentData", "-UseEphemeralDataStore",
                "-BlueprintAdsScrollVerification", "-AppleLanguages", "(en)",
                "-appAppearance", appearance.lowercased(),
            ]
            app.launch()
            defer { app.terminate() }

            let explore = app.tabBars.buttons["Explore"]
            XCTAssertTrue(explore.waitForExistence(timeout: 8))
            explore.tap()

            let first = card(1, in: app)
            let third = card(3, in: app)
            XCTAssertTrue(first.waitForExistence(timeout: 10))
            XCTAssertTrue(third.waitForExistence(timeout: 5))
            let firstFrame = first.frame
            let thirdFrame = third.frame
            let initialYDelta = thirdFrame.minY - firstFrame.minY
            attach(app, name: "Explore ads — \(appearance) — initial catalog")

            let scrollView = app.scrollViews["blueprint.catalog.scroll"]
            XCTAssertTrue(scrollView.waitForExistence(timeout: 5))
            let ad = app.descendants(matching: .any)["explore.ad.explore-ad-6"]
            XCTAssertTrue(
                ad.waitForExistence(timeout: 30),
                "Google's prefetched sample ad did not settle at the initial browse position."
            )
            for _ in 0..<12 where !ad.isHittable {
                if ad.frame.minY > scrollView.frame.maxY { scrollView.swipeUp() }
                else { scrollView.swipeDown() }
            }
            XCTAssertTrue(ad.isHittable, "The loaded sample ad should be visible in the scroll feed.")
            attach(app, name: "Explore ads — \(appearance) — Google sample loaded")
            dismissAdValidator(in: app)

            for _ in 0..<12 where !first.isHittable {
                dismissAdValidator(in: app)
                scrollView.swipeDown()
            }
            XCTAssertTrue(first.isHittable)
            XCTAssertEqual(first.frame.minX, firstFrame.minX, accuracy: 1)
            XCTAssertEqual(first.frame.width, firstFrame.width, accuracy: 1)
            XCTAssertEqual(first.frame.height, firstFrame.height, accuracy: 1)
            XCTAssertEqual(third.frame.minX, thirdFrame.minX, accuracy: 1)
            XCTAssertEqual(third.frame.width, thirdFrame.width, accuracy: 1)
            XCTAssertEqual(third.frame.height, thirdFrame.height, accuracy: 1)
            XCTAssertEqual(third.frame.minY - first.frame.minY, initialYDelta, accuracy: 1)
            attach(app, name: "Explore ads — \(appearance) — returned to catalog")

            let twentyFirst = card(21, in: app)
            for _ in 0..<18 where !twentyFirst.exists {
                dismissAdValidator(in: app)
                scrollView.swipeUp()
            }
            XCTAssertTrue(twentyFirst.waitForExistence(timeout: 12), "The fixture's second page should contain cards 21–40.")

            let fortieth = card(40, in: app)
            for _ in 0..<18 where !fortieth.exists {
                dismissAdValidator(in: app)
                scrollView.swipeUp()
            }
            attach(app, name: "Explore ads — \(appearance) — paged end")
            XCTAssertTrue(fortieth.waitForExistence(timeout: 12), "The final fixture card should load without repeating a page.")
            let identifiers = catalogCards(in: app).map(\.identifier)
            XCTAssertEqual(identifiers.count, Set(identifiers).count, "Paged catalog cards should have unique accessibility identifiers.")

            for _ in 0..<20 where !first.isHittable {
                dismissAdValidator(in: app)
                scrollView.swipeDown()
            }
            XCTAssertTrue(first.isHittable)
            first.tap()

            let closePreview = app.buttons["blueprint.preview.close"]
            XCTAssertTrue(closePreview.waitForExistence(timeout: 10), "Opening an organic card should present its preview.")
            attach(app, name: "Explore ads — \(appearance) — organic preview")
            closePreview.tap()

            XCTAssertTrue(first.waitForExistence(timeout: 8), "Closing the preview should return to the same browse catalog.")
            XCTAssertTrue(app.searchFields["Search blueprints"].exists)
            XCTAssertFalse(app.buttons["Cancel"].exists, "Browse should return without activating Search.")
            XCTAssertEqual(first.frame.minX, firstFrame.minX, accuracy: 1)
            XCTAssertEqual(first.frame.width, firstFrame.width, accuracy: 1)
            XCTAssertEqual(first.frame.height, firstFrame.height, accuracy: 1)
            XCTAssertTrue(ad.waitForExistence(timeout: 30), "The real sample ad should remain available after preview dismissal resumes Explore inventory.")
            attach(app, name: "Explore ads — \(appearance) — browse restored")
        }
    }

    @MainActor
    func testGoogleTestAdAtAccessibilityTextSize() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += [
            "-DisableProductionFlowSimulation", "-SkipAuthentication",
            "-SeedDevelopmentData", "-UseEphemeralDataStore",
            "-BlueprintAdsScrollVerification", "-AppleLanguages", "(en)",
            "-appAppearance", "dark",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
        ]
        app.launch()
        defer { app.terminate() }
        let explore = app.tabBars.buttons["Explore"]
        XCTAssertTrue(explore.waitForExistence(timeout: 8))
        explore.tap()
        let scrollView = app.scrollViews["blueprint.catalog.scroll"]
        XCTAssertTrue(scrollView.waitForExistence(timeout: 8))
        let ad = app.descendants(matching: .any)["explore.ad.explore-ad-6"]
        for _ in 0..<14 where !ad.exists {
            dismissAdValidator(in: app)
            scrollView.swipeUp()
        }
        XCTAssertTrue(ad.waitForExistence(timeout: 30), "A real SDK sample must be present at accessibility text size.")
        for _ in 0..<8 where !ad.isHittable {
            dismissAdValidator(in: app)
            scrollView.swipeUp()
        }
        XCTAssertTrue(ad.isHittable)
        let height = ad.frame.height
        XCTAssertGreaterThan(height, 160)
        XCTAssertLessThanOrEqual(ad.frame.width, scrollView.frame.width)
        attach(app, name: "Explore ads — accessibility text — native assets")
        dismissAdValidator(in: app)
        scrollView.swipeUp()
        scrollView.swipeDown()
        XCTAssertEqual(ad.frame.height, height, accuracy: 1)
        attach(app, name: "Explore ads — accessibility text — settled")
    }

    @MainActor
    private func dismissAdValidator(in app: XCUIApplication) {
        // This SDK diagnostic is separate from the ad. Never tap an ad CTA.
        if app.staticTexts["AdMob native ad validator"].exists {
            let dismiss = app.buttons["Dismiss"]
            if dismiss.isHittable { dismiss.tap() }
        }
    }

    @MainActor
    private func card(_ index: Int, in app: XCUIApplication) -> XCUIElement {
        app.buttons["blueprint.catalog.card.wedding-visual-\(index)"]
    }

    @MainActor
    private func catalogCards(in app: XCUIApplication) -> [XCUIElement] {
        app.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH %@", "blueprint.catalog.card.wedding-visual-"
        )).allElementsBoundByIndex
    }

    @MainActor
    private func attach(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
