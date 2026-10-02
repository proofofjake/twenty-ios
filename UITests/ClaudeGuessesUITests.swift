import XCTest

/// Claude's educated guesses (Debug builds), in demo mode: swipe right to
/// stage, apply from Recent actions, swipe left and undo.
final class ClaudeGuessesUITests: XCTestCase {
    private var suffix: String { ProcessInfo.processInfo.environment["SNAPSHOT_SUFFIX"].map { "-\($0)" } ?? "" }

    private func snap(_ name: String) {
        guard let dir = ProcessInfo.processInfo.environment["SNAPSHOT_DIR"] else { return }
        Thread.sleep(forTimeInterval: 1)
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir).appending(path: "\(name)\(suffix).png"))
    }

    private func launchDeck() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "-resetPreferences"]
        app.launch()
        app.tabBars.buttons["More"].tap()
        let row = app.buttons["more.guesses"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        XCTAssertTrue(app.otherElements["guess.card"].waitForExistence(timeout: 5))
        return app
    }

    private func waitForProgress(_ prefix: String, in app: XCUIApplication) -> Bool {
        let progress = app.staticTexts.matching(NSPredicate(format: "identifier == 'guess.progress' AND label BEGINSWITH %@", prefix)).firstMatch
        return progress.waitForExistence(timeout: 5)
    }

    private func element(containing text: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    func testAcceptApplyDeclineAndUndo() throws {
        let app = launchDeck()
        XCTAssertTrue(waitForProgress("1 of 6", in: app))
        XCTAssertTrue(app.staticTexts["Atlas Asset Management"].exists)

        // Right: staged in Recent actions, not written.
        app.otherElements["guess.card"].swipeRight()
        XCTAssertTrue(waitForProgress("2 of 6", in: app))
        XCTAssertTrue(app.staticTexts["Northwind Exchange"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["undo.banner"].exists) // the deck has its own undo

        app.tabBars.buttons["Settings"].tap()
        let staged = app.staticTexts["Claude's guess for Atlas Asset Management: website, owner, type, company type"]
        XCTAssertTrue(staged.waitForExistence(timeout: 5))
        app.buttons["guess.apply"].tap()
        XCTAssertTrue(element(containing: "Applied Atlas Asset Management", in: app).waitForExistence(timeout: 5))
        XCTAssertFalse(staged.exists)

        // Applied: the company has all four.
        app.tabBars.buttons["Companies"].tap()
        let atlas = app.staticTexts["Atlas Asset Management"]
        XCTAssertTrue(atlas.waitForExistence(timeout: 5))
        atlas.tap()
        XCTAssertTrue(app.buttons["record.edit"].waitForExistence(timeout: 5))
        XCTAssertTrue(element(containing: "atlas-am.example", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(element(containing: "Jake Demo", in: app).exists)
        XCTAssertTrue(app.staticTexts["Institutional"].exists)
        XCTAssertTrue(app.staticTexts["Asset Manger"].exists)

        // Left on the next card, then undo brings it back.
        app.tabBars.buttons["More"].tap()
        XCTAssertTrue(waitForProgress("2 of 6", in: app))
        app.otherElements["guess.card"].swipeLeft()
        XCTAssertTrue(waitForProgress("3 of 6", in: app))
        XCTAssertTrue(app.staticTexts["Lumen Payments"].waitForExistence(timeout: 5))
        app.buttons["guess.undo"].tap()
        XCTAssertTrue(waitForProgress("2 of 6", in: app))
        XCTAssertTrue(app.staticTexts["Northwind Exchange"].waitForExistence(timeout: 5))
    }

    func testSwipeAsPicksTheOwner() throws {
        let app = launchDeck()
        XCTAssertTrue(waitForProgress("1 of 6", in: app))
        // Claude guessed Jake for Atlas; swipe as Sam instead.
        let jake = app.buttons["guess.owner.m0000000-0000-4000-8000-000000000001"]
        let sam = app.buttons["guess.owner.m0000000-0000-4000-8000-000000000002"]
        XCTAssertTrue(jake.waitForExistence(timeout: 5))
        XCTAssertTrue(jake.isSelected)
        sam.tap()
        XCTAssertTrue(sam.isSelected)
        XCTAssertFalse(jake.isSelected)
        XCTAssertTrue(element(containing: "Sam Rivera", in: app).exists)
        snap("guesses-swipe-as")

        app.otherElements["guess.card"].swipeRight()
        XCTAssertTrue(waitForProgress("2 of 6", in: app))
        app.tabBars.buttons["Settings"].tap()
        XCTAssertTrue(app.buttons["guess.apply"].waitForExistence(timeout: 5))
        app.buttons["guess.apply"].tap()
        XCTAssertTrue(element(containing: "Applied Atlas Asset Management", in: app).waitForExistence(timeout: 5))

        app.tabBars.buttons["Companies"].tap()
        let atlas = app.staticTexts["Atlas Asset Management"]
        XCTAssertTrue(atlas.waitForExistence(timeout: 5))
        atlas.tap()
        XCTAssertTrue(app.buttons["record.edit"].waitForExistence(timeout: 5))
        XCTAssertTrue(element(containing: "Sam Rivera", in: app).waitForExistence(timeout: 5))
    }

    func testSkipSendsCardToBottomAndUndo() throws {
        let app = launchDeck()
        XCTAssertTrue(waitForProgress("1 of 6", in: app))
        XCTAssertTrue(app.staticTexts["Atlas Asset Management"].exists)

        // Skip (button): the next card comes up; nothing is used up.
        app.buttons["guess.skip"].tap()
        XCTAssertTrue(app.staticTexts["Northwind Exchange"].waitForExistence(timeout: 5))
        XCTAssertTrue(waitForProgress("1 of 6", in: app))
        XCTAssertFalse(app.staticTexts["Atlas Asset Management"].exists) // now at the bottom, not drawn

        // Skip (swipe up), then undo twice: back in the original order.
        app.otherElements["guess.card"].swipeUp()
        XCTAssertTrue(app.staticTexts["Lumen Payments"].waitForExistence(timeout: 5))
        app.buttons["guess.undo"].tap()
        XCTAssertTrue(app.staticTexts["Northwind Exchange"].waitForExistence(timeout: 5))
        app.buttons["guess.undo"].tap()
        XCTAssertTrue(app.staticTexts["Atlas Asset Management"].waitForExistence(timeout: 5))

        // A skip survives a relaunch: Atlas stays at the bottom.
        app.buttons["guess.skip"].tap()
        XCTAssertTrue(app.staticTexts["Northwind Exchange"].waitForExistence(timeout: 5))
        app.terminate()
        let relaunched = XCUIApplication()
        relaunched.launchArguments = ["-demo"]
        relaunched.launch()
        relaunched.tabBars.buttons["More"].tap()
        relaunched.buttons["more.guesses"].tap()
        XCTAssertTrue(relaunched.otherElements["guess.card"].waitForExistence(timeout: 5))
        XCTAssertTrue(relaunched.staticTexts["Northwind Exchange"].waitForExistence(timeout: 5))
    }

    func testSuggestedDeleteNeedsASlideAndUndoRestores() throws {
        let app = launchDeck()
        // Decline down to Inkwell Sign, whose note says it's inbox noise.
        for _ in 0..<6 where !app.buttons["guess.delete"].exists {
            app.buttons["guess.decline"].tap()
            _ = app.buttons["guess.delete"].waitForExistence(timeout: 2)
        }
        let delete = app.buttons["guess.delete"]
        XCTAssertTrue(delete.exists)
        XCTAssertTrue(app.staticTexts["Inkwell Sign"].exists)
        delete.tap()

        // A tap on the slider does nothing; it has to be slid across.
        let slider = app.buttons["slide.confirm"]
        XCTAssertTrue(slider.waitForExistence(timeout: 5))
        slider.tap()
        XCTAssertTrue(slider.exists)
        slider.coordinate(withNormalizedOffset: CGVector(dx: 0.06, dy: 0.5))
            .press(forDuration: 0.1, thenDragTo: slider.coordinate(withNormalizedOffset: CGVector(dx: 0.99, dy: 0.5)))
        XCTAssertTrue(slider.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Inkwell Sign"].waitForNonExistence(timeout: 5))

        // It's in Recent actions like any delete; the deck's undo restores it.
        app.buttons["guess.undo"].tap()
        XCTAssertTrue(app.staticTexts["Inkwell Sign"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["guess.delete"].exists)
    }

    func testTogglesButtonsAndNoteCards() throws {
        let app = launchDeck()
        // Tapping a guess leaves it out of the accept.
        let tag = app.buttons["guess.row.tag"]
        XCTAssertTrue(tag.waitForExistence(timeout: 5))
        tag.tap()
        XCTAssertEqual(tag.value as? String, "Left out")
        app.buttons["guess.accept"].tap()
        XCTAssertTrue(waitForProgress("2 of 6", in: app))

        // Decline down to the note-only card: ✓ reads "Done" there.
        for n in 3...6 {
            app.buttons["guess.decline"].tap()
            XCTAssertTrue(waitForProgress("\(n) of 6", in: app))
        }
        XCTAssertTrue(app.staticTexts["Inkwell Sign"].exists)
        XCTAssertTrue(app.otherElements["guess.note"].exists || element(containing: "Inbox noise", in: app).exists)
        XCTAssertEqual(app.buttons["guess.accept"].label, "Done")
        app.buttons["guess.accept"].tap()
        XCTAssertTrue(app.otherElements["guess.empty"].waitForExistence(timeout: 5)
                      || app.staticTexts["No guesses to review"].waitForExistence(timeout: 1))

        // Staged without the type; the More row counts what's left (none).
        app.tabBars.buttons["Settings"].tap()
        XCTAssertTrue(app.staticTexts["Claude's guess for Atlas Asset Management: website, owner, company type"].waitForExistence(timeout: 5))
        app.buttons["guess.discard"].tap()
        XCTAssertTrue(app.staticTexts["Nothing in the last 24 hours"].waitForExistence(timeout: 5))
    }

    /// Cobalt Custody was added twice: merge Cobalt Custody Ltd into it from
    /// the deck (staged), then run it from Recent actions with a slide.
    func testMergeStagedThenSlid() throws {
        let cobalt = "c0000000-0000-4000-8000-000000000006"
        let ltd = "c0000000-0000-4000-8000-000000000008"
        let app = launchDeck()
        for _ in 0..<6 where !app.buttons["guess.merge"].exists {
            app.buttons["guess.decline"].tap()
            _ = app.buttons["guess.merge"].waitForExistence(timeout: 2)
        }
        let merge = app.buttons["guess.merge"]
        XCTAssertTrue(merge.exists)
        XCTAssertTrue(app.staticTexts["Cobalt Custody"].exists)
        XCTAssertTrue(merge.label.contains("Merge with Cobalt Custody Ltd"))
        merge.tap()

        // Claude's picks are selected; the survivor is Claude's keep.
        XCTAssertTrue(app.staticTexts["Merge 2 companies"].waitForExistence(timeout: 5) || app.otherElements["merge.title"].waitForExistence(timeout: 1))
        XCTAssertEqual(app.buttons["merge.keep.\(cobalt)"].value as? String, "Kept")
        let ltdName = app.buttons["merge.option.name.\(ltd)"]
        XCTAssertTrue(ltdName.waitForExistence(timeout: 5))
        XCTAssertEqual(ltdName.value as? String, "Selected")
        XCTAssertTrue(ltdName.label.contains("The registered name"))
        XCTAssertEqual(app.buttons["merge.option.domainName.\(ltd)"].value as? String, "Selected")
        snap("merge-window")

        // Keep this one's own name instead.
        let ownName = app.buttons["merge.option.name.\(cobalt)"]
        ownName.tap()
        XCTAssertEqual(ownName.value as? String, "Selected")
        XCTAssertNotEqual(ltdName.value as? String, "Selected")

        let address = app.buttons["merge.option.address.\(ltd)"]
        for _ in 0..<4 where !address.isHittable { app.swipeUp() }
        XCTAssertEqual(address.value as? String, "Selected")
        let stage = app.buttons["merge.stage"]
        for _ in 0..<6 where !(stage.exists && stage.isHittable) { app.swipeUp() }
        XCTAssertTrue(element(containing: "Moves to Cobalt Custody: 1 person", in: app).exists)
        XCTAssertTrue(element(containing: "Cobalt Custody Ltd will be permanently deleted", in: app).exists)
        snap("merge-window-bottom")
        stage.tap()

        // Staged, not run: the card says so and Ltd still exists.
        XCTAssertTrue(app.otherElements["guess.mergeStaged"].waitForExistence(timeout: 5) || element(containing: "is in Recent actions", in: app).waitForExistence(timeout: 1))
        app.tabBars.buttons["Settings"].tap()
        let staged = app.staticTexts["Merge Cobalt Custody Ltd into Cobalt Custody (Claude's suggestion)"]
        XCTAssertTrue(staged.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["guess.applyAll"].exists) // merges aren't guesses to apply
        app.buttons["merge.open"].tap()

        // A tap on the slider does nothing; it has to be slid across.
        let slider = app.buttons["slide.confirm"]
        XCTAssertTrue(slider.waitForExistence(timeout: 5))
        XCTAssertTrue(element(containing: "1 person", in: app).waitForExistence(timeout: 5))
        snap("merge-confirm")
        slider.tap()
        XCTAssertTrue(slider.exists)
        XCTAssertTrue(staged.exists)
        slider.coordinate(withNormalizedOffset: CGVector(dx: 0.06, dy: 0.5))
            .press(forDuration: 0.1, thenDragTo: slider.coordinate(withNormalizedOffset: CGVector(dx: 0.99, dy: 0.5)))
        XCTAssertTrue(slider.waitForNonExistence(timeout: 5))
        XCTAssertTrue(element(containing: "Merged Cobalt Custody Ltd into Cobalt Custody", in: app).waitForExistence(timeout: 5))
        XCTAssertFalse(staged.exists)

        // One Cobalt left, with its own name, Ltd's address and website, and Gus.
        app.tabBars.buttons["Companies"].tap()
        let kept = app.staticTexts["Cobalt Custody"]
        XCTAssertTrue(kept.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Cobalt Custody Ltd"].exists)
        kept.tap()
        XCTAssertTrue(app.buttons["record.edit"].waitForExistence(timeout: 5))
        XCTAssertTrue(element(containing: "20 Gresham St", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(element(containing: "cobaltcustody.example", in: app).exists)
        for _ in 0..<4 where !element(containing: "Gus Moreau", in: app).exists { app.swipeUp() }
        XCTAssertTrue(element(containing: "Gus Moreau", in: app).exists)
    }

    /// Screenshots only (SNAPSHOT_DIR set): the deck, a card mid-drag (taken
    /// by the caller with simctl while the drag is held), a note card and
    /// Recent actions.
    func testSnapshots() throws {
        guard let dir = ProcessInfo.processInfo.environment["SNAPSHOT_DIR"] else { throw XCTSkip("SNAPSHOT_DIR not set") }
        let app = launchDeck()
        XCTAssertTrue(waitForProgress("1 of 6", in: app))
        snap("guess-deck")

        // Hold a drag to the right; the caller screenshots when the marker appears.
        let card = app.otherElements["guess.card"]
        let start = card.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45))
        let end = start.withOffset(CGVector(dx: 110, dy: 14))
        FileManager.default.createFile(atPath: URL(fileURLWithPath: dir).appending(path: "drag-hold\(suffix)").path, contents: nil)
        start.press(forDuration: 0.1, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 4)
        XCTAssertTrue(waitForProgress("1 of 6", in: app)) // sprang back

        app.buttons["guess.row.tag"].tap()
        snap("guess-toggled")
        for n in 2...5 {
            app.buttons["guess.decline"].tap()
            XCTAssertTrue(waitForProgress("\(n) of 6", in: app))
        }
        snap("guess-note")
        app.buttons["guess.accept"].tap()
        app.tabBars.buttons["Settings"].tap()
        XCTAssertTrue(app.buttons["guess.apply"].waitForExistence(timeout: 5))
        snap("guess-settings")
    }
}
