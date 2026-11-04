import XCTest

final class IdeaDiscoveryPagingUITests: XCTestCase {
    @MainActor
    func testIdeasLoadLazilyByPageAcrossFilterAndTabChanges() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = [
            "-DisableProductionFlowSimulation", "-SkipAuthentication",
            "-SeedDevelopmentData", "-UseEphemeralDataStore", "-UseProductionOnboarding",
            "-IdeaDiscoveryPagingFixture", "-AppleLanguages", "(en)",
            "-AppleInterfaceStyle", "Light", "-appAppearance", "light",
        ]
        app.launch()
        defer { app.terminate() }

        let explore = app.tabBars.buttons["Explore"]
        XCTAssertTrue(explore.waitForExistence(timeout: 8))
        explore.tap()

        let audit = app.descendants(matching: .any)["idea.discovery.paging.audit"]
        XCTAssertTrue(audit.waitForExistence(timeout: 5))
        waitForAudit(audit) { $0["requestCount"] as? Int == 1 && $0["loadedCount"] as? Int == 20 }

        app.buttons["explore.content.filter"].tap()
        app.buttons["Ideas"].tap()
        waitForAudit(audit) { $0["requestCount"] as? Int == 1 && $0["loadedCount"] as? Int == 20 }
        XCTAssertTrue(app.buttons["idea.discovery.card.paging-idea-001"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["idea.discovery.card.paging-idea-020"].exists,
                       "The last card of the first page should remain unmounted before scrolling near it.")

        let events = app.tabBars.buttons["Events"]
        XCTAssertTrue(events.waitForExistence(timeout: 5))
        events.tap()
        explore.tap()
        waitForAudit(audit) { $0["requestCount"] as? Int == 1 && $0["loadedCount"] as? Int == 20 }

        let scroll = app.scrollViews["idea.discovery.scroll"]
        XCTAssertTrue(scroll.waitForExistence(timeout: 5))
        for _ in 0..<12 {
            if (try? readAudit(audit)["loadedCount"] as? Int) == 40 { break }
            scroll.swipeUp()
        }
        waitForAudit(audit) { $0["requestCount"] as? Int == 2 && $0["loadedCount"] as? Int == 40 }
        XCTAssertFalse(app.buttons["idea.discovery.card.paging-idea-080"].exists,
                       "Scrolling into page two should not fetch the full catalog.")
    }

    @MainActor
    private func readAudit(_ element: XCUIElement) throws -> [String: Any] {
        let raw = try XCTUnwrap(element.value as? String)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any])
    }

    @MainActor
    private func waitForAudit(_ element: XCUIElement, predicate: @escaping ([String: Any]) -> Bool) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { object, _ in
            guard let element = object as? XCUIElement,
                  let raw = element.value as? String,
                  let value = try? JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any]
            else { return false }
            return predicate(value)
        }, object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 10), .completed,
                       "Unexpected paging audit: \(element.value as? String ?? "missing")")
    }
}
