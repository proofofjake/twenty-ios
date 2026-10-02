import Foundation

/// Something the user did that can be undone for 24 hours: one delete, with
/// the people it took along and the blocklist entry it added.
struct RecentAction: Codable, Identifiable, Hashable, Sendable {
    enum Item: Codable, Hashable, Sendable {
        /// A record soft-deleted into Twenty's trash; undo restores it.
        case deleted(object: String, id: String, title: String)
        /// A blocklist entry this app created; undo removes it.
        case blocked(id: String, handle: String)
        #if DEBUG
        /// Field values staged but not written to Twenty yet (Claude's
        /// educated guesses). Apply writes them; Discard drops them.
        case pendingUpdate(object: String, id: String, title: String, changes: [PendingChange])
        /// A merge of duplicate companies staged but not run yet (Claude's
        /// suggestion). Merge… runs it, for good; Discard drops it.
        case pendingMerge(merge: PendingMerge)
        #endif
    }

    var id = UUID()
    var date = Date()
    var items: [Item] = []

    static let lifetime: TimeInterval = 24 * 3600

    private enum CodingKeys: String, CodingKey { case id, date, items }

    var isExpired: Bool {
        #if DEBUG
        // Staged updates and merges wait until they're applied or discarded.
        if isPendingUpdate || isPendingMerge { return false }
        #endif
        return Date().timeIntervalSince(date) > Self.lifetime
    }

    /// Whether Commit has anything to make final here.
    var hasDeletes: Bool { items.contains { if case .deleted = $0 { true } else { false } } }

    /// "Deleted Lake Como Villas and 2 people · blocked @lakecomovillas.it"
    var summary: String {
        #if DEBUG
        if let merge = pendingMerge { return merge.summary }
        if let pending = pendingUpdate {
            let fields = pending.changes.map(\.shortName).joined(separator: ", ")
            return "Claude's guess for \(pending.title)" + (fields.isEmpty ? "" : ": \(fields)")
        }
        #endif
        let deleted = items.compactMap { if case .deleted(let object, _, let title) = $0 { (object, title) } else { nil } }
        let blocked = items.compactMap { if case .blocked(_, let handle) = $0 { handle } else { nil } }
        var parts: [String] = []
        if let main = deleted.last {
            let others = deleted.dropLast()
            let people = others.filter { $0.0 == "person" }.count
            parts.append("Deleted \(main.1)" + (people == 0 ? "" : people == 1 ? " and 1 person" : " and \(people) people"))
        }
        if let handle = blocked.first { parts.append("blocked \(handle)") }
        return parts.isEmpty ? "Nothing" : parts.joined(separator: " · ")
    }

    /// Decodes saved actions one by one, skipping any this build can't read
    /// (e.g. a Debug-only kind, read by a Release build), so one unknown
    /// entry doesn't lose the rest.
    static func decodeList(_ data: Data) -> [RecentAction] {
        struct Lossy: Decodable {
            let value: RecentAction?
            init(from decoder: Decoder) throws { value = try? RecentAction(from: decoder) }
        }
        return ((try? JSONDecoder().decode([Lossy].self, from: data)) ?? []).compactMap(\.value)
    }
}

extension RecentAction {
    /// Items decode one by one too: one this build can't read is dropped and
    /// the rest kept. An action left with none fails, so `decodeList` skips it.
    init(from decoder: Decoder) throws {
        struct LossyItem: Decodable {
            let value: Item?
            init(from decoder: Decoder) throws { value = try? Item(from: decoder) }
        }
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        date = try c.decode(Date.self, forKey: .date)
        let raw = try c.decode([LossyItem].self, forKey: .items)
        items = raw.compactMap(\.value)
        if items.isEmpty, !raw.isEmpty {
            throw DecodingError.dataCorruptedError(forKey: .items, in: c, debugDescription: "No item this build can read")
        }
    }
}

#if DEBUG
/// One field of a staged update, e.g. Claude's guessed website.
struct PendingChange: Codable, Hashable, Sendable {
    /// The schema field (`accountOwner`, not its `accountOwnerId` column).
    let field: String
    /// The field's label when it was staged ("Website").
    let label: String
    /// What the card showed: "aberdeenplc.com", "Raphaelle", "Asset Manger, Bank".
    let summary: String
    /// Written on Apply as is: a LINKS object, an option key or keys, or a
    /// member id (sent through the relation's join column).
    let value: JSONValue
    /// For a merge override: the survivor's value as shown when staged.
    /// Apply skips the change if it's different by then.
    var previous: String? = nil

    /// "website", "owner", … for Recent actions summaries.
    var shortName: String { ClaudeGuesses.Field(rawValue: field)?.shortName ?? label.lowercased() }
}

/// A staged merge: `mergeIDs` are merged into `keepID` (Twenty's priority
/// record) and then hard-deleted by Twenty. `overrides` are values picked
/// from the other records, PATCHed onto the survivor first.
struct PendingMerge: Codable, Hashable, Sendable {
    let object: String
    let keepID: String
    let keepTitle: String
    let mergeIDs: [String]
    let mergeTitles: [String]
    let overrides: [PendingChange]

    /// Survivor first, as sent to Twenty (`conflictPriorityIndex` 0).
    var ids: [String] { [keepID] + mergeIDs }

    /// "Merge Cobalt Custody Ltd into Cobalt Custody (Claude's suggestion)"
    var summary: String { "Merge \(ClaudeGuesses.list(mergeTitles)) into \(keepTitle) (Claude's suggestion)" }
}

extension RecentAction {
    /// Only a staged merge: it never expires.
    var isPendingMerge: Bool { !items.isEmpty && items.allSatisfy { $0.pendingMerge != nil } }

    var pendingMerge: PendingMerge? { items.lazy.compactMap { $0.pendingMerge }.first }

    /// Only staged updates (nothing deleted): these never expire.
    var isPendingUpdate: Bool { !items.isEmpty && items.allSatisfy { $0.pendingUpdate != nil } }

    /// The staged update's company id, title and changes, if this is one.
    var pendingUpdate: (object: String, id: String, title: String, changes: [PendingChange])? {
        items.lazy.compactMap { $0.pendingUpdate }.first
    }
}

extension RecentAction.Item {
    var pendingMerge: PendingMerge? {
        if case .pendingMerge(let merge) = self { merge } else { nil }
    }

    var pendingUpdate: (object: String, id: String, title: String, changes: [PendingChange])? {
        if case .pendingUpdate(let object, let id, let title, let changes) = self { (object, id, title, changes) } else { nil }
    }
}
#endif
