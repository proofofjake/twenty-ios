import SwiftUI

/// Which editor a field gets. Anything not listed stays read-only rather than
/// being flattened into a text box (the bug in other clients that turns a
/// multi-select into plain text and corrupts it on save).
enum FieldEditorKind: Equatable {
    case text, number, boolean, date, dateTime, select, multiSelect, rating
    case fullName, emails, phones, links, currency, address, stringList
    case relation
    case readOnly

    init(field: FieldMetadata) {
        guard field.isWritable, !Self.systemFieldNames.contains(field.name) else {
            self = .readOnly
            return
        }
        switch field.type {
        case .text: self = .text
        case .number, .numeric: self = .number
        case .boolean: self = .boolean
        case .date: self = .date
        case .dateTime: self = .dateTime
        case .select: self = .select
        case .multiSelect: self = .multiSelect
        case .rating: self = .rating
        case .fullName: self = .fullName
        case .emails: self = .emails
        case .phones: self = .phones
        case .links: self = .links
        case .currency: self = .currency
        case .address: self = .address
        case .array: self = .stringList
        // Needs the target object, which only the GraphQL schema provides.
        case .relation where field.relationType == .manyToOne && field.relation?.targetObjectMetadata != nil: self = .relation
        default: self = .readOnly
        }
    }

    /// Twenty marks these writable, but a client must never send them back:
    /// the server would silently overwrite ids, timestamps and ordering.
    static let systemFieldNames: Set<String> = ["id", "createdAt", "updatedAt", "deletedAt", "createdBy", "updatedBy", "position", "searchVector"]

    /// Composite editors render several rows and get their own form section.
    var needsSection: Bool {
        switch self {
        case .fullName, .emails, .phones, .links, .address: true
        default: false
        }
    }
}

extension ObjectMetadata {
    /// Record keys the client may PATCH. Relations are written through their
    /// foreign key (`company` → `companyId`), never as nested objects.
    var writableFieldNames: Set<String> {
        var names = Set<String>()
        for field in visibleFields {
            switch FieldEditorKind(field: field) {
            case .readOnly: continue
            case .relation: names.insert(field.joinColumnName)
            default: names.insert(field.name)
            }
        }
        return names
    }
}

/// Picks the editor for one field. `record` is bound so relation editors can
/// update both the foreign key and the expanded object used for display.
struct FieldEditor: View {
    let field: FieldMetadata
    @Binding var record: Record
    /// False when a section header already shows the field's name.
    var showsLabel = true

    var body: some View {
        let value = Binding<JSONValue>(get: { record[field.name] }, set: { record[field.name] = $0 })
        switch FieldEditorKind(field: field) {
        case .text: TextFieldEditor(field: field, value: value, showsLabel: showsLabel)
        case .number: NumberFieldEditor(field: field, value: value)
        case .boolean: BooleanEditor(field: field, value: value)
        case .date: DateEditor(field: field, includesTime: false, value: value)
        case .dateTime: DateEditor(field: field, includesTime: true, value: value)
        case .select: SelectEditor(field: field, value: value)
        case .multiSelect: MultiSelectEditor(field: field, value: value)
        case .rating: RatingEditor(field: field, value: value)
        case .fullName: FullNameEditor(field: field, value: value)
        case .emails: EmailsEditor(field: field, value: value)
        case .phones: PhonesEditor(field: field, value: value)
        case .links: LinksEditor(field: field, value: value)
        case .currency: CurrencyEditor(field: field, value: value)
        case .address: AddressEditor(field: field, value: value)
        case .stringList: StringListEditor(field: field, value: value)
        case .relation: RelationEditor(field: field, record: $record)
        case .readOnly: ReadOnlyFieldRow(field: field, value: record[field.name])
        }
    }
}
