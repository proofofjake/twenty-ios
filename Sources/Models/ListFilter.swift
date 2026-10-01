import Foundation

/// Stackable filters for a record list: AND across fields, OR within a
/// field ("Tier 1 or Tier 2" and "owned by me"). Values are select option
/// keys, or record ids for owner relations, plus two tokens: `none` (no
/// value set) and `me` (the signed-in member, resolved at request time so a
/// saved "My accounts" filter follows whoever is signed in).
struct ListFilter: Codable, Hashable, Sendable {
    var selections: [String: Set<String>] = [:]

    static let none = "__none__"
    static let me = "__me__"

    var isEmpty: Bool { selections.values.allSatisfy(\.isEmpty) }
    /// Fields with at least one value picked.
    var activeFieldCount: Int { selections.values.filter { !$0.isEmpty }.count }

    func values(for field: String) -> Set<String> { selections[field] ?? [] }

    mutating func toggle(_ value: String, in field: String) {
        var set = selections[field] ?? []
        if set.contains(value) { set.remove(value) } else { set.insert(value) }
        selections[field] = set.isEmpty ? nil : set
    }

    mutating func clear(_ field: String) { selections[field] = nil }

    /// REST `filter` clause for the active selections, or nil when none apply.
    /// Syntax per twenty-server's REST filter parser (v2.41): `f[in]:["A","B"]`,
    /// `f[containsAny]:[…]`, `f[is]:NULL`, nested in `and(…)` / `or(…)`.
    func restClause(for object: ObjectMetadata, currentMemberID: String?) -> String? {
        var clauses: [String] = []
        for field in object.filterableFields {
            let picked = values(for: field.name)
            guard !picked.isEmpty else { continue }
            var parts: [String] = []
            switch field.type {
            case .select, .multiSelect:
                // Option keys that no longer exist would silently empty the list.
                let known = Set(field.sortedOptions.map(\.value))
                let keys = picked.filter { known.contains($0) }.sorted()
                if !keys.isEmpty {
                    let list = keys.map { JSONValue.string($0).jsonLiteral }.joined(separator: ",")
                    parts.append("\(field.name)[\(field.type == .multiSelect ? "containsAny" : "in")]:[\(list)]")
                }
                if picked.contains(Self.none), field.type == .select { parts.append("\(field.name)[is]:NULL") }
            case .relation:
                let ids = picked.compactMap { $0 == Self.me ? currentMemberID : ($0 == Self.none ? nil : $0) }.sorted()
                if field.name == PointOfContactSources.fieldName, let sources = object.pointOfContact {
                    if let clause = sources.restClause(ids: ids, includeNone: picked.contains(Self.none)) { parts.append(clause) }
                    break
                }
                if !ids.isEmpty { parts.append("\(field.joinColumnName)[in]:[\(ids.joined(separator: ","))]") }
                if picked.contains(Self.none) { parts.append("\(field.joinColumnName)[is]:NULL") }
            default:
                continue
            }
            if parts.count == 1 { clauses.append(parts[0]) } else if parts.count > 1 { clauses.append("or(\(parts.joined(separator: ",")))") }
        }
        switch clauses.count {
        case 0: return nil
        case 1: return clauses[0]
        default: return "and(\(clauses.joined(separator: ",")))"
        }
    }

    /// The same test applied in memory (demo data).
    func matches(_ record: Record, object: ObjectMetadata, currentMemberID: String?) -> Bool {
        for field in object.filterableFields {
            let picked = values(for: field.name)
            guard !picked.isEmpty else { continue }
            let ok: Bool
            switch field.type {
            case .select:
                let value = record[field.name].stringValue
                ok = value.map(picked.contains) ?? picked.contains(Self.none)
            case .multiSelect:
                let values = Set((record[field.name].arrayValue ?? []).compactMap(\.stringValue))
                ok = !values.isDisjoint(with: picked)
            case .relation:
                let id = record[field.joinColumnName].stringValue
                let wanted = Set(picked.compactMap { $0 == Self.me ? currentMemberID : $0 })
                ok = id.map(wanted.contains) ?? picked.contains(Self.none)
            default:
                ok = true
            }
            if !ok { return false }
        }
        return true
    }
}

/// Where a person's internal point of contact is inferred from, when people
/// have no owner field of their own (as in the tGBP workspace):
/// 1. their company's account owner, else
/// 2. whoever brought them into Twenty: `createdBy.workspaceMemberId`, set
///    for manual creates and for contacts imported from that member's inbox
///    or calendar.
struct PointOfContactSources: Hashable, Sendable {
    /// `company` and its join column `companyId`, if people link to companies.
    var companyField: String?
    var companyJoinColumn: String?
    /// The company's owner join column (`accountOwnerId`), if it has one.
    var companyOwnerJoinColumn: String?
    var usesCreatedBy: Bool

    static let fieldName = "inferredPointOfContact"
    static let joinColumn = "inferredPointOfContactId"

    /// A filterable stand-in field; its values are workspace member ids.
    static let virtualField = FieldMetadata(
        id: "virtual.inferredPointOfContact", type: .relation, name: fieldName, label: "Point of contact",
        description: nil, icon: nil, isNullable: true, isActive: true, isSystem: false, isUIEditable: false,
        isUIReadOnly: true, writability: "READ_ONLY", options: nil,
        settings: ["relationType": "MANY_TO_ONE", "joinColumnName": .string(joinColumn)],
        relation: RelationInfo(type: .manyToOne, targetObjectMetadata: .init(id: nil, nameSingular: "workspaceMember", namePlural: "workspaceMembers"))
    )

    /// Decides whether `object` gets an inferred point of contact.
    static func infer(for object: ObjectMetadata, in objects: [ObjectMetadata]) -> PointOfContactSources? {
        guard object.nameSingular == "person", !object.visibleFields.contains(where: \.isOwnerLink) else { return nil }
        let company = object.companyRelationField
        let companyObject = objects.first { $0.nameSingular == "company" }
        let owner = companyObject?.visibleFields.first(where: \.isOwnerLink)
        let createdBy = object.field(named: "createdBy") != nil
        guard (company != nil && owner != nil) || createdBy else { return nil }
        return PointOfContactSources(companyField: company?.name, companyJoinColumn: company?.joinColumnName,
                                     companyOwnerJoinColumn: company == nil ? nil : owner?.joinColumnName, usesCreatedBy: createdBy)
    }

    /// REST clause for "point of contact is one of `ids`" (and/or unassigned).
    /// Relation sub-filters (`company.accountOwnerId`) are LEFT JOINs one hop
    /// deep in twenty-server, so people without a company still match.
    func restClause(ids: [String], includeNone: Bool) -> String? {
        let list = "[\(ids.joined(separator: ","))]"
        var companyOwnerIn: String?
        var noCompanyOwner: String?
        if let field = companyField, let join = companyJoinColumn, let owner = companyOwnerJoinColumn {
            companyOwnerIn = "\(field).\(owner)[in]:\(list)"
            noCompanyOwner = "or(\(join)[is]:NULL,\(field).\(owner)[is]:NULL)"
        }
        func and(_ parts: [String?]) -> String? {
            let p = parts.compactMap { $0 }
            return p.isEmpty ? nil : p.count == 1 ? p[0] : "and(\(p.joined(separator: ",")))"
        }
        var options: [String] = []
        if !ids.isEmpty {
            var matches: [String] = []
            if let companyOwnerIn { matches.append(companyOwnerIn) }
            if usesCreatedBy, let viaCreator = and([noCompanyOwner, "createdBy.workspaceMemberId[in]:\(list)"]) { matches.append(viaCreator) }
            if !matches.isEmpty { options.append(matches.count == 1 ? matches[0] : "or(\(matches.joined(separator: ",")))") }
        }
        if includeNone, let none = and([noCompanyOwner, usesCreatedBy ? "createdBy.workspaceMemberId[is]:NULL" : nil]) {
            options.append(none)
        }
        switch options.count {
        case 0: return nil
        case 1: return options[0]
        default: return "or(\(options.joined(separator: ",")))"
        }
    }

    /// The inferred member id for one person, given their company's owner.
    func memberID(for person: Record, companyOwnerID: String?) -> (id: String, source: Source)? {
        if companyField != nil, companyOwnerJoinColumn != nil, let owner = companyOwnerID { return (owner, .companyOwner) }
        if usesCreatedBy, let creator = person["createdBy"]["workspaceMemberId"]?.stringValue { return (creator, .createdBy) }
        return nil
    }

    enum Source { case companyOwner, createdBy }
}

extension ObjectMetadata {
    /// Fields a list can be filtered by: select and multi-select fields, and
    /// owner links to workspace members (plus an inferred point of contact).
    /// Tier and owner come first.
    var filterableFields: [FieldMetadata] {
        var candidates = visibleFields.filter { field in
            if Self.isHiddenFromFilters(field, in: nameSingular) { return false }
            switch field.type {
            case .select, .multiSelect: return !(field.options ?? []).isEmpty
            case .relation: return field.isOwnerLink
            default: return false
            }
        }
        if pointOfContact != nil { candidates.insert(PointOfContactSources.virtualField, at: 0) }
        func rank(_ field: FieldMetadata) -> Int {
            if field.name == "tier" { return 0 }
            if field.isOwnerLink { return 1 }
            return field.type == .select ? 2 : 3
        }
        return candidates.enumerated()
            .sorted { (rank($0.element), $0.offset) < (rank($1.element), $1.offset) }
            .map(\.element)
    }
}

extension ObjectMetadata {
    /// Fields that exist but make no sense as list filters, by object.
    /// Matched on name and label with spaces/punctuation dropped, so
    /// "Subteam", "Sub team" and "sub_team" are all caught.
    static let hiddenFilterFields: [String: Set<String>] = [
        "person": ["subteam"],
    ]

    static func isHiddenFromFilters(_ field: FieldMetadata, in object: String) -> Bool {
        guard let hidden = hiddenFilterFields[object] else { return false }
        let normalise = { (s: String) in s.lowercased().filter(\.isLetter) }
        return hidden.contains(normalise(field.name)) || hidden.contains(normalise(field.label))
    }
}

extension FieldMetadata {
    /// A many-to-one link to a workspace member, like `company.accountOwner`.
    /// REST-only metadata lacks relation targets, so fall back to the name.
    var isOwnerLink: Bool {
        guard type == .relation, relationType == .manyToOne else { return false }
        if let target = relation?.targetObjectMetadata?.nameSingular { return target == "workspaceMember" }
        return ObjectMetadata.ownerFieldNames.contains(name)
    }
}
