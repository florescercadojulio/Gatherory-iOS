import XCTest

final class HomeEventCardInteractionUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testOverviewMainAndChildInteractionsInLightAndDark() throws {
        for appearance in ["Light", "Dark"] {
            exerciseCard(layout: "overview", appearance: appearance, isChild: false)
            exerciseCard(layout: "overview", appearance: appearance, isChild: true)
        }
    }

    @MainActor
    func testCardsMainInteractionInLight() throws {
        exerciseCard(layout: "cards", appearance: "Light", isChild: false)
    }

    @MainActor
    private func exerciseCard(layout: String, appearance: String, isChild: Bool) {
        let app = XCUIApplication()
        app.launchArguments = [
            "-DisableProductionFlowSimulation", "-SkipAuthentication",
            "-SeedDevelopmentData", "-UseEphemeralDataStore",
            "-UseProductionOnboarding", "-AppleLanguages", "(en)",
            "-AppleInterfaceStyle", appearance,
            "-appAppearance", appearance.lowercased(),
            "-home.layout", layout
        ]
        app.launch()

        let workspace = app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "Alex & Jordan")
        ).firstMatch
        XCTAssertTrue(workspace.waitForExistence(timeout: 10))
        workspace.tap()

        let homeCard: XCUIElement
        let homeContainer: XCUIElement
        let manageID: String
        if layout == "overview" {
            let overview = app.scrollViews["home.overview"]
            XCTAssertTrue(overview.waitForExistence(timeout: 6))
            homeContainer = overview
            if isChild {
                homeCard = app.buttons.matching(
                    NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@",
                                "home.overview.event.", "Ceremony")
                ).firstMatch
                XCTAssertTrue(homeCard.waitForExistence(timeout: 6))
                let eventID = String(homeCard.identifier.dropFirst("home.overview.event.".count))
                manageID = "home.manage.subevent-\(eventID)"
            } else {
                homeCard = app.descendants(matching: .any)["home.overview.mainEvent"]
                manageID = "home.manage.main"
            }
        } else {
            homeContainer = app
            homeCard = app.buttons["home.event.main"]
            manageID = "home.manage.main"
        }

        XCTAssertTrue(homeCard.waitForExistence(timeout: 6))
        for _ in 0..<8 where !homeCard.isHittable { homeContainer.swipeUp() }
        XCTAssertTrue(waitForHittable(homeCard, timeout: 2), interactionDiagnostic(for: homeCard, in: app))

        let dayGroup = layout == "overview" && isChild
            ? matchingDayGroup(for: homeCard, in: app)
            : nil
        if let dayGroup {
            revealHorizontally(homeCard, in: dayGroup)
        }
        guard let initialCardPoint = visiblePoint(for: homeCard, in: app) else {
            XCTFail("The event card has no visible primary-button hit point. \(interactionDiagnostic(for: homeCard, in: app))")
            app.terminate()
            return
        }

        initialCardPoint.press(forDuration: 1.0)
        let editAction = app.buttons["Edit Event"]
        XCTAssertTrue(editAction.waitForExistence(timeout: 5),
                      "The \(layout) \(isChild ? "child" : "main") card should offer its non-destructive Edit Event menu action.")
        // Use the background gutter. A toolbar tap can also activate Share
        // while dismissing the system menu and cover the card with its sheet.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.005, dy: 0.5)).tap()
        XCTAssertFalse(editAction.waitForExistence(timeout: 1), "Tapping outside should dismiss the context menu.")

        let restoredCard = freshHomeCard(layout: layout, isChild: isChild, in: app)
        var restoredCardIsHittable = waitForHittable(restoredCard, timeout: 3)
        if !restoredCardIsHittable {
            revealVertically(restoredCard, in: homeContainer)
            restoredCardIsHittable = waitForHittable(restoredCard, timeout: 3)
        }
        if let dayGroup {
            revealHorizontally(restoredCard, in: dayGroup)
        }
        let restoredPoint = visiblePoint(for: restoredCard, in: app)
        XCTAssertTrue(restoredCardIsHittable && restoredPoint != nil,
                      "The event card should be hittable after dismissing its context menu. \(interactionDiagnostic(for: restoredCard, in: app))")
        guard restoredCardIsHittable, let restoredPoint else {
            app.terminate()
            return
        }
        restoredPoint.tap()
        let invitation = app.navigationBars["Invitation"]
        XCTAssertTrue(invitation.waitForExistence(timeout: 6), "Tapping the primary card should open its invitation.")

        dragFromLeadingEdge(in: app, toFraction: 0.12)
        XCTAssertTrue(invitation.waitForExistence(timeout: 3),
                      "A short interactive back drag should cancel and leave the invitation open. \(interactionDiagnostic(for: invitation, in: app))")

        dragFromLeadingEdge(in: app, toFraction: 0.72)
        let returnedCard = freshHomeCard(layout: layout, isChild: isChild, in: app)
        XCTAssertTrue(returnedCard.waitForExistence(timeout: 6),
                      "Completing the interactive back gesture should return to the selected Home layout. \(interactionDiagnostic(for: returnedCard, in: app))")

        let manage = app.buttons[manageID]
        XCTAssertTrue(manage.waitForExistence(timeout: 5))
        revealVertically(manage, in: homeContainer)
        if let dayGroup {
            revealHorizontally(manage, in: dayGroup)
        }
        XCTAssertTrue(manage.isHittable, interactionDiagnostic(for: manage, in: app))
        if let managePoint = visiblePoint(for: manage, in: app) {
            managePoint.tap()
        } else {
            XCTFail("The Manage footer has no visible hit point. \(interactionDiagnostic(for: manage, in: app))")
            app.terminate()
            return
        }
        XCTAssertTrue(app.scrollViews["event.management.dashboard"].waitForExistence(timeout: 6),
                      "The card footer should open the selected event dashboard after menu and back gestures.")
        app.terminate()
    }

    @MainActor
    private func freshHomeCard(layout: String, isChild: Bool, in app: XCUIApplication) -> XCUIElement {
        if layout == "cards" {
            return app.buttons["home.event.main"]
        }
        if isChild {
            return app.buttons.matching(
                NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@",
                            "home.overview.event.", "Ceremony")
            ).firstMatch
        }
        return app.buttons["home.overview.mainEvent"]
    }

    @MainActor
    private func matchingDayGroup(for card: XCUIElement, in app: XCUIApplication) -> XCUIElement? {
        let groups = app.scrollViews.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "home.overview.day.")
        )
        for index in 0..<groups.count {
            let group = groups.element(boundBy: index)
            if group.buttons.matching(identifier: card.identifier).firstMatch.exists { return group }
        }
        return nil
    }

    @MainActor
    private func revealVertically(_ element: XCUIElement, in container: XCUIElement) {
        for _ in 0..<8 where !element.isHittable {
            container.swipeUp()
        }
    }

    @MainActor
    private func waitForHittable(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == true AND hittable == true"),
            object: element
        )
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    @MainActor
    private func revealHorizontally(_ element: XCUIElement, in group: XCUIElement) {
        for _ in 0..<6 where element.frame.midX < group.frame.minX || element.frame.midX > group.frame.maxX {
            if element.frame.midX < group.frame.minX {
                group.swipeRight()
            } else {
                group.swipeLeft()
            }
        }
    }

    @MainActor
    private func visiblePoint(for element: XCUIElement, in app: XCUIApplication) -> XCUICoordinate? {
        var visibleFrame = element.frame.intersection(app.frame)
        let navigationBar = app.navigationBars.firstMatch
        if navigationBar.exists {
            visibleFrame = visibleFrame.intersection(CGRect(
                x: app.frame.minX, y: navigationBar.frame.maxY,
                width: app.frame.width, height: app.frame.maxY - navigationBar.frame.maxY
            ))
        }
        let tabBar = app.tabBars.firstMatch
        if tabBar.exists {
            visibleFrame = visibleFrame.intersection(CGRect(
                x: app.frame.minX, y: app.frame.minY,
                width: app.frame.width, height: tabBar.frame.minY - app.frame.minY
            ))
        }
        guard visibleFrame.width > 0, visibleFrame.height > 0 else { return nil }
        let point = CGPoint(x: visibleFrame.midX, y: visibleFrame.midY)
        return app.coordinate(withNormalizedOffset: CGVector(
            dx: (point.x - app.frame.minX) / app.frame.width,
            dy: (point.y - app.frame.minY) / app.frame.height
        ))
    }

    @MainActor
    private func interactionDiagnostic(for element: XCUIElement, in app: XCUIApplication) -> String {
        "Element `\(element.identifier)` frame=\(element.frame), hittable=\(element.isHittable). App hierarchy:\n\(app.debugDescription)"
    }

    @MainActor
    private func dragFromLeadingEdge(in app: XCUIApplication, toFraction fraction: CGFloat) {
        let screen = app.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0))
        let start = screen.withOffset(CGVector(dx: 2, dy: app.frame.height * 0.5))
        let end = screen.withOffset(CGVector(dx: app.frame.width * fraction, dy: app.frame.height * 0.5))
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.5)
    }
}
