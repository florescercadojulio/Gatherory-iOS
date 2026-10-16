import XCTest
import UIKit

final class SharedAlbumUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testIPadCollageUsesMoreColumns() throws {
        guard UIDevice.current.userInterfaceIdiom == .pad else {
            throw XCTSkip("Adaptive multi-column geometry is verified on the iPad destination.")
        }
        let originalOrientation = XCUIDevice.shared.orientation
        XCUIDevice.shared.orientation = .portrait
        defer { XCUIDevice.shared.orientation = originalOrientation }
        let app = fixtureApplication(withPhotos: true)
        app.launch()
        defer { app.terminate() }
        openMainEvent(in: app)
        let openAlbum = app.buttons["View Album"]
        reveal(openAlbum, in: app)
        openAlbum.tap()
        XCTAssertTrue(app.buttons["album.close"].waitForExistence(timeout: 5))
        let gallery = app.scrollViews.containing(.staticText, identifier: "album.hint").firstMatch
        let photos = gallery.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "album.photo."))
        XCTAssertTrue(photos.firstMatch.waitForExistence(timeout: 5))
        let firstCards = Array(photos.allElementsBoundByIndex.prefix(4))
        XCTAssertEqual(firstCards.count, 4)
        XCTAssertTrue(firstCards.allSatisfy { $0.frame.width > 0 && $0.frame.height > 0 })
        let columnCenters = Set(firstCards.map { Int(($0.frame.midX / 4).rounded()) })
        XCTAssertGreaterThanOrEqual(columnCenters.count, 3, "A full-width iPad collage should show more than the phone's two columns.")
        attachScreenshot(of: app, named: "Album gallery — iPad portrait adaptive columns")
    }

    @MainActor
    func testPreviewPhotoOpensViewerAndCloseReturnsThroughAlbumToEvent() {
        let app = fixtureApplication(withPhotos: true)
        app.launch()
        defer { app.terminate() }
        openMainEvent(in: app)
        let preview = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "album.photo.")).firstMatch
        reveal(preview, in: app)
        preview.tap()
        XCTAssertTrue(app.buttons["album.viewer.close"].waitForExistence(timeout: 5))
        app.buttons["album.viewer.close"].tap()
        XCTAssertTrue(app.buttons["album.select"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["album.viewer.close"].waitForNonExistence(timeout: 3), "Closing the viewer must not replay the original preview navigation.")
        app.buttons["album.close"].tap()
        XCTAssertTrue(app.buttons["Event Actions"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["View Album"].exists)
    }

    @MainActor
    func testAlbumPreviewViewerAndSelectionInLightDarkAndLargeText() throws {
        for (appearance, largeText) in [("Light", false), ("Dark", false), ("Dark", true)] {
            let app = fixtureApplication(withPhotos: true, appearance: appearance, largeText: largeText)
            app.launch()
            defer { app.terminate() }
            openMainEvent(in: app)

            let openAlbum = app.buttons["View Album"]
            reveal(openAlbum, in: app)
            attachScreenshot(of: app, named: "Album event preview — \(appearance)\(largeText ? " — Large Text" : "")")
            openAlbum.tap()
            XCTAssertTrue(app.buttons["album.close"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.buttons["album.select"].isHittable)
            attachScreenshot(of: app, named: "Album gallery — \(appearance)\(largeText ? " — Large Text" : "")")

            let gallery = app.scrollViews.containing(.staticText, identifier: "album.hint").firstMatch
            let photos = gallery.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "album.photo."))
            XCTAssertTrue(photos.firstMatch.waitForExistence(timeout: 5))
            let firstPhotoID = photos.allElementsBoundByIndex.first(where: \.isHittable)?.identifier
            let photoID = try XCTUnwrap(firstPhotoID, "The collage should expose a tappable image card.")
            XCTAssertTrue(gallery.buttons[photoID].label.hasPrefix("Photo added by "))
            gallery.buttons[photoID].tap()
            XCTAssertTrue(app.buttons["album.viewer.close"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.buttons["album.viewer.save"].isHittable)
            XCTAssertTrue(app.buttons["album.viewer.actions"].isHittable)
            attachScreenshot(of: app, named: "Album photo viewer — \(appearance)\(largeText ? " — Large Text" : "")")
            app.buttons["album.viewer.close"].tap()
            XCTAssertTrue(app.buttons["album.select"].waitForExistence(timeout: 5))
            app.buttons["album.select"].tap()

            let save = app.buttons["album.saveSelection"]
            XCTAssertTrue(save.waitForExistence(timeout: 3))
            XCTAssertFalse(save.isEnabled, "Saving requires at least one selected photo.")
            let selectablePhoto = gallery.buttons[photoID]
            reveal(selectablePhoto, in: app)
            selectablePhoto.tap()
            XCTAssertEqual(selectablePhoto.value as? String, "Selected")
            XCTAssertTrue(save.isEnabled)
            XCTAssertTrue(save.label.contains("(1)"))
            XCTAssertFalse(app.buttons["album.viewer.close"].exists, "Selecting a card must keep the collage open.")

            let secondPhoto = photos.allElementsBoundByIndex.first { $0.identifier != photoID && $0.isHittable }
            let second = try XCTUnwrap(secondPhoto, "Two-column collage should expose a second card.")
            second.tap()
            XCTAssertEqual(second.value as? String, "Selected")
            XCTAssertTrue(save.label.contains("(2)"))
            let selectAll = app.buttons["album.selectAll"]
            XCTAssertTrue(selectAll.isHittable)
            selectAll.tap()
            XCTAssertEqual(selectAll.label, "Deselect All")
            XCTAssertTrue(save.label.contains("(4)"))
            attachScreenshot(of: app, named: "Album multiple selection — \(appearance)\(largeText ? " — Large Text" : "")")
            selectAll.tap()
            XCTAssertEqual(selectAll.label, "Select All")
            XCTAssertFalse(save.isEnabled)
            XCTAssertEqual(selectablePhoto.value as? String, "Not selected")

            // Exiting selection clears its state before the next selection session.
            selectablePhoto.tap()
            app.buttons["album.select"].tap()
            XCTAssertFalse(save.exists)
            app.buttons["album.select"].tap()
            XCTAssertFalse(save.isEnabled)
            app.buttons["album.close"].tap()
            XCTAssertTrue(openAlbum.waitForExistence(timeout: 5))
        }
    }

    @MainActor
    func testOrdinaryDevelopmentFixtureKeepsAlbumEmpty() {
        let app = fixtureApplication(withPhotos: false)
        app.launch()
        defer { app.terminate() }
        openMainEvent(in: app)
        let empty = app.staticTexts["Photos shared during the event will gather here."]
        reveal(empty, in: app)
        XCTAssertFalse(app.buttons["View Album"].exists)
        reveal(app.buttons["Add Photos"], in: app)
    }

    @MainActor
    private func fixtureApplication(withPhotos: Bool, appearance: String = "Light", largeText: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += [
            "-DisableProductionFlowSimulation", "-SkipAuthentication", "-SeedDevelopmentData",
            "-UseEphemeralDataStore", "-UseProductionOnboarding", "-AppleLanguages", "(en)",
            "-AppleInterfaceStyle", appearance, "-appAppearance", appearance.lowercased()
        ]
        if withPhotos { app.launchArguments += ["-SeedSharedAlbumUITestPhotos"] }
        if largeText { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        return app
    }

    @MainActor
    private func openMainEvent(in app: XCUIApplication) {
        let workspace = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Maya & Theo")).firstMatch
        XCTAssertTrue(workspace.waitForExistence(timeout: 8))
        reveal(workspace, in: app)
        workspace.tap()
        let event = app.buttons["home.event.main"]
        XCTAssertTrue(event.waitForExistence(timeout: 5))
        event.tap()
        XCTAssertTrue(app.buttons["Event Actions"].waitForExistence(timeout: 5))
    }

    @MainActor
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<16 where !element.isHittable { app.swipeUp() }
        XCTAssertTrue(element.isHittable, "Expected album control should be reachable by scrolling.")
    }

    @MainActor
    private func attachScreenshot(of app: XCUIApplication, named name: String) {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
