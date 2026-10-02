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

    func fetchRecords(_ object: ObjectMetadata, search: String, filter: ListFilter, memberID: String?, after cursor: String?) async throws -> RecordPage {
        let objectWithInference = AppModel.withInferences(objects).first { $0.nameSingular == object.nameSingular } ?? object
        var all = (store[object.namePlural] ?? []).map { withInferredPointOfContact($0, object: objectWithInference) }
            .filter { filter.matches($0, object: objectWithInference, currentMemberID: memberID) }
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

    /// Soft-deleted records, restorable like Twenty's trash.
    private var trash: [String: Record] = [:]

    func deleteRecord(_ object: ObjectMetadata, id: String, permanently: Bool) async throws {
        // Permanently deleting a trashed record empties it from the trash.
        if permanently, trash.removeValue(forKey: "\(object.namePlural)/\(id)") != nil { return }
        guard let record = store[object.namePlural]?.first(where: { $0.id == id }) else { throw TwentyError(message: "Not found") }
        store[object.namePlural]?.removeAll { $0.id == id }
        if !permanently { trash["\(object.namePlural)/\(id)"] = record }
    }

    func restoreRecord(_ object: ObjectMetadata, id: String) async throws {
        guard let record = trash.removeValue(forKey: "\(object.namePlural)/\(id)") else { throw TwentyError(message: "Not in the trash") }
        store[object.namePlural, default: []].append(record)
    }

    func fetchCurrentMember() async throws -> Record? { nil }

    #if DEBUG
    /// Like Twenty's: merged values (`TwentyMerge`) on the survivor, every
    /// many-to-one relation to the others re-pointed at it, and the others
    /// destroyed (not trashed). `dryRun` only returns the would-be record.
    func mergeRecords(_ object: ObjectMetadata, ids: [String], conflictPriorityIndex: Int, dryRun: Bool) async throws -> Record {
        guard (2...ClaudeGuesses.maxMergeRecords).contains(ids.count), ids.indices.contains(conflictPriorityIndex) else {
            throw TwentyError(message: "Merge 2 to \(ClaudeGuesses.maxMergeRecords) records", status: 400)
        }
        let all = store[object.namePlural] ?? []
        let records = ids.compactMap { id in all.first { $0.id == id } }
        guard records.count == ids.count else { throw TwentyError(message: "One or more records were not found.", status: 404) }
        let survivorID = ids[conflictPriorityIndex]
        var survivor = Record(id: survivorID, values: TwentyMerge.merged(records, priorityID: survivorID, object: object))
        if dryRun {
            // Twenty gives the would-be record a fresh id.
            let id = UUID().uuidString.lowercased()
            var preview = survivor.values
            preview["id"] = .string(id)
            return expand(Record(id: id, values: preview), object: object)
        }
        survivor.values["updatedAt"] = .string(FieldFormatter.dateTimeString(Date()))
        let others = Set(ids).subtracting([survivorID])
        for other in objects {
            for field in other.fields where field.type == .relation && field.relationType == .manyToOne
                && field.relation?.targetObjectMetadata?.nameSingular == object.nameSingular {
                guard var rows = store[other.namePlural] else { continue }
                for index in rows.indices where rows[index][field.joinColumnName].stringValue.map(others.contains) == true {
                    rows[index][field.joinColumnName] = .string(survivorID)
                }
                store[other.namePlural] = rows
            }
        }
        store[object.namePlural] = all.filter { !others.contains($0.id) }.map { $0.id == survivorID ? survivor : $0 }
        return expand(survivor, object: object)
    }
    #endif

    /// What the server's relation filter computes: the person's inferred point
    /// of contact, stored where `ListFilter.matches` looks for it.
    private func withInferredPointOfContact(_ record: Record, object: ObjectMetadata) -> Record {
        guard let sources = object.pointOfContact else { return record }
        let companyOwner = sources.companyJoinColumn
            .flatMap { record[$0].stringValue }
            .flatMap { id in store["companies"]?.first { $0.id == id } }
            .flatMap { company in sources.companyOwnerJoinColumn.flatMap { company[$0].stringValue } }
        var copy = record
        copy[PointOfContactSources.joinColumn] = sources.memberID(for: record, companyOwnerID: companyOwner).map { .string($0.id) } ?? .null
        return copy
    }

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
