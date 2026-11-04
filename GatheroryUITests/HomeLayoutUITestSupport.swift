import XCTest

@MainActor
enum HomeLayoutUITestSupport {
    static func select(
        _ layout: String,
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let accountButton = app.navigationBars.buttons.matching(identifier: "Account and settings").firstMatch
        XCTAssertTrue(accountButton.waitForExistence(timeout: 5), "Home should expose Account settings.", file: file, line: line)
        accountButton.tap()

        let homeLayoutLink = app.buttons.matching(identifier: "account.home.layout").firstMatch
        XCTAssertTrue(homeLayoutLink.waitForExistence(timeout: 5), "Account should expose Home view preferences.", file: file, line: line)
        homeLayoutLink.tap()

        let layoutOption = app.buttons.matching(identifier: layout).firstMatch
        XCTAssertTrue(layoutOption.waitForExistence(timeout: 5), "Home view should offer \(layout).", file: file, line: line)
        layoutOption.tap()

        let accountBack = app.navigationBars.buttons.matching(identifier: "Account").firstMatch
        if accountBack.waitForExistence(timeout: 1) {
            accountBack.tap()
        }

        let done = app.buttons.matching(identifier: "Done").firstMatch
        if done.waitForExistence(timeout: 2) {
            done.tap()
        }
        // Updating Home's layout can dismiss the profile presentation as its
        // presenting toolbar is rebuilt. Verify the chosen Home layout in
        // either native dismissal path rather than requiring an extra Back.
        let content = layout == "Overview"
            ? app.scrollViews["home.overview"]
            : app.buttons.matching(NSPredicate(format: "identifier == %@ OR identifier == %@", "home.event.main", "home.event.child")).firstMatch
        XCTAssertTrue(content.waitForExistence(timeout: 5), "The requested Home layout should be active after leaving Account.", file: file, line: line)
    }
}
