#if DEBUG
import XCTest
@testable import TwentyCRM

/// Claude's merge suggestions (Debug only): reading them, the merge window's
/// rows and defaults, what's staged, and the demo service's merge.
final class ClaudeMergesTests: XCTestCase {
    private let cobalt = "c0000000-0000-4000-8000-000000000006"
    private let cobaltLtd = "c0000000-0000-4000-8000-000000000008"
    private let northwind = "c0000000-0000-4000-8000-000000000001"
    private let gus = "p0000000-0000-4000-8000-000000000007"
    private let sam = "m0000000-0000-4000-8000-000000000002"
    private let jake = "m0000000-0000-4000-8000-000000000001"

    private func objects() throws -> [ObjectMetadata] { try LiveTwentyService.decodeObjects(Data(DemoData.metadataJSON.utf8)) }
    private func company() throws -> ObjectMetadata { try XCTUnwrap(objects().first { $0.nameSingular == "company" }) }
    private func file() throws -> ClaudeGuesses.File { try ClaudeGuesses.parse(Data(DemoData.guessesJSON.utf8)) }
    private func companies() -> [Record] { DemoData.records()["companies"] ?? [] }
    private func record(_ id: String) throws -> Record { try XCTUnwrap(companies().first { $0.id == id }) }

    private func cards(merges: [ClaudeGuesses.Merge]? = nil, records: [Record]? = nil, declined: Set<String> = [],
                       staged: Set<String> = [], stagedMerges: Set<String> = []) throws -> [ClaudeGuesses.Card] {
        let all = DemoData.records()
        return ClaudeGuesses.cards(for: try file().entries, records: records ?? companies(), object: try company(),
                                   members: all["workspaceMembers"] ?? [], memberObject: try objects().first { $0.nameSingular == "workspaceMember" },
                                   declined: declined, staged: staged, merges: try merges ?? file().merges, stagedMerges: stagedMerges)
    }

    private func rows(_ records: [Record], picks: [String: ClaudeGuesses.FieldPick]? = nil) throws -> [ClaudeGuesses.MergeRow] {
        let all = DemoData.records()
        return ClaudeGuesses.mergeRows(records: records, object: try company(), picks: try picks ?? XCTUnwrap(file().merges.first).fields,
                                       members: all["workspaceMembers"] ?? [], memberObject: try objects().first { $0.nameSingular == "workspaceMember" })
    }

    // MARK: Parsing

    func testParsesMergesAndSkipsBadOnes() throws {
        let merges = try file().merges
        // The non-string id and the empty merge are skipped; the unknown company is checked later.
        XCTAssertEqual(merges.map(\.keep), [cobalt, northwind])
        let first = merges[0]
        XCTAssertEqual(first.merge, [cobaltLtd])
        XCTAssertEqual(first.ids, [cobalt, cobaltLtd])
        XCTAssertEqual(first.confidence, .high)
        XCTAssertEqual(Set(first.fields.keys), ["name", "domainName", "address", "companyType"]) // tier's pick names an outsider
        XCTAssertEqual(first.fields["domainName"], ClaudeGuesses.FieldPick(from: cobaltLtd, reason: "Only this one has a website"))
        XCTAssertEqual(first.key, "merge|\(cobalt),\(cobaltLtd)")
        XCTAssertEqual(ClaudeGuesses.mergeKey([cobaltLtd, cobalt.uppercased()]), first.key) // order and case don't matter

        let json = #"""
        {"companies":[],"merges":[
          {"keep":"A","merge":"B","fields":{"name":"b","notes":{"from":"z"}}},
          {"keep":"A","merge":["A","C","C"]},
          {"merge":["B"]},
          {"keep":"A","merge":["B",null]},
          {"keep":"A","merge":["1","2","3","4","5","6","7","8","9"]},
          {"keep":"A","merge":["1","2","3","4","5","6","7","8"]},
          "nope"
        ]}
        """#
        let parsed = try ClaudeGuesses.parse(Data(json.utf8)).merges
        XCTAssertEqual(parsed.map(\.ids), [["a", "b"], ["a", "c"], ["a", "1", "2", "3", "4", "5", "6", "7", "8"]]) // 9 ids at most
        XCTAssertEqual(parsed[0].fields, ["name": ClaudeGuesses.FieldPick(from: "b", reason: nil)])
        XCTAssertTrue(try ClaudeGuesses.parse(Data(#"{"companies":[]}"#.utf8)).merges.isEmpty)
    }

    // MARK: On the deck

    func testCobaltsCardOffersTheMerge() throws {
        let deck = try cards()
        // No new cards: Cobalt already has one, and the unknown company spoils Northwind's merge.
        XCTAssertEqual(deck.count, 6)
        let card = try XCTUnwrap(deck.first { $0.id == cobalt })
        XCTAssertEqual(card.merge?.key, ClaudeGuesses.mergeKey([cobalt, cobaltLtd]))
        XCTAssertEqual(card.merge?.others(than: cobalt), "Cobalt Custody Ltd")
        XCTAssertEqual(card.merge?.others(than: cobaltLtd), "Cobalt Custody")
        XCTAssertNil(deck.first { $0.id == northwind }?.merge)

        // Dismissed ("Not duplicates"), staged, or a company gone: no merge.
        let key = ClaudeGuesses.mergeKey([cobalt, cobaltLtd])
        XCTAssertNil(try cards(declined: [key]).first { $0.id == cobalt }?.merge)
        XCTAssertNil(try cards(stagedMerges: [key]).first { $0.id == cobalt }?.merge)
        XCTAssertNil(try cards(records: companies().filter { $0.id != cobaltLtd }).first { $0.id == cobalt }?.merge)
    }

    func testMergeAddsACardForAKeepWithout() throws {
        var records = companies()
        records.append(Record(id: "x1", values: ["id": "x1", "name": "Cobalt Custody (old)"]))
        let merge = try XCTUnwrap(ClaudeGuesses.merge(["keep": .string(cobaltLtd), "merge": ["x1"]]))
        let deck = try cards(merges: [merge], records: records)
        XCTAssertEqual(deck.count, 7)
        let card = try XCTUnwrap(deck.last)
        XCTAssertEqual(card.id, cobaltLtd)
        XCTAssertEqual(card.merge?.others(than: cobaltLtd), "Cobalt Custody (old)")
        XCTAssertTrue(card.suggestions.isEmpty)
        XCTAssertNil(card.note)
        // Not if the keep's merge is staged, or the keep has a staged update.
        XCTAssertEqual(try cards(merges: [merge], records: records, stagedMerges: [merge.key]).count, 6)
        XCTAssertEqual(try cards(merges: [merge], records: records, staged: [cobaltLtd]).count, 6)
    }

    // MARK: The merge window

    func testRowsDefaultsAndOverrides() throws {
        let records = [try record(cobalt), try record(cobaltLtd)]
        let rows = try rows(records)
        // Equal (tier, sectors) and empty-everywhere (tag, ARR) fields are left out.
        XCTAssertEqual(rows.map(\.id), ["name", "domainName", "employees", "address", "accountOwner", "companyType"])
        let kinds = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0.kind) })
        XCTAssertEqual(kinds, ["name": .choice, "domainName": .primary, "employees": .choice, "address": .choice,
                               "accountOwner": .choice, "companyType": .combined])
        let row = { (name: String) in try XCTUnwrap(rows.first { $0.id == name }) }
        XCTAssertEqual(try row("accountOwner").values.map(\.display), ["Sam Rivera", ""])
        XCTAssertEqual(try row("address").values.map(\.display), ["Edinburgh, United Kingdom", "20 Gresham St, London, EC2V 7JE, United Kingdom"])

        // Claude's pick where given; else the survivor's value if it has one, else the other's.
        func defaults(survivor: String, in rows: [ClaudeGuesses.MergeRow]) -> [String: String] {
            rows.reduce(into: [:]) { $0[$1.id] = ClaudeGuesses.defaultChoice(for: $1, survivor: survivor) }
        }
        XCTAssertEqual(defaults(survivor: cobalt, in: rows),
                       ["name": cobaltLtd, "domainName": cobaltLtd, "employees": cobaltLtd, "address": cobaltLtd, "accountOwner": cobalt])
        let unpicked = try self.rows(records, picks: [:])
        XCTAssertEqual(defaults(survivor: cobalt, in: unpicked),
                       ["name": cobalt, "domainName": cobaltLtd, "employees": cobaltLtd, "address": cobalt, "accountOwner": cobalt])
        XCTAssertEqual(defaults(survivor: cobaltLtd, in: unpicked),
                       ["name": cobaltLtd, "domainName": cobaltLtd, "employees": cobaltLtd, "address": cobaltLtd, "accountOwner": cobalt])

        // Overrides: only what Twenty wouldn't keep by itself (the website and
        // employees come over anyway; Sam stays owner).
        let overrides = ClaudeGuesses.mergeOverrides(rows: rows, selection: [:], records: records, survivor: cobalt)
        XCTAssertEqual(overrides.map(\.field), ["name", "address"])
        XCTAssertEqual(overrides[0].value, "Cobalt Custody Ltd")
        XCTAssertEqual(overrides[0].previous, "Cobalt Custody")
        XCTAssertEqual(overrides[1].value, try record(cobaltLtd)["address"])
        XCTAssertEqual(overrides[1].summary, "20 Gresham St, London, EC2V 7JE, United Kingdom")
        // Picking the survivor's own name back drops that override.
        XCTAssertEqual(ClaudeGuesses.mergeOverrides(rows: rows, selection: ["name": cobalt], records: records, survivor: cobalt).map(\.field), ["address"])
        // Keeping Cobalt Custody Ltd: Twenty would bring Sam over as owner by itself.
        XCTAssertTrue(ClaudeGuesses.mergeOverrides(rows: unpicked, selection: [:], records: records, survivor: cobaltLtd).isEmpty)
        // If it has an owner of its own, keeping Sam is an override, written through the join column.
        var ltd = try record(cobaltLtd)
        ltd["accountOwnerId"] = .string(jake)
        let owned = [try record(cobalt), ltd]
        let ownerRows = try self.rows(owned, picks: [:])
        XCTAssertTrue(ClaudeGuesses.mergeOverrides(rows: ownerRows, selection: [:], records: owned, survivor: cobaltLtd).isEmpty)
        let flipped = ClaudeGuesses.mergeOverrides(rows: ownerRows, selection: ["accountOwner": cobalt], records: owned, survivor: cobaltLtd)
        XCTAssertEqual(flipped.map(\.field), ["accountOwner"])
        XCTAssertEqual(flipped[0].value, .string(sam))
        XCTAssertEqual(flipped[0].previous, "Jake Demo")
        let all = DemoData.records()
        let (patch, skipped) = ClaudeGuesses.mergePatch(for: flipped, survivor: ltd, object: try company(), members: all["workspaceMembers"] ?? [],
                                                        memberObject: try objects().first { $0.nameSingular == "workspaceMember" })
        XCTAssertEqual(patch, ["accountOwnerId": .string(sam)]) // through the join column
        XCTAssertTrue(skipped.isEmpty)
    }

    func testMultiSelectIsCombined() throws {
        var a = try record(cobalt), b = try record(cobaltLtd)
        a["companyType"] = ["CUSTODIAN", "EXCHANGE"]
        b["companyType"] = ["EXCHANGE", "MERCH"]
        let row = try XCTUnwrap(try rows([a, b]).first { $0.id == "companyType" })
        XCTAssertEqual(row.kind, .combined)
        XCTAssertEqual(row.combined?.chips, ["Custodian", "Exchange", "merch"])
        XCTAssertNil(ClaudeGuesses.defaultChoice(for: row, survivor: cobalt))
        XCTAssertFalse(ClaudeGuesses.mergeOverrides(rows: [row], selection: ["companyType": cobaltLtd], records: [a, b], survivor: cobalt)
            .contains { $0.field == "companyType" })
        XCTAssertEqual(TwentyMerge.merged([a, b], priorityID: cobalt, object: try company())["companyType"], ["CUSTODIAN", "EXCHANGE", "MERCH"])
    }

    func testLinksPrimaryOverrideKeepsEveryLink() throws {
        let object = try company()
        var a = try record(cobalt), b = try record(cobaltLtd)
        a["domainName"] = ["primaryLinkUrl": "https://cobalt.example", "primaryLinkLabel": "", "secondaryLinks": [["url": "https://cobalt.example/blog", "label": ""]]]
        b["domainName"] = ["primaryLinkUrl": "https://cobaltcustody.example", "primaryLinkLabel": "", "secondaryLinks": []]
        let row = try XCTUnwrap(try rows([a, b]).first { $0.id == "domainName" })
        XCTAssertEqual(row.kind, .primary)
        XCTAssertEqual(row.values.map(\.display), ["https://cobalt.example", "https://cobaltcustody.example"])
        XCTAssertEqual(ClaudeGuesses.defaultChoice(for: row, survivor: cobalt), cobaltLtd) // Claude's pick

        let override = try XCTUnwrap(ClaudeGuesses.mergeOverrides(rows: [row], selection: [:], records: [a, b], survivor: cobalt).first)
        XCTAssertEqual(override.value, ["primaryLinkUrl": "https://cobaltcustody.example", "primaryLinkLabel": "",
                                        "secondaryLinks": [["url": "https://cobalt.example", "label": ""], ["url": "https://cobalt.example/blog", "label": ""]]])
        // Then Twenty's merge keeps that primary and drops the duplicate.
        a["domainName"] = override.value
        XCTAssertEqual(TwentyMerge.merged([a, b], priorityID: cobalt, object: object)["domainName"]?["secondaryLinks"]?.arrayValue?.count, 2)
        // Without the override, the survivor's primary wins and the other's becomes secondary.
        a["domainName"] = ["primaryLinkUrl": "https://cobalt.example", "primaryLinkLabel": "", "secondaryLinks": []]
        XCTAssertEqual(TwentyMerge.merged([a, b], priorityID: cobalt, object: object)["domainName"],
                       ["primaryLinkUrl": "https://cobalt.example", "primaryLinkLabel": "", "secondaryLinks": [["url": "https://cobaltcustody.example", "label": ""]]])
    }

    func testTwentysIdeaOfAValueDecidesTheOverride() throws {
        // A currency code with no amount counts as a value to Twenty, so it
        // would keep the survivor's empty ARR; picking the other's needs a PATCH.
        var a = try record(cobalt), b = try record(cobaltLtd)
        a["annualRecurringRevenue"] = ["amountMicros": nil, "currencyCode": "GBP"]
        b["annualRecurringRevenue"] = ["amountMicros": 2_000_000_000_000, "currencyCode": "GBP"]
        let row = try XCTUnwrap(try rows([a, b], picks: [:]).first { $0.id == "annualRecurringRevenue" })
        XCTAssertEqual(ClaudeGuesses.defaultChoice(for: row, survivor: cobalt), cobaltLtd)
        XCTAssertEqual(ClaudeGuesses.twentyChoice(for: row, survivor: cobalt), cobalt)
        XCTAssertEqual(ClaudeGuesses.mergeOverrides(rows: [row], selection: [:], records: [a, b], survivor: cobalt).map(\.field), ["annualRecurringRevenue"])
        XCTAssertTrue(TwentyMerge.hasValue(["amountMicros": nil, "currencyCode": "GBP"]))
        XCTAssertFalse(TwentyMerge.hasValue(["addressStreet1": "", "addressCity": " "]))
        XCTAssertTrue(TwentyMerge.hasValue(false))
    }

    func testApplySkipsOverridesChangedSinceStaging() throws {
        let object = try company()
        let records = [try record(cobalt), try record(cobaltLtd)]
        let overrides = ClaudeGuesses.mergeOverrides(rows: try rows(records), selection: [:], records: records, survivor: cobalt)
        var now = records[0]
        now["address"] = ["addressCity": "Glasgow", "addressCountry": "United Kingdom"]
        let (patch, skipped) = ClaudeGuesses.mergePatch(for: overrides, survivor: now, object: object)
        XCTAssertEqual(Set(patch.keys), ["name"])
        XCTAssertEqual(skipped.map(\.message), ["Skipped address: changed since you staged it"])
    }

    func testMoves() throws {
        let objects = try objects()
        let ltd = Record(id: cobaltLtd, values: ["people": [["id": "p1"], ["id": "p2"]]])
        XCTAssertEqual(ClaudeGuesses.moves(from: [ltd], object: try company(), objects: objects), "2 people")
        XCTAssertEqual(ClaudeGuesses.moves(from: [Record(id: cobaltLtd, values: ["people": [["id": "p1"]]])], object: try company(), objects: objects), "1 person")
        XCTAssertNil(ClaudeGuesses.moves(from: [Record(id: cobaltLtd, values: [:])], object: try company(), objects: objects))
    }

    // MARK: Recent actions

    private func pendingMerge() -> PendingMerge {
        PendingMerge(object: "company", keepID: cobalt, keepTitle: "Cobalt Custody", mergeIDs: [cobaltLtd], mergeTitles: ["Cobalt Custody Ltd"],
                     overrides: [PendingChange(field: "address", label: "Address", summary: "20 Gresham St", value: ["addressCity": "London"], previous: "Edinburgh")])
    }

    func testPendingMergeRoundTripsAndNeverExpires() throws {
        let action = RecentAction(date: Date().addingTimeInterval(-60 * 24 * 3600), items: [.pendingMerge(merge: pendingMerge())])
        XCTAssertTrue(action.isPendingMerge)
        XCTAssertFalse(action.isPendingUpdate) // so "Apply all guesses" leaves it out
        XCTAssertFalse(action.hasDeletes)
        XCTAssertFalse(action.isExpired)
        XCTAssertEqual(action.summary, "Merge Cobalt Custody Ltd into Cobalt Custody (Claude's suggestion)")
        XCTAssertEqual(action.pendingMerge?.ids, [cobalt, cobaltLtd])
        XCTAssertEqual(RecentAction.decodeList(try JSONEncoder().encode([action])), [action])
    }

    func testOldSavedActionsStillDecode() throws {
        // A staged update saved before `previous` existed, and an action with
        // a kind this build doesn't know next to one it does.
        let old = #"""
        [{"id":"6F9619FF-8B86-D011-B42D-00CF4FC964FF","date":800000000,
          "items":[{"pendingUpdate":{"object":"company","id":"c1","title":"Aberdeenplc",
                    "changes":[{"field":"tag","label":"Type","summary":"Institutional","value":"INSTITUTIONAL"}]}}]},
         {"id":"7F9619FF-8B86-D011-B42D-00CF4FC964FF","date":800000000,
          "items":[{"somethingNew":{"x":1}},{"deleted":{"object":"company","id":"c2","title":"Lake Como Villas"}}]}]
        """#
        let decoded = RecentAction.decodeList(Data(old.utf8))
        XCTAssertEqual(decoded.count, 2)
        XCTAssertEqual(decoded[0].pendingUpdate?.changes.first?.value, "INSTITUTIONAL")
        XCTAssertNil(decoded[0].pendingUpdate?.changes.first?.previous)
        XCTAssertEqual(decoded[1].items, [.deleted(object: "company", id: "c2", title: "Lake Como Villas")])
    }

    // MARK: Services

    func testDemoServiceMergesLikeTwenty() async throws {
        let service = DemoTwentyService()
        let object = try company()
        let person = try XCTUnwrap(objects().first { $0.nameSingular == "person" })

        // A dry run changes nothing.
        let preview = try await service.mergeRecords(object, ids: [cobalt, cobaltLtd], conflictPriorityIndex: 0, dryRun: true)
        XCTAssertNotEqual(preview.id, cobalt)
        XCTAssertEqual(preview["domainName"]["primaryLinkUrl"], "cobaltcustody.example")
        _ = try await service.fetchRecord(object, id: cobaltLtd)

        let merged = try await service.mergeRecords(object, ids: [cobalt, cobaltLtd], conflictPriorityIndex: 0, dryRun: false)
        XCTAssertEqual(merged.id, cobalt)
        XCTAssertEqual(merged["name"], "Cobalt Custody")                                  // the survivor's
        XCTAssertEqual(merged["domainName"]["primaryLinkUrl"], "cobaltcustody.example")    // the only one
        XCTAssertEqual(merged["address"]["addressCity"], "Edinburgh")                      // the survivor's
        XCTAssertEqual(merged["employees"], 35)
        XCTAssertEqual(merged["companyType"], ["CUSTODIAN"])
        XCTAssertEqual(merged["accountOwnerId"], .string(sam))
        XCTAssertEqual(merged["people"].arrayValue?.compactMap { $0["id"]?.stringValue }, [gus])
        let moved = try await service.fetchRecord(person, id: gus)
        XCTAssertEqual(moved["companyId"], .string(cobalt))
        // Hard-deleted: gone, and not in the trash.
        await assertThrows { _ = try await service.fetchRecord(object, id: cobaltLtd) }
        await assertThrows { try await service.restoreRecord(object, id: cobaltLtd) }
        await assertThrows { _ = try await service.mergeRecords(object, ids: [cobalt], conflictPriorityIndex: 0, dryRun: false) }
    }

    func testDecodesTwentysMergeResponse() throws {
        let body = #"{"data":{"mergeCompanies":{"id":"c1","name":"Bitgo","people":[{"id":"p1"}]}}}"#
        let record = try LiveTwentyService.decodeRecord(Data(body.utf8), object: try company())
        XCTAssertEqual(record.id, "c1")
        XCTAssertEqual(record["people"].arrayValue?.count, 1)
    }

    func testMergeLogAppendsOneLinePerMerge() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "merge-log-\(UUID().uuidString).jsonl")
        defer { try? FileManager.default.removeItem(at: url) }
        try MergeLog.append(pendingMerge(), records: [try record(cobalt), try record(cobaltLtd)], to: url)
        try MergeLog.append(pendingMerge(), records: [try record(cobalt)], to: url)
        let lines = try String(contentsOf: url, encoding: .utf8).split(separator: "\n")
        XCTAssertEqual(lines.count, 2)
        let first = try JSONDecoder().decode(JSONValue.self, from: Data(lines[0].utf8))
        XCTAssertEqual(first["keepID"], .string(cobalt))
        XCTAssertEqual(first["records"]?.arrayValue?.compactMap { $0["name"]?.stringValue }, ["Cobalt Custody", "Cobalt Custody Ltd"])
    }

    private func assertThrows(_ work: () async throws -> Void, file: StaticString = #filePath, line: UInt = #line) async {
        do {
            try await work()
            XCTFail("Expected an error", file: file, line: line)
        } catch {}
    }
}
#endif
