import XCTest

final class BlueprintDiscoverySessionUITests: XCTestCase {
    @MainActor
    func testSeenHistoryWaitsForRefreshAndPreviewAndTabReturnPreserveBrowse() throws {
        continueAfterFailure = false
        for appearance in ["light", "dark"] {
            let app = XCUIApplication()
            app.launchArguments += [
                "-DisableProductionFlowSimulation", "-SkipAuthentication",
                "-SeedDevelopmentData", "-UseEphemeralDataStore",
                "-BlueprintDiscoverySessionFixture", "-BlueprintPreviewActionsVisualFixture",
                "-BlueprintPreviewFixtureContext", "discovery",
                "-AppleLanguages", "(en)", "-appAppearance", appearance,
            ]
            app.launch()
            defer { app.terminate() }
            let explore = app.tabBars.buttons["Explore"]
            XCTAssertTrue(explore.waitForExistence(timeout: 10))
            explore.tap()
            let first = app.buttons["blueprint.catalog.card.wedding-visual-1"]
            XCTAssertTrue(first.waitForExistence(timeout: 10))
            let audit = app.descendants(matching: .any).matching(identifier: "blueprint.discovery.session").firstMatch
            XCTAssertTrue(audit.waitForExistence(timeout: 8))
            waitForAudit(audit) { state in
                !(state["sessionId"] as? String ?? "").isEmpty
                    && (state["seenKeys"] as? [String] ?? []).contains("wedding-visual-1")
            }
            let initial = try readAudit(audit)
            let sessionID = try XCTUnwrap(initial["sessionId"] as? String)
            XCTAssertEqual(initial["contextSeenKeys"] as? [String], [],
                           "Meaningful views must not change the active request snapshot.")
            XCTAssertFalse((initial["seenKeys"] as? [String] ?? []).contains("wedding-visual-20"),
                           "Fetched cards below the viewport must not count as viewed.")

            let scroll = app.scrollViews["blueprint.catalog.scroll"]
            XCTAssertTrue(scroll.exists)
            scroll.swipeUp()
            let visibleCard = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "blueprint.catalog.card."))
                .allElementsBoundByIndex.first { $0.isHittable && $0.frame.midY > 220 && $0.frame.midY < app.frame.maxY - 200 }
            let anchor = try XCTUnwrap(visibleCard)
            let anchorID = anchor.identifier
            let anchorY = anchor.frame.minY
            let beforePreview = try readAudit(audit)
            anchor.tap()
            let back = app.buttons["blueprint.preview.close"]
            XCTAssertTrue(back.waitForExistence(timeout: 10))
            back.tap()
            XCTAssertTrue(back.waitForNonExistence(timeout: 8))
            let returnedAnchor = app.buttons[anchorID]
            XCTAssertTrue(returnedAnchor.isHittable)
            XCTAssertEqual(returnedAnchor.frame.minY, anchorY, accuracy: 3,
                           "Returning from a preview should preserve the browsing position.")
            let afterPreview = try readAudit(audit)
            XCTAssertEqual(afterPreview["sessionId"] as? String, sessionID)
            XCTAssertEqual(afterPreview["firstPageRequests"] as? Int, beforePreview["firstPageRequests"] as? Int)

            let blueprints = app.tabBars.buttons["Blueprints"]
            if !blueprints.exists {
                // Native iOS minimizes the tab bar while scrolling. Tap the
                // selected tab to expand its available destinations first.
                app.tabBars.buttons["Explore"].tap()
            }
            XCTAssertTrue(blueprints.waitForExistence(timeout: 5))
            blueprints.tap()
            XCTAssertTrue(app.segmentedControls["blueprint.library.collections"].waitForExistence(timeout: 8))
            app.tabBars.buttons["Explore"].tap()
            XCTAssertTrue(returnedAnchor.waitForExistence(timeout: 8))
            XCTAssertTrue(returnedAnchor.isHittable)
            XCTAssertEqual(returnedAnchor.frame.minY, anchorY, accuracy: 3)
            let afterTab = try readAudit(audit)
            XCTAssertEqual(afterTab["sessionId"] as? String, sessionID)
            XCTAssertEqual(afterTab["firstPageRequests"] as? Int, beforePreview["firstPageRequests"] as? Int,
                           "A quick tab return must not fetch and reorder page one.")

            for _ in 0..<5 where !first.isHittable { scroll.swipeDown() }
            XCTAssertTrue(first.isHittable)
            let refresh = app.buttons["blueprint.discovery.refresh"]
            XCTAssertTrue(refresh.waitForExistence(timeout: 5))
            XCTAssertTrue(refresh.isHittable)
            refresh.tap()
            waitForAudit(audit) { state in
                (state["sessionId"] as? String) != sessionID
                    && (state["contextSeenKeys"] as? [String] ?? []).contains("wedding-visual-1")
            }
            let refreshed = try readAudit(audit)
            XCTAssertGreaterThan(try XCTUnwrap(refreshed["firstPageRequests"] as? Int),
                                 try XCTUnwrap(afterTab["firstPageRequests"] as? Int))
            XCTAssertFalse((refreshed["contextSeenKeys"] as? [String] ?? []).contains("wedding-visual-40"))
            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.name = "Discovery session after explicit refresh — \(appearance)"
            attachment.lifetime = .keepAlways
            add(attachment)
            app.terminate()
        }
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
                       "Unexpected discovery audit: \(element.value as? String ?? "missing")")
    }
}
