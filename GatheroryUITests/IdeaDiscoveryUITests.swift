import XCTest

final class IdeaDiscoveryUITests: XCTestCase {
    @MainActor
    func testCancellingAddLeavesIdeaAvailable() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = [
            "-DisableProductionFlowSimulation", "-SkipAuthentication",
            "-SeedDevelopmentData", "-UseEphemeralDataStore", "-UseProductionOnboarding",
            "-IdeaDiscoveryVisualFixture", "-AppleLanguages", "(en)",
            "-AppleInterfaceStyle", "Light", "-appAppearance", "light",
        ]
        app.launch()
        defer { app.terminate() }

        let explore = app.tabBars.buttons["Explore"]
        XCTAssertTrue(explore.waitForExistence(timeout: 8))
        explore.tap()
        let contentFilter = app.buttons["explore.content.filter"]
        XCTAssertTrue(contentFilter.waitForExistence(timeout: 8))
        contentFilter.tap()
        app.buttons["Ideas"].tap()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("Garden\n")

        let card = app.buttons["idea.discovery.card.idea-fixture-1"]
        XCTAssertTrue(card.waitForExistence(timeout: 8))
        card.tap()
        let add = app.buttons["idea.discovery.addToEvent"]
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        add.tap()
        XCTAssertTrue(app.navigationBars["Add to Event"].waitForExistence(timeout: 5))
        app.buttons["Cancel"].tap()

        XCTAssertTrue(add.waitForExistence(timeout: 5), "Cancel should return to the idea detail.")
        XCTAssertEqual(add.label, "Add to Event")
        app.buttons["Done"].tap()
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        XCTAssertFalse(card.label.localizedCaseInsensitiveContains("Added"))
    }

    @MainActor
    func testIdeaCanBeAddedToAnEventInLightAndDarkAppearance() throws {
        continueAfterFailure = false
        for appearance in ["Light", "Dark"] {
            let app = XCUIApplication()
            app.launchArguments = [
                "-DisableProductionFlowSimulation", "-SkipAuthentication",
                "-SeedDevelopmentData", "-UseEphemeralDataStore", "-UseProductionOnboarding",
                "-IdeaDiscoveryVisualFixture", "-AppleLanguages", "(en)",
                "-AppleInterfaceStyle", appearance, "-appAppearance", appearance.lowercased(),
            ]
            app.launch()
            defer { app.terminate() }

            let explore = app.tabBars.buttons["Explore"]
            XCTAssertTrue(explore.waitForExistence(timeout: 8))
            explore.tap()
            let contentFilter = app.buttons["explore.content.filter"]
            XCTAssertTrue(contentFilter.waitForExistence(timeout: 8))
            XCTAssertFalse(app.buttons["idea.discovery.more"].exists)
            XCTAssertFalse(app.navigationBars.staticTexts["Search"].exists)
            XCTAssertFalse(app.segmentedControls["Explore content"].exists)
            contentFilter.tap()
            let ideasFilter = app.buttons["Ideas"]
            XCTAssertTrue(ideasFilter.waitForExistence(timeout: 8))
            ideasFilter.tap()

            let search = app.searchFields.firstMatch
            XCTAssertTrue(search.waitForExistence(timeout: 5))
            search.tap()
            search.typeText("Garden\n")
            XCTAssertEqual(search.value as? String, "Garden")

            let card = app.buttons["idea.discovery.card.idea-fixture-1"]
            XCTAssertTrue(card.waitForExistence(timeout: 8))
            card.tap()
            let add = app.buttons["idea.discovery.addToEvent"]
            XCTAssertTrue(add.waitForExistence(timeout: 5))
            add.tap()

            XCTAssertTrue(app.navigationBars["Add to Event"].waitForExistence(timeout: 5))
            let workspaceSearch = app.searchFields["Search your events"].firstMatch
            XCTAssertTrue(workspaceSearch.waitForExistence(timeout: 5))
            workspaceSearch.tap()
            workspaceSearch.typeText("Ceremony\n")
            let workspaceCard = app.buttons.matching(NSPredicate(
                format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "idea.add.workspace.", "Alex"
            )).firstMatch
            XCTAssertTrue(workspaceCard.waitForExistence(timeout: 5))
            let workspaceID = String(workspaceCard.identifier.dropFirst("idea.add.workspace.".count))
            workspaceCard.tap()
            let mainTarget = app.buttons["idea.add.destination.\(workspaceID)"]
            XCTAssertTrue(mainTarget.waitForExistence(timeout: 5),
                          "Opening a search match must still offer its main event.")
            let childTarget = app.buttons.matching(NSPredicate(
                format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "idea.add.destination.", "Ceremony"
            )).firstMatch
            XCTAssertTrue(childTarget.waitForExistence(timeout: 5))
            XCTAssertFalse(app.buttons["idea.add.confirm"].isEnabled)
            let destinationBar = app.navigationBars.matching(NSPredicate(
                format: "identifier CONTAINS %@", "Alex"
            )).firstMatch
            XCTAssertTrue(destinationBar.waitForExistence(timeout: 5))
            destinationBar.buttons.element(boundBy: 0).tap()
            XCTAssertTrue(workspaceCard.waitForExistence(timeout: 5))
            XCTAssertEqual(workspaceSearch.value as? String, "Ceremony")
            workspaceCard.tap()
            XCTAssertTrue(mainTarget.waitForExistence(timeout: 5))
            let destination = appearance == "Light" ? mainTarget : childTarget
            destination.tap()
            let confirm = app.buttons["idea.add.confirm"]
            XCTAssertTrue(confirm.isEnabled)
            confirm.tap()
            XCTAssertTrue(explore.waitForExistence(timeout: 8),
                          "Adding an idea should close both sheets and return to Explore.")
            XCTAssertFalse(app.navigationBars["Add to Event"].exists)
            XCTAssertFalse(app.navigationBars["Idea"].exists)
            XCTAssertEqual(search.value as? String, "Garden",
                           "Returning from Add should retain the active idea search.")
            XCTAssertFalse(app.scrollViews["blueprint.catalog.scroll"].exists,
                          "Returning from Add should retain the Ideas filter.")
            XCTAssertTrue(card.label.localizedCaseInsensitiveContains("Added"),
                          "The added idea should show its added state in the discovery card.")

            card.tap()
            let repeatAdd = app.buttons["idea.discovery.addToEvent"]
            XCTAssertTrue(repeatAdd.waitForExistence(timeout: 5))
            XCTAssertTrue(repeatAdd.isEnabled,
                          "The added marker is informational; adding the idea to another event remains available.")
            app.buttons["Done"].tap()
            XCTAssertTrue(card.waitForExistence(timeout: 5))

            let eventsTab = app.tabBars.buttons["Events"]
            XCTAssertTrue(eventsTab.waitForExistence(timeout: 5))
            eventsTab.tap()
            let workspace = app.buttons.matching(NSPredicate(
                format: "identifier == %@", "events.event.\(workspaceID)"
            )).firstMatch
            XCTAssertTrue(workspace.waitForExistence(timeout: 8))
            workspace.tap()
            let ideasTab = app.tabBars.buttons["Ideas"]
            XCTAssertTrue(ideasTab.waitForExistence(timeout: 8))
            ideasTab.tap()

            let copiedIdea = app.buttons.matching(NSPredicate(
                format: "label CONTAINS[c] %@", "Garden brunch"
            )).firstMatch
            XCTAssertTrue(copiedIdea.waitForExistence(timeout: 8),
                          "The copied idea should appear in the chosen event's Ideas tab in \(appearance) appearance.")
        }
    }
}
