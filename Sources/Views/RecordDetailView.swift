import SwiftUI

struct RecordDetailView: View {
    let object: ObjectMetadata
    @State var record: Record

    @Environment(AppModel.self) private var app
    @State private var isEditing = false
    /// Target object and prefilled values for "Add person" etc.
    @State private var creating: RelatedCreate?
    @State private var error: String?

    struct RelatedCreate: Identifiable {
        let id = UUID()
        let object: ObjectMetadata
        let prefill: Record
    }

    var body: some View {
        List {
            Section {
                HStack(spacing: 14) {
                    RecordAvatar(object: object, record: record, size: 56)
                    Text(record.title(in: object)).font(.title2.bold())
                }
                .listRowBackground(Color.clear)
            }
            Section {
                ForEach(object.pinnedFirst(object.visibleFields).filter { $0.id != object.labelIdentifierField?.id }) { field in
                    FieldValueRow(field: field, value: record[field.name])
                }
            }
            ForEach(object.relatedLists(in: app.objects), id: \.field.id) { list in
                relatedSection(field: list.field, target: list.target)
            }
        }
        .navigationTitle(object.labelSingular)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if object.isWritable {
                Button("Edit") { isEditing = true }.accessibilityIdentifier("record.edit")
            }
        }
        .refreshable { await refresh() }
        // List rows are fetched without relations; load the full record here.
        .task { await refresh() }
        .alert("Couldn't refresh", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
        } message: {
            Text(error ?? "")
        }
        .sheet(isPresented: $isEditing) {
            RecordEditView(object: object, original: record) { saved in record = saved }
        }
        .sheet(item: $creating) { item in
            CreateFlowView(object: item.object, prefill: item.prefill) { _ in
                Task { await refresh() }
            }
        }
    }

    /// e.g. the People who work at this company, from the depth=1 fetch.
    @ViewBuilder
    private func relatedSection(field: FieldMetadata, target: ObjectMetadata) -> some View {
        let related = (record[field.name].arrayValue ?? []).compactMap(Record.init(json:))
            .map { app.savedRecords[$0.id] ?? $0 }
        Section {
            ForEach(related) { item in
                NavigationLink(value: Route.record(object: target.nameSingular, item)) {
                    RecordRow(object: target, record: item, showsCompany: object.nameSingular != "company")
                }
            }
            if related.isEmpty {
                Text("No \(field.label.lowercased()) yet").foregroundStyle(.secondary)
            }
            if let prefill = prefill(for: field, target: target), target.isWritable {
                Button("Add \(target.labelSingular.lowercased())", systemImage: "plus.circle.fill") {
                    creating = RelatedCreate(object: target, prefill: prefill)
                }
                .accessibilityIdentifier("related.add.\(field.name)")
            }
        } header: {
            Text(related.isEmpty ? field.label : "\(field.label) (\(related.count))")
        }
    }

    /// A new target record already linked back to this one
    /// (a person created from a company gets that `companyId`).
    private func prefill(for field: FieldMetadata, target: ObjectMetadata) -> Record? {
        guard let inverseName = field.relation?.targetFieldMetadata?.name,
              let inverse = target.field(named: inverseName),
              FieldEditorKind(field: inverse) == .relation else { return nil }
        return Record(id: "", values: [
            inverse.joinColumnName: .string(record.id),
            inverse.name: .object(record.values),
        ])
    }

    private func refresh() async {
        guard let service = app.service else { return }
        do {
            record = try await service.fetchRecord(object, id: record.id)
            app.didSave(record)
        } catch is CancellationError {
        } catch let urlError as URLError where urlError.code == .cancelled {
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// Read-only display of one field, with type-aware rendering.
struct FieldValueRow: View {
    let field: FieldMetadata
    let value: JSONValue

    var body: some View {
        switch field.type {
        case .multiSelect, .select:
            let keys = field.type == .multiSelect
                ? (value.arrayValue ?? []).compactMap(\.stringValue)
                : [value.stringValue].compactMap { $0 }
            HStack(alignment: .firstTextBaseline) {
                Text(field.label)
                Spacer(minLength: 16)
                if keys.isEmpty {
                    Text("—").foregroundStyle(.tertiary)
                } else {
                    FlowLayout(spacing: 4) {
                        ForEach(keys, id: \.self) { key in
                            let option = field.option(for: key)
                            TagChip(label: option?.label ?? key, colorName: option?.color)
                        }
                    }
                    .frame(maxWidth: 230, alignment: .trailing)
                }
            }
        case .emails:
            linkRows(FieldFormatter.emails(value).map { ($0, URL(string: "mailto:\($0)")) })
        case .phones:
            linkRows(FieldFormatter.phones(value).map { ($0, URL(string: "tel:\($0.filter { $0.isNumber || $0 == "+" })")) })
        case .links:
            linkRows(FieldFormatter.links(value).map { link in
                let url = link.url.contains("://") ? link.url : "https://\(link.url)"
                return (link.label ?? link.url, URL(string: url))
            })
        default:
            let text = FieldFormatter.plainText(value, field: field)
            LabeledContent(field.label) {
                Text(text.nilIfEmpty ?? "—")
                    .foregroundStyle(text.isEmpty ? .tertiary : .primary)
                    .multilineTextAlignment(.trailing)
                    .textSelection(.enabled)
            }
        }
    }

    @ViewBuilder
    private func linkRows(_ items: [(String, URL?)]) -> some View {
        if items.isEmpty {
            LabeledContent(field.label) { Text("—").foregroundStyle(.tertiary) }
        } else {
            LabeledContent(field.label) {
                VStack(alignment: .trailing, spacing: 4) {
                    ForEach(items, id: \.0) { title, url in
                        if let url { Link(title, destination: url).lineLimit(1) } else { Text(title) }
                    }
                }
            }
        }
    }
}
