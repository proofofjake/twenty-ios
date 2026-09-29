import SwiftUI

/// Many-to-one relation (e.g. a person's company). Writes the foreign key
/// `<field>Id` and mirrors the picked record into `<field>` for display.
struct RelationEditor: View {
    let field: FieldMetadata
    @Binding var record: Record
    @Environment(AppModel.self) private var app
    @State private var isPicking = false

    private var target: ObjectMetadata? {
        field.relation?.targetObjectMetadata.flatMap { app.object(named: $0.nameSingular) }
    }

    var body: some View {
        Button { isPicking = true } label: {
            LabeledContent(field.label) {
                HStack {
                    let title = FieldFormatter.relationTitle(record[field.name])
                    Text(title.nilIfEmpty ?? "None").foregroundStyle(title.isEmpty ? .secondary : .primary)
                    Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                }
            }
        }
        .foregroundStyle(.primary)
        .disabled(target == nil)
        .accessibilityIdentifier("edit.\(field.name)")
        .sheet(isPresented: $isPicking) {
            if let target {
                RecordPicker(object: target, selectedID: record[field.joinColumnName].stringValue) { picked in
                    record[field.joinColumnName] = picked.map { .string($0.id) } ?? .null
                    record[field.name] = picked.map { .object($0.values) } ?? .null
                }
            }
        }
    }
}

/// Searchable list of records of one object, for choosing a relation target.
struct RecordPicker: View {
    let object: ObjectMetadata
    let selectedID: String?
    let onPick: (Record?) -> Void

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var records: [Record] = []
    @State private var error: String?
    @State private var isCreating = false

    var body: some View {
        NavigationStack {
            List {
                Button("None") { pick(nil) }.foregroundStyle(.secondary)
                ForEach(records) { record in
                    Button { pick(record) } label: {
                        HStack {
                            Text(record.title(in: object)).foregroundStyle(.primary)
                            Spacer()
                            if record.id == selectedID { Image(systemName: "checkmark").foregroundStyle(Color.accentColor) }
                        }
                    }
                }
                if object.isWritable, object.isSystem != true {
                    let typed = query.trimmingCharacters(in: .whitespaces)
                    Button {
                        isCreating = true
                    } label: {
                        Label(typed.isEmpty ? "Add a new \(object.labelSingular.lowercased())" : "Add “\(typed)” as a new \(object.labelSingular.lowercased())",
                              systemImage: "plus.circle.fill")
                            .font(.body.weight(.semibold))
                    }
                    .accessibilityIdentifier("picker.add")
                }
                if let error { Text(error).foregroundStyle(.red) }
            }
            .sheet(isPresented: $isCreating) {
                CreateFlowView(object: object, prefill: object.draft(titled: query)) { created in pick(created) }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always))
            .navigationTitle(object.labelSingular)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .task(id: query) {
                // Debounce typing.
                if !query.isEmpty { try? await Task.sleep(for: .milliseconds(300)) }
                guard !Task.isCancelled, let service = app.service else { return }
                do {
                    records = try await service.fetchRecords(object, search: query, after: nil).records
                    error = nil
                } catch is CancellationError {
                } catch {
                    self.error = error.localizedDescription
                }
            }
        }
    }

    private func pick(_ record: Record?) {
        onPick(record)
        dismiss()
    }
}
