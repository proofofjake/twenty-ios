import Foundation

/// Twenty `FieldMetadataType`. Kept open (not a closed enum) so a newer server
/// with new field types still decodes; unknown types render read-only.
struct FieldType: RawRepresentable, Codable, Hashable, Sendable {
    let rawValue: String
    init(rawValue: String) { self.rawValue = rawValue }
    init(from decoder: Decoder) throws { rawValue = try decoder.singleValueContainer().decode(String.self) }
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    static let uuid = FieldType(rawValue: "UUID")
    static let text = FieldType(rawValue: "TEXT")
    static let number = FieldType(rawValue: "NUMBER")
    static let numeric = FieldType(rawValue: "NUMERIC")
    static let boolean = FieldType(rawValue: "BOOLEAN")
    static let date = FieldType(rawValue: "DATE")
    static let dateTime = FieldType(rawValue: "DATE_TIME")
    static let select = FieldType(rawValue: "SELECT")
    static let multiSelect = FieldType(rawValue: "MULTI_SELECT")
    static let rating = FieldType(rawValue: "RATING")
    static let fullName = FieldType(rawValue: "FULL_NAME")
    static let emails = FieldType(rawValue: "EMAILS")
    static let phones = FieldType(rawValue: "PHONES")
    static let links = FieldType(rawValue: "LINKS")
    static let currency = FieldType(rawValue: "CURRENCY")
    static let address = FieldType(rawValue: "ADDRESS")
    static let array = FieldType(rawValue: "ARRAY")
    static let actor = FieldType(rawValue: "ACTOR")
    static let relation = FieldType(rawValue: "RELATION")
    static let morphRelation = FieldType(rawValue: "MORPH_RELATION")
    static let richText = FieldType(rawValue: "RICH_TEXT")
    static let position = FieldType(rawValue: "POSITION")
    static let tsVector = FieldType(rawValue: "TS_VECTOR")
    static let rawJSON = FieldType(rawValue: "RAW_JSON")
    static let files = FieldType(rawValue: "FILES")
}

struct FieldOption: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let value: String
    let label: String
    let color: String?
    let position: Double?

    init(id: String, value: String, label: String, color: String?, position: Double?) {
        self.id = id
        self.value = value
        self.label = label
        self.color = color
        self.position = position
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        value = try c.decode(String.self, forKey: .value)
        id = (try? c.decode(String.self, forKey: .id)) ?? value
        label = (try? c.decode(String.self, forKey: .label)) ?? value
        color = try? c.decodeIfPresent(String.self, forKey: .color)
        position = try? c.decodeIfPresent(Double.self, forKey: .position)
    }
}

/// Relation details on a RELATION field. Only what the client needs to pick a
/// target record for many-to-one relations.
struct RelationInfo: Codable, Hashable, Sendable {
    enum Kind: String, Codable, Sendable { case manyToOne = "MANY_TO_ONE", oneToMany = "ONE_TO_MANY", oneToOne = "ONE_TO_ONE" }

    struct TargetObject: Codable, Hashable, Sendable {
        let id: String?
        let nameSingular: String
        let namePlural: String
    }

    struct TargetField: Codable, Hashable, Sendable {
        let id: String?
        let name: String
    }

    let type: Kind?
    let targetObjectMetadata: TargetObject?
    /// The inverse field on the target (for `company.people` this is `person.company`).
    let targetFieldMetadata: TargetField?

    init(type: Kind?, targetObjectMetadata: TargetObject?, targetFieldMetadata: TargetField? = nil) {
        self.type = type
        self.targetObjectMetadata = targetObjectMetadata
        self.targetFieldMetadata = targetFieldMetadata
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        type = try? c.decodeIfPresent(Kind.self, forKey: .type)
        targetObjectMetadata = try? c.decodeIfPresent(TargetObject.self, forKey: .targetObjectMetadata)
        targetFieldMetadata = try? c.decodeIfPresent(TargetField.self, forKey: .targetFieldMetadata)
    }
}

struct FieldMetadata: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let type: FieldType
    let name: String
    let label: String
    let description: String?
    let icon: String?
    let isNullable: Bool?
    let isActive: Bool?
    let isSystem: Bool?
    let isUIEditable: Bool?
    let isUIReadOnly: Bool?
    /// OPEN, APPLICATION or SYSTEM; the server rejects data writes unless OPEN.
    let writability: String?
    let options: [FieldOption]?
    let settings: JSONValue?
    /// Only present when loaded via GraphQL `/metadata`; REST omits relation targets.
    let relation: RelationInfo?

    /// MANY_TO_ONE / ONE_TO_MANY, from the GraphQL relation or REST `settings.relationType`.
    var relationType: RelationInfo.Kind? {
        relation?.type ?? settings?["relationType"]?.stringValue.flatMap(RelationInfo.Kind.init(rawValue:))
    }

    /// Foreign-key column written to set a many-to-one relation (`company` → `companyId`).
    var joinColumnName: String {
        settings?["joinColumnName"]?.nonEmptyString ?? "\(name)Id"
    }

    var isWritable: Bool {
        isUIEditable != false && isUIReadOnly != true && (writability == nil || writability == "OPEN")
    }

    var sortedOptions: [FieldOption] {
        (options ?? []).sorted { ($0.position ?? 0) < ($1.position ?? 0) }
    }

    func option(for value: String) -> FieldOption? {
        options?.first { $0.value == value }
    }
}

struct ObjectMetadata: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let nameSingular: String
    let namePlural: String
    let labelSingular: String
    let labelPlural: String
    let icon: String?
    let isActive: Bool?
    let isSystem: Bool?
    let isUIEditable: Bool?
    let writability: String?
    let labelIdentifierFieldMetadataId: String?
    let imageIdentifierFieldMetadataId: String?
    let fields: [FieldMetadata]
    /// Set by the app (not the server) when this object has no owner field
    /// of its own but one can be inferred; see `PointOfContactSources`.
    var pointOfContact: PointOfContactSources?

    enum CodingKeys: String, CodingKey {
        case id, nameSingular, namePlural, labelSingular, labelPlural, icon, isActive, isSystem, isUIEditable, writability
        case labelIdentifierFieldMetadataId, imageIdentifierFieldMetadataId, fields
        case fieldsList // GraphQL name for `fields`
    }

    var isWritable: Bool { isUIEditable != false && (writability == nil || writability == "OPEN") }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(nameSingular, forKey: .nameSingular)
        try c.encode(namePlural, forKey: .namePlural)
        try c.encode(labelSingular, forKey: .labelSingular)
        try c.encode(labelPlural, forKey: .labelPlural)
        try c.encodeIfPresent(icon, forKey: .icon)
        try c.encodeIfPresent(isActive, forKey: .isActive)
        try c.encodeIfPresent(isSystem, forKey: .isSystem)
        try c.encodeIfPresent(isUIEditable, forKey: .isUIEditable)
        try c.encodeIfPresent(writability, forKey: .writability)
        try c.encodeIfPresent(labelIdentifierFieldMetadataId, forKey: .labelIdentifierFieldMetadataId)
        try c.encodeIfPresent(imageIdentifierFieldMetadataId, forKey: .imageIdentifierFieldMetadataId)
        try c.encode(fields, forKey: .fields)
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        nameSingular = try c.decode(String.self, forKey: .nameSingular)
        namePlural = try c.decode(String.self, forKey: .namePlural)
        labelSingular = (try? c.decode(String.self, forKey: .labelSingular)) ?? nameSingular
        labelPlural = (try? c.decode(String.self, forKey: .labelPlural)) ?? namePlural
        icon = try? c.decodeIfPresent(String.self, forKey: .icon)
        isActive = try? c.decodeIfPresent(Bool.self, forKey: .isActive)
        isSystem = try? c.decodeIfPresent(Bool.self, forKey: .isSystem)
        isUIEditable = try? c.decodeIfPresent(Bool.self, forKey: .isUIEditable)
        writability = try? c.decodeIfPresent(String.self, forKey: .writability)
        labelIdentifierFieldMetadataId = try? c.decodeIfPresent(String.self, forKey: .labelIdentifierFieldMetadataId)
        imageIdentifierFieldMetadataId = try? c.decodeIfPresent(String.self, forKey: .imageIdentifierFieldMetadataId)
        // Decode fields one by one so a single unexpected field shape doesn't
        // hide the whole object.
        let raw = (try? c.decode([LossyField].self, forKey: .fields)) ?? (try? c.decode([LossyField].self, forKey: .fieldsList)) ?? []
        fields = raw.compactMap(\.value)
    }

    private struct LossyField: Decodable {
        let value: FieldMetadata?
        init(from decoder: Decoder) throws { value = try? FieldMetadata(from: decoder) }
    }

    func field(named name: String) -> FieldMetadata? {
        fields.first { $0.name == name }
    }

    /// The field Twenty uses as the record's title (e.g. `name`).
    var labelIdentifierField: FieldMetadata? {
        if let id = labelIdentifierFieldMetadataId, let field = fields.first(where: { $0.id == id }) {
            return field
        }
        return field(named: "name")
    }

    /// Fields shown to the user, in a stable, sensible order.
    var visibleFields: [FieldMetadata] {
        let hidden: Set<String> = ["id", "position", "searchVector", "deletedAt", "updatedBy"]
        let hiddenTypes: Set<FieldType> = [.tsVector, .position, .uuid]
        return fields
            .filter { $0.isActive != false && $0.isSystem != true }
            .filter { !hidden.contains($0.name) && !hiddenTypes.contains($0.type) }
            .filter { !($0.type == .relation && $0.relationType == .oneToMany) }
    }
}
