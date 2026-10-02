#if DEBUG
import XCTest
@testable import TwentyCRM

/// Claude's educated guesses (Debug only): reading the file, checking guesses
/// against the workspace, and what Accept stages and Apply sends.
final class ClaudeGuessesTests: XCTestCase {
    private let atlas = "c0000000-0000-4000-8000-000000000004"
    private let northwind = "c0000000-0000-4000-8000-000000000001"
    private let lumen = "c0000000-0000-4000-8000-000000000003"
    private let brightline = "c0000000-0000-4000-8000-000000000005"
    private let cobalt = "c0000000-0000-4000-8000-000000000006"
    private let inkwell = "c0000000-0000-4000-8000-000000000007"
    private let jake = "m0000000-0000-4000-8000-000000000001"
    private let sam = "m0000000-0000-4000-8000-000000000002"

    private func objects() throws -> [ObjectMetadata] { try LiveTwentyService.decodeObjects(Data(DemoData.metadataJSON.utf8)) }
    private func company() throws -> ObjectMetadata { try XCTUnwrap(objects().first { $0.nameSingular == "company" }) }
    private func file() throws -> ClaudeGuesses.File { try ClaudeGuesses.parse(Data(DemoData.guessesJSON.utf8)) }

    private func cards(declined: Set<String> = [], staged: Set<String> = [], records: [String: [Record]] = DemoData.records()) throws -> [ClaudeGuesses.Card] {
        ClaudeGuesses.cards(for: try file().entries, records: records["companies"] ?? [], object: try company(),
                            members: records["workspaceMembers"] ?? [], memberObject: try objects().first { $0.nameSingular == "workspaceMember" },
                            declined: declined, staged: staged)
    }

    private func card(_ id: String, in cards: [ClaudeGuesses.Card]) throws -> ClaudeGuesses.Card {
        try XCTUnwrap(cards.first { $0.id == id })
    }

    private func kind(_ field: ClaudeGuesses.Field, _ card: ClaudeGuesses.Card) -> ClaudeGuesses.Row.Kind? {
        card.rows.first { $0.field == field }?.kind
    }

    // MARK: Parsing

    func testParsesVersionOneAndIgnoresUnknownKeys() throws {
        let parsed = try file()
        XCTAssertEqual(parsed.entries.count, 8)
        XCTAssertEqual(parsed.generatedAt, FieldFormatter.parseDate("2026-10-01T16:00:00Z"))
        let first = try XCTUnwrap(parsed.entries.first)
        XCTAssertEqual(first.id, atlas)
        XCTAssertEqual(Set(first.guesses.keys), Set(ClaudeGuesses.Field.allCases))
        XCTAssertEqual(first.guesses[.companyType]?.value, ["ASSET_MANGER", "CUSTODIAN"])
        XCTAssertEqual(first.guesses[.domainName]?.confidence, .high)
        XCTAssertEqual(first.guesses[.domainName]?.reason, "Farah emails from @atlas-am.example")

        let cobalt = try XCTUnwrap(parsed.entries.first { $0.id == self.cobalt })
        XCTAssertEqual(cobalt.note, "Duplicate: there's also a Cobalt Custody Ltd. Consider merging")
        XCTAssertNil(cobalt.guesses[.companyType]?.confidence) // "very high" isn't a level
        XCTAssertNil(cobalt.guesses[.tag])                     // missing key
        XCTAssertEqual(cobalt.guesses.count, 2)                // "employees" ignored
    }

    func testParseIsDefensive() throws {
        let json = #"""
        {"companies":[
          {"id":"A1","guesses":{"tag":"DEFI","companyType":"BANK","accountOwner":{"value":42},"domainName":{"value":"  "}}},
          {"name":"no id"},
          "not an object"
        ]}
        """#
        let entries = try ClaudeGuesses.parse(Data(json.utf8)).entries
        XCTAssertEqual(entries.map(\.id), ["a1"])
        XCTAssertEqual(entries[0].guesses[.tag]?.value, "DEFI")          // bare value
        XCTAssertEqual(entries[0].guesses[.companyType]?.value, ["BANK"]) // one key, as a list
        XCTAssertNil(entries[0].guesses[.accountOwner])                   // wrong type
        XCTAssertNil(entries[0].guesses[.domainName])                     // blank
        XCTAssertThrowsError(try ClaudeGuesses.parse(Data(#"{"version":2,"companies":[]}"#.utf8)))
        XCTAssertThrowsError(try ClaudeGuesses.parse(Data("[]".utf8)))
    }

    func testMissingResourceIsReported() {
        XCTAssertThrowsError(try ClaudeGuesses.bundled(in: Bundle(for: Self.self))) { error in
            XCTAssertEqual(error as? ClaudeGuesses.LoadError, .missing)
        }
    }

    // MARK: Checking against the workspace

    func testDeckKeepsOnlyGuessesForEmptyFieldsWithValidValues() throws {
        let deck = try cards()
        // Harbour Bank (all stale) and the unknown id have no card.
        XCTAssertEqual(deck.map(\.id), [atlas, northwind, lumen, brightline, cobalt, inkwell])

        let atlasCard = try card(atlas, in: deck)
        XCTAssertEqual(atlasCard.suggestions.map(\.field), ClaudeGuesses.Field.allCases)
        XCTAssertEqual(atlasCard.suggestions.first { $0.field == .accountOwner }?.display, "Jake Demo")
        XCTAssertEqual(atlasCard.suggestions.first { $0.field == .companyType }?.chips, ["Asset Manger", "Custodian"])
        XCTAssertEqual(atlasCard.rows.map(\.label), ["Website", "Account Owner", "Type", "Company type"])

        // Stale: Northwind's website, owner and company type are already set.
        let northwindCard = try card(northwind, in: deck)
        XCTAssertEqual(northwindCard.suggestions.map(\.field), [.tag])
        XCTAssertEqual(kind(.domainName, northwindCard), .current("northwind.example", chips: []))
        XCTAssertEqual(kind(.accountOwner, northwindCard), .current("Jake Demo", chips: []))
        XCTAssertEqual(kind(.companyType, northwindCard), .current("Exchange", chips: ["Exchange"]))
        XCTAssertEqual(northwindCard.website, "northwind.example")

        // Unknown member and option dropped; the valid company types kept.
        let lumenCard = try card(lumen, in: deck)
        XCTAssertEqual(lumenCard.suggestions.map(\.field), [.companyType])
        XCTAssertEqual(lumenCard.suggestions.first?.value, ["PAYMENTS_INFRA", "CARD_PROVIDER"])
        XCTAssertEqual(kind(.accountOwner, lumenCard), .empty)
        XCTAssertEqual(kind(.tag, lumenCard), .empty)

        // Malformed domain dropped.
        let brightlineCard = try card(brightline, in: deck)
        XCTAssertEqual(brightlineCard.suggestions.map(\.field), [.accountOwner, .tag])
        XCTAssertEqual(kind(.domainName, brightlineCard), .empty)

        // A URL is reduced to its host; the note comes along.
        let cobaltCard = try card(cobalt, in: deck)
        XCTAssertEqual(cobaltCard.suggestions.first { $0.field == .domainName }?.value, "www.cobaltcustody.example")
        XCTAssertNotNil(cobaltCard.note)

        // A note alone still makes a card.
        let inkwellCard = try card(inkwell, in: deck)
        XCTAssertTrue(inkwellCard.suggestions.isEmpty)
        XCTAssertEqual(inkwellCard.note, "Inbox noise: e-signature notification emails. Probably delete")
    }

    func testDeclinedStagedAndNewGuesses() throws {
        let deck = try cards()
        let atlasCard = try card(atlas, in: deck)
        let tag = try XCTUnwrap(atlasCard.suggestions.first { $0.field == .tag })
        XCTAssertEqual(atlasCard.declineKey(tag), "\(atlas)|tag|INSTITUTIONAL")
        let inkwellNote = try XCTUnwrap(try card(inkwell, in: deck).noteKey)
        let northwindTag = try XCTUnwrap(try card(northwind, in: deck).suggestions.first)

        let after = try cards(declined: [atlasCard.declineKey(tag), inkwellNote, try card(northwind, in: deck).declineKey(northwindTag)],
                              staged: [lumen])
        XCTAssertEqual(after.map(\.id), [atlas, brightline, cobalt])
        XCTAssertEqual(try card(atlas, in: after).suggestions.map(\.field), [.domainName, .accountOwner, .companyType])

        // A different guess for a declined field shows again.
        XCTAssertNotEqual(ClaudeGuesses.declineKey(company: atlas, field: "tag", value: "DEFI"), atlasCard.declineKey(tag))
        // Multi-select keys are order-independent.
        XCTAssertEqual(ClaudeGuesses.declineKey(company: "c", field: "companyType", value: ["B", "A"]), "c|companyType|A,B")
    }

    func testOwnerMustBeAMember() throws {
        var records = DemoData.records()
        records["workspaceMembers"]?.removeAll { $0.id == jake }
        let atlasCard = try card(atlas, in: try cards(records: records))
        XCTAssertNil(atlasCard.suggestions.first { $0.field == .accountOwner })
        // Sam's guess for Brightline still stands.
        XCTAssertEqual(try card(brightline, in: try cards(records: records)).suggestions.first?.value, .string(sam))
    }

    func testHostnames() {
        XCTAssertEqual(ClaudeGuesses.host(from: "aberdeenplc.com"), "aberdeenplc.com")
        XCTAssertEqual(ClaudeGuesses.host(from: " https://www.Agridex.COM/ "), "www.agridex.com")
        XCTAssertEqual(ClaudeGuesses.host(from: "sub.my-site.co.uk"), "sub.my-site.co.uk")
        for bad in ["", "localhost", "brightline labs dot com", "-bad.com", "bad-.com", "a..com", "acme.com/about",
                    "ftp://acme.com", "me@acme.com", "acme.c", "acme.123", "a.\(String(repeating: "x", count: 64)).com"] {
            XCTAssertNil(ClaudeGuesses.host(from: bad), bad)
        }
    }

    // MARK: Staging and applying

    func testStagedChangesAndPatch() throws {
        let object = try company()
        let atlasCard = try card(atlas, in: try cards())
        let changes = atlasCard.suggestions.map(ClaudeGuesses.change(for:))
        XCTAssertEqual(changes.map(\.field), ["domainName", "accountOwner", "tag", "companyType"])
        XCTAssertEqual(changes.map(\.summary), ["atlas-am.example", "Jake Demo", "Institutional", "Asset Manger, Custodian"])

        // Website as a whole LINKS value with a scheme, as the link editor writes it.
        XCTAssertEqual(changes[0].value, ["primaryLinkUrl": "https://atlas-am.example", "primaryLinkLabel": "", "secondaryLinks": []])

        let (patch, skipped) = ClaudeGuesses.patch(for: changes, current: atlasCard.company, object: object)
        XCTAssertTrue(skipped.isEmpty)
        XCTAssertEqual(Set(patch.keys), ["domainName", "accountOwnerId", "tag", "companyType"])
        XCTAssertEqual(patch["accountOwnerId"], .string(jake))
        let wire = try JSONSerialization.jsonObject(with: JSONEncoder().encode(patch)) as? [String: Any]
        let links = try XCTUnwrap(wire?["domainName"] as? [String: Any])
        XCTAssertEqual(links["primaryLinkUrl"] as? String, "https://atlas-am.example")
        XCTAssertEqual(links["primaryLinkLabel"] as? String, "")
        XCTAssertEqual((links["secondaryLinks"] as? [Any])?.count, 0)
        XCTAssertEqual(wire?["companyType"] as? [String], ["ASSET_MANGER", "CUSTODIAN"])
    }

    func testApplySkipsFieldsSetSince() throws {
        let object = try company()
        let changes = try card(atlas, in: try cards()).suggestions.map(ClaudeGuesses.change(for:))
        var current = Record(id: atlas, values: ["id": .string(atlas)])
        current["domainName"] = ["primaryLinkUrl": "atlas.example", "primaryLinkLabel": "", "secondaryLinks": []]
        current["accountOwnerId"] = .string(sam)
        current["companyType"] = []
        let (patch, skipped) = ClaudeGuesses.patch(for: changes, current: current, object: object)
        XCTAssertEqual(Set(patch.keys), ["tag", "companyType"])
        XCTAssertEqual(skipped.map(\.message), ["Skipped website: already set", "Skipped owner: already set"])

        let gone = PendingChange(field: "nope", label: "Nope", summary: "x", value: "x")
        XCTAssertEqual(ClaudeGuesses.patch(for: [gone], current: current, object: object).skipped.first?.reason, "not in this workspace")
    }

    // MARK: Recent actions

    func testOldRecentActionsStillDecode() throws {
        // Saved by builds before staged updates existed.
        let old = #"""
        [{"id":"6F9619FF-8B86-D011-B42D-00CF4FC964FF","date":780000000,
          "items":[{"blocked":{"id":"b1","handle":"@lakecomovillas.it"}},
                   {"deleted":{"object":"company","id":"c1","title":"Lake Como Villas"}}]}]
        """#
        let decoded = try JSONDecoder().decode([RecentAction].self, from: Data(old.utf8))
        XCTAssertEqual(decoded.count, 1)
        XCTAssertEqual(decoded[0].items, [.blocked(id: "b1", handle: "@lakecomovillas.it"),
                                          .deleted(object: "company", id: "c1", title: "Lake Como Villas")])
        XCTAssertTrue(decoded[0].hasDeletes)
        XCTAssertFalse(decoded[0].isPendingUpdate)
        XCTAssertTrue(decoded[0].isExpired) // 2025, so long gone
        XCTAssertEqual(RecentAction.decodeList(Data(old.utf8)), decoded)
    }

    func testUnknownKindsAreSkippedNotFatal() {
        let mixed = #"""
        [{"id":"6F9619FF-8B86-D011-B42D-00CF4FC964FF","date":0,"items":[{"somethingNew":{"x":1}}]},
         {"id":"7F9619FF-8B86-D011-B42D-00CF4FC964FF","date":0,"items":[{"deleted":{"object":"person","id":"p","title":"Ada"}}]}]
        """#
        XCTAssertEqual(RecentAction.decodeList(Data(mixed.utf8)).map(\.summary), ["Deleted Ada"])
        XCTAssertEqual(RecentAction.decodeList(Data("garbage".utf8)), [])
    }

    func testPendingUpdatesNeverExpireAndRoundTrip() throws {
        let changes = [
            PendingChange(field: "domainName", label: "Website", summary: "aberdeenplc.com",
                          value: ["primaryLinkUrl": "https://aberdeenplc.com", "primaryLinkLabel": "", "secondaryLinks": []]),
            PendingChange(field: "accountOwner", label: "Account Owner", summary: "Raphaelle", value: .string(jake)),
            PendingChange(field: "tag", label: "Type", summary: "Institutional", value: "INSTITUTIONAL"),
            PendingChange(field: "companyType", label: "Company type", summary: "Asset Manger", value: ["ASSET_MANGER"]),
        ]
        let action = RecentAction(date: Date().addingTimeInterval(-30 * 24 * 3600),
                                  items: [.pendingUpdate(object: "company", id: "c1", title: "Aberdeenplc", changes: changes)])
        XCTAssertTrue(action.isPendingUpdate)
        XCTAssertFalse(action.isExpired)
        XCTAssertFalse(action.hasDeletes)
        XCTAssertEqual(action.summary, "Claude's guess for Aberdeenplc: website, owner, type, company type")
        let decoded = RecentAction.decodeList(try JSONEncoder().encode([action]))
        XCTAssertEqual(decoded, [action])

        // Deletes still expire after a day.
        let delete = RecentAction(date: Date().addingTimeInterval(-25 * 3600), items: [.deleted(object: "company", id: "c", title: "X")])
        XCTAssertTrue(delete.isExpired)
    }

    // MARK: Declines

    func testDeclinesPersistPerWorkspace() throws {
        let suite = "ClaudeGuessesTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = GuessDeclineStore(workspaceKey: "https://api.twenty.com|https://tokenisedgbp.twenty.com", defaults: defaults)
        XCTAssertEqual(store.load(), [])
        store.save(["c1|tag|DEFI", "c1|note|Duplicate"])
        XCTAssertEqual(GuessDeclineStore(workspaceKey: "https://api.twenty.com|https://tokenisedgbp.twenty.com", defaults: defaults).load(),
                       ["c1|tag|DEFI", "c1|note|Duplicate"])
        XCTAssertEqual(GuessDeclineStore(workspaceKey: "demo", defaults: defaults).load(), [])
        XCTAssertEqual(store.key, "claudeGuessDeclines.https://api.twenty.com|https://tokenisedgbp.twenty.com")
    }

    // MARK: Suggested deletes

    func testSuggestDeleteFromFlagOrNote() throws {
        let entry = { (json: String) in try ClaudeGuesses.parse(Data("{\"version\":1,\"companies\":[\(json)]}".utf8)).entries.first }
        XCTAssertEqual(try entry(#"{"id":"a","note":"Inbox noise: airline emails. Delete it"}"#)?.suggestDelete, true)
        XCTAssertEqual(try entry(#"{"id":"a","note":"Inbox noise: Doodle. Probably delete"}"#)?.suggestDelete, true)
        XCTAssertEqual(try entry(#"{"id":"a","note":"Duplicate: consider merging"}"#)?.suggestDelete, false)
        XCTAssertEqual(try entry(#"{"id":"a","note":"Deleted-looking but fine"}"#)?.suggestDelete, false) // whole word only
        XCTAssertEqual(try entry(#"{"id":"a","note":"Probably delete","suggestDelete":false}"#)?.suggestDelete, false) // the flag wins
        XCTAssertEqual(try entry(#"{"id":"a","suggestDelete":true}"#)?.suggestDelete, true)
        // Demo: Inkwell Sign's card offers it.
        XCTAssertEqual(try card(inkwell, in: cards()).suggestsDelete, true)
        XCTAssertEqual(try card(atlas, in: cards()).suggestsDelete, false)
    }

    // MARK: Skips

    func testSkippedCardsGoLastOldestSkipFirst() throws {
        let deck = try cards()
        let ids = deck.map(\.id)
        XCTAssertEqual(ClaudeGuesses.skippedLast(deck, skips: [:]).map(\.id), ids)

        let now = Date()
        let skips = [ids[0]: now, ids[2]: now.addingTimeInterval(-60)]
        let ordered = ClaudeGuesses.skippedLast(deck, skips: skips).map(\.id)
        XCTAssertEqual(ordered.suffix(2), [ids[2], ids[0]]) // skipped a minute ago, then just now
        XCTAssertEqual(Array(ordered.prefix(ids.count - 2)), ids.filter { skips[$0] == nil })
        // A skip for a company that's no longer in the deck changes nothing.
        XCTAssertEqual(ClaudeGuesses.skippedLast(deck, skips: ["gone": now]).map(\.id), ids)
    }

    func testSkipsPersistPerWorkspace() throws {
        let suite = "ClaudeGuessesTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let when = Date(timeIntervalSince1970: 1_790_000_000)
        GuessSkipStore(workspaceKey: "live", defaults: defaults).save(["c1": when])
        XCTAssertEqual(GuessSkipStore(workspaceKey: "live", defaults: defaults).load(), ["c1": when])
        XCTAssertEqual(GuessSkipStore(workspaceKey: "demo", defaults: defaults).load(), [:])
    }
}
#endif
