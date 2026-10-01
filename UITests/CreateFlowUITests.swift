import XCTest

/// Demo workspace: the Typeform-style add flow, including creating a company
/// from inside a new person's "Where do they work?" step.
final class CreateFlowUITests: XCTestCase {
    private func snap(_ name: String) {
        guard let dir = ProcessInfo.processInfo.environment["SNAPSHOT_DIR"] else { return }
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir).appending(path: "\(name).png"))
    }

    /// Lists are lazy: rows below the fold don't exist until scrolled to.
    @discardableResult
    private func scrollTo(_ element: XCUIElement, in app: XCUIApplication) -> Bool {
        for _ in 0..<8 where !element.exists { app.swipeUp() }
        return element.waitForExistence(timeout: 2)
    }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "-resetPreferences"]
        app.launch()
        return app
    }

    func testAddPersonWithNewCompany() throws {
        let app = launch()
        XCTAssertTrue(app.buttons["list.add"].waitForExistence(timeout: 5))
        app.buttons["list.add"].tap()

        // 1. Name — auto-focused, Next disabled until filled.
        let first = app.textFields["flow.name.firstName"]
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["flow.person.next"].isEnabled)
        first.typeText("Grace")
        app.textFields["flow.name.lastName"].tap()
        app.textFields["flow.name.lastName"].typeText("Liu")
        snap("f1-name")
        app.buttons["flow.person.next"].tap()

        // 2. Company — search, no match, add it inline.
        XCTAssertTrue(app.staticTexts["Where do they work?"].waitForExistence(timeout: 5))
        let search = app.textFields["flow.search"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("Zeta Labs")
        let add = app.buttons["flow.addRelated"]
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        XCTAssertTrue(add.label.contains("Zeta Labs"))
        snap("f2-company-search")
        add.tap()

        // Nested company flow, name prefilled from the search.
        XCTAssertTrue(app.staticTexts["What's the company called?"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields["flow.name"].value as? String, "Zeta Labs")
        app.buttons["flow.company.next"].tap()
        XCTAssertTrue(app.staticTexts["What's their website?"].waitForExistence(timeout: 5))
        snap("f3-company-website")
        app.buttons["flow.company.skip"].tap()
        // Tier and account owner share one step (as in the tGBP workspace);
        // Create is available from any step.
        XCTAssertTrue(app.staticTexts["Tier, owner and type"].waitForExistence(timeout: 5))
        snap("f4-company-tier")
        XCTAssertTrue(app.buttons["flow.company.createNow"].waitForExistence(timeout: 5))
        app.buttons["flow.company.createNow"].tap()

        // Back in the person flow with the company picked, moved on to contact.
        XCTAssertTrue(app.staticTexts["How do you reach them?"].waitForExistence(timeout: 5))
        snap("f5-contact")
        app.buttons["flow.person.createNow"].tap()

        // Lands on the new person, linked to the new company.
        XCTAssertTrue(app.buttons["record.edit"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Grace Liu"].exists)
        // LabeledContent reads as one element ("Company, Zeta Labs").
        let companyRow = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'Zeta Labs'")).firstMatch
        XCTAssertTrue(scrollTo(companyRow, in: app))
        snap("f6-person-created")

        // The new person shows up in the list.
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(scrollTo(app.staticTexts["Grace Liu"], in: app))

        // The new company exists too, with Grace under People.
        app.tabBars.buttons["Companies"].tap()
        XCTAssertTrue(scrollTo(app.staticTexts["Zeta Labs"], in: app))
        app.staticTexts["Zeta Labs"].tap()
        XCTAssertTrue(scrollTo(app.staticTexts["People (1)"], in: app))
        snap("f7-company-people")
    }

    func testAddPersonFromCompanyAndEditOrder() throws {
        let app = launch()
        app.tabBars.buttons["Companies"].tap()
        XCTAssertTrue(app.staticTexts["Northwind Exchange"].waitForExistence(timeout: 5))
        app.staticTexts["Northwind Exchange"].tap()
        XCTAssertTrue(app.buttons["record.edit"].waitForExistence(timeout: 5))

        // Edit page: name, then website, at the top.
        app.buttons["record.edit"].tap()
        XCTAssertTrue(app.textFields["edit.name"].waitForExistence(timeout: 5))
        snap("g1-edit-order")
        app.buttons["Cancel"].tap()

        // People who work here, and "Add person" with the company prefilled.
        XCTAssertTrue(scrollTo(app.staticTexts["Ada Hart"], in: app))
        scrollTo(app.buttons["related.add.people"], in: app)
        app.buttons["related.add.people"].tap()
        let first = app.textFields["flow.name.firstName"]
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        first.typeText("Hugo")
        app.buttons["flow.person.next"].tap()
        // Company step already answered.
        XCTAssertTrue(app.staticTexts["Northwind Exchange"].waitForExistence(timeout: 5))
        snap("g2-company-prefilled")
        app.buttons["flow.person.createNow"].tap()

        XCTAssertTrue(scrollTo(app.staticTexts["People (3)"], in: app))
        XCTAssertTrue(app.staticTexts["Hugo"].exists)
    }

    func testAdvancedModeShowsWholeCard() throws {
        let app = launch()
        app.buttons["list.add"].tap()
        XCTAssertTrue(app.textFields["flow.name.firstName"].waitForExistence(timeout: 5))

        // Toggle on the first question switches to the full card.
        let toggle = app.switches["flow.advanced"]
        XCTAssertTrue(toggle.exists)
        toggle.switches.firstMatch.tap()
        let first = app.textFields["edit.name.firstName"]
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["edit.jobTitle"].exists)   // all fields on one page
        XCTAssertFalse(app.staticTexts["What's their name?"].exists)
        first.tap()
        first.typeText("Ivy")
        XCTAssertTrue(scrollTo(app.buttons["edit.tags"], in: app))  // multi-select still a real picker
        snap("h1-advanced")
        app.buttons["flow.person.createNow"].tap()
        XCTAssertTrue(app.buttons["record.edit"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Ivy"].exists)

        // Remembered next time; switching back returns to the questions.
        app.navigationBars.buttons.firstMatch.tap()
        app.buttons["list.add"].tap()
        XCTAssertTrue(app.textFields["edit.name.firstName"].waitForExistence(timeout: 5))
        app.switches["flow.advanced"].switches.firstMatch.tap()
        XCTAssertTrue(app.staticTexts["What's their name?"].waitForExistence(timeout: 5))
    }
}
