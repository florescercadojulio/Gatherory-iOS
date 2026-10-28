import XCTest

final class InvitationHeroLayoutUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testMainAndChildInvitationHeroesKeepScheduleAndResponsesAccessibleInLightAndDark() throws {
        for appearance in ["Light", "Dark"] {
            let app = fixtureApplication(appearance: appearance)
            app.launch()
            defer { app.terminate() }

            openBirthdayWorkspace(in: app)
            openMainInvitation(in: app)

            let mainSchedule = app.buttons.matching(identifier: "invitation.edit.date").firstMatch
            assertScheduleAndResponseLayout(
                schedule: mainSchedule,
                eventName: "Main event",
                appearance: appearance,
                in: app
            )
            attach(app, name: "Main invitation hero — \(appearance)")

            // A long, locally saved fixture title must be allowed to grow and scroll
            // without making the schedule or RSVP controls unreachable.
            let title = app.buttons["invitation.edit.title"]
            XCTAssertTrue(title.waitForExistence(timeout: 5))
            title.tap()
            let titleField = app.textFields["invitation.edit.title.field"]
            XCTAssertTrue(titleField.waitForExistence(timeout: 5))
            replaceText(
                in: titleField,
                with: "Maya’s Birthday Dinner with Friends and Family from Near and Far, Celebrating Together All Evening Long"
            )
            app.buttons["invitation.edit.title.save"].tap()
            XCTAssertTrue(title.waitForExistence(timeout: 5))
            XCTAssertTrue(title.label.contains("Celebrating Together"), "The long-title case should be present before scrolling.")

            let heroScroll = app.scrollViews.firstMatch
            XCTAssertTrue(heroScroll.waitForExistence(timeout: 5))
            let response = app.descendants(matching: .any)["invitation.hero.response"]
            reveal(mainSchedule, in: heroScroll, app: app)
            XCTAssertTrue(
                mainSchedule.isHittable,
                "The schedule should remain reachable after a long title is saved. Accessibility tree: \(app.debugDescription)"
            )
            XCTAssertNotNil(
                mainSchedule.label.range(of: #"\b\d{1,2}:\d{2}\b"#, options: .regularExpression),
                "The schedule should keep its formatted time after scrolling. Label: \(mainSchedule.label)"
            )
            reveal(response, in: heroScroll, app: app)
            XCTAssertTrue(
                response.isHittable,
                "The RSVP row should remain reachable after a long title is saved. Accessibility tree: \(app.debugDescription)"
            )

            app.navigationBars.buttons.firstMatch.tap()
            let childCard = app.buttons.matching(
                NSPredicate(format: "identifier == %@ AND label CONTAINS %@", "home.event.child", "Drinks & catch-ups")
            ).firstMatch
            let homeScroll = app.scrollViews.firstMatch
            for _ in 0..<8 {
                if childCard.exists && childCard.isHittable { break }
                homeScroll.swipeUp()
            }
            XCTAssertTrue(childCard.isHittable, "The seeded child event should be reachable from Home.")
            childCard.tap()
            XCTAssertTrue(app.navigationBars["Invitation"].waitForExistence(timeout: 8))

            let childSchedule = scheduleElement(in: app, identifier: "invitation.hero.schedule")
            assertScheduleAndResponseLayout(
                schedule: childSchedule,
                eventName: "Drinks & catch-ups",
                appearance: appearance,
                in: app
            )
            attach(app, name: "Child invitation hero — \(appearance)")
        }
    }

    @MainActor
    private func fixtureApplication(appearance: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-DisableProductionFlowSimulation",
            "-SkipAuthentication",
            "-SeedDevelopmentData",
            "-UseEphemeralDataStore",
            "-UseBirthdayMarketingFixture",
            "-UseProductionOnboarding",
            "-AppleLanguages", "(en)",
            "-AppleInterfaceStyle", appearance,
            "-appAppearance", appearance.lowercased()
        ]
        return app
    }

    @MainActor
    private func openBirthdayWorkspace(in app: XCUIApplication) {
        let workspace = app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "Maya’s Birthday Dinner")
        ).firstMatch
        XCTAssertTrue(workspace.waitForExistence(timeout: 10), "The isolated birthday fixture should be available.")
        workspace.tap()
        HomeLayoutUITestSupport.select("Cards", in: app)
    }

    @MainActor
    private func openMainInvitation(in app: XCUIApplication) {
        let main = app.buttons["home.event.main"]
        XCTAssertTrue(main.waitForExistence(timeout: 8))
        main.tap()
        XCTAssertTrue(app.navigationBars["Invitation"].waitForExistence(timeout: 8))
    }

    @MainActor
    private func assertScheduleAndResponseLayout(
        schedule: XCUIElement,
        eventName: String,
        appearance: String,
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(
            schedule.waitForExistence(timeout: 8),
            "\(eventName) should show its schedule. Accessibility tree: \(app.debugDescription)",
            file: file,
            line: line
        )
        XCTAssertNotNil(
            schedule.label.range(of: #"\b\d{1,2}:\d{2}\b"#, options: .regularExpression),
            "\(eventName) schedule should expose a formatted time. Label: \(schedule.label)",
            file: file,
            line: line
        )
        XCTAssertTrue(
            schedule.label.contains("2026") && schedule.label.contains("EST"),
            "\(eventName) schedule accessibility should retain the full fixture date and timezone. Label: \(schedule.label)",
            file: file,
            line: line
        )
        let response = app.descendants(matching: .any)["invitation.hero.response"]
        XCTAssertTrue(response.waitForExistence(timeout: 5), "\(eventName) should show its RSVP row.", file: file, line: line)
        XCTAssertTrue(response.isHittable, "\(eventName) RSVP row should be visible.", file: file, line: line)

        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 5), "The native workspace tabs should remain visible.", file: file, line: line)
        if schedule.elementType == .button {
            XCTAssertTrue(
                schedule.isHittable,
                "The actionable \(eventName) schedule should be hittable. Accessibility tree: \(app.debugDescription)",
                file: file,
                line: line
            )
        } else {
            let navigationBar = app.navigationBars.firstMatch
            XCTAssertTrue(navigationBar.exists, "The invitation navigation bar should be visible.", file: file, line: line)
            XCTAssertGreaterThanOrEqual(
                schedule.frame.minY,
                navigationBar.frame.maxY,
                "The static \(eventName) schedule should be below navigation. Accessibility tree: \(app.debugDescription)",
                file: file,
                line: line
            )
            XCTAssertLessThanOrEqual(
                schedule.frame.maxY,
                tabBar.frame.minY,
                "The static \(eventName) schedule should be fully visible above tabs. Accessibility tree: \(app.debugDescription)",
                file: file,
                line: line
            )
        }
        XCTAssertLessThan(
            response.frame.maxY,
            tabBar.frame.minY,
            "The RSVP row should not overlap the native tabs in \(appearance).",
            file: file,
            line: line
        )
        XCTAssertLessThanOrEqual(
            tabBar.frame.minY - response.frame.maxY,
            36,
            "The RSVP row should stay reasonably close to the native tabs in \(appearance).",
            file: file,
            line: line
        )
    }

    @MainActor
    private func scheduleElement(in app: XCUIApplication, identifier: String) -> XCUIElement {
        let identifiedElement = app.descendants(matching: .any).matching(identifier: identifier).firstMatch
        if identifiedElement.waitForExistence(timeout: 2) {
            return identifiedElement
        }

        // A read-only hero may combine its children into one accessible element.
        // Fall back to the rendered hero label that exposes the formatted schedule.
        let timedElements = app.descendants(matching: .any).matching(
            NSPredicate(format: "label MATCHES %@", #".*\b\d{1,2}:\d{2}\b.*"#)
        )
        for element in timedElements.allElementsBoundByIndex where element.isHittable {
            if element.frame.minY < app.frame.height * 0.78 {
                return element
            }
        }
        return identifiedElement
    }

    @MainActor
    private func reveal(_ element: XCUIElement, in scroll: XCUIElement, app: XCUIApplication) {
        for _ in 0..<8 where !element.isHittable {
            let frame = element.frame
            let viewport = scroll.frame
            if frame.midY < viewport.minY + 8 {
                scroll.swipeDown()
            } else if frame.midY > viewport.maxY - 8 {
                scroll.swipeUp()
            } else if frame.midY < viewport.midY {
                scroll.swipeDown()
            } else {
                scroll.swipeUp()
            }
        }
        XCTAssertTrue(element.isHittable, "The invitation content should be reachable by scrolling. Accessibility tree: \(app.debugDescription)")
    }

    @MainActor
    private func replaceText(in field: XCUIElement, with value: String) {
        field.tap()
        let current = field.value as? String ?? ""
        if !current.isEmpty {
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count))
        }
        field.typeText(value)
    }

    @MainActor
    private func attach(_ app: XCUIApplication, name: String) {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
