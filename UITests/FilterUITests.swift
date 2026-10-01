import XCTest

/// Filters on the Companies list stack, and survive quitting the app.
final class FilterUITests: XCTestCase {
    private func snap(_ name: String) {
        guard let dir = ProcessInfo.processInfo.environment["SNAPSHOT_DIR"] else { return }
        // Let iOS 26's blur-in tab and sheet transitions finish first.
        Thread.sleep(forTimeInterval: 1.5)
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir).appending(path: "\(name).png"))
    }

    private func openCompanies(_ app: XCUIApplication) {
        app.tabBars.buttons["Companies"].tap()
        XCTAssertTrue(app.buttons["filter.chip.tier"].waitForExistence(timeout: 5))
    }

    func testStackedFiltersPersistAcrossLaunches() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "-resetPreferences"]
        app.launch()
        openCompanies(app)
        XCTAssertTrue(app.staticTexts["Harbour Bank"].waitForExistence(timeout: 5))
        snap("f1-companies")

        // Tier 1 or no tier…
        app.buttons["filter.chip.tier"].tap()
        app.buttons["filter.option.tier.TIER_1"].tap()
        app.buttons["filter.option.tier.__none__"].tap()
        snap("f2-tier-sheet")
        app.buttons["filter.done"].tap()
        XCTAssertTrue(app.staticTexts["Lumen Payments"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Harbour Bank"].exists)

        // …stacked with an owner: only Northwind is Tier 1 and owned by Jake.
        app.buttons["filter.chip.accountOwner"].tap()
        let jake = app.buttons["filter.option.accountOwner.m0000000-0000-4000-8000-000000000001"]
        XCTAssertTrue(jake.waitForExistence(timeout: 5))
        jake.tap()
        app.buttons["filter.done"].tap()
        XCTAssertTrue(app.staticTexts["Northwind Exchange"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Lumen Payments"].waitForExistence(timeout: 1))
        snap("f3-stacked")

        // Quit and relaunch without resetting preferences: filters are still on.
        app.terminate()
        app.launchArguments = ["-demo"]
        app.launch()
        openCompanies(app)
        XCTAssertTrue(app.staticTexts["Northwind Exchange"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Harbour Bank"].exists)
        XCTAssertFalse(app.staticTexts["Lumen Payments"].exists)
        XCTAssertTrue(app.buttons["filter.clearAll"].exists)
        snap("f4-relaunched")

        app.buttons["filter.clearAll"].tap()
        XCTAssertTrue(app.staticTexts["Harbour Bank"].waitForExistence(timeout: 5))
    }
}
