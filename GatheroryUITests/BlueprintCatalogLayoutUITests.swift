import XCTest

final class BlueprintCatalogLayoutUITests: XCTestCase {
    @MainActor
    func testCardGeometrySurvivesImageLoadingAndScrollRemounts() throws {
        continueAfterFailure = false
        for appearance in ["Light", "Dark"] {
            let app = XCUIApplication()
            app.launchArguments += [
                "-DisableProductionFlowSimulation", "-SkipAuthentication",
                "-SeedDevelopmentData", "-UseEphemeralDataStore",
                "-BlueprintSearchVisualFixture", "-AppleLanguages", "(en)",
                "-appAppearance", appearance.lowercased(),
            ]
            app.launch()
            let explore = app.tabBars.buttons["Explore"]
            XCTAssertTrue(explore.waitForExistence(timeout: 8))
            explore.tap()
            let first = card(1, in: app)
            let third = card(3, in: app)
            XCTAssertTrue(first.waitForExistence(timeout: 8))
            XCTAssertTrue(third.waitForExistence(timeout: 5))
            let firstOrigin = first.frame.minY
            let firstHeight = first.frame.height
            let thirdHeight = third.frame.height
            let initialDelta = third.frame.minY - first.frame.minY
            attach(app, name: "Cards — \(appearance) — first render")

            // The production cover labels decoded artwork; don't treat a timeout
            // or a failed remote image request as proof of loaded-image stability.
            let loaded = NSPredicate(format: "label CONTAINS %@", "Cover Image")
            let artwork = XCTNSPredicateExpectation(predicate: loaded, object: first)
            XCTAssertEqual(XCTWaiter.wait(for: [artwork], timeout: 12), .completed)
            XCTAssertEqual(first.frame.minY, firstOrigin, accuracy: 1)
            XCTAssertEqual(first.frame.height, firstHeight, accuracy: 1)
            XCTAssertEqual(third.frame.height, thirdHeight, accuracy: 1)
            XCTAssertEqual(third.frame.minY - first.frame.minY, initialDelta, accuracy: 1)
            attach(app, name: "Cards — \(appearance) — loaded")

            for _ in 0..<8 { app.swipeUp() }
            for _ in 0..<4 { app.swipeUp() }
            XCTAssertFalse(first.isHittable)
            // Inactive ad slots must not bias the column allocation and leave
            // a large empty tail down one side of the catalog.
            let visibleCards = app.buttons.matching(NSPredicate(
                format: "identifier BEGINSWITH %@", "blueprint.catalog.card."
            )).allElementsBoundByIndex.filter { $0.isHittable }
            let frames = visibleCards.map { $0.frame }
            let middle = app.frame.midX
            let left = frames.filter { $0.midX < middle }
            let right = frames.filter { $0.midX > middle }
            XCTAssertFalse(left.isEmpty)
            XCTAssertFalse(right.isEmpty)
            let leftBottom = try XCTUnwrap(left.map { $0.maxY }.max())
            let rightBottom = try XCTUnwrap(right.map { $0.maxY }.max())
            let tallest = try XCTUnwrap(frames.map { $0.height }.max())
            XCTAssertLessThanOrEqual(abs(leftBottom - rightBottom), tallest + 12)
            attach(app, name: "Cards — \(appearance) — scrolled")
            for _ in 0..<16 { app.swipeDown() }
            XCTAssertTrue(first.isHittable)
            XCTAssertTrue(third.isHittable)
            XCTAssertEqual(first.frame.height, firstHeight, accuracy: 1)
            XCTAssertEqual(third.frame.height, thirdHeight, accuracy: 1)
            XCTAssertEqual(third.frame.minY - first.frame.minY, initialDelta, accuracy: 1)
            attach(app, name: "Cards — \(appearance) — returned")
            XCTAssertTrue(app.searchFields["Search blueprints"].exists)
            XCTAssertTrue(app.buttons["Account and settings"].isHittable)
            app.terminate()
        }
    }

    @MainActor
    private func card(_ index: Int, in app: XCUIApplication) -> XCUIElement {
        app.buttons["blueprint.catalog.card.wedding-visual-\(index)"]
    }

    @MainActor
    private func attach(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
