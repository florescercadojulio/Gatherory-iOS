import XCTest

final class MovieNightOnboardingUITests: XCTestCase {
    @MainActor
    func testMovieNightOnboardingInstallsRealCopyAndGuidesRealPlanningActions() throws {
        continueAfterFailure = false

        for appearance in ["light", "dark"] {
            try runCompleteTour(appearance: appearance)
        }
    }

    /// Reused on each selected simulator without forcing an appearance mode.
    @MainActor
    func testTourLayoutAndPlanningFlowOnCurrentDevice() throws {
        continueAfterFailure = false
        try runCompleteTour(appearance: nil, checksSearch: true)
    }

    @MainActor
    private func runCompleteTour(appearance: String?, checksSearch: Bool = false) throws {
        let app = launch(appearance: appearance, extraArguments: checksSearch ? ["-BlueprintSearchVisualFixture"] : [])
        defer { app.terminate() }
        _ = try installMovieNightWorkspaceAndWaitForGuide(in: app, appearance: appearance)
        assertGuideFitsScreen(in: app)
        if checksSearch { assertNativeTabFocus("Decide", in: app) }
        let exitDuringTour = workspaceExitButton(in: app)
        XCTAssertTrue(exitDuringTour.waitForExistence(timeout: 5))
        XCTAssertTrue(exitDuringTour.isHittable, "The guide must leave native navigation accessible.")

        let bubble = tourOverlay(in: app)
        XCTAssertTrue(bubble.waitForExistence(timeout: 5))
        let homeEvent = app.descendants(matching: .any)["home.overview.mainEvent"]
        XCTAssertTrue(homeEvent.waitForExistence(timeout: 5))
        let eventFrameWithGuide = homeEvent.frame
        let navigationFrameWithGuide = exitDuringTour.frame
        assertInstructionsOnlyGuide(in: app)
        navigationButton(named: "Ideas", in: app).tap()
        XCTAssertTrue(tourOverlay(in: app).waitForExistence(timeout: 5),
                      "The instructions should remain available across native tabs.")
        navigationButton(named: "Home", in: app).tap()
        assertSameFrame(homeEvent.frame, eventFrameWithGuide, "The guide must not move the Home event card.")
        assertSameFrame(exitDuringTour.frame, navigationFrameWithGuide,
                        "The guide must not move the native navigation control.")

        let nextToIdeas = app.buttons["movieNightTour.next"]
        XCTAssertTrue(nextToIdeas.waitForExistence(timeout: 5))
        XCTAssertTrue(nextToIdeas.isEnabled)
        nextToIdeas.tap()
        dismissPrimer("decide-primer-continue", in: app)
        XCTAssertTrue(navigationButton(named: "Ideas", in: app).waitForExistence(timeout: 5))

        navigationButton(named: "Decide", in: app).tap()
        loveIdea(named: "Popcorn bar", in: app)
        XCTAssertTrue(app.staticTexts["movieNightTour.instruction"].waitForExistence(timeout: 5))
        assertGuideFitsScreen(in: app)
        if checksSearch { assertNativeTabFocus("Ideas", in: app) }
        let previousStep = app.buttons["movieNightTour.previous"]
        XCTAssertTrue(previousStep.waitForExistence(timeout: 5))
        XCTAssertTrue(previousStep.isEnabled,
                       "Previous should let the person review earlier guidance after a real Love It action.")
        previousStep.tap()
        let overlay = tourOverlay(in: app)
        let previousInstruction = XCTNSPredicateExpectation(
            predicate: NSPredicate { element, _ in (element as? XCUIElement)?.value as? String == "ideas" },
            object: overlay
        )
        XCTAssertEqual(XCTWaiter.wait(for: [previousInstruction], timeout: 5), .completed,
                       "Previous should browse back to the earlier Decide instruction without changing the saved action.")
        XCTAssertTrue(navigationButton(named: "Decide", in: app).isSelected)
        let nextToLoveIt = app.buttons["movieNightTour.next"]
        XCTAssertTrue(nextToLoveIt.isEnabled,
                       "The recorded Love It action should unlock its corresponding Ideas instruction.")
        nextToLoveIt.tap()
        XCTAssertTrue(navigationButton(named: "Ideas", in: app).isSelected)

        let filter = app.buttons["ideas.filter"]
        XCTAssertTrue(filter.waitForExistence(timeout: 8))
        XCTAssertTrue(ideaCard(named: "Popcorn bar", in: app).waitForExistence(timeout: 8),
                      "Browsing to the previous instruction must preserve the saved Love It response.")
        let nextToApproval = app.buttons["movieNightTour.next"]
        XCTAssertFalse(nextToApproval.isEnabled,
                       "The next instruction must stay gated until Popcorn bar is actually approved.")
        let filterFocus = app.otherElements["movieNightTour.focus"]
        let filterFocusExists = filterFocus.waitForExistence(timeout: 5)
        if !filterFocusExists {
            let hierarchy = XCTAttachment(
                data: Data(app.debugDescription.utf8),
                uniformTypeIdentifier: "public.plain-text"
            )
            hierarchy.name = "Movie Night filter focus accessibility hierarchy"
            hierarchy.lifetime = .keepAlways
            add(hierarchy)

            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "Movie Night filter focus window"
            screenshot.lifetime = .keepAlways
            add(screenshot)
        }
        XCTAssertTrue(filterFocusExists, "The guide should point at the real native filter.")
        XCTAssertTrue(filterFocus.label.localizedCaseInsensitiveContains("filter"))
        XCTAssertTrue(filter.frame.insetBy(dx: -6, dy: -6).contains(filterFocus.frame))
        assertGuideFitsScreen(in: app)
        attach(app, name: "Guide points at native Ideas filter")
        filter.tap()
        let liked = app.buttons["Liked"]
        XCTAssertTrue(liked.waitForExistence(timeout: 5))
        liked.tap()
        let popcorn = ideaCard(named: "Popcorn bar", in: app)
        XCTAssertTrue(popcorn.waitForExistence(timeout: 8), "The real Love It response should place Popcorn bar in Liked.")
        for _ in 0..<6 where !popcorn.isHittable { app.scrollViews.firstMatch.swipeUp() }
        popcorn.tap()
        XCTAssertTrue(app.buttons["Edit idea"].waitForExistence(timeout: 5))
        XCTAssertTrue(tourOverlay(in: app).waitForNonExistence(timeout: 5), "Pushed idea details should cover the root guide.")
        popIdeaDetail(in: app)
        XCTAssertTrue(tourOverlay(in: app).waitForExistence(timeout: 8))
        let returnedFocus = app.otherElements["movieNightTour.focus"]
        let snackFocus = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in returnedFocus.exists && returnedFocus.label.contains("Popcorn bar") }, object: nil
        )
        XCTAssertEqual(XCTWaiter.wait(for: [snackFocus], timeout: 5), .completed,
                       "Returning from details should preserve Liked and point at the snack rather than cover it with filter guidance.")
        popcorn.press(forDuration: 1.0)
        let approve = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Approve")).firstMatch
        XCTAssertTrue(approve.waitForExistence(timeout: 5))
        approve.tap()
        XCTAssertTrue(tourOverlay(in: app).waitForNonExistence(timeout: 5),
                      "The guide should yield while the approval sheet is presented.")
        let approveConfirmation = app.buttons["idea.approval.confirm"]
        XCTAssertTrue(approveConfirmation.waitForExistence(timeout: 5))
        approveConfirmation.tap()
        XCTAssertTrue(tourOverlay(in: app).waitForExistence(timeout: 8),
                      "Approving the liked snack should keep contextual guidance visible on Ideas.")

        filter.tap()
        let allIdeas = app.buttons["All"]
        XCTAssertTrue(allIdeas.waitForExistence(timeout: 5))
        allIdeas.tap()
        let movieIdea = ideaCard(named: "Watch the movie", in: app)
        XCTAssertTrue(movieIdea.waitForExistence(timeout: 8))
        for _ in 0..<6 where !movieIdea.isHittable { app.scrollViews.firstMatch.swipeUp() }
        movieIdea.press(forDuration: 1.0)
        let schedule = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Schedule")).firstMatch
        XCTAssertTrue(schedule.waitForExistence(timeout: 5))
        schedule.tap()
        XCTAssertTrue(app.staticTexts["idea.schedule.title"].waitForExistence(timeout: 5))
        XCTAssertTrue(tourOverlay(in: app).waitForNonExistence(timeout: 5),
                      "The guide should yield while the scheduling sheet is presented.")
        let confirmSchedule = app.buttons["idea.schedule.confirm"]
        XCTAssertTrue(confirmSchedule.waitForExistence(timeout: 5))
        confirmSchedule.tap()
        XCTAssertTrue(tourOverlay(in: app).waitForExistence(timeout: 8),
                      "The guide should return after the scheduling sheet is dismissed.")

        let done = app.buttons.matching(identifier: "movieNightTour.next")
            .matching(NSPredicate(format: "label == %@", "Finish tour")).firstMatch
        XCTAssertTrue(done.waitForExistence(timeout: 10),
                      "Scheduling the real event idea should add it to the timeline and complete the guide.")
        assertGuideFitsScreen(in: app)
        if checksSearch { assertNativeTabFocus("Home", in: app) }
        navigationButton(named: "Home", in: app).tap()
        let snackActivity = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Snacks & catch-up")).firstMatch
        let movieActivity = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Watch the movie")).firstMatch
        XCTAssertTrue(snackActivity.waitForExistence(timeout: 8))
        XCTAssertTrue(movieActivity.waitForExistence(timeout: 8),
                      "Home should show the blueprint activity and the newly scheduled movie activity.")
        attach(app, name: "Movie Night with two activities — \(appearance ?? "current device")")
        navigationButton(named: "Decide", in: app).tap()
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        done.tap()
        let keepEvent = app.alerts.buttons["movieNightTour.keepEvent"].firstMatch
        XCTAssertTrue(keepEvent.waitForExistence(timeout: 5),
                      "Finishing should ask whether to keep or remove the practice event.")
        keepEvent.tap()
        XCTAssertTrue(done.waitForNonExistence(timeout: 5), "Done should persist completion and dismiss the guide.")
        XCTAssertFalse(app.buttons["decide-primer-continue"].exists,
                       "Completing on Decide must return Home without presenting a primer for the inactive tab.")
        let workspaces = workspaceExitButton(in: app)
        XCTAssertTrue(workspaces.waitForExistence(timeout: 5))
        XCTAssertTrue(workspaces.isHittable)
        workspaces.tap()
        let installedWorkspace = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "Movie Night")
        ).firstMatch
        XCTAssertTrue(installedWorkspace.waitForExistence(timeout: 8))
        installedWorkspace.tap()
        XCTAssertTrue(navigationButton(named: "Home", in: app).waitForExistence(timeout: 8))
        XCTAssertFalse(tourOverlay(in: app).exists,
                       "Reopening a completed workspace should not restart its tour.")
        if checksSearch { try verifySearchAfterTour(in: app) }
    }

    @MainActor
    func testSkippingMovieNightGuideStaysDismissedAcrossAppearanceModes() throws {
        continueAfterFailure = false

        for appearance in ["light", "dark"] {
            let app = launch(appearance: appearance)
            defer { app.terminate() }
            _ = try installMovieNightWorkspaceAndWaitForGuide(in: app, appearance: appearance)

            navigationButton(named: "Ideas", in: app).tap()
            XCTAssertTrue(app.staticTexts["Let's find an idea you love. Open Decide with me."].waitForExistence(timeout: 8),
                          "Using the real native tab should advance education without requiring the guide's route button.")

            let skip = app.buttons["movieNightTour.skip"]
            XCTAssertTrue(skip.waitForExistence(timeout: 5))
            skip.tap()
            let keepEvent = app.alerts.buttons["movieNightTour.keepEvent"].firstMatch
            XCTAssertTrue(keepEvent.waitForExistence(timeout: 5),
                          "Skipping an owned lesson should offer a keep/remove choice.")
            keepEvent.tap()
            XCTAssertTrue(tourOverlay(in: app).waitForNonExistence(timeout: 5),
                          "Keeping the practice event should complete and dismiss the guide.")
            navigationButton(named: "Ideas", in: app).tap()
            navigationButton(named: "Home", in: app).tap()
            XCTAssertFalse(tourOverlay(in: app).exists,
                            "A skipped guide should remain dismissed when returning to Home for the same account.")
            XCTAssertFalse(app.buttons["movieNightTour.resume"].exists,
                           "Skipping should dismiss the mascot entry point too.")
        }
    }

    @MainActor
    func testSkipCanRemoveOwnedPracticeEvent() throws {
        continueAfterFailure = false
        let app = launch(appearance: "light", extraArguments: ["-MovieNightCatalogUnavailable"])
        defer { app.terminate() }
        _ = try installMovieNightWorkspaceAndWaitForGuide(in: app, appearance: "light")

        app.buttons["movieNightTour.skip"].tap()
        let removeEvent = app.alerts.buttons["movieNightTour.removeEvent"].firstMatch
        XCTAssertTrue(removeEvent.waitForExistence(timeout: 5),
                      "The remove option should be available after an owned Movie Night workspace exists.")
        removeEvent.tap()

        let workspacesTab = navigationButton(named: "Events", in: app)
        XCTAssertTrue(workspacesTab.waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Movie Night")).firstMatch.exists,
                       "Removing the practice event should remove it from the account's workspace list.")
    }

    @MainActor
    func testOriginalWelcomePrecedesTourAndSearchWaitsForExplore() throws {
        continueAfterFailure = false
        let app = launch(appearance: nil, extraArguments: ["-MovieNightCatalogUnavailable"], continuesWelcome: false)
        defer { app.terminate() }
        continueWelcome(in: app)
        app.buttons["movieNightOnboarding.skip"].tap()
        XCTAssertTrue(navigationButton(named: "Events", in: app).waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["search.primer.continue"].exists)
        XCTAssertFalse(app.buttons["decide-primer-continue"].exists)
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Movie Night")).firstMatch.exists)
        navigationButton(named: "Explore", in: app).tap()
        let searchHeading = app.staticTexts["Find ideas for your event"]
        XCTAssertTrue(searchHeading.waitForExistence(timeout: 8),
                      "The first Explore visit after skipping the tour should present the Search primer.")
        for (identifier, title) in [
            ("search.primer.feature.search", "Search blueprints and ideas"),
            ("search.primer.feature.filter", "Choose what to browse"),
            ("search.primer.feature.add", "Add an idea to your event")
        ] {
            let featureRow = app.descendants(matching: .any)[identifier].firstMatch
            XCTAssertTrue(featureRow.waitForExistence(timeout: 5))
            XCTAssertTrue(featureRow.label.contains(title), "Each feature row should retain its education content.")
        }
        XCTAssertTrue(app.descendants(matching: .any)["primer.brandHeader"].firstMatch.exists)
        XCTAssertFalse(app.sheets.firstMatch.exists, "Search education should share the welcome screen's presentation.")
        let continueSearch = app.buttons["search.primer.continue"]
        XCTAssertTrue(continueSearch.waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(continueSearch.frame.height, 44,
                                    "The Search primer action should meet the minimum touch target.")
        XCTAssertTrue(app.windows.firstMatch.frame.contains(continueSearch.frame),
                      "The Search primer action should remain on screen.")
        XCTAssertTrue(continueSearch.isHittable)
        XCTAssertEqual(continueSearch.label, "Continue")
        attach(app, name: "Welcome-style Explore primer")
        let addFeature = app.descendants(matching: .any)["search.primer.feature.add"].firstMatch
        if addFeature.frame.maxY > continueSearch.frame.minY - 8 {
            app.scrollViews.firstMatch.swipeUp()
        }
        XCTAssertLessThanOrEqual(addFeature.frame.maxY, continueSearch.frame.minY - 8,
                                 "The last feature must scroll clear of the fixed action.")
        XCTAssertTrue(continueSearch.isHittable)
        attach(app, name: "Explore primer last feature clear of action")
        dismissPrimer("search.primer.continue", in: app)
        XCTAssertTrue(app.searchFields.firstMatch.waitForExistence(timeout: 8))
        navigationButton(named: "Events", in: app).tap()
        navigationButton(named: "Explore", in: app).tap()
        XCTAssertFalse(app.buttons["search.primer.continue"].exists,
                       "Search education should appear only on the first Explore visit.")
    }

    @MainActor
    func testGuidedExploreKeepsNormalFeedVisibleButOnlyMovieNightSelectable() throws {
        continueAfterFailure = false
        for appearance in ["light", "dark"] {
            let app = launch(appearance: appearance, extraArguments: ["-BlueprintSearchVisualFixture"])
            defer { app.terminate() }
            let start = app.buttons["movieNightOnboarding.start"]
            XCTAssertTrue(start.waitForExistence(timeout: 12))
            start.tap()
            try selectBundledMovieNightFromDiscovery(in: app)
            XCTAssertTrue(tourOverlay(in: app).waitForExistence(timeout: 15),
                          "The single enabled Movie Night feed card should open its saved local lesson.")

            app.buttons["movieNightTour.skip"].tap()
            let keepEvent = app.alerts.buttons["movieNightTour.keepEvent"].firstMatch
            XCTAssertTrue(keepEvent.waitForExistence(timeout: 5),
                          "Skipping the owned lesson should preserve the real keep/remove choice.")
            keepEvent.tap()
            XCTAssertTrue(tourOverlay(in: app).waitForNonExistence(timeout: 8))

            navigationButton(named: "Home", in: app).tap()
            let exitWorkspace = workspaceExitButton(in: app)
            XCTAssertTrue(exitWorkspace.waitForExistence(timeout: 5))
            XCTAssertTrue(exitWorkspace.isHittable)
            exitWorkspace.tap()
            navigationButton(named: "Explore", in: app).tap()

            let searchPrimer = app.buttons["search.primer.continue"]
            if searchPrimer.waitForExistence(timeout: 5) {
                searchPrimer.tap()
                XCTAssertTrue(searchPrimer.waitForNonExistence(timeout: 5))
            }
            let search = app.searchFields.firstMatch
            XCTAssertTrue(search.waitForExistence(timeout: 8),
                          "The regular Explore search field should return after the tour ends.")
            XCTAssertTrue(search.isEnabled)
            XCTAssertTrue(search.isHittable)
            search.tap()
            search.typeText("wedding")
            XCTAssertEqual(search.value as? String, "wedding")
            search.typeText("\n")

            let results = app.buttons.matching(
                NSPredicate(format: "identifier BEGINSWITH %@", "blueprint.catalog.card.")
            )
            let weddingResult = results.firstMatch
            XCTAssertTrue(weddingResult.waitForExistence(timeout: 8),
                          "Normal Search should return the fixture's matching blueprint cards after guided mode ends.")
            XCTAssertTrue(weddingResult.isEnabled)
            let catalogScroll = app.scrollViews["blueprint.catalog.scroll"]
            XCTAssertTrue(catalogScroll.waitForExistence(timeout: 5))
            catalogScroll.swipeUp()
            XCTAssertEqual(search.value as? String, "wedding",
                           "Scrolling normal Search results should retain the active query.")

            let dismissSearch = searchCloseButton(in: app)
            XCTAssertTrue(dismissSearch.waitForExistence(timeout: 5))
            XCTAssertTrue(dismissSearch.isHittable)
            dismissSearch.tap()
            XCTAssertTrue(dismissSearch.waitForNonExistence(timeout: 5))
        }
    }

    @MainActor
    func testSkippingDiscoveryStepLeavesNoWorkspaceAndRestoresNormalExplore() throws {
        continueAfterFailure = false
        let app = launch(appearance: "light", extraArguments: ["-MovieNightCatalogUnavailable"])
        defer { app.terminate() }

        XCTAssertTrue(app.buttons["movieNightOnboarding.start"].waitForExistence(timeout: 12))
        app.buttons["movieNightOnboarding.start"].tap()
        let discoveryGuide = app.descendants(matching: .any)["movieNightTour.discovery.overlay"].firstMatch
        XCTAssertTrue(discoveryGuide.waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["Tap Explore to find Movie Night."].waitForExistence(timeout: 5))
        let next = app.buttons["movieNightTour.next"]
        XCTAssertTrue(next.waitForExistence(timeout: 5))
        XCTAssertFalse(next.isEnabled,
                       "The entry step cannot advance until the person visits Explore and chooses Movie Night.")
        XCTAssertFalse(app.buttons["search.primer.continue"].exists,
                       "Search education must not appear during the active discovery guide.")

        let skip = app.buttons["movieNightTour.skip"]
        XCTAssertTrue(skip.waitForExistence(timeout: 5))
        skip.tap()
        XCTAssertTrue(discoveryGuide.waitForNonExistence(timeout: 5))

        navigationButton(named: "Events", in: app).tap()
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Movie Night")).firstMatch.exists,
                       "Skipping the discovery step must not create a practice workspace.")
        navigationButton(named: "Explore", in: app).tap()
        dismissPrimer("search.primer.continue", in: app)
        let searchField = app.searchFields.firstMatch
        XCTAssertTrue(searchField.waitForExistence(timeout: 8),
                      "Explore should return to its unrestricted searchable surface after the primer.")
        XCTAssertTrue(searchField.isEnabled)
        XCTAssertTrue(searchField.isHittable)
    }

    @MainActor
    func testWorkspaceGuidePointersFollowDecideAndIdeasTabs() throws {
        continueAfterFailure = false
        let app = launch(appearance: nil, extraArguments: ["-MovieNightCatalogUnavailable"])
        defer { app.terminate() }

        let start = app.buttons["movieNightOnboarding.start"]
        XCTAssertTrue(start.waitForExistence(timeout: 12))
        start.tap()
        try selectBundledMovieNightFromDiscovery(in: app)

        let decideTab = navigationButton(named: "Decide", in: app)
        XCTAssertTrue(decideTab.waitForExistence(timeout: 8))
        XCTAssertTrue(decideTab.isHittable, "The Decide tab should remain tappable beneath its guide spotlight.")
        let decideFocus = app.otherElements["movieNightTour.tabFocus"]
        XCTAssertTrue(decideFocus.waitForExistence(timeout: 8))
        XCTAssertTrue(decideFocus.label.contains("Decide"))
        let measuredDecideFrame = measuredFocusFrame(from: decideFocus)
        XCTAssertNotNil(measuredDecideFrame, "The test diagnostic should expose the measured Decide tab frame.")
        if let measuredDecideFrame {
            XCTAssertTrue(measuredDecideFrame.insetBy(dx: -3, dy: -3).contains(decideTab.frame),
                          "The guide spotlight should match the real Decide tab frame.")
        }
        assertInstructionsOnlyGuide(in: app)
        assertGuideFitsScreen(in: app)
        attach(app, name: "Guide points at native Decide")
        XCTAssertFalse(app.buttons["decide-primer-continue"].exists)
        decideTab.tap()
        dismissPrimer("decide-primer-continue", in: app)
        loveIdea(named: "Popcorn bar", in: app)

        let ideasTab = navigationButton(named: "Ideas", in: app)
        XCTAssertTrue(ideasTab.waitForExistence(timeout: 8))
        XCTAssertTrue(ideasTab.isHittable, "The Ideas tab should remain tappable beneath its guide spotlight.")
        let ideasFocus = app.otherElements["movieNightTour.tabFocus"]
        XCTAssertTrue(ideasFocus.waitForExistence(timeout: 8))
        XCTAssertTrue(ideasFocus.label.contains("Ideas"))
        let measuredIdeasFrame = measuredFocusFrame(from: ideasFocus)
        XCTAssertNotNil(measuredIdeasFrame, "The test diagnostic should expose the measured Ideas tab frame.")
        if let measuredIdeasFrame {
            XCTAssertTrue(measuredIdeasFrame.insetBy(dx: -3, dy: -3).contains(ideasTab.frame),
                          "The guide spotlight should match the real Ideas tab frame.")
        }
        attach(app, name: "Guide points at native Ideas")
        ideasTab.tap()

        let ideasFilter = app.buttons["ideas.filter"]
        XCTAssertTrue(ideasFilter.waitForExistence(timeout: 8))
        let filterFocus = app.otherElements["movieNightTour.focus"]
        XCTAssertTrue(filterFocus.waitForExistence(timeout: 8),
                      "After reaching Ideas, guidance should move to the filter or saved idea card.")
        XCTAssertTrue(filterFocus.label.localizedCaseInsensitiveContains("filter")
                      || filterFocus.label.localizedCaseInsensitiveContains("Popcorn bar"))
    }

    @MainActor
    func testAdaptiveExplorePointerSurvivesRepeatedEntry() throws {
        continueAfterFailure = false

        for _ in 0..<2 {
            let app = launch(appearance: nil, extraArguments: ["-MovieNightCatalogUnavailable"])
            defer { app.terminate() }

            let start = app.buttons["movieNightOnboarding.start"]
            XCTAssertTrue(start.waitForExistence(timeout: 12))
            start.tap()
            let discoveryGuide = app.descendants(matching: .any)["movieNightTour.discovery.overlay"].firstMatch
            XCTAssertTrue(discoveryGuide.waitForExistence(timeout: 8))
            XCTAssertTrue(app.staticTexts["Tap Explore to find Movie Night."].waitForExistence(timeout: 5))

            let explore = navigationButton(named: "Explore", in: app)
            XCTAssertTrue(explore.waitForExistence(timeout: 8))
            XCTAssertTrue(explore.isHittable, "The adaptive Explore control must remain tappable under its spotlight.")
            let focus = app.otherElements["movieNightTour.discovery.focus"]
            let exploreFocus = XCTNSPredicateExpectation(
                predicate: NSPredicate { _, _ in focus.exists && focus.label.contains("Explore") },
                object: nil
            )
            XCTAssertEqual(XCTWaiter.wait(for: [exploreFocus], timeout: 8), .completed)
            let measuredExploreFrame = measuredFocusFrame(from: focus)
            XCTAssertNotNil(measuredExploreFrame, "The guide should expose the measured native Explore frame.")
            if let measuredExploreFrame {
                assertSameFrame(measuredExploreFrame, explore.frame,
                                "The spotlight should track the actual adaptive Explore button.", accuracy: 3)
            }

            explore.tap()
            dismissPrimer("search.primer.continue", in: app)
            XCTAssertTrue(app.staticTexts["Tap Movie Night to start your plan."].waitForExistence(timeout: 8))
            let previous = app.buttons["movieNightTour.previous"]
            XCTAssertTrue(previous.waitForExistence(timeout: 5))
            XCTAssertTrue(previous.isHittable)
            previous.tap()
            XCTAssertTrue(app.staticTexts["Tap Explore to find Movie Night."].waitForExistence(timeout: 8))
            XCTAssertTrue(explore.isHittable, "Returning to the first step should restore the Explore spotlight.")
            let restoredFocus = XCTNSPredicateExpectation(
                predicate: NSPredicate { _, _ in focus.exists && focus.label.contains("Explore") },
                object: nil
            )
            XCTAssertEqual(XCTWaiter.wait(for: [restoredFocus], timeout: 8), .completed)
            guard let restoredFrame = measuredFocusFrame(from: focus) else {
                XCTFail("Returning to the first step should restore measured Explore coordinates.")
                continue
            }
            assertSameFrame(restoredFrame, explore.frame,
                            "Previous should restore focus to the same native Explore control.", accuracy: 3)

            let skip = app.buttons["movieNightTour.skip"]
            XCTAssertTrue(skip.waitForExistence(timeout: 5))
            XCTAssertTrue(skip.isHittable)
            skip.tap()
            XCTAssertTrue(discoveryGuide.waitForNonExistence(timeout: 8),
                          "Skipping before selecting Movie Night should dismiss discovery without installing a workspace.")
            XCTAssertFalse(app.buttons.matching(
                NSPredicate(format: "label CONTAINS[c] %@", "Movie Night")
            ).firstMatch.exists)
        }
    }

    @MainActor
    func testClassicOverrideKeepsOriginalOnboarding() throws {
        let app = launch(appearance: nil, extraArguments: ["-ClassicOnboarding"])
        defer { app.terminate() }
        XCTAssertTrue(app.staticTexts["Welcome to Gatherory"].waitForExistence(timeout: 12))
        app.buttons["Continue"].tap()
        let skip = app.buttons["onboarding.skipEventCreation"]
        XCTAssertTrue(skip.waitForExistence(timeout: 5))
        skip.tap()
        XCTAssertTrue(navigationButton(named: "Events", in: app).waitForExistence(timeout: 10))
    }

    @MainActor
    func testAccountReplayResumesUnfinishedAndReplacesCompletedTour() throws {
        continueAfterFailure = false
        let app = launch(appearance: nil, extraArguments: ["-MovieNightCatalogUnavailable"])
        defer { app.terminate() }
        _ = try installMovieNightWorkspaceAndWaitForGuide(in: app, appearance: nil)
        try replayFromAccount(in: app)
        XCTAssertTrue(tourOverlay(in: app).waitForExistence(timeout: 8), "Replay must resume the unfinished guide in the same workspace.")
        app.buttons["movieNightTour.skip"].tap()
        let keepUnfinishedEvent = app.alerts.buttons["movieNightTour.keepEvent"].firstMatch
        XCTAssertTrue(keepUnfinishedEvent.waitForExistence(timeout: 5))
        keepUnfinishedEvent.tap()
        navigationButton(named: "Decide", in: app).tap()
        dismissPrimer("decide-primer-continue", in: app)
        navigationButton(named: "Home", in: app).tap()
        try replayFromAccount(in: app)
        XCTAssertTrue(tourOverlay(in: app).waitForExistence(timeout: 8))
        app.buttons["movieNightTour.skip"].tap()
        let keepReplayedEvent = app.alerts.buttons["movieNightTour.keepEvent"].firstMatch
        XCTAssertTrue(keepReplayedEvent.waitForExistence(timeout: 5))
        keepReplayedEvent.tap()
        let workspaceExit = workspaceExitButton(in: app)
        XCTAssertTrue(workspaceExit.waitForExistence(timeout: 5))
        XCTAssertTrue(workspaceExit.isHittable)
        workspaceExit.tap()
        let movieNights = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Movie Night"))
        XCTAssertTrue(movieNights.firstMatch.waitForExistence(timeout: 8))
        XCTAssertEqual(movieNights.count, 2, "Completed replay creates one fresh lesson and preserves the earlier event; unfinished replay creates no duplicate.")
    }

    @MainActor
    func testDeveloperRedoOnboardingRepeatsWelcomeAndSkipWithoutChangingAccountOrWorkspaces() throws {
        continueAfterFailure = false
        let app = launch(appearance: nil, extraArguments: [], continuesWelcome: false, seedsDevelopmentData: true)
        defer { app.terminate() }

        // An existing seeded account enters its cached library directly.
        // Replay must work from there even though ordinary onboarding is bypassed.
        XCTAssertTrue(navigationButton(named: "Events", in: app).waitForExistence(timeout: 12))

        let workspaceTitlesBefore = try seededWorkspaceTitles(in: app)
        XCTAssertFalse(workspaceTitlesBefore.isEmpty, "The developer replay regression needs a seeded account workspace.")

        for replayIndex in 0..<2 {
            try openDeveloperOnboardingReplay(in: app)
            XCTAssertTrue(app.staticTexts["Welcome to Gatherory"].waitForExistence(timeout: 8),
                          "Developer replay \(replayIndex + 1) should return to the original Welcome screen.")
            XCTAssertTrue(app.buttons["onboarding.welcome.continue"].isHittable)
            app.buttons["onboarding.welcome.continue"].tap()
            XCTAssertTrue(app.buttons["movieNightOnboarding.skip"].waitForExistence(timeout: 8),
                          "Continuing should show the existing Movie Night onboarding choice.")
            app.buttons["movieNightOnboarding.skip"].tap()
            XCTAssertTrue(navigationButton(named: "Events", in: app).waitForExistence(timeout: 8),
                          "Skipping the optional Movie Night onboarding should return to the same account app.")

            let workspaceTitlesAfter = try seededWorkspaceTitles(in: app)
            XCTAssertEqual(workspaceTitlesAfter, workspaceTitlesBefore,
                           "Redo onboarding and skipping should preserve the account's existing workspaces.")
        }
    }

    @MainActor
    func testExploreSpotlightPreservesNativeTapAndGuideControls() throws {
        continueAfterFailure = false
        for appearance in ["light", "dark"] {
            let app = launch(appearance: appearance, extraArguments: ["-MovieNightCatalogUnavailable"])
            defer { app.terminate() }
            let start = app.buttons["movieNightOnboarding.start"]
            XCTAssertTrue(start.waitForExistence(timeout: 12))
            start.tap()
            let explore = navigationButton(named: "Explore", in: app)
            XCTAssertTrue(explore.waitForExistence(timeout: 8))
            let focus = app.otherElements["movieNightTour.discovery.focus"]
            XCTAssertTrue(focus.waitForExistence(timeout: 5))
            XCTAssertTrue(focus.label.contains("Explore"))
            XCTAssertTrue(explore.isHittable, "The dimming overlay must not intercept the native tab.")
            let tabFrame = explore.frame
            XCTAssertTrue(app.buttons["movieNightTour.skip"].isHittable)
            attach(app, name: "Feathered guide and Explore spotlight — \(appearance)")
            explore.tap()
            dismissPrimer("search.primer.continue", in: app)
            XCTAssertTrue(app.buttons["movieNightTour.explore.movieNight"].waitForExistence(timeout: 8))
            let previous = app.buttons["movieNightTour.previous"]
            XCTAssertTrue(previous.isHittable, "The blur must not intercept guide controls.")
            previous.tap()
            XCTAssertTrue(app.staticTexts["Tap Explore to find Movie Night."].waitForExistence(timeout: 5))
            XCTAssertTrue(explore.isHittable)
            assertSameFrame(explore.frame, tabFrame, "The spotlight must not move the native tab.")
            app.buttons["movieNightTour.skip"].tap()
            XCTAssertTrue(app.staticTexts["Tap Explore to find Movie Night."].waitForNonExistence(timeout: 5))
            XCTAssertTrue(explore.isHittable, "Skipping must remove the spotlight without affecting navigation.")
        }
    }

    @MainActor
    private func replayFromAccount(in app: XCUIApplication) throws {
        let barAccount = app.navigationBars.buttons["Account and settings"].firstMatch
        let account = barAccount.exists ? barAccount : app.buttons["Account and settings"].firstMatch
        XCTAssertTrue(account.waitForExistence(timeout: 5))
        account.tap()
        let replay = app.buttons["account.redoTour"]
        // Account uses a native lazy List: offscreen rows may not exist yet.
        for _ in 0..<6 {
            if replay.exists && replay.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(replay.waitForExistence(timeout: 5))
        XCTAssertTrue(replay.isHittable)
        replay.tap()
        continueWelcome(in: app)
        let start = app.buttons["movieNightOnboarding.start"]
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        start.tap()
        XCTAssertTrue(start.waitForNonExistence(timeout: 8))
        try selectBundledMovieNightFromDiscovery(in: app)
    }

    @MainActor
    private func openDeveloperOnboardingReplay(in app: XCUIApplication) throws {
        let toolbarAccount = app.navigationBars.buttons["Account and settings"].firstMatch
        let globalAccount = app.buttons["Account and settings"].firstMatch
        let account = toolbarAccount.exists ? toolbarAccount : globalAccount
        XCTAssertTrue(account.waitForExistence(timeout: 8), "The current account should remain accessible from the app toolbar.")
        account.tap()

        let redo = app.buttons["account.developer.redoOnboarding"]
        for _ in 0..<8 {
            if redo.exists && redo.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(redo.waitForExistence(timeout: 5), "The debug development action should appear in Account's lazy list.")
        XCTAssertTrue(redo.isHittable)
        redo.tap()
    }

    @MainActor
    private func seededWorkspaceTitles(in app: XCUIApplication) throws -> [String] {
        XCTAssertTrue(navigationButton(named: "Events", in: app).waitForExistence(timeout: 5))
        let cards = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "events.event.")
        )
        XCTAssertTrue(cards.firstMatch.waitForExistence(timeout: 8), "The seeded account's workspaces should be visible in Events.")
        let ids = (0..<cards.count).map { cards.element(boundBy: $0).identifier }.sorted()
        return ids
    }

    @MainActor
    private func selectBundledMovieNightFromDiscovery(in app: XCUIApplication) throws {
        let discoveryGuide = app.descendants(matching: .any)["movieNightTour.discovery.overlay"].firstMatch
        XCTAssertTrue(discoveryGuide.waitForExistence(timeout: 8))
        let explorePrompt = app.staticTexts["Tap Explore to find Movie Night."]
        if explorePrompt.exists {
            attach(app, name: "Native Explore tab pointer")
            let exploreTab = navigationButton(named: "Explore", in: app)
            XCTAssertTrue(exploreTab.isHittable,
                          "The first discovery step should point to the actual native Explore tab.")
            let exploreFocus = app.otherElements["movieNightTour.discovery.focus"]
            XCTAssertTrue(exploreFocus.waitForExistence(timeout: 5))
            XCTAssertTrue(exploreFocus.label.contains("Explore"))
            let measuredExploreFrame = measuredFocusFrame(from: exploreFocus)
            XCTAssertNotNil(measuredExploreFrame, "The test diagnostic should expose the measured Explore target frame.")
            if let measuredExploreFrame {
                XCTAssertTrue(measuredExploreFrame.insetBy(dx: -3, dy: -3).contains(exploreTab.frame),
                              "The guide focus should match the actual Explore tab frame.")
            }
            XCTAssertEqual(app.buttons["movieNightTour.previous"].label, "Previous")
            XCTAssertEqual(app.buttons["movieNightTour.skip"].label, "Skip tour")
            XCTAssertEqual(app.buttons["movieNightTour.next"].label, "Next")
            XCTAssertFalse(app.buttons["movieNightTour.next"].isEnabled,
                           "The entry step cannot advance until its real Explore action is complete.")
            navigationButton(named: "Explore", in: app).tap()
            dismissPrimer("search.primer.continue", in: app)
        } else if app.buttons["search.primer.continue"].waitForExistence(timeout: 3) {
            dismissPrimer("search.primer.continue", in: app)
        }
        XCTAssertFalse(app.buttons["search.primer.continue"].exists,
                       "Dismissing Search should return to the active discovery guide.")
        XCTAssertTrue(app.staticTexts["Tap Movie Night to start your plan."].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["movieNightTour.next"].isEnabled,
                       "The Movie Night choice must be selected before the guided intro can continue.")
        XCTAssertEqual(app.buttons["movieNightTour.previous"].label, "Previous")
        XCTAssertEqual(app.buttons["movieNightTour.skip"].label, "Skip tour")
        XCTAssertEqual(app.buttons["movieNightTour.next"].label, "Next")
        app.buttons["movieNightTour.previous"].tap()
        XCTAssertTrue(app.staticTexts["Tap Explore to find Movie Night."].waitForExistence(timeout: 5),
                      "Previous should return to the Events and Explore introduction step.")
        XCTAssertFalse(app.buttons["movieNightTour.next"].isEnabled)
        navigationButton(named: "Explore", in: app).tap()
        XCTAssertTrue(app.staticTexts["Tap Movie Night to start your plan."].waitForExistence(timeout: 5))
        let searchField = app.searchFields.firstMatch
        XCTAssertTrue(searchField.waitForExistence(timeout: 8),
                      "Guided Explore should retain the standard feed's visible Search field.")
        XCTAssertFalse(searchField.isEnabled,
                       "Search should remain visible but unavailable during guided Movie Night discovery.")
        XCTAssertFalse(app.buttons["explore.content.filter"].isEnabled,
                       "The regular content filter should be unavailable during guided discovery.")
        XCTAssertFalse(app.buttons["Account and settings"].isEnabled,
                       "Account controls should be unavailable during guided discovery.")
        let lesson = app.buttons["movieNightTour.explore.movieNight"]
        XCTAssertTrue(lesson.waitForExistence(timeout: 8))
        let movieNightFocus = app.otherElements["movieNightTour.discovery.focus"]
        XCTAssertTrue(movieNightFocus.waitForExistence(timeout: 5))
        XCTAssertTrue(movieNightFocus.label.contains("Movie Night"))
        let measuredMovieNightFrame = measuredFocusFrame(from: movieNightFocus)
        XCTAssertNotNil(measuredMovieNightFrame, "The test diagnostic should expose the measured Movie Night target frame.")
        if let measuredMovieNightFrame {
            XCTAssertTrue(measuredMovieNightFrame.insetBy(dx: -3, dy: -3).contains(lesson.frame),
                          "The guide focus should match the actual bundled Movie Night card frame.")
        }
        XCTAssertTrue(lesson.isEnabled,
                      "Movie Night should be the only selectable blueprint while discovery is guided.")
        let otherCards = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "blueprint.catalog.card.")
        )
        if app.launchArguments.contains("-BlueprintSearchVisualFixture") {
            XCTAssertGreaterThan(otherCards.count, 0,
                                 "The standard Explore feed should remain visible around the bundled lesson.")
        }
        for index in 0..<otherCards.count {
            XCTAssertFalse(otherCards.element(boundBy: index).isEnabled,
                           "Non-Movie Night feed cards must be disabled during guided discovery.")
        }
        XCTAssertEqual(app.buttons.matching(identifier: "movieNightTour.explore.movieNight").count, 1,
                       "The guided feed should contain one selectable bundled Movie Night card.")
        XCTAssertFalse(app.buttons["search.primer.continue"].exists)
        assertGuideFitsScreen(in: app, discovery: true)
        attach(app, name: "Only bundled Movie Night in guided Explore")
        lesson.tap()
        XCTAssertTrue(tourOverlay(in: app).waitForExistence(timeout: 15),
                      "Selecting the bundled lesson should create/open its local workspace and begin the planning guide.")
    }

    @MainActor
    private func launch(
        appearance: String?,
        extraArguments: [String] = [],
        continuesWelcome: Bool = true,
        seedsDevelopmentData: Bool = false
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-DisableProductionFlowSimulation", "-SkipAuthentication"]
        if seedsDevelopmentData {
            app.launchArguments.append("-SeedDevelopmentData")
        } else {
            app.launchArguments.append("-DisableSeedData")
        }
        app.launchArguments += [
            "-UseEphemeralDataStore", "-AlwaysShowOnboarding", "-ResetMovieNightTourUITestState",
            "-home.layout", "overview", "-AppleLanguages", "(en)",
        ]
        if let appearance {
            app.launchArguments += ["-AppleInterfaceStyle", appearance, "-appAppearance", appearance]
        }
        app.launchArguments += extraArguments
        app.launch()
        if continuesWelcome, !extraArguments.contains("-ClassicOnboarding") {
            continueWelcome(in: app)
        }
        return app
    }

    @MainActor
    private func continueWelcome(in app: XCUIApplication,
                                 file: StaticString = #filePath, line: UInt = #line) {
        let welcome = app.staticTexts["Welcome to Gatherory"]
        XCTAssertTrue(welcome.waitForExistence(timeout: 12), file: file, line: line)
        XCTAssertFalse(app.buttons["decide-primer-continue"].exists, file: file, line: line)
        XCTAssertFalse(app.buttons["search.primer.continue"].exists, file: file, line: line)
        XCTAssertFalse(app.buttons["movieNightOnboarding.start"].exists, file: file, line: line)
        let next = app.buttons["onboarding.welcome.continue"]
        XCTAssertTrue(next.isHittable, file: file, line: line)
        next.tap()
        XCTAssertTrue(app.buttons["movieNightOnboarding.start"].waitForExistence(timeout: 5), file: file, line: line)
        XCTAssertFalse(app.buttons["decide-primer-continue"].exists, file: file, line: line)
        XCTAssertFalse(app.buttons["search.primer.continue"].exists, file: file, line: line)
    }

    @MainActor
    private func dismissPrimer(_ identifier: String, in app: XCUIApplication,
                               file: StaticString = #filePath, line: UInt = #line) {
        let action = app.buttons[identifier]
        XCTAssertTrue(action.waitForExistence(timeout: 8), "A tab's first visit should present its primer.", file: file, line: line)
        XCTAssertTrue(action.isHittable, file: file, line: line)
        action.tap()
        XCTAssertTrue(action.waitForNonExistence(timeout: 5), file: file, line: line)
    }

    @MainActor
    private func installMovieNightWorkspaceAndWaitForGuide(
        in app: XCUIApplication,
        appearance: String?
    ) throws -> XCUIElement {
        let start = app.buttons["movieNightOnboarding.start"]
        XCTAssertTrue(start.waitForExistence(timeout: 12))
        XCTAssertFalse(app.buttons["movieNightOnboarding.preview"].exists)
        attach(app, name: "Bundled Movie Night choice — \(appearance ?? "current device")")
        start.tap()
        let discoveryGuide = app.descendants(matching: .any)["movieNightTour.discovery.overlay"]
        XCTAssertTrue(discoveryGuide.waitForExistence(timeout: 8))
        let exploreTab = navigationButton(named: "Explore", in: app)
        if !exploreTab.isHittable {
            let hierarchy = XCTAttachment(
                data: Data(app.debugDescription.utf8),
                uniformTypeIdentifier: "public.plain-text"
            )
            hierarchy.name = "Adaptive Explore spotlight accessibility hierarchy"
            hierarchy.lifetime = .keepAlways
            add(hierarchy)

            let guideScreenshot = XCTAttachment(screenshot: discoveryGuide.screenshot())
            guideScreenshot.name = "Adaptive Explore discovery guide element"
            guideScreenshot.lifetime = .keepAlways
            add(guideScreenshot)
        }
        XCTAssertTrue(exploreTab.isHittable,
                      "The spotlight overlay must pass taps through to the actual native Explore tab.")
        XCTAssertTrue(app.buttons["movieNightTour.skip"].isHittable,
                      "The spotlight must leave the feathered guide's own controls tappable.")
        let exploreFocus = app.otherElements["movieNightTour.discovery.focus"]
        XCTAssertTrue(exploreFocus.waitForExistence(timeout: 5))
        XCTAssertTrue(exploreFocus.label.contains("Explore"))
        let measuredExploreFrame = measuredFocusFrame(from: exploreFocus)
        XCTAssertNotNil(measuredExploreFrame, "The test diagnostic should expose the measured Explore target frame.")
        if let measuredExploreFrame {
            XCTAssertTrue(measuredExploreFrame.insetBy(dx: -3, dy: -3).contains(exploreTab.frame),
                          "The guide focus should match the actual Explore tab frame.")
        }
        navigationButton(named: "Events", in: app).tap()
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Movie Night")).firstMatch.exists,
                       "Starting the tour should open discovery without creating a workspace.")
        assertInstructionsOnlyGuide(in: app, discovery: true)
        assertGuideFitsScreen(in: app, discovery: true)
        attach(app, name: "Feathered guide and native Explore spotlight — \(appearance ?? "current device")")
        navigationButton(named: "Explore", in: app).tap()
        try selectBundledMovieNightFromDiscovery(in: app)
        let guideInstruction = app.staticTexts["movieNightTour.instruction"]
        XCTAssertTrue(guideInstruction.waitForExistence(timeout: 20),
                      "The successful installation should open the actual imported workspace and resume the guide.")
        let previous = app.buttons["movieNightTour.previous"]
        let skip = app.buttons["movieNightTour.skip"]
        let next = app.buttons["movieNightTour.next"]
        XCTAssertTrue(previous.waitForExistence(timeout: 5))
        XCTAssertTrue(skip.waitForExistence(timeout: 5))
        XCTAssertTrue(next.waitForExistence(timeout: 5))
        XCTAssertEqual(skip.frame.midX, (previous.frame.midX + next.frame.midX) / 2, accuracy: 3,
                       "Skip should stay centered between the Previous and Next controls.")
        assertInstructionsOnlyGuide(in: app)
        return guideInstruction
    }

    @MainActor
    private func assertInstructionsOnlyGuide(in app: XCUIApplication, discovery: Bool = false,
                                             file: StaticString = #filePath, line: UInt = #line) {
        let instruction = app.staticTexts[discovery
            ? "movieNightTour.discovery.instruction" : "movieNightTour.instruction"]
        XCTAssertTrue(instruction.waitForExistence(timeout: 5), file: file, line: line)
        XCTAssertFalse(instruction.label.isEmpty, file: file, line: line)
        XCTAssertFalse(app.staticTexts["Your Movie Night guide"].exists, file: file, line: line)
        XCTAssertFalse(app.buttons["movieNightTour.hide"].exists, file: file, line: line)
        XCTAssertFalse(app.buttons["movieNightTour.resume"].exists, file: file, line: line)
    }

    @MainActor
    private func assertGuideFitsScreen(in app: XCUIApplication, discovery: Bool = false,
                                       file: StaticString = #filePath, line: UInt = #line) {
        let guide = discovery
            ? app.descendants(matching: .any)["movieNightTour.discovery.overlay"].firstMatch
            : tourOverlay(in: app)
        XCTAssertTrue(guide.waitForExistence(timeout: 5), file: file, line: line)
        let screen = app.frame.insetBy(dx: -1, dy: -1)
        // The feathered blur intentionally extends beyond the screen. Check
        // readable text and interactive controls rather than its effect bounds.
        let previous = app.buttons["movieNightTour.previous"]
        let skip = app.buttons["movieNightTour.skip"]
        let next = app.buttons["movieNightTour.next"]
        for control in [previous, skip, next] {
            XCTAssertTrue(screen.contains(control.frame), "Tour navigation must remain on screen.", file: file, line: line)
            XCTAssertGreaterThanOrEqual(control.frame.height, 43, file: file, line: line)
            if control.isEnabled {
                XCTAssertTrue(control.isHittable, "Enabled tour controls must be tappable on this device.", file: file, line: line)
            }
        }
        XCTAssertLessThanOrEqual(previous.frame.maxX, skip.frame.minX + 1, file: file, line: line)
        XCTAssertLessThanOrEqual(skip.frame.maxX, next.frame.minX + 1, file: file, line: line)
        for text in guide.staticTexts.allElementsBoundByIndex where !text.frame.isEmpty {
            XCTAssertTrue(screen.contains(text.frame), "Guide text must not clip offscreen.", file: file, line: line)
        }
    }

    @MainActor
    private func workspaceExitButton(in app: XCUIApplication) -> XCUIElement {
        let navigationBarButton = app.navigationBars.buttons["Events"].firstMatch
        if navigationBarButton.exists { return navigationBarButton }
        return app.buttons.matching(
            NSPredicate(format: "label == %@ AND identifier == %@", "Events", "rectangle.grid.2x2.fill")
        ).firstMatch
    }

    @MainActor
    private func searchCloseButton(in app: XCUIApplication) -> XCUIElement {
        let predicate = NSPredicate(format: "label == %@ OR label == %@", "Close", "Cancel")
        let navigationBarButton = app.navigationBars.buttons.matching(predicate).firstMatch
        if navigationBarButton.exists { return navigationBarButton }
        return app.buttons.matching(predicate).firstMatch
    }

    @MainActor
    private func popIdeaDetail(in app: XCUIApplication) {
        let navigationBarButtons = app.navigationBars.buttons
        for index in 0..<navigationBarButtons.count {
            let candidate = navigationBarButtons.element(boundBy: index)
            if candidate.isHittable {
                candidate.tap()
                return
            }
        }

        let adaptiveBackButtons = app.buttons.matching(NSPredicate(format: "label == %@", "Back"))
        for index in 0..<adaptiveBackButtons.count {
            let candidate = adaptiveBackButtons.element(boundBy: index)
            if candidate.isHittable {
                candidate.tap()
                return
            }
        }

        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.5))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: end)
    }

    @MainActor
    private func navigationButton(named title: String, in app: XCUIApplication) -> XCUIElement {
        let tabBarButton = app.tabBars.buttons[title]
        if tabBarButton.exists { return tabBarButton }

        let systemImage: String
        switch title {
        case "Events": systemImage = "rectangle.stack.fill"
        case "Blueprints": systemImage = "square.stack.3d.up.fill"
        case "Explore": systemImage = "magnifyingglass"
        case "Home": systemImage = "house.fill"
        case "Ideas": systemImage = "sparkles.rectangle.stack.fill"
        case "Decide": systemImage = "rectangle.on.rectangle.angled"
        default:
            XCTFail("Add the native system image identifier for navigation item: \(title)")
            return app.buttons.matching(identifier: title).firstMatch
        }
        return app.buttons.matching(
            NSPredicate(format: "label == %@ AND identifier == %@", title, systemImage)
        ).firstMatch
    }

    @MainActor
    private func assertNativeTabFocus(_ title: String, in app: XCUIApplication,
                                      file: StaticString = #filePath, line: UInt = #line) {
        let tab = navigationButton(named: title, in: app)
        let focus = app.otherElements["movieNightTour.tabFocus"]
        let expected = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            focus.exists && focus.label.contains(title)
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [expected], timeout: 8), .completed, file: file, line: line)
        XCTAssertTrue(tab.isHittable, file: file, line: line)
        if let frame = measuredFocusFrame(from: focus) {
            assertSameFrame(frame, tab.frame, "The arrow must follow this device's actual native tab.", accuracy: 3,
                            file: file, line: line)
        } else {
            XCTFail("Missing measured tab coordinates.", file: file, line: line)
        }
    }

    @MainActor
    private func verifySearchAfterTour(in app: XCUIApplication) throws {
        let workspaceExit = workspaceExitButton(in: app)
        XCTAssertTrue(workspaceExit.waitForExistence(timeout: 5))
        XCTAssertTrue(workspaceExit.isHittable)
        workspaceExit.tap()
        navigationButton(named: "Explore", in: app).tap()
        let primer = app.buttons["search.primer.continue"]
        if primer.waitForExistence(timeout: 5) { primer.tap() }
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 8))
        XCTAssertTrue(search.isEnabled)
        XCTAssertTrue(search.isHittable)
        search.tap()
        search.typeText("wedding")
        XCTAssertEqual(search.value as? String, "wedding")
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        let close = searchCloseButton(in: app)
        XCTAssertTrue(close.waitForExistence(timeout: 5), "Search should expose its native Close or Cancel control.")
        XCTAssertTrue(close.isHittable, "The keyboard must leave native Search dismissal accessible.")
        attach(app, name: "Native search with keyboard on current device")
        search.typeText("\n")
        let result = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "blueprint.catalog.card.")).firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 8))
        XCTAssertTrue(result.isEnabled)
        app.scrollViews["blueprint.catalog.scroll"].swipeUp()
        XCTAssertEqual(search.value as? String, "wedding")
        close.tap()
        XCTAssertTrue(close.waitForNonExistence(timeout: 5))
    }

    @MainActor
    private func tourOverlay(in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)["movieNightTour.overlay"].firstMatch
    }

    private func measuredFocusFrame(from element: XCUIElement) -> CGRect? {
        let components: [NSNumber]
        if let json = element.value as? String,
           let data = json.data(using: .utf8),
           let decoded = try? JSONSerialization.jsonObject(with: data) as? [NSNumber] {
            components = decoded
        } else if let decoded = element.value as? [NSNumber] {
            components = decoded
        } else {
            return nil
        }
        guard components.count == 4 else { return nil }
        return CGRect(
            x: CGFloat(components[0].doubleValue),
            y: CGFloat(components[1].doubleValue),
            width: CGFloat(components[2].doubleValue),
            height: CGFloat(components[3].doubleValue)
        )
    }

    @MainActor
    private func assertSameFrame(
        _ actual: CGRect,
        _ expected: CGRect,
        _ message: String,
        accuracy: CGFloat = 1,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(actual.minX, expected.minX, accuracy: accuracy, message, file: file, line: line)
        XCTAssertEqual(actual.minY, expected.minY, accuracy: accuracy, message, file: file, line: line)
        XCTAssertEqual(actual.width, expected.width, accuracy: accuracy, message, file: file, line: line)
        XCTAssertEqual(actual.height, expected.height, accuracy: accuracy, message, file: file, line: line)
    }

    @MainActor
    private func loveIdea(named title: String, in app: XCUIApplication) {
        let identifier = NSPredicate(format: "identifier BEGINSWITH %@", "decision-card-")
        let cards = app.buttons.matching(identifier)
        for _ in 0..<8 {
            let card = cards.firstMatch
            XCTAssertTrue(card.waitForExistence(timeout: 6), "Decide should show the installed blueprint ideas.")
            if card.label.localizedCaseInsensitiveContains(title) {
                let focus = app.otherElements["movieNightTour.focus"]
                XCTAssertTrue(focus.waitForExistence(timeout: 5), "The guide should expose its measured focus target.")
                XCTAssertTrue(focus.label.localizedCaseInsensitiveContains(title),
                              "The guide focus should identify the actual idea control without exposing an internal ID.")
                XCTAssertTrue(card.frame.insetBy(dx: -2, dy: -2).contains(focus.frame),
                              "The focus must lie within the actual visible decision card.")
                XCTAssertGreaterThan(focus.frame.width * focus.frame.height, card.frame.width * card.frame.height * 0.5)
                XCTAssertTrue(card.isHittable, "The highlighted decision card must remain tappable.")
                attach(app, name: "Movie Night mascot points at Popcorn bar")
                card.swipeRight()
                return
            }
            // Keep earlier unrelated ideas in Maybe so the target remains available.
            card.swipeUp()
        }
        XCTFail("The Decide deck did not expose \(title).")
    }

    @MainActor
    private func ideaCard(named title: String, in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", title)).firstMatch
    }

    @MainActor
    private func attach(_ app: XCUIApplication, name: String) {
        // On multi-display simulators, capture the actual app window instead
        // of an inactive default display stream.
        let window = app.windows.firstMatch
        let attachment = XCTAttachment(screenshot: window.exists ? window.screenshot() : app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
