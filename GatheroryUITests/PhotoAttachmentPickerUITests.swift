import XCTest

final class PhotoAttachmentPickerUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testMainEventPhotoPickerOpensCancelsAndReopensWithoutDiscardingDraft() throws {
        for appearance in ["Light", "Dark"] {
            let app = fixtureApplication(appearance: appearance)
            app.launch()
            addFailureDiagnostics(for: app, context: "Photo picker — \(appearance)")

            let workspace = app.buttons.matching(
                NSPredicate(format: "label CONTAINS %@", "Maya & Theo")
            ).firstMatch
            XCTAssertTrue(workspace.waitForExistence(timeout: 8))
            workspace.tap()

            HomeLayoutUITestSupport.select("Cards", in: app)

            let mainEvent = app.buttons["home.event.main"]
            XCTAssertTrue(mainEvent.waitForExistence(timeout: 5))
            mainEvent.tap()
            XCTAssertTrue(app.navigationBars["Invitation"].waitForExistence(timeout: 5))
            let eventActions = app.descendants(matching: .any)
                .matching(identifier: "invitation.actions").firstMatch
            XCTAssertTrue(eventActions.waitForExistence(timeout: 5))
            eventActions.tap()
            let editEvent = app.buttons["Edit Event"]
            XCTAssertTrue(editEvent.waitForExistence(timeout: 3))
            editEvent.tap()
            XCTAssertTrue(app.navigationBars["Edit Event"].waitForExistence(timeout: 5))

            let titleField = app.textFields["event.editor.title"]
            XCTAssertTrue(titleField.waitForExistence(timeout: 3))
            let originalTitle = titleField.value as? String ?? ""
            titleField.tap()
            titleField.typeText(" Photo Picker Draft")
            let editedTitle = titleField.value as? String ?? ""
            XCTAssertFalse(editedTitle.isEmpty)
            XCTAssertNotEqual(editedTitle, originalTitle, "The test must create an unsaved event edit before opening Photos.")

            // Keep the draft but clear the keyboard so it cannot cover the
            // image-card button at the bottom of this form on Dark appearance.
            let keyboardDone = app.buttons["Done"]
            XCTAssertTrue(keyboardDone.waitForExistence(timeout: 3))
            keyboardDone.tap()
            XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))

            let openImagePicker = app.buttons["photoAttachmentPicker.open"]
            for _ in 0..<8 where !openImagePicker.isHittable {
                app.swipeUp()
            }
            XCTAssertTrue(openImagePicker.isHittable)
            openImagePicker.tap()
            XCTAssertTrue(app.navigationBars["Choose Image"].waitForExistence(timeout: 5))

            let chooseFromPhotos = app.buttons["photoAttachmentPicker.chooseFromPhotos"]
            XCTAssertTrue(chooseFromPhotos.waitForExistence(timeout: 3))
            for _ in 0..<4 where !chooseFromPhotos.isHittable {
                app.swipeUp()
            }
            XCTAssertTrue(chooseFromPhotos.isHittable)

            for _ in 0..<2 {
                chooseFromPhotos.tap()

                // PhotosPicker briefly exposes PUPickerUnavailableView while the native
                // library loads. Wait for the actual picker navigation bar before looking
                // for its Cancel button; the app's own source-sheet controls may also be
                // present in the accessibility tree during that handoff.
                let photosNavigationBar = app.navigationBars["Photos"]
                let hasPhotosPicker = photosNavigationBar.waitForExistence(timeout: 12)
                XCTAssertTrue(
                    hasPhotosPicker,
                    "The native Photos picker should finish presenting. Accessibility tree: \(app.debugDescription)"
                )
                XCTAssertTrue(photosNavigationBar.isHittable)

                let accessibilitySnapshot = app.debugDescription
                print("PHOTO_PICKER_BEFORE_DISMISS_\(appearance)\n\(accessibilitySnapshot)")
                let accessibilityAttachment = XCTAttachment(
                    data: Data(accessibilitySnapshot.utf8),
                    uniformTypeIdentifier: "public.plain-text"
                )
                accessibilityAttachment.name = "Photos picker accessibility tree before dismissal — \(appearance)"
                accessibilityAttachment.lifetime = .keepAlways
                add(accessibilityAttachment)
                let screenshotAttachment = XCTAttachment(screenshot: app.screenshot())
                screenshotAttachment.name = "Photos picker before dismissal — \(appearance)"
                screenshotAttachment.lifetime = .keepAlways
                add(screenshotAttachment)

                let nativeCancelButton = photosNavigationBar.buttons["Cancel"]
                XCTAssertTrue(
                    nativeCancelButton.waitForExistence(timeout: 3),
                    "The Photos navigation bar should provide its native Cancel button. Accessibility tree: \(app.debugDescription)"
                )
                XCTAssertTrue(nativeCancelButton.isHittable)
                nativeCancelButton.tap()

                let sourceButtonReturned = NSPredicate(format: "exists == true AND isHittable == true")
                let sourceButtonExpectation = XCTNSPredicateExpectation(
                    predicate: sourceButtonReturned,
                    object: chooseFromPhotos
                )
                XCTAssertEqual(XCTWaiter.wait(for: [sourceButtonExpectation], timeout: 8), .completed)
                XCTAssertTrue(
                    chooseFromPhotos.isHittable,
                    "Cancelling Photos should return to image choices without closing the edit sheets."
                )
            }

            app.buttons["photoAttachmentPicker.close"].tap()
            XCTAssertTrue(app.navigationBars["Edit Event"].waitForExistence(timeout: 5))
            XCTAssertEqual(titleField.value as? String, editedTitle)
            app.terminate()
        }
    }

    @MainActor
    private func fixtureApplication(appearance: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += [
            "-DisableProductionFlowSimulation",
            "-SkipAuthentication",
            "-SeedDevelopmentData",
            "-UseEphemeralDataStore",
            "-UseProductionOnboarding",
            "-AppleLanguages", "(en)",
            "-AppleInterfaceStyle", appearance,
            "-appAppearance", appearance.lowercased()
        ]
        return app
    }

    @MainActor
    private func addFailureDiagnostics(for app: XCUIApplication, context: String) {
        addTeardownBlock { [weak self] in
            defer { app.terminate() }
            guard let self, self.testRun?.hasSucceeded == false,
                  app.state == .runningForeground else { return }
            let snapshot = app.debugDescription
            print("UI_FAILURE_\(context)\n\(snapshot)")
            let accessibilityAttachment = XCTAttachment(
                data: Data(snapshot.utf8),
                uniformTypeIdentifier: "public.plain-text"
            )
            accessibilityAttachment.name = "Accessibility tree — \(context)"
            accessibilityAttachment.lifetime = .keepAlways
            self.add(accessibilityAttachment)

            let screenshotAttachment = XCTAttachment(screenshot: app.screenshot())
            screenshotAttachment.name = "Failure screen — \(context)"
            screenshotAttachment.lifetime = .keepAlways
            self.add(screenshotAttachment)
        }
    }
}
