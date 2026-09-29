import XCTest

/// Drives the demo workspace: edit a person's multi-select and save it.
final class EditFlowUITests: XCTestCase {
    private func snap(_ name: String) {
        guard let dir = ProcessInfo.processInfo.environment["SNAPSHOT_DIR"] else { return }
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir).appending(path: "\(name).png"))
    }

    func testEditMultiSelectAndSave() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "-resetPreferences"]
        app.launch()

        app.staticTexts["Ben Okafor"].tap()
        XCTAssertTrue(app.staticTexts["Investor"].waitForExistence(timeout: 5))
        snap("2-detail")

        app.buttons["record.edit"].tap()
        let tags = app.buttons["edit.tags"]
        XCTAssertTrue(tags.waitForExistence(timeout: 5))
        snap("3-edit")
        tags.tap()

        XCTAssertTrue(app.buttons["option.Advisor"].waitForExistence(timeout: 5))
        app.buttons["option.Advisor"].tap()
        app.buttons["option.Press"].tap()
        snap("4-picker")
        app.buttons["Done"].tap()
        snap("5-edit-after")

        app.buttons["record.save"].tap()
        XCTAssertTrue(app.buttons["record.edit"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Advisor"].exists)
        XCTAssertTrue(app.staticTexts["Press"].exists)
        XCTAssertTrue(app.staticTexts["Investor"].exists)
        snap("6-detail-saved")
    }
}
