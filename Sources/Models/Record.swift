import Foundation

/// A Twenty record of any object type, kept as raw JSON keyed by field name.
struct Record: Identifiable, Hashable, Sendable {
    let id: String
    var values: [String: JSONValue]

    init(id: String, values: [String: JSONValue]) {
        self.id = id
        self.values = values
    }

    init?(json: JSONValue) {
        guard let object = json.objectValue, let id = object["id"]?.stringValue else { return nil }
        self.id = id
        self.values = object
    }

    subscript(field: String) -> JSONValue {
        get { values[field] ?? .null }
        set { values[field] = newValue }
    }

    /// Human-readable title using the object's label identifier field.
    func title(in object: ObjectMetadata) -> String {
        guard let field = object.labelIdentifierField else { return "Untitled" }
        let text = FieldFormatter.plainText(self[field.name], field: field)
        return text.isEmpty ? "Untitled" : text
    }

    /// Only the fields whose values differ from `original`, restricted to
    /// fields the client knows how to write. This is what gets PATCHed, so
    /// untouched and read-only fields are never sent back to the server.
    func changes(from original: Record, writable: Set<String>) -> [String: JSONValue] {
        var patch: [String: JSONValue] = [:]
        for name in writable where values[name] != original.values[name] {
            patch[name] = values[name] ?? .null
        }
        return patch
    }
}

struct RecordPage: Sendable {
    var records: [Record]
    var hasNextPage: Bool
    var endCursor: String?
    var totalCount: Int?
}
