import XCTest

final class OfflineConnectionUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testOfflineAccountStatusKeepsSavedLibraryVisibleInLightAndDark() throws {
        for appearance in ["Light", "Dark"] {
            let app = fixtureApplication(appearance: appearance, connection: "Offline")
            app.launch()

            let savedEvent = app.buttons.matching(
                NSPredicate(format: "label CONTAINS %@", "Alex & Jordan")
            ).firstMatch
            XCTAssertTrue(savedEvent.waitForExistence(timeout: 8),
                          "Saved event content should remain available in the offline library.")
            XCTAssertFalse(app.staticTexts["Showing saved content. Changes will sync when you reconnect."].exists,
                           "A large offline banner should not displace saved content.")
            XCTAssertFalse(app.buttons["offline-account.retry"].exists)
            XCTAssertFalse(app.buttons["workspace-library.retry"].exists)
            XCTAssertFalse(app.buttons["Try Again"].exists,
                           "An empty-state guest retry should not cover a populated library.")

            let accountButton = app.buttons["Account and settings"]
            XCTAssertTrue(accountButton.waitForExistence(timeout: 5))
            accountButton.tap()

            let status = app.staticTexts["account.connection.status"]
            for _ in 0..<6 where !status.isHittable { app.swipeUp() }
            XCTAssertTrue(status.waitForExistence(timeout: 5))
            XCTAssertTrue(status.isHittable)
            XCTAssertEqual(status.label, "Offline")
            XCTAssertTrue(app.buttons["account.connection.retry"].exists,
                          "Offline status should offer a retry action.")
            app.terminate()
        }
    }

    @MainActor
    func testOnlineAccountStatusDoesNotOfferRetryInLightAndDark() throws {
        for appearance in ["Light", "Dark"] {
            let app = fixtureApplication(appearance: appearance, connection: "Online")
            app.launch()

            let savedEvent = app.buttons.matching(
                NSPredicate(format: "label CONTAINS %@", "Alex & Jordan")
            ).firstMatch
            XCTAssertTrue(savedEvent.waitForExistence(timeout: 8))
            let accountButton = app.buttons["Account and settings"]
            XCTAssertTrue(accountButton.waitForExistence(timeout: 5))
            accountButton.tap()

            let status = app.staticTexts["account.connection.status"]
            for _ in 0..<6 where !status.isHittable { app.swipeUp() }
            XCTAssertTrue(status.waitForExistence(timeout: 5))
            XCTAssertTrue(status.isHittable)
            XCTAssertEqual(status.label, "Online")
            XCTAssertFalse(app.buttons["account.connection.retry"].exists,
                           "Online status should not offer an offline retry action.")
            app.terminate()
        }
    }

    @MainActor
    private func fixtureApplication(appearance: String, connection: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += [
            "-DisableProductionFlowSimulation", "-SkipAuthentication",
            "-SeedDevelopmentData", "-UseEphemeralDataStore",
            "-UseProductionOnboarding", "-AppleLanguages", "(en)",
            "-AppleInterfaceStyle", appearance,
            "-appAppearance", appearance.lowercased(),
            "-Connection\(connection)UITest"
        ]
        return app
    }
}
