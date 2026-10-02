#if DEBUG
import Foundation

/// Claude's educated guesses (Debug builds only): suggested values for four
/// company fields left empty in Twenty. Claude writes them offline to
/// `Config/claude-guesses.json`, which a Debug-only build phase copies into
/// the app; demo mode uses `DemoData.guessesJSON`. Nothing here writes to
/// Twenty: an accepted card is staged in Recent actions until Apply.
enum ClaudeGuesses {
    static let resourceName = "claude-guesses"

    /// The fields Claude guesses, in card order.
    enum Field: String, CaseIterable, Sendable {
        case domainName, accountOwner, tag, companyType

        /// Row label when the workspace doesn't have the field.
        var defaultLabel: String {
            switch self {
            case .domainName: "Website"
            case .accountOwner: "Account owner"
            case .tag: "Type"
            case .companyType: "Company type"
            }
        }

        /// "Claude's guess for Aberdeenplc: website, owner, type, company type"
        var shortName: String {
            switch self {
            case .domainName: "website"
            case .accountOwner: "owner"
            case .tag: "type"
            case .companyType: "company type"
            }
        }
    }

    enum Confidence: String, Sendable { case high, medium, low }

    /// One guess as written in the file, before checking it against the workspace.
    struct Guess: Hashable, Sendable {
        /// A string, or option keys for a multi-select.
        let value: JSONValue
        let confidence: Confidence?
        let reason: String?
    }

    struct Entry: Hashable, Sendable {
        let id: String
        let name: String?
        /// Something to check that isn't a field ("Duplicate: …"); nothing to stage.
        let note: String?
        /// Claude thinks it's junk to delete ("Inbox noise: … Probably delete").
        let suggestDelete: Bool
        let guesses: [Field: Guess]
    }

    struct File: Sendable {
        let generatedAt: Date?
        let entries: [Entry]
        /// Duplicates Claude suggests merging (see ClaudeMerges.swift).
        var merges: [Merge] = []

        /// Every company the deck needs: the entries' and the merges'.
        var companyIDs: [String] {
            var ids: [String] = []
            for id in entries.map(\.id) + merges.flatMap(\.ids) where !ids.contains(id) { ids.append(id) }
            return ids
        }
    }

    enum LoadError: LocalizedError, Equatable {
        case missing
        case unreadable(String)

        var errorDescription: String? {
            switch self {
            case .missing: "This build has no claude-guesses.json."
            case .unreadable(let why): "Couldn't read claude-guesses.json: \(why)"
            }
        }
    }

    // MARK: Reading the file (version 1)

    /// The guesses bundled into this build, or `.missing`.
    static func bundled(in bundle: Bundle = .main) throws -> File {
        guard let url = bundle.url(forResource: resourceName, withExtension: "json") else { throw LoadError.missing }
        do { return try parse(try Data(contentsOf: url)) } catch let error as LoadError { throw error } catch {
            throw LoadError.unreadable(error.localizedDescription)
        }
    }

    /// Defensive: unknown keys are ignored, and a malformed entry or guess is
    /// skipped rather than failing the whole file.
    static func parse(_ data: Data) throws -> File {
        guard let root = (try? JSONDecoder().decode(JSONValue.self, from: data))?.objectValue else {
            throw LoadError.unreadable("not a JSON object")
        }
        if let version = root["version"]?.doubleValue, version != 1 {
            throw LoadError.unreadable("version \(version.formatted()) isn't supported (expected 1)")
        }
        return File(
            generatedAt: FieldFormatter.parseDate(root["generatedAt"]?.stringValue),
            entries: (root["companies"]?.arrayValue ?? []).compactMap(entry),
            merges: (root["merges"]?.arrayValue ?? []).compactMap(merge)
        )
    }

    private static func entry(_ json: JSONValue) -> Entry? {
        guard let id = json["id"]?.nonEmptyString?.lowercased() else { return nil }
        var guesses: [Field: Guess] = [:]
        for field in Field.allCases {
            guard let raw = json["guesses"]?[field.rawValue] else { continue }
            // `{"value": …}` as documented, or a bare value.
            let value = raw.objectValue == nil ? raw : raw["value"] ?? .null
            let normalized: JSONValue
            switch (field, value) {
            case (.companyType, .array(let items)):
                normalized = .array(items.compactMap(\.nonEmptyString).map(JSONValue.string))
            case (.companyType, .string):
                normalized = value.nonEmptyString.map { [.string($0)] } ?? .null
            case (_, .string):
                normalized = value.nonEmptyString.map(JSONValue.string) ?? .null
            default:
                continue
            }
            guard !normalized.isNull, normalized.arrayValue?.isEmpty != true else { continue }
            guesses[field] = Guess(
                value: normalized,
                confidence: raw["confidence"]?.nonEmptyString.flatMap { Confidence(rawValue: $0.lowercased()) },
                reason: raw["reason"]?.nonEmptyString
            )
        }
        let note = json["note"]?.nonEmptyString
        return Entry(id: id, name: json["name"]?.nonEmptyString, note: note,
                     suggestDelete: json["suggestDelete"]?.boolValue ?? note.map(suggestsDeleting) ?? false, guesses: guesses)
    }

    /// Older files have no `suggestDelete`; a note saying to delete counts.
    static func suggestsDeleting(_ note: String) -> Bool {
        note.range(of: #"\bdelete\b"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    // MARK: Checking guesses against the workspace

    /// A guess that still applies: the field is empty and the value exists.
    struct Suggestion: Identifiable, Hashable, Sendable {
        var id: String { field.rawValue }
        let field: Field
        let label: String
        /// As checked: a bare host, a member id, an option key or option keys.
        let value: JSONValue
        /// The host, the member's name, or the option labels.
        let display: String
        /// Option labels, for select and multi-select chips.
        let chips: [String]
        let confidence: Confidence?
        let reason: String?
    }

    /// One of the card's four rows.
    struct Row: Identifiable, Hashable, Sendable {
        enum Kind: Hashable, Sendable {
            /// Already filled in Twenty.
            case current(String, chips: [String])
            case guess(Suggestion)
            /// Neither set nor guessed.
            case empty
        }
        var id: String { field.rawValue }
        let field: Field
        let label: String
        let kind: Kind
    }

    struct Card: Identifiable, Hashable, Sendable {
        var id: String { company.id }
        let company: Record
        let title: String
        let note: String?
        let suggestsDelete: Bool
        let rows: [Row]
        /// A still-valid merge this company is part of.
        var merge: MergeSuggestion? = nil

        var suggestions: [Suggestion] {
            rows.compactMap { if case .guess(let suggestion) = $0.kind { suggestion } else { nil } }
        }

        /// The current website, for the subtitle.
        var website: String? {
            rows.first { $0.field == .domainName }.flatMap { if case .current(let text, _) = $0.kind { text } else { nil } }
        }

        func declineKey(_ suggestion: Suggestion) -> String {
            ClaudeGuesses.declineKey(company: company.id, field: suggestion.field.rawValue, value: suggestion.value)
        }

        /// Dismissing the card records this, so the same note isn't shown again.
        var noteKey: String? { note.map { ClaudeGuesses.declineKey(company: company.id, field: "note", value: .string($0)) } }
    }

    /// "<company>|<field>|<value>": a different guess later still shows.
    static func declineKey(company: String, field: String, value: JSONValue) -> String {
        let text = value.arrayValue.map { $0.compactMap(\.stringValue).sorted().joined(separator: ",") } ?? value.stringValue ?? value.jsonLiteral
        return "\(company)|\(field)|\(text)"
    }

    /// The deck, in file order: companies with guesses for still-empty fields
    /// (or a note, or a merge suggestion) that the owner hasn't staged or
    /// declined. A merge whose companies have no card adds one for its keep.
    /// `records` must include the merges' companies; `stagedMerges` are
    /// `mergeKey`s already in Recent actions.
    static func cards(for entries: [Entry], records: [Record], object: ObjectMetadata, members: [Record],
                      memberObject: ObjectMetadata?, declined: Set<String>, staged: Set<String>,
                      merges: [Merge] = [], stagedMerges: Set<String> = []) -> [Card] {
        let byID = Dictionary(records.map { ($0.id.lowercased(), $0) }, uniquingKeysWith: { first, _ in first })
        let valid = validMerges(merges, records: byID, object: object, declined: declined, staged: stagedMerges)
        let isStaged = { (id: String) in staged.contains(where: { $0.lowercased() == id }) }
        var deck = cards(for: entries, byID: byID, object: object, members: members, memberObject: memberObject,
                         declined: declined, isStaged: isStaged, merges: valid)
        for suggestion in valid where !deck.contains(where: { $0.merge?.key == suggestion.key }) {
            let keep = suggestion.merge.keep
            guard !isStaged(keep), !deck.contains(where: { $0.id == keep }) else { continue }
            deck += cards(for: [Entry(id: keep, name: nil, note: nil, suggestDelete: false, guesses: [:])], byID: byID, object: object,
                          members: members, memberObject: memberObject, declined: declined, isStaged: isStaged, merges: [suggestion])
        }
        return deck
    }

    private static func cards(for entries: [Entry], byID: [String: Record], object: ObjectMetadata, members: [Record],
                              memberObject: ObjectMetadata?, declined: Set<String>, isStaged: (String) -> Bool,
                              merges: [MergeSuggestion]) -> [Card] {
        var seen = Set<String>()
        return entries.compactMap { entry -> Card? in
            guard !isStaged(entry.id), seen.insert(entry.id).inserted, let record = byID[entry.id] else { return nil }
            let rows = Field.allCases.map { field -> Row in
                let label = object.field(named: field.rawValue)?.label ?? field.defaultLabel
                guard let metadata = object.field(named: field.rawValue) else { return Row(field: field, label: label, kind: .empty) }
                if !isEmpty(record, field: metadata) {
                    return Row(field: field, label: label, kind: current(record, field: metadata, members: members, memberObject: memberObject))
                }
                if let guess = entry.guesses[field],
                   let suggestion = suggestion(guess, for: field, metadata: metadata, members: members, memberObject: memberObject),
                   !declined.contains(declineKey(company: record.id, field: field.rawValue, value: suggestion.value)) {
                    return Row(field: field, label: label, kind: .guess(suggestion))
                }
                return Row(field: field, label: label, kind: .empty)
            }
            let card = Card(company: record, title: record.title(in: object), note: entry.note, suggestsDelete: entry.suggestDelete, rows: rows,
                            merge: merges.first { $0.merge.ids.contains(entry.id) })
            let noteIsNew = card.noteKey.map { !declined.contains($0) } ?? false
            return card.suggestions.isEmpty && !noteIsNew && card.merge == nil ? nil : card
        }
    }

    /// Nil unless `guess` is valid here: an option that exists (unknown
    /// multi-select keys are dropped, the rest kept), a known member, or a hostname.
    static func suggestion(_ guess: Guess, for field: Field, metadata: FieldMetadata, members: [Record],
                           memberObject: ObjectMetadata?) -> Suggestion? {
        let value: JSONValue
        let display: String
        var chips: [String] = []
        switch (field, metadata.type) {
        case (.domainName, .links):
            guard let host = guess.value.stringValue.flatMap(host(from:)) else { return nil }
            value = .string(host)
            display = host
        case (.accountOwner, .relation):
            guard let id = guess.value.nonEmptyString?.lowercased(),
                  let member = members.first(where: { $0.id.lowercased() == id }) else { return nil }
            value = .string(member.id)
            display = memberName(member, memberObject: memberObject)
        case (.tag, .select):
            guard let key = guess.value.stringValue, let option = metadata.option(for: key) else { return nil }
            value = .string(key)
            chips = [option.label]
            display = option.label
        case (.companyType, .multiSelect):
            var keys: [String] = []
            for key in (guess.value.arrayValue ?? []).compactMap(\.stringValue)
            where metadata.option(for: key) != nil && !keys.contains(key) { keys.append(key) }
            guard !keys.isEmpty else { return nil }
            value = .array(keys.map(JSONValue.string))
            chips = keys.compactMap { metadata.option(for: $0)?.label }
            display = chips.joined(separator: ", ")
        default:
            // The workspace's field isn't the type the guess was made for.
            return nil
        }
        return Suggestion(field: field, label: metadata.label, value: value, display: display, chips: chips,
                          confidence: guess.confidence, reason: guess.reason)
    }

    /// Whether `field` has no value yet, so a guess may fill it.
    static func isEmpty(_ record: Record, field: FieldMetadata) -> Bool {
        let value = record[field.name]
        switch field.type {
        case .links: return FieldFormatter.links(value).isEmpty
        case .relation: return record[field.joinColumnName].nonEmptyString == nil && value["id"]?.nonEmptyString == nil
        case .multiSelect: return (value.arrayValue ?? []).compactMap(\.nonEmptyString).isEmpty
        case .select: return value.nonEmptyString == nil
        default: return FieldFormatter.plainText(value, field: field).isEmpty
        }
    }

    private static func current(_ record: Record, field: FieldMetadata, members: [Record], memberObject: ObjectMetadata?) -> Row.Kind {
        switch field.type {
        case .links:
            let url = FieldFormatter.links(record[field.name]).first?.url ?? ""
            return .current(host(from: url) ?? url, chips: [])
        case .relation:
            let id = record[field.joinColumnName].stringValue ?? record[field.name]["id"]?.stringValue
            let member = members.first { $0.id == id }
            let name = member.map { memberName($0, memberObject: memberObject) } ?? FieldFormatter.relationTitle(record[field.name])
            return .current(name.isEmpty ? "Someone" : name, chips: [])
        case .select, .multiSelect:
            let keys = field.type == .multiSelect
                ? (record[field.name].arrayValue ?? []).compactMap(\.stringValue)
                : [record[field.name].stringValue].compactMap { $0 }
            let labels = keys.map { field.option(for: $0)?.label ?? $0 }
            return .current(labels.joined(separator: ", "), chips: labels)
        default:
            return .current(FieldFormatter.plainText(record[field.name], field: field), chips: [])
        }
    }

    private static func memberName(_ member: Record, memberObject: ObjectMetadata?) -> String {
        memberObject.map { member.title(in: $0) } ?? FieldFormatter.relationTitle(.object(member.values))
    }

    /// "https://www.Acme.com/" → "www.acme.com"; nil unless it looks like a
    /// hostname (dot-separated labels of letters, digits and hyphens).
    static func host(from text: String) -> String? {
        var host = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        for scheme in ["https://", "http://"] where host.hasPrefix(scheme) { host.removeFirst(scheme.count) }
        while host.hasSuffix("/") { host.removeLast() }
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        guard host.count <= 253, labels.count >= 2, let tld = labels.last, tld.count >= 2, tld.contains(where: \.isLetter) else { return nil }
        let allowed = Set("abcdefghijklmnopqrstuvwxyz0123456789-")
        for label in labels {
            guard (1...63).contains(label.count), label.allSatisfy(allowed.contains),
                  label.first != "-", label.last != "-" else { return nil }
        }
        return host
    }

    // MARK: Staging and applying

    /// What an accepted guess stages. A website becomes a whole LINKS value,
    /// as the link editor writes it.
    static func change(for suggestion: Suggestion) -> PendingChange {
        let value: JSONValue = switch suggestion.field {
        case .domainName:
            ["primaryLinkUrl": .string("https://" + (suggestion.value.stringValue ?? "")), "primaryLinkLabel": "", "secondaryLinks": []]
        default:
            suggestion.value
        }
        return PendingChange(field: suggestion.field.rawValue, label: suggestion.label, summary: suggestion.display, value: value)
    }

    struct Skipped: Hashable, Sendable {
        let change: PendingChange
        let reason: String

        /// "Skipped website: already set"
        var message: String { "Skipped \(change.shortName): \(reason)" }
    }

    /// The PATCH for `changes`, leaving out any field that's been filled
    /// since (or removed from the workspace), so Apply never overwrites.
    /// Relations are written through their join column (`accountOwnerId`).
    static func patch(for changes: [PendingChange], current: Record, object: ObjectMetadata) -> (patch: [String: JSONValue], skipped: [Skipped]) {
        var patch: [String: JSONValue] = [:]
        var skipped: [Skipped] = []
        for change in changes {
            guard let field = object.field(named: change.field), field.isWritable else {
                skipped.append(Skipped(change: change, reason: "not in this workspace"))
                continue
            }
            guard isEmpty(current, field: field) else {
                skipped.append(Skipped(change: change, reason: "already set"))
                continue
            }
            patch[field.type == .relation ? field.joinColumnName : field.name] = change.value
        }
        return (patch, skipped)
    }
}

/// Guesses the owner swiped away, saved per workspace so they don't come
/// back. Keys come from `ClaudeGuesses.declineKey`.
struct GuessDeclineStore {
    var defaults: UserDefaults = .standard
    let key: String

    init(workspaceKey: String, defaults: UserDefaults = .standard) {
        self.key = "claudeGuessDeclines." + workspaceKey
        self.defaults = defaults
    }

    func load() -> Set<String> { Set(defaults.stringArray(forKey: key) ?? []) }
    func save(_ keys: Set<String>) { defaults.set(keys.sorted(), forKey: key) }
}

/// Cards skipped to the bottom of the pile, per workspace: company id → when.
/// Kept across launches so a skipped card doesn't come back on top.
struct GuessSkipStore {
    var defaults: UserDefaults = .standard
    let key: String

    init(workspaceKey: String, defaults: UserDefaults = .standard) {
        self.key = "claudeGuessSkips." + workspaceKey
        self.defaults = defaults
    }

    func load() -> [String: Date] {
        (defaults.dictionary(forKey: key) as? [String: Double] ?? [:]).mapValues { Date(timeIntervalSince1970: $0) }
    }

    func save(_ skips: [String: Date]) { defaults.set(skips.mapValues(\.timeIntervalSince1970), forKey: key) }
}

extension ClaudeGuesses {
    /// Unskipped cards first, in file order; then skipped ones, longest-skipped first.
    static func skippedLast(_ cards: [Card], skips: [String: Date]) -> [Card] {
        let fresh = cards.filter { skips[$0.id] == nil }
        let skipped = cards.filter { skips[$0.id] != nil }
            .enumerated()
            .sorted { (skips[$0.element.id]!, $0.offset) < (skips[$1.element.id]!, $1.offset) }
            .map(\.element)
        return fresh + skipped
    }
}
#endif
