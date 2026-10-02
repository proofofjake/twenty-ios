#if DEBUG
import Foundation

/// Claude's merge suggestions (Debug builds only): companies that look like
/// the same one added twice. They come from the guesses file's optional
/// top-level `merges` list. A merge is staged in Recent actions, like an
/// accepted guess, and only written when confirmed there. Twenty's merge
/// can't be undone, because the merged-away records are hard-deleted.
extension ClaudeGuesses {
    /// Twenty merges at most this many records at once (`MUTATION_MAX_MERGE_RECORDS`).
    static let maxMergeRecords = 9

    /// Which record's value Claude would keep for one field, and why.
    struct FieldPick: Hashable, Sendable {
        let from: String
        let reason: String?
    }

    /// One suggestion as written in the file.
    struct Merge: Hashable, Sendable {
        /// The company that survives.
        let keep: String
        /// The ones merged into it (and deleted).
        let merge: [String]
        let confidence: Confidence?
        let reason: String?
        /// Field name → Claude's pick. May be partial.
        let fields: [String: FieldPick]

        /// Claude's keep first, then the rest in file order.
        var ids: [String] { [keep] + merge }
        var key: String { ClaudeGuesses.mergeKey(ids) }
    }

    /// "merge|<id>,<id>", sorted, so "Not duplicates" sticks to the set of
    /// companies whichever one is kept.
    static func mergeKey(_ ids: [String]) -> String {
        "merge|" + ids.map { $0.lowercased() }.sorted().joined(separator: ",")
    }

    /// Defensive like the rest of the file: an entry without a usable keep,
    /// with a non-string id, with nothing to merge or with too many records
    /// is skipped. A pick naming a record outside the merge is dropped.
    static func merge(_ json: JSONValue) -> Merge? {
        guard let keep = json["keep"]?.nonEmptyString?.lowercased() else { return nil }
        let raw = json["merge"]?.arrayValue ?? json["merge"].flatMap(\.nonEmptyString).map { [.string($0)] } ?? []
        var others: [String] = []
        for value in raw {
            guard let id = value.nonEmptyString?.lowercased() else { return nil }
            if id != keep, !others.contains(id) { others.append(id) }
        }
        guard !others.isEmpty, others.count + 1 <= maxMergeRecords else { return nil }
        let ids = Set([keep] + others)
        var fields: [String: FieldPick] = [:]
        for (name, pick) in json["fields"]?.objectValue ?? [:] {
            guard let from = (pick["from"]?.nonEmptyString ?? pick.nonEmptyString)?.lowercased(), ids.contains(from) else { continue }
            fields[name] = FieldPick(from: from, reason: pick["reason"]?.nonEmptyString)
        }
        return Merge(keep: keep, merge: others,
                     confidence: json["confidence"]?.nonEmptyString.flatMap { Confidence(rawValue: $0.lowercased()) },
                     reason: json["reason"]?.nonEmptyString, fields: fields)
    }

    /// A merge that still applies: every company exists, and it hasn't been
    /// dismissed or staged.
    struct MergeSuggestion: Hashable, Sendable {
        let merge: Merge
        /// Its companies as listed (depth 0), Claude's keep first.
        let records: [Record]
        let titles: [String]

        var key: String { merge.key }

        func title(of id: String) -> String {
            zip(records, titles).first { $0.0.id == id }?.1 ?? "Untitled"
        }

        /// "Cobalt Custody Ltd", "A and B", "A and 2 others": everyone but `id`.
        func others(than id: String) -> String {
            ClaudeGuesses.list(zip(records, titles).filter { $0.0.id != id }.map(\.1))
        }
    }

    static func list(_ names: [String]) -> String {
        switch names.count {
        case 0: ""
        case 1: names[0]
        case 2: "\(names[0]) and \(names[1])"
        default: "\(names[0]) and \(names.count - 1) others"
        }
    }

    /// File order; the first suggestion wins when two share a company.
    static func validMerges(_ merges: [Merge], records byID: [String: Record], object: ObjectMetadata,
                            declined: Set<String>, staged: Set<String>) -> [MergeSuggestion] {
        var used = Set<String>()
        var result: [MergeSuggestion] = []
        for merge in merges {
            let records = merge.ids.compactMap { byID[$0] }
            guard records.count == merge.ids.count, !declined.contains(merge.key), !staged.contains(merge.key),
                  used.isDisjoint(with: merge.ids) else { continue }
            used.formUnion(merge.ids)
            result.append(MergeSuggestion(merge: merge, records: records, titles: records.map { $0.title(in: object) }))
        }
        return result
    }

    // MARK: The merge window

    struct MergeValue: Hashable, Sendable {
        let recordID: String
        /// As shown ("" when empty).
        let display: String
        /// Option labels, for select and multi-select chips.
        let chips: [String]
        /// Twenty's notion of having a value, which decides what its merge keeps.
        let twentyHasValue: Bool

        var isEmpty: Bool { display.isEmpty }
    }

    struct MergeRow: Identifiable, Hashable, Sendable {
        enum Kind: Hashable, Sendable {
            /// One value survives; tapping picks which.
            case choice
            /// LINKS, EMAILS, PHONES: the pick is primary, the rest are kept as secondary values.
            case primary
            /// MULTI_SELECT, ARRAY (and composite lists with one primary): Twenty combines them.
            case combined
        }

        var id: String { field.name }
        let field: FieldMetadata
        let kind: Kind
        /// Each record's value, in the records' order.
        let values: [MergeValue]
        let pick: FieldPick?
        /// What the merge makes of it, for `.combined` rows.
        let combined: MergeValue?

        var options: [MergeValue] { values.filter { !$0.isEmpty } }

        /// "link", "email", "phone number", for the secondary-value caption.
        var secondaryNoun: String {
            switch field.type {
            case .emails: "email"
            case .phones: "phone number"
            default: "link"
            }
        }
    }

    /// Fields a merge could change: visible, writable, not bookkeeping.
    static func mergeableFields(of object: ObjectMetadata) -> [FieldMetadata] {
        let skipped: Set<String> = ["createdAt", "updatedAt", "deletedAt", "createdBy", "updatedBy"]
        let skippedTypes: Set<FieldType> = [.actor, .files, .rawJSON, .morphRelation]
        return object.pinnedFirst(object.visibleFields).filter { field in
            field.isWritable && !skipped.contains(field.name) && !skippedTypes.contains(field.type)
                && (field.type != .relation || field.relationType == .manyToOne)
        }
    }

    /// One row per field whose values differ between `records` (in the
    /// order given); fields that are all equal or all empty are left out.
    static func mergeRows(records: [Record], object: ObjectMetadata, picks: [String: FieldPick],
                          members: [Record], memberObject: ObjectMetadata?) -> [MergeRow] {
        mergeableFields(of: object).compactMap { field -> MergeRow? in
            let full = records.map { mergeValue($0, field: field, primaryOnly: false, members: members, memberObject: memberObject) }
            let shown = Set(full.map(\.display))
            guard shown.count > 1 else { return nil } // all equal, or all empty
            /// Claude's pick, if that record has a value to pick.
            func pick(among values: [MergeValue]) -> FieldPick? {
                picks[field.name].flatMap { pick in values.contains { $0.recordID == pick.from && !$0.isEmpty } ? pick : nil }
            }
            switch field.type {
            case .multiSelect, .array:
                return MergeRow(field: field, kind: .combined, values: full, pick: picks[field.name],
                                combined: combinedValue(records, field: field))
            case .links, .emails, .phones:
                let primaries = records.map { mergeValue($0, field: field, primaryOnly: true, members: members, memberObject: memberObject) }
                // The same primary on several records: only the secondary values differ, and those are combined.
                let present = primaries.filter { !$0.isEmpty }
                guard Set(present.map(\.display)).count > 1 || present.count == 1 else {
                    return MergeRow(field: field, kind: .combined, values: full, pick: picks[field.name],
                                    combined: combinedValue(records, field: field))
                }
                return MergeRow(field: field, kind: .primary, values: primaries, pick: pick(among: primaries), combined: nil)
            default:
                return MergeRow(field: field, kind: .choice, values: full, pick: pick(among: full), combined: nil)
            }
        }
    }

    private static func mergeValue(_ record: Record, field: FieldMetadata, primaryOnly: Bool,
                                   members: [Record], memberObject: ObjectMetadata?) -> MergeValue {
        let raw = rawValue(record, field: field)
        var chips: [String] = []
        let display: String
        switch field.type {
        case .links where primaryOnly:
            display = FieldFormatter.links(.object(["primaryLinkUrl": raw["primaryLinkUrl"] ?? .null])).first?.url ?? ""
        case .emails where primaryOnly:
            display = raw["primaryEmail"]?.nonEmptyString ?? ""
        case .phones where primaryOnly:
            display = FieldFormatter.phones(.object(raw.objectValue?.filter { $0.key != "additionalPhones" } ?? [:])).first ?? ""
        case .relation:
            let id = raw.nonEmptyString
            let member = members.first { $0.id == id }
            let name = member.map { memberObject.map($0.title(in:)) ?? FieldFormatter.relationTitle(.object($0.values)) }
                ?? FieldFormatter.relationTitle(record[field.name])
            display = id == nil ? "" : (name.isEmpty ? "Someone" : name)
        case .select, .multiSelect:
            let keys = field.type == .multiSelect ? (raw.arrayValue ?? []).compactMap(\.nonEmptyString) : [raw.nonEmptyString].compactMap { $0 }
            chips = keys.map { field.option(for: $0)?.label ?? $0 }
            display = chips.joined(separator: ", ")
        default:
            display = FieldFormatter.plainText(raw, field: field)
        }
        let primary: JSONValue = switch field.type {
        case .links where primaryOnly: raw["primaryLinkUrl"] ?? .null
        case .emails where primaryOnly: raw["primaryEmail"] ?? .null
        case .phones where primaryOnly: raw["primaryPhoneNumber"] ?? .null
        default: raw
        }
        return MergeValue(recordID: record.id, display: display, chips: chips, twentyHasValue: TwentyMerge.hasValue(primary))
    }

    /// What's stored for `field`: a relation's id comes from its join column.
    static func rawValue(_ record: Record, field: FieldMetadata) -> JSONValue {
        guard field.type == .relation else { return record[field.name] }
        return record[field.joinColumnName].nonEmptyString.map(JSONValue.string) ?? record[field.name]["id"] ?? .null
    }

    private static func combinedValue(_ records: [Record], field: FieldMetadata) -> MergeValue {
        let values = records.map { (value: $0[field.name], recordID: $0.id) }
        let merged = TwentyMerge.mergeValues(values.filter { TwentyMerge.hasValue($0.value) }, type: field.type,
                                             priorityID: records.first?.id ?? "") ?? .null
        let chips = field.type == .multiSelect ? (merged.arrayValue ?? []).compactMap(\.stringValue).map { field.option(for: $0)?.label ?? $0 } : []
        let display = chips.isEmpty ? FieldFormatter.plainText(merged, field: field) : chips.joined(separator: ", ")
        return MergeValue(recordID: "", display: display, chips: chips, twentyHasValue: TwentyMerge.hasValue(merged))
    }

    /// The other records, in order, after the survivor: Twenty's fallback order.
    private static func ordered(_ values: [MergeValue], survivor: String) -> [MergeValue] {
        values.filter { $0.recordID == survivor } + values.filter { $0.recordID != survivor }
    }

    /// Claude's pick if given; else what Twenty would do: the survivor's
    /// value if it has one, else the first other record's.
    static func defaultChoice(for row: MergeRow, survivor: String) -> String? {
        guard row.kind != .combined else { return nil }
        if let pick = row.pick, row.options.contains(where: { $0.recordID == pick.from }) { return pick.from }
        return ordered(row.values, survivor: survivor).first { !$0.isEmpty }?.recordID
    }

    /// The record whose value Twenty's merge keeps, by its own rules (which
    /// count e.g. a currency code with no amount as a value).
    static func twentyChoice(for row: MergeRow, survivor: String) -> String? {
        ordered(row.values, survivor: survivor).first(where: \.twentyHasValue)?.recordID
    }

    /// The values to PATCH onto the survivor before merging: each field
    /// where the chosen value isn't what Twenty's merge would keep anyway.
    /// `selection` is field name → record id, for the rows the owner tapped.
    static func mergeOverrides(rows: [MergeRow], selection: [String: String], records: [Record],
                               survivor: String) -> [PendingChange] {
        guard let kept = records.first(where: { $0.id == survivor }) else { return [] }
        return rows.compactMap { row -> PendingChange? in
            guard row.kind != .combined,
                  let chosenID = selection[row.id] ?? defaultChoice(for: row, survivor: survivor),
                  let chosen = row.values.first(where: { $0.recordID == chosenID }), !chosen.isEmpty,
                  let source = records.first(where: { $0.id == chosenID }) else { return nil }
            let twenty = twentyChoice(for: row, survivor: survivor).flatMap { id in row.values.first { $0.recordID == id } }
            guard chosen.display != twenty?.display else { return nil }
            let field = row.field
            let value: JSONValue = row.kind == .primary
                ? primaryOverride(field: field, chosen: source, survivor: kept)
                : rawValue(source, field: field)
            let previous = row.values.first { $0.recordID == survivor }?.display ?? ""
            return PendingChange(field: field.name, label: field.label, summary: chosen.display, value: value, previous: previous)
        }
    }

    /// The chosen record's primary value, keeping the survivor's own values
    /// as secondary ones so the PATCH loses nothing. The merge then adds the
    /// other records' values as secondary ones too.
    static func primaryOverride(field: FieldMetadata, chosen: Record, survivor: Record) -> JSONValue {
        let mine = survivor[field.name], theirs = chosen[field.name]
        switch field.type {
        case .links:
            let url = theirs["primaryLinkUrl"]?.stringValue ?? ""
            var secondary: [JSONValue] = []
            if let own = mine["primaryLinkUrl"]?.nonEmptyString, own != url {
                secondary.append(["url": .string(own), "label": mine["primaryLinkLabel"] ?? ""])
            }
            secondary += (mine["secondaryLinks"]?.arrayValue ?? []).filter { $0["url"]?.stringValue != url }
            return ["primaryLinkUrl": .string(url), "primaryLinkLabel": theirs["primaryLinkLabel"] ?? "", "secondaryLinks": .array(secondary)]
        case .emails:
            let email = theirs["primaryEmail"]?.stringValue ?? ""
            let additional = ([mine["primaryEmail"]?.nonEmptyString].compactMap { $0 } + (mine["additionalEmails"]?.arrayValue ?? []).compactMap(\.nonEmptyString))
                .filter { $0 != email }
            return ["primaryEmail": .string(email), "additionalEmails": .array(additional.map(JSONValue.string))]
        default: // phones
            let number = theirs["primaryPhoneNumber"]?.stringValue ?? ""
            var additional: [JSONValue] = []
            if let own = mine["primaryPhoneNumber"]?.nonEmptyString, own != number {
                additional.append(["number": .string(own), "countryCode": mine["primaryPhoneCountryCode"] ?? "", "callingCode": mine["primaryPhoneCallingCode"] ?? ""])
            }
            additional += (mine["additionalPhones"]?.arrayValue ?? []).filter { $0["number"]?.stringValue != number }
            return ["primaryPhoneNumber": .string(number), "primaryPhoneCountryCode": theirs["primaryPhoneCountryCode"] ?? "",
                    "primaryPhoneCallingCode": theirs["primaryPhoneCallingCode"] ?? "", "additionalPhones": .array(additional)]
        }
    }

    /// The survivor's PATCH at Apply, leaving out any override whose field
    /// has changed on the survivor since it was staged.
    static func mergePatch(for overrides: [PendingChange], survivor current: Record, object: ObjectMetadata,
                           members: [Record] = [], memberObject: ObjectMetadata? = nil) -> (patch: [String: JSONValue], skipped: [Skipped]) {
        var patch: [String: JSONValue] = [:]
        var skipped: [Skipped] = []
        for change in overrides {
            guard let field = object.field(named: change.field), field.isWritable else {
                skipped.append(Skipped(change: change, reason: "not in this workspace"))
                continue
            }
            if let previous = change.previous {
                let now = mergeValue(current, field: field, primaryOnly: [.links, .emails, .phones].contains(field.type),
                                     members: members, memberObject: memberObject).display
                guard now == previous else {
                    skipped.append(Skipped(change: change, reason: "changed since you staged it"))
                    continue
                }
            }
            patch[field.type == .relation ? field.joinColumnName : field.name] = change.value
        }
        return (patch, skipped)
    }

    /// "Moves to Cobalt Custody: 1 person, 2 opportunities", from the
    /// depth-1 records being merged away. Nil when nothing moves.
    static func moves(from records: [Record], object: ObjectMetadata, objects: [ObjectMetadata]) -> String? {
        let parts = object.relatedLists(in: objects).compactMap { list -> String? in
            let count = records.reduce(0) { $0 + ($1[list.field.name].arrayValue?.count ?? 0) }
            guard count > 0 else { return nil }
            let noun = count == 1 ? list.target.labelSingular : list.target.labelPlural
            return "\(count) \(noun.lowercased())"
        }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }
}

/// Twenty's merge rules (twenty-server `mergeFieldValues`, v2.44): the
/// priority record's value wins if it has one, else the first other's;
/// ARRAY and MULTI_SELECT are unioned; LINKS, EMAILS and PHONES keep the
/// winner's primary and add everyone else's values as secondary ones. Used
/// for the merge window's preview and by the demo service.
enum TwentyMerge {
    /// Bookkeeping Twenty doesn't merge (or that makes no difference).
    static let skippedKeys: Set<String> = ["id", "createdAt", "updatedAt", "deletedAt", "createdBy", "updatedBy", "position", "searchVector"]

    /// `hasRecordFieldValue`: a composite has a value if any part does.
    static func hasValue(_ value: JSONValue) -> Bool {
        switch value {
        case .null: false
        case .string(let text): !text.trimmingCharacters(in: .whitespaces).isEmpty
        case .number(let number): !number.isNaN
        case .bool: true
        case .array(let items): !items.isEmpty
        case .object(let fields): fields.values.contains(where: hasValue)
        }
    }

    /// The survivor's merged values (depth 0: plain columns and join columns),
    /// from `records` in the order sent to Twenty.
    static func merged(_ records: [Record], priorityID: String, object: ObjectMetadata) -> [String: JSONValue] {
        guard let priority = records.first(where: { $0.id == priorityID }) else { return [:] }
        var result = priority.values
        let keys = Set(records.flatMap(\.values.keys)).subtracting(skippedKeys)
        for key in keys {
            let field = object.field(named: key)
            if field?.type == .relation { continue } // expanded relations; their join columns are merged
            let withValues = records.map { (value: $0[key], recordID: $0.id) }.filter { hasValue($0.value) }
            switch withValues.count {
            case 0: continue
            case 1: result[key] = withValues[0].value
            default: result[key] = mergeValues(withValues, type: field?.type, priorityID: priorityID) ?? .null
            }
        }
        return result
    }

    static func mergeValues(_ values: [(value: JSONValue, recordID: String)], type: FieldType?, priorityID: String) -> JSONValue? {
        guard !values.isEmpty else { return nil }
        switch type {
        case .array?, .multiSelect?:
            var union: [JSONValue] = []
            for item in values.flatMap({ $0.value.arrayValue ?? [] }) where hasValue(item) && !union.contains(item) { union.append(item) }
            return union.isEmpty ? .null : .array(union)
        case .links?:
            return mergeComposite(values, priorityID: priorityID, primary: "primaryLinkUrl") { value in
                (value["primaryLinkUrl"]?.nonEmptyString.map { [["url": .string($0), "label": value["primaryLinkLabel"] ?? ""]] } ?? [])
                    + (value["secondaryLinks"]?.arrayValue ?? []).filter { $0["url"]?.nonEmptyString != nil }
            } identity: { $0["url"]?.stringValue ?? "" } build: { winner, rest in
                ["primaryLinkUrl": winner["primaryLinkUrl"] ?? "", "primaryLinkLabel": winner["primaryLinkLabel"] ?? "",
                 "secondaryLinks": rest.isEmpty ? .null : .array(rest)]
            }
        case .emails?:
            return mergeComposite(values, priorityID: priorityID, primary: "primaryEmail") { value in
                ([value["primaryEmail"]].compactMap { $0 } + (value["additionalEmails"]?.arrayValue ?? [])).filter { $0.nonEmptyString != nil }
            } identity: { $0.stringValue ?? "" } build: { winner, rest in
                ["primaryEmail": winner["primaryEmail"] ?? "", "additionalEmails": rest.isEmpty ? .null : .array(rest)]
            }
        case .phones?:
            return mergeComposite(values, priorityID: priorityID, primary: "primaryPhoneNumber") { value in
                (value["primaryPhoneNumber"]?.nonEmptyString.map {
                    [["number": .string($0), "countryCode": value["primaryPhoneCountryCode"] ?? "", "callingCode": value["primaryPhoneCallingCode"] ?? ""]]
                } ?? []) + (value["additionalPhones"]?.arrayValue ?? []).filter { $0["number"]?.nonEmptyString != nil }
            } identity: { $0["number"]?.stringValue ?? "" } build: { winner, rest in
                ["primaryPhoneNumber": winner["primaryPhoneNumber"] ?? "", "primaryPhoneCountryCode": winner["primaryPhoneCountryCode"] ?? "",
                 "primaryPhoneCallingCode": winner["primaryPhoneCallingCode"] ?? "", "additionalPhones": rest.isEmpty ? .null : .array(rest)]
            }
        default:
            if let priority = values.first(where: { $0.recordID == priorityID }), hasValue(priority.value) { return priority.value }
            return values.first { hasValue($0.value) }?.value
        }
    }

    /// The winner's primary, then every record's values (deduplicated, minus
    /// the primary) as secondary ones.
    private static func mergeComposite(_ values: [(value: JSONValue, recordID: String)], priorityID: String, primary: String,
                                       all: (JSONValue) -> [JSONValue], identity: (JSONValue) -> String,
                                       build: (JSONValue, [JSONValue]) -> JSONValue) -> JSONValue {
        let priority = values.first { $0.recordID == priorityID }
        let winner = priority.flatMap { hasValue($0.value[primary] ?? .null) ? $0.value : nil }
            ?? values.first { hasValue($0.value[primary] ?? .null) }?.value ?? .object([:])
        let primaryID = winner[primary]?.stringValue ?? ""
        var seen = Set<String>()
        var rest: [JSONValue] = []
        for item in values.flatMap({ all($0.value) }) {
            let id = identity(item)
            guard seen.insert(id).inserted, id != primaryID else { continue }
            rest.append(item)
        }
        return build(winner, rest)
    }
}

/// Before a merge is applied, every record (depth 1) is appended to
/// Documents/merge-log.jsonl, one JSON object per line, so the merged-away
/// data could be put back by hand.
enum MergeLog {
    static var url: URL { URL.documentsDirectory.appending(path: "merge-log.jsonl") }

    static func append(_ merge: PendingMerge, records: [Record], to url: URL = url) throws {
        let entry: JSONValue = [
            "date": .string(FieldFormatter.dateTimeString(Date())),
            "object": .string(merge.object),
            "keepID": .string(merge.keepID),
            "mergeIDs": .array(merge.mergeIDs.map(JSONValue.string)),
            "overrides": .array(merge.overrides.map { ["field": .string($0.field), "value": $0.value] }),
            "records": .array(records.map { .object($0.values) }),
        ]
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        var line = try encoder.encode(entry)
        line.append(0x0A)
        if !FileManager.default.fileExists(atPath: url.path) {
            try line.write(to: url, options: .atomic)
            return
        }
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: line)
    }
}
#endif
