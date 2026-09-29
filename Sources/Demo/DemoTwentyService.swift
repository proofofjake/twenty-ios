import Foundation

/// In-memory workspace with Twenty-shaped sample data, for trying the app
/// (and UI testing) without a server. Metadata is decoded from the same JSON
/// shape the real `/rest/metadata/objects` endpoint returns.
actor DemoTwentyService: TwentyService {
    private var store: [String: [Record]] = [:]
    private let objects: [ObjectMetadata]

    init() {
        objects = (try? LiveTwentyService.decodeObjects(Data(DemoData.metadataJSON.utf8))) ?? []
        store = DemoData.records()
    }

    func fetchObjects() async throws -> [ObjectMetadata] { objects }

    func fetchRecords(_ object: ObjectMetadata, search: String, after cursor: String?) async throws -> RecordPage {
        var all = store[object.namePlural] ?? []
        let query = search.trimmingCharacters(in: .whitespaces)
        if !query.isEmpty { all = all.filter { $0.title(in: object).localizedCaseInsensitiveContains(query) } }
        all.sort { $0.title(in: object).localizedCaseInsensitiveCompare($1.title(in: object)) == .orderedAscending }
        // Like the live list (depth=0): no expanded relations.
        return RecordPage(records: all, hasNextPage: false, endCursor: nil, totalCount: all.count)
    }

    func fetchRecords(_ object: ObjectMetadata, ids: [String]) async throws -> [Record] {
        (store[object.namePlural] ?? []).filter { ids.contains($0.id) }
    }

    func fetchRecord(_ object: ObjectMetadata, id: String) async throws -> Record {
        guard let record = store[object.namePlural]?.first(where: { $0.id == id }) else { throw TwentyError(message: "Not found") }
        return expand(record, object: object)
    }

    func updateRecord(_ object: ObjectMetadata, id: String, patch: [String: JSONValue]) async throws -> Record {
        guard var records = store[object.namePlural], let index = records.firstIndex(where: { $0.id == id }) else {
            throw TwentyError(message: "Not found")
        }
        for (key, value) in patch { records[index].values[key] = value }
        records[index].values["updatedAt"] = .string(FieldFormatter.dateTimeString(Date()))
        store[object.namePlural] = records
        return records[index]
    }

    func createRecord(_ object: ObjectMetadata, values: [String: JSONValue]) async throws -> Record {
        let id = UUID().uuidString.lowercased()
        var record = Record(id: id, values: values)
        let now = JSONValue.string(FieldFormatter.dateTimeString(Date()))
        record.values["id"] = .string(id)
        record.values["createdAt"] = now
        record.values["updatedAt"] = now
        store[object.namePlural, default: []].append(record)
        return expand(record, object: object)
    }

    func fetchCurrentMember() async throws -> Record? { nil }

    /// Mimics `depth=1`: expands many-to-one relations from their foreign key.
    private func expand(_ record: Record, object: ObjectMetadata) -> Record {
        var copy = record
        for field in object.fields where field.type == .relation && field.relationType == .manyToOne {
            guard let target = field.relation?.targetObjectMetadata,
                  let id = record[field.joinColumnName].stringValue,
                  let related = store[target.namePlural]?.first(where: { $0.id == id }) else {
                copy[field.name] = .null
                continue
            }
            copy[field.name] = .object(related.values)
        }
        for field in object.fields where field.type == .relation && field.relationType == .oneToMany {
            guard let target = field.relation?.targetObjectMetadata,
                  let inverse = field.relation?.targetFieldMetadata?.name else { continue }
            let related = (store[target.namePlural] ?? []).filter { $0["\(inverse)Id"].stringValue == record.id }
            copy[field.name] = .array(related.map { .object($0.values) })
        }
        return copy
    }
}
