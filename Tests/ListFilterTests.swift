import XCTest
@testable import TwentyCRM

final class ListFilterTests: XCTestCase {
    private func company() throws -> ObjectMetadata {
        let objects = try LiveTwentyService.decodeObjects(Data(DemoData.metadataJSON.utf8))
        return try XCTUnwrap(objects.first { $0.nameSingular == "company" })
    }

    private let me = "m0000000-0000-4000-8000-000000000001"
    private let sam = "m0000000-0000-4000-8000-000000000002"

    func testFilterableFieldsPutTierAndOwnerFirst() throws {
        let names = try company().filterableFields.map(\.name)
        XCTAssertEqual(Array(names.prefix(2)), ["tier", "accountOwner"])
        XCTAssertTrue(names.contains("sectors"))
    }

    func testEmptyFilterSendsNothing() throws {
        XCTAssertNil(ListFilter().restClause(for: try company(), currentMemberID: me))
    }

    func testOneFieldIsAnInList() throws {
        var filter = ListFilter()
        filter.toggle("TIER_2", in: "tier")
        filter.toggle("TIER_1", in: "tier")
        XCTAssertEqual(filter.restClause(for: try company(), currentMemberID: nil), #"tier[in]:["TIER_1","TIER_2"]"#)
    }

    func testFieldsStackWithAndAndNoneIsNull() throws {
        var filter = ListFilter()
        filter.toggle("TIER_1", in: "tier")
        filter.toggle(ListFilter.none, in: "tier")
        filter.toggle(ListFilter.me, in: "accountOwner")
        filter.toggle(sam, in: "accountOwner")
        XCTAssertEqual(
            filter.restClause(for: try company(), currentMemberID: me),
            #"and(or(tier[in]:["TIER_1"],tier[is]:NULL),accountOwnerId[in]:[\#(me),\#(sam)])"#
        )
    }

    func testMultiSelectUsesContainsAny() throws {
        var filter = ListFilter()
        filter.toggle("DEFI", in: "sectors")
        XCTAssertEqual(filter.restClause(for: try company(), currentMemberID: nil), #"sectors[containsAny]:["DEFI"]"#)
    }

    func testStaleOptionsAndUnresolvedMeAreDropped() throws {
        var filter = ListFilter()
        filter.toggle("TIER_GONE", in: "tier")
        filter.toggle(ListFilter.me, in: "accountOwner")
        // An API key has no "me" and TIER_GONE was deleted from the workspace.
        XCTAssertNil(filter.restClause(for: try company(), currentMemberID: nil))
    }

    func testSearchAndFiltersCombine() {
        XCTAssertEqual(LiveTwentyService.combine("name[ilike]:\"%a%\"", #"tier[in]:["TIER_1"]"#),
                       #"and(name[ilike]:"%a%",tier[in]:["TIER_1"])"#)
        XCTAssertEqual(LiveTwentyService.combine(nil, "x[is]:NULL"), "x[is]:NULL")
        XCTAssertNil(LiveTwentyService.combine(nil, nil))
    }

    func testMatchesInMemoryLikeTheServer() throws {
        let object = try company()
        let rows = DemoData.records()["companies"] ?? []
        var filter = ListFilter()
        filter.toggle("TIER_1", in: "tier")
        filter.toggle(ListFilter.none, in: "tier")
        XCTAssertEqual(rows.filter { filter.matches($0, object: object, currentMemberID: me) }.map { $0.title(in: object) },
                       ["Northwind Exchange", "Lumen Payments"])
        filter.toggle(ListFilter.me, in: "accountOwner")
        XCTAssertEqual(rows.filter { filter.matches($0, object: object, currentMemberID: me) }.map { $0.title(in: object) },
                       ["Northwind Exchange"])
    }

    func testRoundTripsThroughJSONForPersistence() throws {
        var filter = ListFilter()
        filter.toggle("TIER_1", in: "tier")
        filter.toggle(ListFilter.me, in: "accountOwner")
        let saved = try JSONEncoder().encode(["company": filter])
        XCTAssertEqual(try JSONDecoder().decode([String: ListFilter].self, from: saved)["company"], filter)
    }
}

final class DeleteTests: XCTestCase {
    private func objects() throws -> [ObjectMetadata] { try LiveTwentyService.decodeObjects(Data(DemoData.metadataJSON.utf8)) }

    func testBlocksCompanyWebsiteDomain() throws {
        let company = try XCTUnwrap(objects().first { $0.nameSingular == "company" })
        let record = Record(id: "c", values: ["domainName": ["primaryLinkUrl": "https://www.LakeComoVillas.it/book?x=1"]])
        XCTAssertEqual(record.importBlockHandle(in: company), "@lakecomovillas.it")
        XCTAssertNil(Record(id: "c", values: [:]).importBlockHandle(in: company))
    }

    func testBlocksPersonDomainButExactWebmailAddress() throws {
        let person = try XCTUnwrap(objects().first { $0.nameSingular == "person" })
        let booking = Record(id: "p", values: ["emails": ["primaryEmail": "Reservations@LakeComoVillas.it"]])
        XCTAssertEqual(booking.importBlockHandle(in: person), "@lakecomovillas.it")
        let gmail = Record(id: "p", values: ["emails": ["primaryEmail": "someone@gmail.com"]])
        XCTAssertEqual(gmail.importBlockHandle(in: person), "someone@gmail.com")
    }
}

final class RecentActionTests: XCTestCase {
    func testSummaryNamesTheRecordPeopleAndBlock() {
        let action = RecentAction(items: [
            .blocked(id: "b", handle: "@lakecomovillas.it"),
            .deleted(object: "person", id: "p1", title: "Front Desk"),
            .deleted(object: "person", id: "p2", title: "Concierge"),
            .deleted(object: "company", id: "c", title: "Lake Como Villas"),
        ])
        XCTAssertEqual(action.summary, "Deleted Lake Como Villas and 2 people · blocked @lakecomovillas.it")
    }

    func testExpiresAfterADayAndRoundTrips() throws {
        let old = RecentAction(date: Date().addingTimeInterval(-25 * 3600), items: [.deleted(object: "company", id: "c", title: "X")])
        XCTAssertTrue(old.isExpired)
        let fresh = RecentAction(items: [.deleted(object: "company", id: "c", title: "X")])
        XCTAssertFalse(fresh.isExpired)
        let decoded = try JSONDecoder().decode([RecentAction].self, from: JSONEncoder().encode([fresh]))
        XCTAssertEqual(decoded, [fresh])
    }
}

final class PointOfContactTests: XCTestCase {
    private func objects() throws -> [ObjectMetadata] {
        AppModel.withInferences(try LiveTwentyService.decodeObjects(Data(DemoData.metadataJSON.utf8)))
    }
    private let jake = "m0000000-0000-4000-8000-000000000001"
    private let sam = "m0000000-0000-4000-8000-000000000002"

    func testPeopleInferFromCompanyOwnerThenCreator() throws {
        let person = try XCTUnwrap(objects().first { $0.nameSingular == "person" })
        let sources = try XCTUnwrap(person.pointOfContact)
        XCTAssertEqual(sources.companyOwnerJoinColumn, "accountOwnerId")
        XCTAssertTrue(sources.usesCreatedBy)
        XCTAssertEqual(person.filterableFields.first?.name, PointOfContactSources.fieldName)
        // Companies have a real owner field, so nothing is inferred for them.
        XCTAssertNil(try objects().first { $0.nameSingular == "company" }?.pointOfContact)

        let added = Record(id: "p", values: ["createdBy": ["workspaceMemberId": .string(sam)]])
        XCTAssertEqual(sources.memberID(for: added, companyOwnerID: jake)?.id, jake)   // company owner wins
        XCTAssertEqual(sources.memberID(for: added, companyOwnerID: nil)?.id, sam)     // else who added them
    }

    func testFilterClauseReachesThroughTheCompany() throws {
        let person = try XCTUnwrap(objects().first { $0.nameSingular == "person" })
        var filter = ListFilter()
        filter.toggle(ListFilter.me, in: PointOfContactSources.fieldName)
        XCTAssertEqual(
            filter.restClause(for: person, currentMemberID: jake),
            "or(company.accountOwnerId[in]:[\(jake)],and(or(companyId[is]:NULL,company.accountOwnerId[is]:NULL),createdBy.workspaceMemberId[in]:[\(jake)]))"
        )
        var none = ListFilter()
        none.toggle(ListFilter.none, in: PointOfContactSources.fieldName)
        XCTAssertEqual(none.restClause(for: person, currentMemberID: jake),
                       "and(or(companyId[is]:NULL,company.accountOwnerId[is]:NULL),createdBy.workspaceMemberId[is]:NULL)")
    }
}

final class HiddenFilterFieldTests: XCTestCase {
    func testSubteamIsNotAPeopleFilter() {
        func field(_ name: String, _ label: String) -> FieldMetadata {
            FieldMetadata(id: name, type: .select, name: name, label: label, description: nil, icon: nil, isNullable: true,
                          isActive: true, isSystem: false, isUIEditable: true, isUIReadOnly: false, writability: "OPEN",
                          options: nil, settings: nil, relation: nil)
        }
        XCTAssertTrue(ObjectMetadata.isHiddenFromFilters(field("subTeam", "Subteam"), in: "person"))
        XCTAssertTrue(ObjectMetadata.isHiddenFromFilters(field("team2", "Sub team"), in: "person"))
        XCTAssertFalse(ObjectMetadata.isHiddenFromFilters(field("subTeam", "Subteam"), in: "company"))
        XCTAssertFalse(ObjectMetadata.isHiddenFromFilters(field("tags", "Tags"), in: "person"))
    }
}
