import XCTest

@MainActor
enum HomeLayoutUITestSupport {
    static func select(
        _ layout: String,
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let accountButton = app.buttons["Account and settings"]
        XCTAssertTrue(accountButton.waitForExistence(timeout: 5), "Home should expose Account settings.", file: file, line: line)
        accountButton.tap()

        let homeLayoutLink = app.descendants(matching: .any)["account.home.layout"]
        XCTAssertTrue(homeLayoutLink.waitForExistence(timeout: 5), "Account should expose Home view preferences.", file: file, line: line)
        homeLayoutLink.tap()

        let layoutOption = app.buttons[layout]
        XCTAssertTrue(layoutOption.waitForExistence(timeout: 5), "Home view should offer \(layout).", file: file, line: line)
        layoutOption.tap()

        let accountBack = app.navigationBars.buttons["Account"]
        XCTAssertTrue(accountBack.waitForExistence(timeout: 5), "Selecting a Home view should return through Account navigation.", file: file, line: line)
        accountBack.tap()

        let done = app.buttons["Done"]
        XCTAssertTrue(done.waitForExistence(timeout: 5), "The Home view picker should return to Account.", file: file, line: line)
        done.tap()
    }
}
