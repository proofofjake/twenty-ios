import SwiftUI

/// One choice in a filter: an option key, a member id, or a token.
struct FilterOption: Identifiable, Hashable {
    let id: String
    let label: String
    var colorName: String?
    var isToken = false
}

extension FieldMetadata {
    /// What can be picked for this field, in display order.
    func filterOptions(members: [Record], memberObject: ObjectMetadata?, hasMe: Bool) -> [FilterOption] {
        switch type {
        case .relation:
            var out: [FilterOption] = []
            if hasMe { out.append(FilterOption(id: ListFilter.me, label: "Me", isToken: true)) }
            if let memberObject {
                out += members.map { FilterOption(id: $0.id, label: $0.title(in: memberObject)) }
                    .sorted { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending }
            }
            out.append(FilterOption(id: ListFilter.none, label: "Unassigned", isToken: true))
            return out
        case .select:
            return sortedOptions.map { FilterOption(id: $0.value, label: $0.label, colorName: $0.color) }
                + [FilterOption(id: ListFilter.none, label: "No \(label.lowercased())", isToken: true)]
        default:
            return sortedOptions.map { FilterOption(id: $0.value, label: $0.label, colorName: $0.color) }
        }
    }

    /// Chip text: the label, or what's picked ("Tier 1 +1", "Me").
    func filterSummary(_ picked: Set<String>, options: [FilterOption]) -> String {
        let names = options.filter { picked.contains($0.id) }.map(\.label)
        // Owner chips show the person (with an icon); unset, "Account Owner" reads as "Owner".
        guard let first = names.first else { return isOwnerLink ? "Owner" : label }
        return names.count > 1 ? "\(first) +\(names.count - 1)" : first
    }
}

/// Chips pinned above a list: the first few filterable fields (tier, owner…)
/// each open their own picker; "Filters" shows every field at once.
struct FilterBar: View {
    let object: ObjectMetadata
    @Binding var filter: ListFilter
    let members: [Record]
    let memberObject: ObjectMetadata?
    let hasMe: Bool
    let resultCount: Int?

    @State private var editing: FieldMetadata?
    @State private var showingAll = false

    private var fields: [FieldMetadata] { object.filterableFields }
    private var primary: [FieldMetadata] { Array(fields.prefix(3)) }

    var body: some View {
        // No horizontal ScrollView: on iOS 26 one pinned under the navigation
        // bar isn't drawn. Show as many field chips as fit; the rest live
        // under "Filters".
        HStack(spacing: 8) {
            ViewThatFits(in: .horizontal) {
                ForEach(Array(stride(from: primary.count, through: 0, by: -1)), id: \.self) { n in
                    chipRow(Array(primary.prefix(n)))
                }
            }
            Spacer(minLength: 0)
            if !filter.isEmpty {
                Button { filter = ListFilter() } label: {
                    Image(systemName: "xmark.circle.fill").font(.title3).foregroundStyle(.secondary)
                }
                .accessibilityLabel("Clear filters")
                .accessibilityIdentifier("filter.clearAll")
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .sheet(item: $editing) { field in
            FilterSheet(title: field.label, fields: [field], filter: $filter, options: options, resultCount: resultCount, noun: object.labelPlural.lowercased())
        }
        .sheet(isPresented: $showingAll) {
            FilterSheet(title: "Filters", fields: fields, filter: $filter, options: options, resultCount: resultCount, noun: object.labelPlural.lowercased())
        }
    }

    private func chipRow(_ shown: [FieldMetadata]) -> some View {
        HStack(spacing: 8) {
            Button { showingAll = true } label: {
                Label(filter.activeFieldCount > 0 ? "\(filter.activeFieldCount)" : "Filters",
                      systemImage: "line.3.horizontal.decrease")
                    .labelStyle(CompactLabelStyle())
            }
            .buttonStyle(ChipButtonStyle(isActive: filter.activeFieldCount > 0))
            .accessibilityLabel(filter.activeFieldCount > 0 ? "Filters, \(filter.activeFieldCount) active" : "Filters")
            .accessibilityIdentifier("filter.all")

            ForEach(shown) { field in
                let picked = filter.values(for: field.name)
                Button { editing = field } label: {
                    HStack(spacing: 3) {
                        if field.isOwnerLink, !picked.isEmpty { Image(systemName: "person.fill").font(.caption) }
                        Text(field.filterSummary(picked, options: options(field))).lineLimit(1)
                        Image(systemName: "chevron.down").font(.caption2.weight(.semibold))
                    }
                }
                .buttonStyle(ChipButtonStyle(isActive: !picked.isEmpty))
                .accessibilityIdentifier("filter.chip.\(field.name)")
            }
        }
        .fixedSize()
    }

    private func options(_ field: FieldMetadata) -> [FilterOption] {
        field.filterOptions(members: members, memberObject: memberObject, hasMe: hasMe)
    }
}

/// Checklist of options for one or more fields. Changes apply as they're
/// tapped, so the list behind updates and the button shows the live count.
struct FilterSheet: View {
    let title: String
    let fields: [FieldMetadata]
    @Binding var filter: ListFilter
    let options: (FieldMetadata) -> [FilterOption]
    let resultCount: Int?
    let noun: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(fields) { field in
                    Section {
                        ForEach(options(field)) { option in
                            let on = filter.values(for: field.name).contains(option.id)
                            Button { filter.toggle(option.id, in: field.name) } label: {
                                HStack {
                                    if let color = option.colorName {
                                        TagChip(label: option.label, colorName: color)
                                    } else {
                                        Text(option.label).foregroundStyle(option.isToken ? .secondary : .primary)
                                    }
                                    Spacer()
                                    Image(systemName: on ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(on ? Color.accentColor : Color.secondary.opacity(0.5))
                                        .font(.title3)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(on ? .isSelected : [])
                            .accessibilityIdentifier("filter.option.\(field.name).\(option.id)")
                        }
                    } header: {
                        if fields.count > 1 {
                            HStack {
                                Text(field.label)
                                Spacer()
                                if !filter.values(for: field.name).isEmpty {
                                    Button("Clear") { filter.clear(field.name) }.font(.caption).textCase(nil)
                                }
                            }
                        }
                    } footer: {
                        if field.type == .multiSelect, fields.count == 1 || field == fields.last {
                            Text("Multi-select fields match records with any of the picked values.")
                        }
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Clear") { for field in fields { filter.clear(field.name) } }
                        .disabled(fields.allSatisfy { filter.values(for: $0.name).isEmpty })
                        .accessibilityIdentifier("filter.clear")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(resultCount.map { "Show \($0)" } ?? "Done") { dismiss() }
                        .fontWeight(.semibold)
                        .accessibilityIdentifier("filter.done")
                }
            }
        }
        .presentationDetents(fields.count == 1 ? [.medium, .large] : [.large])
    }
}

extension View {
    /// Pins `content` under the navigation bar: on iOS 26 as part of the
    /// glass bar (`safeAreaBar`), earlier as an inset on a bar background.
    @ViewBuilder func topBar<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        if #available(iOS 26.0, *) {
            safeAreaBar(edge: .top, spacing: 0, content: content)
        } else {
            safeAreaInset(edge: .top, spacing: 0) { content().background(.bar) }
        }
    }
}

struct ChipButtonStyle: ButtonStyle {
    let isActive: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(isActive ? .semibold : .regular))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .foregroundStyle(isActive ? Color.white : Color.primary)
            .background(isActive ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Color(.secondarySystemFill)), in: Capsule())
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}
