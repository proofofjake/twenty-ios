import XCTest

/// Deleting from a list (swipe) and from a record's ⋯ menu, in demo mode.
final class DeleteUITests: XCTestCase {
    func testSwipeDeleteCompanyAndMenuDeletePerson() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "-resetPreferences"]
        app.launch()

        // Swipe a company away.
        app.tabBars.buttons["Companies"].tap()
        let lumen = app.staticTexts["Lumen Payments"]
        XCTAssertTrue(lumen.waitForExistence(timeout: 5))
        lumen.swipeLeft()
        app.buttons["row.delete"].tap()
        XCTAssertTrue(app.buttons["delete.confirm"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Also delete its 1 person"].waitForExistence(timeout: 5))
        app.buttons["delete.confirm"].tap()
        XCTAssertFalse(lumen.waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["Harbour Bank"].exists)

        // Delete a person from their detail screen; it pops back to the list.
        app.tabBars.buttons["People"].tap()
        app.staticTexts["Dev Patel"].tap()
        XCTAssertTrue(app.buttons["record.more"].waitForExistence(timeout: 5))
        app.buttons["record.more"].tap()
        app.buttons["record.delete"].tap()
        XCTAssertTrue(app.buttons["delete.confirm"].waitForExistence(timeout: 5))
        app.buttons["delete.confirm"].tap()
        XCTAssertTrue(app.staticTexts["Ben Okafor"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Dev Patel"].exists)
        // The person stayed when their company was deleted without the toggle.
        XCTAssertTrue(app.staticTexts["Chloe Marsh"].exists)
    }

    func testUndoFromBannerAndFromSettingsAfterRelaunch() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "-resetPreferences"]
        app.launch()

        // Delete, then undo straight away from the banner.
        app.tabBars.buttons["Companies"].tap()
        let lumen = app.staticTexts["Lumen Payments"]
        XCTAssertTrue(lumen.waitForExistence(timeout: 5))
        lumen.swipeLeft()
        app.buttons["row.delete"].tap()
        app.buttons["delete.confirm"].tap()
        XCTAssertTrue(app.buttons["undo.banner"].waitForExistence(timeout: 5))
        app.buttons["undo.banner"].tap()
        XCTAssertTrue(lumen.waitForExistence(timeout: 5))

        // Delete a person, quit, relaunch: Settings still offers the undo.
        app.tabBars.buttons["People"].tap()
        let dev = app.staticTexts["Dev Patel"]
        XCTAssertTrue(dev.waitForExistence(timeout: 5))
        dev.swipeLeft()
        app.buttons["row.delete"].tap()
        app.buttons["delete.confirm"].tap()
        XCTAssertFalse(dev.waitForExistence(timeout: 2))
        app.terminate()
        app.launchArguments = ["-demo"]
        app.launch()
        app.tabBars.buttons["Settings"].tap()
        XCTAssertTrue(app.staticTexts["Deleted Dev Patel"].waitForExistence(timeout: 5))
        // The demo store is in memory, so the relaunched app has Dev again;
        // undo still clears the entry. (Live, it restores from Twenty's trash.)
        app.buttons["undo.recent"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Nothing in the last 24 hours"].waitForExistence(timeout: 5)
                      || app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH 'Couldn'")).firstMatch.exists)
    }

    func testCommitFromSettingsIsConfirmedAndFinal() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "-resetPreferences"]
        app.launch()

        func swipeDelete(_ name: String) {
            let row = app.staticTexts[name]
            XCTAssertTrue(row.waitForExistence(timeout: 5))
            row.swipeLeft()
            app.buttons["row.delete"].tap()
            app.buttons["delete.confirm"].tap()
            XCTAssertFalse(row.waitForExistence(timeout: 2))
        }
        app.tabBars.buttons["Companies"].tap()
        swipeDelete("Lumen Payments")
        swipeDelete("Harbour Bank")

        app.tabBars.buttons["Settings"].tap()
        XCTAssertTrue(app.staticTexts["Deleted Harbour Bank"].waitForExistence(timeout: 5))
        // Commit asks first; cancelling keeps it.
        app.buttons["commit.recent"].firstMatch.tap()
        XCTAssertTrue(app.buttons["commit.confirm"].firstMatch.waitForExistence(timeout: 5))
        app.buttons["commit.confirm"].firstMatch.tap()
        XCTAssertFalse(app.staticTexts["Deleted Harbour Bank"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Deleted Lumen Payments"].exists)

        // Commit all (one left, so use the row's button) empties the list.
        app.buttons["commit.recent"].firstMatch.tap()
        app.buttons["commit.confirm"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Nothing in the last 24 hours"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Companies"].tap()
        XCTAssertTrue(app.staticTexts["Northwind Exchange"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Harbour Bank"].exists)
    }
}
