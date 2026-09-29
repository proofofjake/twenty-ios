import XCTest
@testable import TwentyCRM

final class TwentyAPITests: XCTestCase {
    // REST metadata as returned by a v2.41 workspace with the new direct format.
    private let restMetadataDirect = #"""
    {"data":[{"id":"o1","nameSingular":"person","namePlural":"people","labelSingular":"Person","labelPlural":"People",
      "isActive":true,"isSystem":false,"labelIdentifierFieldMetadataId":"f-name",
      "fields":[
        {"id":"f-name","type":"FULL_NAME","name":"name","label":"Name","isActive":true,"isSystem":false,"isNullable":true,"writability":"OPEN"},
        {"id":"f-tags","type":"MULTI_SELECT","name":"tags","label":"Tags","isActive":true,"isSystem":false,"isNullable":true,"writability":"OPEN",
         "options":[{"id":"a","value":"VIP","label":"VIP","color":"red","position":1},{"id":"b","value":"INVESTOR","label":"Investor","color":"green","position":0}]},
        {"id":"f-rating","type":"RATING","name":"warmth","label":"Warmth","isActive":true,"isSystem":false,
         "options":[{"value":"RATING_1","label":"1","position":0}]},
        {"id":"f-co","type":"RELATION","name":"company","label":"Company","isActive":true,"isSystem":false,
         "settings":{"relationType":"MANY_TO_ONE","joinColumnName":"companyId","onDelete":"SET_NULL"}},
        {"id":"f-locked","type":"TEXT","name":"locked","label":"Locked","isActive":true,"isSystem":false,"writability":"READ_ONLY"},
        {"id":"f-created","type":"DATE_TIME","name":"createdAt","label":"Created","isActive":true,"isSystem":false,"writability":"OPEN"},
        {"id":"f-pos","type":"POSITION","name":"position","label":"Position","isActive":true,"isSystem":true}
      ]}],
     "pageInfo":{"hasNextPage":true,"endCursor":"o1"},"totalCount":2}
    """#

    private func person() throws -> ObjectMetadata {
        try XCTUnwrap(LiveTwentyService.decodeObjects(Data(restMetadataDirect.utf8)).first)
    }

    func testDecodesDirectMetadataEnvelopeAndCursor() throws {
        let page = try LiveTwentyService.decodeObjectsPage(Data(restMetadataDirect.utf8))
        XCTAssertEqual(page.objects.map(\.namePlural), ["people"])
        XCTAssertEqual(page.nextCursor, "o1")
        let object = try person()
        XCTAssertEqual(object.labelIdentifierField?.name, "name")
        XCTAssertEqual(object.field(named: "tags")?.sortedOptions.map(\.value), ["INVESTOR", "VIP"])
        XCTAssertEqual(object.field(named: "company")?.relationType, .manyToOne)
        XCTAssertEqual(object.field(named: "company")?.joinColumnName, "companyId")
    }

    func testDecodesLegacyMetadataEnvelope() throws {
        let legacy = #"{"data":{"objects":[{"id":"o2","nameSingular":"company","namePlural":"companies","labelSingular":"Company","labelPlural":"Companies","fields":[]}]},"pageInfo":{"hasNextPage":false}}"#
        let page = try LiveTwentyService.decodeObjectsPage(Data(legacy.utf8))
        XCTAssertEqual(page.objects.first?.nameSingular, "company")
        XCTAssertNil(page.nextCursor)
    }

    func testEditorKinds() throws {
        let object = try person()
        XCTAssertEqual(FieldEditorKind(field: object.field(named: "tags")!), .multiSelect)
        XCTAssertEqual(FieldEditorKind(field: object.field(named: "warmth")!), .rating)
        XCTAssertEqual(FieldEditorKind(field: object.field(named: "locked")!), .readOnly)
        XCTAssertEqual(FieldEditorKind(field: object.field(named: "createdAt")!), .readOnly)
        // REST gives no relation target, so the relation can't be picked.
        XCTAssertEqual(FieldEditorKind(field: object.field(named: "company")!), .readOnly)
    }

    func testPatchContainsOnlyChangedWritableFields() throws {
        let object = try person()
        let original = Record(id: "p1", values: [
            "id": "p1",
            "name": ["firstName": "Ada", "lastName": "Hart"],
            "tags": ["INVESTOR"],
            "locked": "x",
            "createdAt": "2026-01-01T00:00:00.000Z",
            "position": 3,
        ])
        var draft = original
        draft["tags"] = ["INVESTOR", "VIP"]
        draft["locked"] = "changed"
        draft["createdAt"] = "2020-01-01T00:00:00.000Z"
        draft["position"] = 9

        let patch = draft.changes(from: original, writable: object.writableFieldNames)
        XCTAssertEqual(patch, ["tags": ["INVESTOR", "VIP"]])

        // Multi-select goes over the wire as an array of option values, not a string.
        let json = try XCTUnwrap(String(data: JSONEncoder().encode(patch), encoding: .utf8))
        XCTAssertEqual(json, #"{"tags":["INVESTOR","VIP"]}"#)
    }

    func testDecodesListAndUpdateEnvelopes() throws {
        let object = try person()
        let list = #"{"data":{"people":[{"id":"p1","name":{"firstName":"Ada","lastName":"Hart"},"tags":["VIP"]}]},"totalCount":41,"pageInfo":{"hasNextPage":true,"startCursor":"s","endCursor":"e"}}"#
        let page = try LiveTwentyService.decodePage(Data(list.utf8), object: object)
        XCTAssertEqual(page.records.first?.title(in: object), "Ada Hart")
        XCTAssertEqual(page.endCursor, "e")
        XCTAssertEqual(page.totalCount, 41)
        XCTAssertTrue(page.hasNextPage)

        let update = #"{"data":{"updatePerson":{"id":"p1","tags":["VIP","INVESTOR"]}}}"#
        let record = try LiveTwentyService.decodeRecord(Data(update.utf8), object: object)
        XCTAssertEqual(record["tags"], ["VIP", "INVESTOR"])
    }

    func testSearchFilter() throws {
        let object = try person()
        XCTAssertEqual(object.searchFilter("ad\"a"), #"or(name.firstName[ilike]:"%ad\"a%",name.lastName[ilike]:"%ad\"a%")"#)
        XCTAssertNil(object.searchFilter("  "))
    }

    func testLargeAmountMicrosStaysIntegral() throws {
        let value: JSONValue = ["amountMicros": 4_500_000_000_000, "currencyCode": "GBP"]
        let json = try XCTUnwrap(String(data: JSONEncoder().encode(value["amountMicros"]), encoding: .utf8))
        XCTAssertEqual(json, "4500000000000")
    }

    func testErrorMessage() {
        let body = #"{"statusCode":400,"error":"BadRequestException","messages":["Invalid value 'FOO' for field tags"]}"#
        XCTAssertEqual(LiveTwentyService.errorMessage(Data(body.utf8), status: 400), "Invalid value 'FOO' for field tags")
    }
}

final class GraphQLMetadataTests: XCTestCase {
    func testDecodesGraphQLObjectsWithRelationTargets() throws {
        let body = #"""
        {"data":{"objects":{"edges":[{"node":{"id":"o1","nameSingular":"person","namePlural":"people","labelSingular":"Person","labelPlural":"People",
          "isActive":true,"isSystem":false,"isUIEditable":true,"writability":"OPEN","labelIdentifierFieldMetadataId":"f1",
          "fieldsList":[
            {"id":"f1","type":"FULL_NAME","name":"name","label":"Name","isActive":true,"isSystem":false,"isUIEditable":true,"writability":"OPEN","isNullable":true,"options":null,"settings":null,"relation":null},
            {"id":"f2","type":"RELATION","name":"company","label":"Company","isActive":true,"isSystem":false,"isUIEditable":true,"writability":"OPEN","isNullable":true,"options":null,
             "settings":{"relationType":"MANY_TO_ONE","joinColumnName":"companyId"},
             "relation":{"type":"MANY_TO_ONE","targetObjectMetadata":{"id":"o2","nameSingular":"company","namePlural":"companies"}}},
            {"id":"f3","type":"TEXT","name":"sysOwned","label":"Owned","isActive":true,"isSystem":false,"isUIEditable":false,"writability":"SYSTEM"}
          ]}}],"pageInfo":{"hasNextPage":false,"endCursor":"o1"}}}}
        """#
        let page = try LiveTwentyService.decodeGraphQLObjects(Data(body.utf8))
        XCTAssertNil(page.nextCursor)
        let person = try XCTUnwrap(page.objects.first)
        XCTAssertEqual(person.fields.count, 3)
        let company = try XCTUnwrap(person.field(named: "company"))
        XCTAssertEqual(company.relation?.targetObjectMetadata?.namePlural, "companies")
        XCTAssertEqual(FieldEditorKind(field: company), .relation)
        XCTAssertEqual(FieldEditorKind(field: person.field(named: "sysOwned")!), .readOnly)
        XCTAssertEqual(person.writableFieldNames, ["name", "companyId"])
    }

    func testGraphQLErrorsSurface() {
        let body = #"{"errors":[{"message":"Cannot query field \"fieldsList\""}],"data":null}"#
        XCTAssertThrowsError(try LiveTwentyService.decodeGraphQLObjects(Data(body.utf8))) { error in
            XCTAssertEqual(error.localizedDescription, #"Cannot query field "fieldsList""#)
        }
    }
}
