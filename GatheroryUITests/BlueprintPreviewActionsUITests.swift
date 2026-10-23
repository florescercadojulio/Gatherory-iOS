import XCTest

final class BlueprintPreviewActionsUITests: XCTestCase {
    @MainActor
    func testDiscoveryKeepsPublicActionsAndReadOnlyWorkspaceInBothAppearances() throws {
        continueAfterFailure = false
        for appearance in ["light", "dark"] {
            let app = launch(context: "discovery", appearance: appearance)
            openDiscoveryPreview(in: app)
            XCTAssertTrue(app.buttons["blueprint.preview.close"].waitForExistence(timeout: 12))
            let like = app.buttons["blueprint.preview.like"]
            let bookmark = app.buttons["blueprint.preview.bookmark"]
            let more = app.buttons["blueprint.preview.more"]
            XCTAssertTrue(like.waitForExistence(timeout: 5))
            XCTAssertTrue(bookmark.exists)
            XCTAssertTrue(more.exists)
            XCTAssertFalse(app.tabBars.buttons["Home"].exists, "Public preview content should not be split into workspace tabs.")
            XCTAssertFalse(app.tabBars.buttons["Ideas"].exists, "Public preview content should not be split into workspace tabs.")
            XCTAssertFalse(app.tabBars.buttons["Decide"].exists)
            XCTAssertFalse(app.buttons["blueprint.preview.addEvent"].exists)
            XCTAssertFalse(app.buttons["blueprint.preview.addIdea"].exists)
            attach(app, name: "Discovery preview — \(appearance)")

            let originalLikeLabel = like.label
            like.tap()
            XCTAssertTrue(waitForLabelChange(of: like, from: originalLikeLabel), "Like should acknowledge and update in memory.")
            let originalBookmarkLabel = bookmark.label
            bookmark.tap()
            XCTAssertTrue(waitForLabelChange(of: bookmark, from: originalBookmarkLabel), "Save should acknowledge and update in memory.")

            more.tap()
            XCTAssertTrue(app.buttons["blueprint.preview.use"].waitForExistence(timeout: 3),
                          "Discovery puts Use in the overflow menu.")
            XCTAssertFalse(app.buttons["blueprint.preview.addEvent"].exists)
            app.terminate()
        }
    }

    @MainActor
    func testDiscoveryBookmarkAppearsInSavedLibraryCollection() throws {
        continueAfterFailure = false
        let app = launch(context: "discovery", appearance: "light")
        openDiscoveryPreview(in: app)
        XCTAssertTrue(app.buttons["blueprint.preview.close"].waitForExistence(timeout: 12))
        let bookmark = app.buttons["blueprint.preview.bookmark"]
        XCTAssertTrue(bookmark.waitForExistence(timeout: 5))
        bookmark.tap()
        app.buttons["blueprint.preview.close"].tap()

        let collections = openLibraryCollection("Saved", in: app)
        let savedWedding = app.buttons["blueprint.library.public.wedding-visual-1"]
        XCTAssertTrue(savedWedding.waitForExistence(timeout: 8),
                      "A preview bookmark should be available to Saved in the same fixture session.")
        savedWedding.tap()
        XCTAssertTrue(app.buttons["blueprint.preview.use"].waitForExistence(timeout: 8))
        attach(app, name: "Saved preview after discovery bookmark")

        // Fixture Use saves through BlueprintPreviewSession to its temporary
        // draft store, then dismisses into Yours with a resumable working copy.
        app.buttons["blueprint.preview.use"].tap()
        XCTAssertTrue(collections.waitForExistence(timeout: 8))
        collections.buttons["Yours"].tap()
        let workingCopy = app.buttons["blueprint.library.fixture.working"]
        XCTAssertTrue(workingCopy.waitForExistence(timeout: 8))
        workingCopy.tap()
        XCTAssertTrue(app.scrollViews["blueprint.preview.singleScroll"].waitForExistence(timeout: 8))
        let workingMainEvent = app.buttons["blueprint.preview.mainEvent"]
        XCTAssertTrue(workingMainEvent.waitForExistence(timeout: 5))
        XCTAssertTrue(workingMainEvent.label.contains("Wedding"),
                      "Use should seed the working copy with the source Blueprint's default event name.")
        XCTAssertTrue(app.buttons["blueprint.preview.createEvents"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.tabBars.buttons["Decide"].exists)
        XCTAssertEqual(app.buttons["blueprint.preview.close"].label, "Back")
        attach(app, name: "Yours working copy after preview Use")
        let workingScroll = app.scrollViews["blueprint.preview.singleScroll"]
        XCTAssertGreaterThan(workingScroll.frame.height, app.windows.firstMatch.frame.height * 0.8,
                             "A resumed working copy should fill the screen like Liked previews.")
        app.buttons["blueprint.preview.close"].tap()
        XCTAssertTrue(workingScroll.waitForNonExistence(timeout: 8), "Back should return from a working copy to Yours.")
        XCTAssertTrue(collections.waitForExistence(timeout: 8))
        XCTAssertTrue(workingCopy.waitForExistence(timeout: 8), "The resumed working copy should remain in Yours after returning.")
        app.terminate()
    }

    @MainActor
    func testBlueprintUseOpensRealSetupAndRequiresExplicitDateConfirmation() throws {
        continueAfterFailure = false
        for appearance in ["light", "dark"] {
            let app = launch(context: "discovery", appearance: appearance, setupFixture: true)
            defer { app.terminate() }

            openDiscoveryPreview(in: app)
            XCTAssertTrue(app.buttons["blueprint.preview.more"].waitForExistence(timeout: 12))
            app.buttons["blueprint.preview.more"].tap()
            let use = app.buttons["blueprint.preview.use"]
            XCTAssertTrue(use.waitForExistence(timeout: 5))
            use.tap()

            XCTAssertTrue(app.buttons["blueprint.setup.mainDate"].waitForExistence(timeout: 12),
                          "Use should open the real SetupView backed by the local fixture coordinator.")
            let primaryAction = app.buttons["blueprint.setup.primaryAction"]
            XCTAssertTrue(primaryAction.exists)
            XCTAssertEqual(primaryAction.label, "Create Events", "Use must enter the explicit creation flow on first presentation.")
            let eventName = app.textFields["blueprint.setup.eventName"]
            XCTAssertTrue(eventName.waitForExistence(timeout: 5))
            XCTAssertEqual(eventName.value as? String, "My celebration")
            let initialName = eventName.value as? String ?? ""
            eventName.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.5)).tap()
            eventName.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: initialName.count))
            XCTAssertFalse(primaryAction.isEnabled, "An empty event name must disable Create Events.")
            let savedName = "Garden celebration revised"
            eventName.typeText(savedName)

            let mainDate = app.buttons["blueprint.setup.mainDate"]
            XCTAssertEqual(mainDate.value as? String, "Confirm date",
                           "The fixture must not treat a suggested main date as user-confirmed.")
            mainDate.tap()
            XCTAssertTrue(app.navigationBars["Date and Time"].waitForExistence(timeout: 5))
            let timeZoneControl = app.buttons["Time Zone"]
            XCTAssertTrue(timeZoneControl.waitForExistence(timeout: 5),
                          "The main date editor must let the person choose its timezone explicitly.")
            app.navigationBars.buttons["Cancel"].tap()
            XCTAssertEqual(mainDate.value as? String, "Confirm date",
                           "Cancel must leave the main date unconfirmed.")
            XCTAssertFalse(primaryAction.isEnabled)

            mainDate.tap()
            XCTAssertTrue(app.navigationBars["Date and Time"].waitForExistence(timeout: 5))
            let savedTimeZoneLabel = app.buttons["Time Zone"].label
            app.navigationBars.buttons["Done"].tap()
            XCTAssertEqual(mainDate.value as? String, "Confirmed date")
            XCTAssertFalse(primaryAction.isEnabled, "Confirming only the main date must leave the selected child date outstanding.")

            let confirmChild = app.buttons["blueprint.setup.childDate.venue_visit.confirm"]
            XCTAssertTrue(confirmChild.waitForExistence(timeout: 8), "The local transport should provide an explicit suggestion to confirm.")
            XCTAssertTrue(confirmChild.isHittable)
            let childDate = app.buttons["blueprint.setup.childDate.venue_visit"]
            XCTAssertTrue(childDate.exists)
            let suggestedChildLabel = childDate.label
            XCTAssertFalse(suggestedChildLabel.isEmpty,
                           "The selected venue visit should retain its suggested date without a preview decision.")
            confirmChild.tap()
            XCTAssertTrue(app.buttons["blueprint.setup.childDate.venue_visit.confirm"].waitForNonExistence(timeout: 5),
                          "Confirming a suggested date should store that exact candidate.")
            let ready = NSPredicate(format: "enabled == true")
            let enabled = XCTNSPredicateExpectation(predicate: ready, object: primaryAction)
            XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: 5), .completed,
                           "The saved main date and explicitly confirmed child suggestion should enable Create Events.")
            let confirmedChildLabel = childDate.label
            XCTAssertFalse(confirmedChildLabel.isEmpty)

            childDate.tap()
            XCTAssertTrue(app.navigationBars["Date and Time"].waitForExistence(timeout: 5),
                          "A confirmed child date should open the native manual date editor.")
            XCTAssertFalse(app.buttons["Time Zone"].exists,
                           "Child dates inherit the main event timezone.")
            app.navigationBars.buttons["Cancel"].tap()
            XCTAssertEqual(childDate.label, confirmedChildLabel,
                           "Cancel must preserve the previously confirmed child date.")
            XCTAssertTrue(primaryAction.isEnabled)

            childDate.tap()
            XCTAssertTrue(app.navigationBars["Date and Time"].waitForExistence(timeout: 5))
            app.navigationBars.buttons["Done"].tap()
            XCTAssertEqual(childDate.label, confirmedChildLabel,
                           "Saving a child date should keep its confirmed date.")
            XCTAssertTrue(primaryAction.isEnabled)
            eventName.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.5)).tap()
            eventName.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: savedName.count))
            XCTAssertFalse(primaryAction.isEnabled,
                           "An empty name must disable creation even when every date is confirmed.")
            eventName.typeText(savedName + "\n")
            XCTAssertTrue(primaryAction.isEnabled, "Restoring a valid name must retain the confirmed dates.")
            attach(app, name: "Blueprint setup after main and child date saves — \(appearance)")

            // The fixture intentionally has no successful install response. Leave
            // setup through its own close control without claiming a server import.
            app.navigationBars.buttons["Close"].tap()
            XCTAssertTrue(app.buttons["blueprint.preview.close"].waitForExistence(timeout: 5))

            app.buttons["blueprint.preview.more"].tap()
            XCTAssertTrue(use.waitForExistence(timeout: 5))
            use.tap()
            XCTAssertTrue(mainDate.waitForExistence(timeout: 12))
            XCTAssertEqual(mainDate.value as? String, "Confirmed date", "The main date should survive closing and reopening setup.")
            XCTAssertEqual(eventName.value as? String, savedName, "The edited event name should survive closing and reopening setup.")
            mainDate.tap()
            XCTAssertTrue(app.navigationBars["Date and Time"].waitForExistence(timeout: 5))
            XCTAssertEqual(app.buttons["Time Zone"].label, savedTimeZoneLabel,
                           "The selected main event timezone should survive closing and reopening setup.")
            app.navigationBars.buttons["Cancel"].tap()
            XCTAssertTrue(primaryAction.isEnabled, "The resumed setup should retain its confirmed child date.")
            XCTAssertFalse(app.buttons["blueprint.setup.childDate.venue_visit.confirm"].exists,
                           "A saved confirmed date should not return as an unconfirmed suggestion.")
            let resumedChildDate = app.buttons["blueprint.setup.childDate.venue_visit"]
            XCTAssertEqual(resumedChildDate.label, confirmedChildLabel,
                           "The saved child date shown in setup should match the date confirmed before closing.")
        }
    }

    @MainActor
    func testDiscoveryUseCopiesInstallsImportsAndLandsInCreatedEventWithRetry() throws {
        continueAfterFailure = false
        let runs: [(context: String, appearance: String, retries: Bool)] = [
            ("discovery", "light", false),
            ("personal", "dark", true),
        ]
        for run in runs {
            let app = launch(context: run.context, appearance: run.appearance, setupFixture: true,
                             retryFirstInstall: run.retries)
            defer { app.terminate() }
            if run.context == "discovery" {
                openDiscoveryPreview(in: app)
                app.buttons["blueprint.preview.more"].tap()
                let use = app.buttons["blueprint.preview.use"]
                XCTAssertTrue(use.waitForExistence(timeout: 5))
                use.tap()
            } else {
                _ = openLibraryCollection("Yours", in: app)
                let card = app.buttons["blueprint.library.card.personal.51000000-0000-4000-8000-000000000001"]
                XCTAssertTrue(card.waitForExistence(timeout: 8))
                card.tap()
                let createEvents = app.toolbars.buttons["blueprint.preview.createEvents"]
                XCTAssertTrue(createEvents.waitForExistence(timeout: 8))
                createEvents.tap()
            }

            let mainDate = app.buttons["blueprint.setup.mainDate"]
            XCTAssertTrue(mainDate.waitForExistence(timeout: 12))
            let submittedName = run.context == "discovery" ? "Discovery handoff celebration" : "Yours handoff celebration"
            let eventName = app.textFields["blueprint.setup.eventName"]
            XCTAssertTrue(eventName.waitForExistence(timeout: 5))
            let originalName = eventName.value as? String ?? ""
            eventName.tap()
            eventName.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: originalName.count) + submittedName + "\n")
            XCTAssertEqual(eventName.value as? String, submittedName)
            mainDate.tap()
            XCTAssertTrue(app.navigationBars["Date and Time"].waitForExistence(timeout: 5))
            app.navigationBars.buttons["Done"].tap()
            let confirmVenue = app.buttons["blueprint.setup.childDate.venue_visit.confirm"]
            XCTAssertTrue(confirmVenue.waitForExistence(timeout: 8),
                          "The copy and schedule calls should complete before the explicit child date confirmation.")
            confirmVenue.tap()
            let create = app.buttons["blueprint.setup.primaryAction"]
            XCTAssertTrue(create.waitForExistence(timeout: 5))
            XCTAssertTrue(create.isEnabled)
            create.tap()

            if run.retries {
                let retry = app.buttons["blueprint.setup.retryInstallation"]
                XCTAssertTrue(retry.waitForExistence(timeout: 12),
                              "A failed local install response should retain the durable request for retry.")
                retry.tap()
            }

            XCTAssertTrue(app.tabBars.buttons["Home"].waitForExistence(timeout: 15),
                          "A successful import should dismiss preview and setup and return to the actual workspace shell.")
            XCTAssertTrue(app.staticTexts[submittedName].waitForExistence(timeout: 8),
                          "The imported main event should match the submitted name and be the selected workspace.")
            XCTAssertFalse(app.buttons["blueprint.preview.close"].exists)
            XCTAssertFalse(app.buttons["blueprint.setup.mainDate"].exists)
            XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Venue visit")).firstMatch
                .waitForExistence(timeout: 8), "The imported selected child event should be visible in Home.")
            app.tabBars.buttons["Ideas"].tap()
            XCTAssertTrue(app.staticTexts["Venue"].waitForExistence(timeout: 8),
                          "The installed starter ideas should be present in the imported workspace.")
            attach(app, name: run.retries
                ? "Created event after retrying the same installation"
                : "Created event after local fixture installation")
            app.terminate()
        }
    }

    @MainActor
    func testCollectionAndPersonalPreviewsExposeContextSpecificActions() throws {
        continueAfterFailure = false

        let collection = launch(context: "collection", appearance: "light")
        _ = openLibraryCollection("Saved", in: collection)
        let savedCard = collection.buttons["blueprint.library.public.wedding-visual-1"]
        XCTAssertTrue(savedCard.waitForExistence(timeout: 8))
        savedCard.tap()
        XCTAssertTrue(collection.buttons["blueprint.preview.close"].waitForExistence(timeout: 12))
        let use = collection.buttons["blueprint.preview.use"]
        XCTAssertTrue(use.waitForExistence(timeout: 5), "Saved collection previews keep Use prominent.")
        XCTAssertTrue(use.isHittable)
        XCTAssertTrue(collection.buttons["blueprint.preview.like"].exists)
        XCTAssertTrue(collection.buttons["blueprint.preview.bookmark"].exists)
        XCTAssertFalse(collection.tabBars.buttons["Decide"].exists)
        attach(collection, name: "Saved collection preview")
        collection.terminate()

        let personal = launch(context: "personal", appearance: "light")
        let personalLibrary = personal.tabBars.buttons["Blueprints"]
        XCTAssertTrue(personalLibrary.waitForExistence(timeout: 8))
        personalLibrary.tap()
        let personalCollections = personal.segmentedControls["blueprint.library.collections"]
        XCTAssertTrue(personalCollections.waitForExistence(timeout: 8))
        personalCollections.buttons["Yours"].tap()
        let personalCard = personal.buttons["blueprint.library.card.personal.51000000-0000-4000-8000-000000000001"]
        XCTAssertTrue(personalCard.waitForExistence(timeout: 8))
        personalCard.tap()
        XCTAssertTrue(personal.buttons["blueprint.preview.close"].waitForExistence(timeout: 12))
        let singleScroll = personal.scrollViews["blueprint.preview.singleScroll"]
        XCTAssertTrue(singleScroll.waitForExistence(timeout: 8))
        XCTAssertTrue(personal.staticTexts["My celebration"].waitForExistence(timeout: 5),
                      "The authored preview should use its saved event name.")
        let createEvents = personal.buttons["blueprint.preview.createEvents"]
        XCTAssertTrue(createEvents.waitForExistence(timeout: 5), "Reusable plans in Yours keep an explicit Create Events action.")
        XCTAssertEqual(createEvents.label, "Use")
        let toolbarCreateEvents = personal.toolbars.buttons["blueprint.preview.createEvents"]
        XCTAssertTrue(toolbarCreateEvents.exists, "Create Events belongs to the native bottom toolbar.")
        XCTAssertTrue(toolbarCreateEvents.isHittable)
        XCTAssertGreaterThan(toolbarCreateEvents.frame.midY, personal.windows.firstMatch.frame.midY)
        XCTAssertFalse(personal.tabBars.buttons["Decide"].exists)
        let mainEvent = personal.buttons["blueprint.preview.mainEvent"]
        let venueIdea = personal.buttons["blueprint.preview.idea.venue"]
        for _ in 0..<5 where !mainEvent.isHittable { singleScroll.swipeUp() }
        XCTAssertTrue(mainEvent.isHittable, "The main event is part of the same Yours scroll.")
        for _ in 0..<5 where !venueIdea.isHittable { singleScroll.swipeUp() }
        XCTAssertTrue(venueIdea.isHittable, "Ideas follow events in the same Yours scroll.")
        for _ in 0..<5 where !mainEvent.isHittable { singleScroll.swipeDown() }
        XCTAssertTrue(mainEvent.isHittable)
        let previewNavigationTop = personal.navigationBars.firstMatch.frame.minY
        mainEvent.tap()
        XCTAssertTrue(personal.navigationBars.staticTexts["Edit Event"].waitForExistence(timeout: 5))
        XCTAssertGreaterThan(personal.navigationBars["Edit Event"].frame.minY, previewNavigationTop,
                             "The event editor should be a native sheet over the full-screen preview.")
        let titleField = personal.textFields.firstMatch
        XCTAssertTrue(titleField.waitForExistence(timeout: 5))
        let originalTitle = titleField.value as? String ?? ""
        XCTAssertFalse(originalTitle.isEmpty)
        let revisedTitle = "A revised celebration"
        titleField.coordinate(withNormalizedOffset: CGVector(dx: 0.99, dy: 0.5)).tap()
        titleField.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: originalTitle.count) + revisedTitle)
        personal.navigationBars.buttons["Save"].tap()
        XCTAssertTrue(singleScroll.waitForExistence(timeout: 5))
        XCTAssertTrue(personal.buttons["blueprint.preview.mainEvent"].label.contains(revisedTitle),
                      "Saving an edit should update the event shown in the Yours overview.")
        personal.buttons["blueprint.preview.mainEvent"].tap()
        XCTAssertTrue(titleField.waitForExistence(timeout: 5))
        XCTAssertEqual(titleField.value as? String, revisedTitle,
                       "Reopening the editor should retain the title that was saved.")
        personal.navigationBars.buttons["Cancel"].tap()
        XCTAssertTrue(singleScroll.waitForExistence(timeout: 5))
        XCTAssertTrue(singleScroll.waitForExistence(timeout: 8))
        let childEvent = personal.buttons["blueprint.preview.event.venue_visit"]
        for _ in 0..<5 where !childEvent.isHittable { singleScroll.swipeUp() }
        XCTAssertTrue(childEvent.isHittable)
        childEvent.tap()
        XCTAssertTrue(personal.navigationBars.staticTexts["Edit Event"].waitForExistence(timeout: 5),
                      "Tapping a child event should open its native editor directly.")
        let childTitle = personal.textFields.firstMatch
        XCTAssertTrue(childTitle.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(personal.navigationBars["Edit Event"].frame.minY, previewNavigationTop,
                             "Child event editing should also use a native sheet.")
        let originalChildTitle = childTitle.value as? String ?? ""
        XCTAssertFalse(originalChildTitle.isEmpty)
        let savedChildTitle = "Revised venue visit"
        childTitle.tap()
        childTitle.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: originalChildTitle.count) + savedChildTitle)
        personal.navigationBars.buttons["Save"].tap()
        XCTAssertTrue(singleScroll.waitForExistence(timeout: 5))
        XCTAssertTrue(childEvent.label.contains(savedChildTitle), "Saving a child event should update the overview.")
        childEvent.tap()
        XCTAssertTrue(childTitle.waitForExistence(timeout: 5))
        XCTAssertEqual(childTitle.value as? String, savedChildTitle)
        childTitle.tap()
        childTitle.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: savedChildTitle.count) + "Discard child title")
        personal.navigationBars.buttons["Cancel"].tap()
        XCTAssertTrue(singleScroll.waitForExistence(timeout: 5))
        XCTAssertTrue(childEvent.label.contains(savedChildTitle), "Cancel should retain the last saved child title.")
        for _ in 0..<5 where !venueIdea.isHittable { singleScroll.swipeUp() }
        XCTAssertTrue(venueIdea.isHittable)
        venueIdea.tap()
        XCTAssertTrue(personal.navigationBars.staticTexts["Edit Idea"].waitForExistence(timeout: 5),
                      "Tapping an idea should open its native editor directly.")
        let ideaTitle = personal.textFields.firstMatch
        XCTAssertTrue(ideaTitle.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(personal.navigationBars["Edit Idea"].frame.minY, previewNavigationTop,
                             "Idea editing should use a native sheet.")
        let originalIdeaTitle = ideaTitle.value as? String ?? ""
        XCTAssertFalse(originalIdeaTitle.isEmpty)
        let savedIdeaTitle = "A garden venue"
        ideaTitle.tap()
        ideaTitle.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: originalIdeaTitle.count) + savedIdeaTitle)
        personal.navigationBars.buttons["Save"].tap()
        XCTAssertTrue(singleScroll.waitForExistence(timeout: 5))
        XCTAssertTrue(venueIdea.label.contains(savedIdeaTitle), "Saving an idea should update the overview.")
        venueIdea.tap()
        XCTAssertTrue(ideaTitle.waitForExistence(timeout: 5))
        XCTAssertEqual(ideaTitle.value as? String, savedIdeaTitle)
        ideaTitle.tap()
        ideaTitle.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: savedIdeaTitle.count) + "Discard idea title")
        personal.navigationBars.buttons["Cancel"].tap()
        XCTAssertTrue(singleScroll.waitForExistence(timeout: 5))
        XCTAssertTrue(venueIdea.label.contains(savedIdeaTitle), "Cancel should retain the last saved idea title.")
        XCTAssertFalse(personal.buttons["blueprint.preview.like"].exists)
        XCTAssertFalse(personal.buttons["blueprint.preview.bookmark"].exists)
        XCTAssertFalse(personal.buttons["blueprint.preview.more"].exists)
        attach(personal, name: "Personal preview editing controls")
        personal.terminate()
    }

    @MainActor
    func testYoursCreateEventsOpensDateConfirmationAndReturnsToOverview() throws {
        continueAfterFailure = false
        let app = launch(context: "personal", appearance: "dark", setupFixture: true)
        defer { app.terminate() }
        _ = openLibraryCollection("Yours", in: app)
        let card = app.buttons["blueprint.library.card.personal.51000000-0000-4000-8000-000000000001"]
        XCTAssertTrue(card.waitForExistence(timeout: 8))
        card.tap()
        let overview = app.scrollViews["blueprint.preview.singleScroll"]
        XCTAssertTrue(overview.waitForExistence(timeout: 12))
        let createEvents = app.buttons["blueprint.preview.createEvents"]
        XCTAssertTrue(createEvents.waitForExistence(timeout: 5))
        let toolbarCreateEvents = app.toolbars.buttons["blueprint.preview.createEvents"]
        XCTAssertTrue(toolbarCreateEvents.exists,
                      "Create Events should use the native bottom toolbar.")
        XCTAssertTrue(toolbarCreateEvents.isHittable)
        XCTAssertGreaterThan(toolbarCreateEvents.frame.midY, app.windows.firstMatch.frame.midY)
        toolbarCreateEvents.tap()
        let mainDate = identified("blueprint.setup.mainDate", in: app)
        XCTAssertTrue(mainDate.waitForExistence(timeout: 12), "Create Events should open the real date-confirmation setup.")
        let create = app.buttons["blueprint.setup.primaryAction"]
        XCTAssertTrue(create.waitForExistence(timeout: 5))
        XCTAssertEqual(create.label, "Create Events", "Yours must enter direct event creation on its first presentation.")
        XCTAssertTrue(app.navigationBars["Create Events"].exists)
        XCTAssertFalse(create.isEnabled, "Unconfirmed dates must not create events.")
        attach(app, name: "Yours Create Events — date confirmation")
        app.navigationBars.buttons["Close"].tap()
        XCTAssertTrue(overview.waitForExistence(timeout: 8), "Cancelling setup should retain the personal overview.")
        let returnedCreateEvents = app.toolbars.buttons["blueprint.preview.createEvents"]
        XCTAssertTrue(returnedCreateEvents.isHittable)
        XCTAssertGreaterThan(returnedCreateEvents.frame.midY, app.windows.firstMatch.frame.midY)
    }

    @MainActor
    func testYoursOverviewKeepsCreateEventsInOneScrollAndBackReturnsToLibrary() throws {
        continueAfterFailure = false
        for appearance in ["light", "dark"] {
            let app = launch(context: "personal", appearance: appearance)
            defer { app.terminate() }
            _ = openLibraryCollection("Yours", in: app)
            let card = app.buttons["blueprint.library.card.personal.51000000-0000-4000-8000-000000000001"]
            XCTAssertTrue(card.waitForExistence(timeout: 8))
            card.tap()

            let scroll = app.scrollViews["blueprint.preview.singleScroll"]
            XCTAssertTrue(scroll.waitForExistence(timeout: 12), "Yours should present its overview and content in one scroll.")
            XCTAssertEqual(app.buttons["blueprint.preview.close"].label, "Back")
            let createEvents = app.buttons["blueprint.preview.createEvents"]
            XCTAssertTrue(createEvents.waitForExistence(timeout: 5))
            XCTAssertEqual(createEvents.label, "Use")
            XCTAssertTrue(createEvents.isHittable)
            let bottomCreateEvents = app.toolbars.buttons["blueprint.preview.createEvents"]
            XCTAssertTrue(bottomCreateEvents.exists)
            XCTAssertTrue(bottomCreateEvents.isHittable)
            XCTAssertTrue(app.windows.firstMatch.frame.contains(bottomCreateEvents.frame),
                          "The native bottom Create Events control must be fully visible.")
            XCTAssertGreaterThan(bottomCreateEvents.frame.midY, app.windows.firstMatch.frame.midY)
            XCTAssertFalse(app.tabBars.buttons["Home"].exists)
            XCTAssertFalse(app.tabBars.buttons["Ideas"].exists)
            XCTAssertFalse(app.tabBars.buttons["Decide"].exists)

            let mainEvent = app.buttons["blueprint.preview.mainEvent"]
            for _ in 0..<5 where !mainEvent.isHittable { scroll.swipeUp() }
            XCTAssertTrue(mainEvent.isHittable, "The main event remains reachable by scrolling the overview.")
            let idea = app.buttons["blueprint.preview.idea.venue"]
            for _ in 0..<5 where !idea.isHittable { scroll.swipeUp() }
            XCTAssertTrue(idea.isHittable, "Ideas remain reachable in the same overview scroll.")
            let attire = app.buttons["blueprint.preview.idea.attire"]
            XCTAssertTrue(attire.exists)
            XCTAssertNotEqual(idea.frame.minX, attire.frame.minX,
                              "The first two Yours ideas should occupy separate columns at regular text size.")
            attach(app, name: "Yours single scroll and Create Events — \(appearance)")

            XCTAssertGreaterThan(scroll.frame.height, app.windows.firstMatch.frame.height * 0.8,
                                 "An authored Blueprint should fill the screen like Liked previews.")
            app.buttons["blueprint.preview.close"].tap()
            XCTAssertTrue(scroll.waitForNonExistence(timeout: 8), "Back should close the authored preview.")
            XCTAssertTrue(card.waitForExistence(timeout: 8), "Back should return to the Yours collection.")
            XCTAssertTrue(card.isHittable)
        }
    }

    @MainActor
    func testDiscoveryUsesOneReadOnlyScrollForEventsAndIdeasAtStandardSizeInBothAppearances() throws {
        continueAfterFailure = false
        for appearance in ["light", "dark"] {
            let app = launch(context: "discovery", appearance: appearance)
            defer { app.terminate() }

            openDiscoveryPreview(in: app)
            XCTAssertTrue(app.buttons["blueprint.preview.close"].waitForExistence(timeout: 12))
            let scroll = app.scrollViews["blueprint.preview.publicScroll"]
            XCTAssertTrue(scroll.waitForExistence(timeout: 5), "Public previews should use one vertical scroll.")
            XCTAssertFalse(app.buttons["blueprint.preview.addEvent"].exists)
            XCTAssertFalse(app.buttons["blueprint.preview.addIdea"].exists)
            XCTAssertFalse(app.buttons["Filter ideas"].exists)
            XCTAssertFalse(app.segmentedControls["blueprint.library.collections"].exists)

            let event = app.buttons["blueprint.preview.event.venue_visit"]
            for _ in 0..<5 where !event.isHittable { scroll.swipeUp() }
            XCTAssertTrue(event.waitForExistence(timeout: 5), "Included events should remain in the same public scroll.")
            XCTAssertTrue(event.isHittable)
            attach(app, name: "Public Blueprint — \(appearance) — standard size")
            event.tap()
            XCTAssertTrue(identified("blueprint.preview.eventDetail", in: app).waitForExistence(timeout: 8))
            XCTAssertFalse(app.buttons["blueprint.preview.addEvent"].exists)
            let editButton = app.buttons.matching(NSPredicate(format: "label ==[c] %@", "Edit")).firstMatch
            XCTAssertFalse(editButton.waitForExistence(timeout: 2), "Public event detail must not offer Edit.")
            app.navigationBars.buttons.element(boundBy: 0).tap()

            for _ in 0..<6 where !app.buttons["blueprint.preview.idea.venue"].isHittable { scroll.swipeUp() }
            let idea = app.buttons["blueprint.preview.idea.venue"]
            XCTAssertTrue(idea.waitForExistence(timeout: 5), "Ideas should follow events in the same public scroll.")
            XCTAssertTrue(idea.isHittable, "The idea card should remain reachable in the standard layout.")
            idea.tap()
            XCTAssertTrue(identified("blueprint.preview.ideaDetail", in: app).waitForExistence(timeout: 8))
            XCTAssertTrue(app.staticTexts["Venue"].exists, "The idea detail should show the authored idea.")
            XCTAssertFalse(app.buttons["blueprint.preview.addIdea"].exists)
            XCTAssertFalse(editButton.waitForExistence(timeout: 2), "Public idea detail must not offer Edit.")
            attach(app, name: "Public idea detail — \(appearance) — standard size")
        }
    }

    @MainActor
    func testPublicIdeasKeepIndependentMasonryColumnsInBothAppearances() throws {
        continueAfterFailure = false
        for appearance in ["light", "dark"] {
            let app = launch(context: "discovery", appearance: appearance)
            defer { app.terminate() }
            openDiscoveryPreview(in: app)
            let scroll = app.scrollViews["blueprint.preview.publicScroll"]
            XCTAssertTrue(scroll.waitForExistence(timeout: 12))
            let venue = app.buttons["blueprint.preview.idea.venue"]
            let attire = app.buttons["blueprint.preview.idea.attire"]
            let food = app.buttons["blueprint.preview.idea.food"]
            for _ in 0..<6 where !venue.isHittable { scroll.swipeUp() }
            XCTAssertTrue(venue.waitForExistence(timeout: 5))
            XCTAssertTrue(attire.exists)
            XCTAssertTrue(food.exists)
            XCTAssertGreaterThan(abs(venue.frame.height - attire.frame.height), 10,
                                 "Different idea artwork ratios should retain their natural card heights.")
            XCTAssertEqual(venue.frame.minY, attire.frame.minY, accuracy: 2)
            XCTAssertEqual(food.frame.minX, venue.frame.minX, accuracy: 2)
            // Accessibility bounds can differ slightly from SwiftUI's layout
            // measurements; the gap must still follow the shorter column.
            XCTAssertEqual(food.frame.minY, venue.frame.maxY + 12, accuracy: 4,
                           "The next card fills the shorter column without waiting for a shared grid row.")
            XCTAssertLessThan(food.frame.minY, attire.frame.maxY,
                              "The shorter column should advance before the taller first card finishes.")
            attach(app, name: "Public ideas masonry — \(appearance)")
            food.tap()
            XCTAssertTrue(identified("blueprint.preview.ideaDetail", in: app).waitForExistence(timeout: 8))
        }
    }

    @MainActor
    func testExploreBackButtonAndSwipeReturnToFeedInBothAppearances() throws {
        continueAfterFailure = false
        for appearance in ["light", "dark"] {
            let app = launch(context: "discovery", appearance: appearance)
            defer { app.terminate() }
            openDiscoveryPreview(in: app)
            let back = app.buttons["blueprint.preview.close"]
            XCTAssertTrue(back.waitForExistence(timeout: 12))
            XCTAssertEqual(back.label, "Back")
            attach(app, name: "Explore preview Back arrow — \(appearance)")
            back.tap()
            XCTAssertTrue(back.waitForNonExistence(timeout: 8))
            let card = app.buttons["blueprint.catalog.card.wedding-visual-1"]
            XCTAssertTrue(card.waitForExistence(timeout: 8))
            XCTAssertTrue(card.isHittable)

            card.tap()
            XCTAssertTrue(back.waitForExistence(timeout: 8))
            app.scrollViews["blueprint.preview.publicScroll"].swipeUp()
            XCTAssertTrue(back.exists, "Reading the preview should not dismiss it.")
            swipeBack(in: app)
            XCTAssertTrue(back.waitForNonExistence(timeout: 8), "The native gesture should dismiss the preview.")
            XCTAssertTrue(card.waitForExistence(timeout: 8))
            XCTAssertTrue(card.isHittable)
            card.tap()
            XCTAssertTrue(back.waitForExistence(timeout: 8), "A dismissed preview should remain reopenable.")
            back.tap()
        }
    }

    @MainActor
    func testExploreNestedDetailSwipeReturnsOneLevelBeforeLeavingPreview() throws {
        continueAfterFailure = false
        let app = launch(context: "discovery", appearance: "light")
        defer { app.terminate() }
        openDiscoveryPreview(in: app)
        let mainEvent = app.buttons["blueprint.preview.mainEvent"]
        XCTAssertTrue(mainEvent.waitForExistence(timeout: 12))
        mainEvent.tap()
        let detail = identified("blueprint.preview.eventDetail", in: app)
        XCTAssertTrue(detail.waitForExistence(timeout: 8))
        swipeBack(in: app)
        XCTAssertTrue(detail.waitForNonExistence(timeout: 8))
        XCTAssertTrue(mainEvent.waitForExistence(timeout: 8), "A detail swipe must return to the Blueprint first.")
        swipeBack(in: app)
        XCTAssertTrue(app.buttons["blueprint.preview.close"].waitForNonExistence(timeout: 8))
        XCTAssertTrue(app.buttons["blueprint.catalog.card.wedding-visual-1"].waitForExistence(timeout: 8))
    }

    @MainActor
    func testExploreSwipeReturnRestoresSearchQuery() throws {
        continueAfterFailure = false
        let app = launch(context: "discovery", appearance: "dark")
        defer { app.terminate() }
        let explore = app.tabBars.buttons["Explore"]
        XCTAssertTrue(explore.waitForExistence(timeout: 12))
        explore.tap()
        let search = app.searchFields["Search blueprints"]
        XCTAssertTrue(search.waitForExistence(timeout: 8))
        search.tap()
        search.typeText("wedding\n")
        let card = app.buttons["blueprint.catalog.card.wedding-visual-1"]
        XCTAssertTrue(card.waitForExistence(timeout: 8))
        card.tap()
        XCTAssertTrue(app.buttons["blueprint.preview.close"].waitForExistence(timeout: 12))
        swipeBack(in: app)
        XCTAssertTrue(app.buttons["blueprint.preview.close"].waitForNonExistence(timeout: 8))
        XCTAssertTrue(search.waitForExistence(timeout: 8))
        XCTAssertEqual(search.value as? String, "wedding")
        XCTAssertTrue(card.waitForExistence(timeout: 8))
    }

    @MainActor
    func testPersonalEditorSaveAndCancelKeepsAuthoredChanges() throws {
        continueAfterFailure = false
        for appearance in ["light", "dark"] {
            let app = launch(context: "personal", appearance: appearance)
            defer { app.terminate() }
            _ = openLibraryCollection("Yours", in: app)
            let card = app.buttons["blueprint.library.card.personal.51000000-0000-4000-8000-000000000001"]
            XCTAssertTrue(card.waitForExistence(timeout: 8))
            card.tap()
            let singleScroll = app.scrollViews["blueprint.preview.singleScroll"]
            XCTAssertTrue(singleScroll.waitForExistence(timeout: 12))
            let mainEvent = app.buttons["blueprint.preview.mainEvent"]
            XCTAssertTrue(mainEvent.waitForExistence(timeout: 5))
            let previewNavigationTop = app.navigationBars.firstMatch.frame.minY
            mainEvent.tap()
            XCTAssertTrue(app.navigationBars.staticTexts["Edit Event"].waitForExistence(timeout: 5))
            XCTAssertGreaterThan(app.navigationBars["Edit Event"].frame.minY, previewNavigationTop,
                                 "The editor should remain a native sheet in each appearance.")
            let title = app.textFields.firstMatch
            XCTAssertTrue(title.waitForExistence(timeout: 5))
            let original = title.value as? String ?? ""
            XCTAssertFalse(original.isEmpty)
            let saved = "Saved celebration title"
            title.tap()
            title.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: original.count) + saved)
            app.navigationBars.buttons["Save"].tap()
            XCTAssertTrue(singleScroll.waitForExistence(timeout: 8))
            XCTAssertTrue(mainEvent.label.contains(saved), "Save should persist the authored title in the Yours preview.")

            mainEvent.tap()
            XCTAssertTrue(title.waitForExistence(timeout: 5))
            XCTAssertEqual(title.value as? String, saved)
            attach(app, name: "Yours saved main event editor — \(appearance)")
            title.tap()
            title.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: saved.count) + "Discard this title")
            app.navigationBars.buttons["Cancel"].tap()
            XCTAssertTrue(singleScroll.waitForExistence(timeout: 8))
            XCTAssertTrue(mainEvent.label.contains(saved), "Cancel should discard the editor's unsaved change.")
            attach(app, name: "Yours main event overview — \(appearance)")

            let addMenu = app.buttons["blueprint.preview.add"]
            XCTAssertTrue(addMenu.waitForExistence(timeout: 5), "Yours keeps Add Event and Add Idea in the native toolbar menu.")
            let bottomAddMenu = app.toolbars.buttons["blueprint.preview.add"]
            XCTAssertTrue(bottomAddMenu.exists)
            XCTAssertTrue(bottomAddMenu.isHittable)
            XCTAssertGreaterThan(bottomAddMenu.frame.midY, app.windows.firstMatch.frame.midY)
            bottomAddMenu.tap()
            let addEvent = app.buttons["blueprint.preview.addEvent"]
            XCTAssertTrue(addEvent.waitForExistence(timeout: 5))
            addEvent.tap()
            XCTAssertTrue(app.navigationBars.staticTexts["Add Event"].waitForExistence(timeout: 5),
                          "Add Event should open the existing native event form.")
            app.navigationBars.buttons["Cancel"].tap()
            XCTAssertTrue(singleScroll.waitForExistence(timeout: 8))

            addMenu.tap()
            let addIdea = app.buttons["blueprint.preview.addIdea"]
            XCTAssertTrue(addIdea.waitForExistence(timeout: 5))
            addIdea.tap()
            XCTAssertTrue(app.navigationBars.staticTexts["Add Idea"].waitForExistence(timeout: 5),
                          "Add Idea should open the existing native idea form.")
            app.navigationBars.buttons["Cancel"].tap()
            XCTAssertTrue(singleScroll.waitForExistence(timeout: 8))
            XCTAssertTrue(app.buttons["blueprint.preview.close"].exists)
            XCTAssertTrue(app.buttons["blueprint.preview.createEvents"].exists)
        }
    }

    @MainActor
    private func swipeBack(in app: XCUIApplication) {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.55))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.90, dy: 0.55))
        start.press(forDuration: 0.05, thenDragTo: end)
    }

    @MainActor
    private func launch(context: String, appearance: String,
                        setupFixture: Bool = false, retryFirstInstall: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += [
            "-DisableProductionFlowSimulation", "-SkipAuthentication",
            "-SeedDevelopmentData", "-UseEphemeralDataStore",
            "-BlueprintSearchVisualFixture",
            "-BlueprintPreviewActionsVisualFixture", "-BlueprintPreviewFixtureContext", context,
            "-AppleLanguages", "(en)", "-appAppearance", appearance,
        ]
        if setupFixture { app.launchArguments.append("-BlueprintSetupDateConfirmationFixture") }
        if retryFirstInstall { app.launchArguments.append("-BlueprintSetupFixtureRetryOnce") }
        app.launch()
        return app
    }

    @MainActor
    private func openDiscoveryPreview(in app: XCUIApplication) {
        let explore = app.tabBars.buttons["Explore"]
        XCTAssertTrue(explore.waitForExistence(timeout: 12))
        explore.tap()
        let firstCard = app.buttons["blueprint.catalog.card.wedding-visual-1"]
        XCTAssertTrue(firstCard.waitForExistence(timeout: 8))
        firstCard.tap()
    }

    @MainActor
    private func openLibraryCollection(_ collection: String, in app: XCUIApplication) -> XCUIElement {
        let library = app.tabBars.buttons["Blueprints"]
        XCTAssertTrue(library.waitForExistence(timeout: 8))
        library.tap()
        let picker = app.segmentedControls["blueprint.library.collections"]
        XCTAssertTrue(picker.waitForExistence(timeout: 8))
        picker.buttons[collection].tap()
        return picker
    }

    @MainActor
    private func attach(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    private func waitForLabelChange(of element: XCUIElement, from oldLabel: String) -> Bool {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label != %@", oldLabel), object: element
        )
        return XCTWaiter.wait(for: [expectation], timeout: 3) == .completed
    }

    @MainActor
    private func identified(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }
}
