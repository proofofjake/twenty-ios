import XCTest

/// People get an inferred point of contact: company owner, else who added them.
final class PointOfContactUITests: XCTestCase {
    func testFilterPeopleByPointOfContact() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "-resetPreferences"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Ada Hart"].waitForExistence(timeout: 5))

        let chip = app.buttons["filter.chip.inferredPointOfContact"]
        XCTAssertTrue(chip.waitForExistence(timeout: 5))
        chip.tap()
        let sam = app.buttons["filter.option.inferredPointOfContact.m0000000-0000-4000-8000-000000000002"]
        XCTAssertTrue(sam.waitForExistence(timeout: 5))
        sam.tap()
        app.buttons["filter.done"].tap()

        // Ben: Harbour Bank is Sam's account. Chloe: Lumen has no owner, Sam added her.
        XCTAssertTrue(app.staticTexts["Ben Okafor"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Chloe Marsh"].exists)
        XCTAssertFalse(app.staticTexts["Ada Hart"].exists)
        XCTAssertFalse(app.staticTexts["Dev Patel"].exists)

        app.staticTexts["Chloe Marsh"].tap()
        // Each line reads as "Point of contact, …".
        let name = app.staticTexts.matching(NSPredicate(format: "label == 'Point of contact, Sam Rivera'")).firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label == 'Point of contact, Added them to Twenty'")).firstMatch.exists)
    }
}
