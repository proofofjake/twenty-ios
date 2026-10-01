import SwiftUI

/// Paged, searchable list of any object's records.
struct RecordListView: View {
    let object: ObjectMetadata
    @Environment(AppModel.self) private var app
    @Environment(Navigator.self) private var navigator
    @State private var isCreating = false
    @State private var deleting: Record?

    @State private var records: [Record] = []
    @State private var cursor: String?
    @State private var hasNextPage = false
    @State private var totalCount: Int?
    @State private var query = ""
    @State private var isLoading = false
    @State private var error: String?
    /// `app.listRevision` this list last loaded at; a create elsewhere makes it stale.
    @State private var loadedRevision = 0
    /// Company names for rows, looked up in one batch per page.
    @State private var relatedTitles: [String: String] = [:]
    /// Each listed company's owner (e.g. `accountOwnerId`), for people's
    /// inferred point of contact.
    @State private var companyOwners: [String: String] = [:]

    /// This list's saved filters (persisted per workspace by AppModel).
    private var filter: Binding<ListFilter> {
        Binding(get: { app.filter(for: object) }, set: { app.setFilter($0, for: object) })
    }
    private var isFiltered: Bool { !app.filter(for: object).isEmpty }
    private var memberObject: ObjectMetadata? { app.object(named: "workspaceMember") }

    var body: some View {
        List {
            ForEach(records.filter { !app.deletedIDs.contains($0.id) }) { listed in
                let record = app.savedRecords[listed.id] ?? listed
                NavigationLink(value: Route.record(object: object.nameSingular, record)) {
                    RecordRow(object: object, record: record, relatedTitles: relatedTitles, pointOfContact: pointOfContactName(record))
                }
                .onAppear { if record.id == records.last?.id { Task { await loadMore() } } }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    if object.isWritable {
                        Button { deleting = record } label: { Label("Delete", systemImage: "trash") }
                            .tint(.red)
                            .accessibilityIdentifier("row.delete")
                    }
                }
            }
            if isLoading { HStack { Spacer(); ProgressView(); Spacer() } }
            if let error {
                Text(error).foregroundStyle(.red)
            }
            if let totalCount, !records.isEmpty {
                let noun = (totalCount == 1 ? object.labelSingular : object.labelPlural).lowercased()
                Text("\(totalCount) \(noun)\(isFiltered ? (totalCount == 1 ? " matches these filters" : " match these filters") : "")")
                    .font(.footnote).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity).listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .overlay {
            if records.isEmpty, !isLoading, error == nil {
                if isFiltered {
                    ContentUnavailableView {
                        Label("No matches", systemImage: "line.3.horizontal.decrease")
                    } description: {
                        Text("No \(object.labelPlural.lowercased()) match these filters\(query.isEmpty ? "" : " and search").")
                    } actions: {
                        Button("Clear filters") { filter.wrappedValue = ListFilter() }
                            .accessibilityIdentifier("filter.emptyClear")
                    }
                } else {
                    ContentUnavailableView(query.isEmpty ? "No \(object.labelPlural)" : "No results", systemImage: "magnifyingglass")
                }
            }
        }
        .topBar {
            if !object.filterableFields.isEmpty {
                FilterBar(object: object, filter: filter, members: app.members, memberObject: memberObject,
                          hasMe: app.currentMember != nil, resultCount: totalCount)
            }
        }
        .navigationTitle(object.labelPlural)
        .overlay(alignment: .bottomTrailing) {
            if object.isWritable {
                AddButton(label: "New \(object.labelSingular.lowercased())") { isCreating = true }
                    .padding(20)
            }
        }
        .sheet(item: $deleting) { record in
            DeleteRecordSheet(object: object, record: record) {}
        }
        .sheet(isPresented: $isCreating) {
            CreateFlowView(object: object) { created in
                navigator.open(.record(object: object.nameSingular, created))
            }
        }
        .searchable(text: $query, prompt: "Search \(object.labelPlural.lowercased())")
        .refreshable { await reload() }
        .onAppear {
            // .task(id:) can miss a revision bump while this list is covered by
            // a pushed screen; catch up when it comes back.
            if loadedRevision != app.listRevision[object.nameSingular] ?? 0 { Task { await reload() } }
        }
        .task(id: "\(query)#\(app.listRevision[object.nameSingular] ?? 0)#\(app.filter(for: object).hashValue)") {
            if !query.isEmpty { try? await Task.sleep(for: .milliseconds(300)) }
            guard !Task.isCancelled else { return }
            await reload()
        }
    }

    private func reload() async {
        loadedRevision = app.listRevision[object.nameSingular] ?? 0
        cursor = nil
        hasNextPage = false
        await fetch(replacing: true)
    }

    /// Lists are fetched at depth=0, so fetch the names of the companies these
    /// rows point at in one `id[in]` request.
    private func loadCompanyNames(for page: [Record]) async {
        guard let field = object.companyRelationField,
              let company = app.object(named: "company"), let service = app.service else { return }
        let ids = Set(page.compactMap { $0[field.joinColumnName].stringValue }).subtracting(relatedTitles.keys)
        guard !ids.isEmpty, let found = try? await service.fetchRecords(company, ids: Array(ids)) else { return }
        let ownerColumn = company.visibleFields.first(where: \.isOwnerLink)?.joinColumnName
        for record in found {
            relatedTitles[record.id] = record.title(in: company)
            if let ownerColumn, let owner = record[ownerColumn].stringValue { companyOwners[record.id] = owner }
        }
    }

    /// "Raph": their company's account owner, else whoever added them.
    private func pointOfContactName(_ record: Record) -> String? {
        guard let sources = object.pointOfContact else { return nil }
        let companyOwner = sources.companyJoinColumn.flatMap { record[$0].stringValue }.flatMap { companyOwners[$0] }
        return app.memberName(sources.memberID(for: record, companyOwnerID: companyOwner)?.id)
    }

    private func loadMore() async {
        guard hasNextPage, !isLoading else { return }
        await fetch(replacing: false)
    }

    private func fetch(replacing: Bool) async {
        guard let service = app.service else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let page = try await service.fetchRecords(object, search: query, filter: app.filter(for: object),
                                                      memberID: app.currentMember?.id, after: replacing ? nil : cursor)
            records = replacing ? page.records : records + page.records.filter { new in !records.contains { $0.id == new.id } }
            await loadCompanyNames(for: page.records)
            cursor = page.endCursor
            hasNextPage = page.hasNextPage
            totalCount = page.totalCount
            error = nil
        } catch is CancellationError {
        } catch let urlError as URLError where urlError.code == .cancelled {
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct CompactLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.icon.font(.caption)
            configuration.title
        }
    }
}

extension ObjectMetadata {
    /// The many-to-one relation to Company (e.g. `person.company`), if any.
    var companyRelationField: FieldMetadata? {
        fields.first {
            $0.type == .relation && $0.relationType == .manyToOne && $0.isActive != false
                && $0.relation?.targetObjectMetadata?.nameSingular == "company"
        }
    }
}

/// Large floating "+" for creating a record.
struct AddButton: View {
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 64, height: 64)
                .background(Color.accentColor.gradient, in: Circle())
                .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
        }
        .accessibilityLabel(label)
        .accessibilityIdentifier("list.add")
    }
}

struct RecordRow: View {
    let object: ObjectMetadata
    let record: Record
    /// Titles of related records by id (e.g. company names), for lists
    /// fetched without expanded relations.
    var relatedTitles: [String: String] = [:]
    /// False where the company is already obvious (a company's People list).
    var showsCompany = true
    /// Inferred internal point of contact (people without an owner field).
    var pointOfContact: String?

    /// "Northwind Exchange" for a person, from the expanded relation or the lookup.
    private var companyName: String? {
        guard showsCompany, let field = object.companyRelationField else { return nil }
        let expanded = FieldFormatter.relationTitle(record[field.name])
        if !expanded.isEmpty { return expanded }
        return record[field.joinColumnName].stringValue.flatMap { relatedTitles[$0] }
    }

    /// A second line under the title: first email, domain, or job title.
    private var subtitleField: FieldMetadata? {
        for name in ["emails", "jobTitle", "domainName", "city"] {
            if let field = object.field(named: name), field.isActive != false { return field }
        }
        return nil
    }

    /// First visible multi-select or select field, shown as chips in the row.
    private var tagField: FieldMetadata? {
        object.visibleFields.first { $0.type == .multiSelect } ?? object.visibleFields.first { $0.type == .select && $0.name != "stage" }
    }

    var body: some View {
        HStack(spacing: 12) {
            RecordAvatar(object: object, record: record)
            VStack(alignment: .leading, spacing: 3) {
                Text(record.title(in: object)).font(.body.weight(.medium))
                if let companyName {
                    Label(companyName, systemImage: "building.2")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .labelStyle(CompactLabelStyle())
                        .lineLimit(1)
                }
                if let pointOfContact {
                    Label(pointOfContact, systemImage: "person.crop.circle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .labelStyle(CompactLabelStyle())
                        .accessibilityLabel("Point of contact \(pointOfContact)")
                }
                if let subtitleField {
                    let subtitle = subtitleField.type == .emails
                        ? FieldFormatter.emails(record[subtitleField.name]).first ?? ""
                        : FieldFormatter.plainText(record[subtitleField.name], field: subtitleField)
                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .font(companyName == nil ? .subheadline : .footnote)
                            .foregroundStyle(companyName == nil ? .secondary : .tertiary)
                            .lineLimit(1)
                    }
                }
                if let tagField {
                    let keys = tagField.type == .multiSelect
                        ? (record[tagField.name].arrayValue ?? []).compactMap(\.stringValue)
                        : [record[tagField.name].stringValue].compactMap { $0 }
                    if !keys.isEmpty {
                        HStack(spacing: 4) {
                            ForEach(keys.prefix(3), id: \.self) { key in
                                let option = tagField.option(for: key)
                                TagChip(label: option?.label ?? key, colorName: option?.color).font(.caption)
                            }
                            if keys.count > 3 { Text("+\(keys.count - 3)").font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }
}

struct Avatar: View {
    let title: String
    let isPerson: Bool
    var size: CGFloat = 38

    var body: some View {
        let initials = title.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined().uppercased()
        Text(initials.isEmpty ? "?" : initials)
            .font(.system(size: size * 0.4, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(color.gradient, in: isPerson ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: size * 0.22)))
    }

    private var color: Color {
        let palette: [Color] = [.blue, .purple, .pink, .orange, .teal, .indigo, .green, .red]
        let hash = title.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF }
        return palette[hash % palette.count]
    }
}
