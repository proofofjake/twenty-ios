import SwiftUI

/// Navigation destinations. Routes carry the object name so any screen can
/// push any object's record (e.g. a person from a company's People section).
enum Route: Hashable {
    case list(object: String)
    case record(object: String, Record)
}

/// Per-tab navigation path, shared through the environment so a create
/// sheet can push the record it just made.
@MainActor
@Observable
final class Navigator {
    var path = NavigationPath()
    func open(_ route: Route) { path.append(route) }
}

/// A tab's NavigationStack with every `Route` destination registered once.
struct RouteStack<Root: View>: View {
    @State private var navigator = Navigator()
    @ViewBuilder let root: () -> Root

    var body: some View {
        NavigationStack(path: $navigator.path) {
            root().navigationDestination(for: Route.self) { RouteView(route: $0) }
        }
        .environment(navigator)
    }
}

private struct RouteView: View {
    let route: Route
    @Environment(AppModel.self) private var app

    var body: some View {
        switch route {
        case .list(let name):
            if let object = app.object(named: name) { RecordListView(object: object) }
        case .record(let name, let record):
            if let object = app.object(named: name) { RecordDetailView(object: object, record: record) }
        }
    }
}

extension ObjectMetadata {
    /// Fields shown first on forms and detail screens: the title, then the
    /// website. Everything else keeps the workspace's field order.
    func pinnedFirst(_ fields: [FieldMetadata]) -> [FieldMetadata] {
        let pinnedNames = [labelIdentifierField?.name, "domainName"].compactMap { $0 }
        let pinned = pinnedNames.compactMap { name in fields.first { $0.name == name } }
        return pinned + fields.filter { field in !pinned.contains { $0.id == field.id } }
    }

    /// One-to-many relations worth listing on a record (People, Opportunities,
    /// …), skipping plumbing like attachments, notes targets and timeline.
    func relatedLists(in objects: [ObjectMetadata]) -> [(field: FieldMetadata, target: ObjectMetadata)] {
        let lists = fields.compactMap { field -> (FieldMetadata, ObjectMetadata)? in
            guard field.type == .relation, field.relationType == .oneToMany, field.isActive != false, field.isSystem != true,
                  let name = field.relation?.targetObjectMetadata?.nameSingular,
                  let target = objects.first(where: { $0.nameSingular == name }),
                  target.isSystem != true, target.isActive != false else { return nil }
            return (field, target)
        }
        // People first; the rest in schema order.
        return lists.filter { $0.1.nameSingular == "person" } + lists.filter { $0.1.nameSingular != "person" }
    }
}
