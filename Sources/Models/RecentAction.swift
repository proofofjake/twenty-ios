import Foundation

/// Something the user did that can be undone for 24 hours: one delete, with
/// the people it took along and the blocklist entry it added.
struct RecentAction: Codable, Identifiable, Hashable, Sendable {
    enum Item: Codable, Hashable, Sendable {
        /// A record soft-deleted into Twenty's trash; undo restores it.
        case deleted(object: String, id: String, title: String)
        /// A blocklist entry this app created; undo removes it.
        case blocked(id: String, handle: String)
    }

    var id = UUID()
    var date = Date()
    var items: [Item] = []

    static let lifetime: TimeInterval = 24 * 3600

    var isExpired: Bool { Date().timeIntervalSince(date) > Self.lifetime }

    /// "Deleted Lake Como Villas and 2 people · blocked @lakecomovillas.it"
    var summary: String {
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
}
