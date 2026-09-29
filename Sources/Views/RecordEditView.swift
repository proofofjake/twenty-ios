import SwiftUI

/// Edits a copy of a record and PATCHes only the fields that changed.
/// New records go through `CreateFlowView`.
struct RecordEditView: View {
    let object: ObjectMetadata
    let original: Record
    let onSave: (Record) -> Void

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var draft: Record
    @State private var isSaving = false
    @State private var error: String?

    init(object: ObjectMetadata, original: Record, onSave: @escaping (Record) -> Void) {
        self.object = object
        self.original = original
        self.onSave = onSave
        self._draft = State(initialValue: original)
    }

    private var patch: [String: JSONValue] {
        draft.changes(from: original, writable: object.writableFieldNames)
    }

    var body: some View {
        NavigationStack {
            Form {
                if let error {
                    Section { Text(error).foregroundStyle(.red) }
                }
                RecordFormSections(object: object, draft: $draft)
            }
            .navigationTitle("Edit \(object.labelSingular)")
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(!patch.isEmpty)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Save") { Task { await save() } }
                            .bold()
                            .disabled(patch.isEmpty)
                            .accessibilityIdentifier("record.save")
                    }
                }
            }
        }
    }

    private func save() async {
        guard let service = app.service else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            let saved = try await service.updateRecord(object, id: original.id, patch: patch)
            // Keep anything the response didn't include (e.g. expanded relations).
            var merged = saved
            for (key, value) in draft.values where merged.values[key] == nil { merged.values[key] = value }
            app.didSave(merged)
            onSave(merged)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// Every editable field of a record as form sections: title, then website,
/// each in its own section, then simple fields together and composite fields
/// (emails, address, …) in sections of their own. Shared by the edit sheet
/// and the add flow's advanced mode.
struct RecordFormSections: View {
    let object: ObjectMetadata
    @Binding var draft: Record

    private var editableFields: [FieldMetadata] {
        object.pinnedFirst(object.visibleFields.filter { FieldEditorKind(field: $0) != .readOnly })
    }

    var body: some View {
        let pinnedCount = editableFields.prefix(2).filter { [object.labelIdentifierField?.name, "domainName"].contains($0.name) }.count
        let pinned = Array(editableFields.prefix(pinnedCount))
        let rest = Array(editableFields.dropFirst(pinnedCount))
        ForEach(pinned) { field in
            Section(field.label) { FieldEditor(field: field, record: $draft, showsLabel: false) }
        }
        let simple = rest.filter { !FieldEditorKind(field: $0).needsSection }
        if !simple.isEmpty {
            Section {
                ForEach(simple) { field in FieldEditor(field: field, record: $draft) }
            }
        }
        ForEach(rest.filter { FieldEditorKind(field: $0).needsSection }) { field in
            Section(field.label) { FieldEditor(field: field, record: $draft) }
        }
    }
}
