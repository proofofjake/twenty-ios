import SwiftUI

/// MULTI_SELECT editor: shows the current values as coloured chips and opens
/// a checklist of the field's options. Values are option `value` keys, as
/// Twenty stores them (e.g. `["VIP", "INVESTOR"]`), never labels.
struct MultiSelectEditor: View {
    let field: FieldMetadata
    @Binding var value: JSONValue
    @State private var isPicking = false

    private var selected: [String] {
        (value.arrayValue ?? []).compactMap(\.stringValue)
    }

    var body: some View {
        Button { isPicking = true } label: {
            HStack(alignment: .firstTextBaseline) {
                Text(field.label).foregroundStyle(.primary)
                Spacer(minLength: 12)
                if selected.isEmpty {
                    Text("None").foregroundStyle(.secondary)
                } else {
                    FlowLayout(spacing: 4) {
                        ForEach(selected, id: \.self) { key in
                            let option = field.option(for: key)
                            TagChip(label: option?.label ?? key, colorName: option?.color)
                        }
                    }
                    .frame(maxWidth: 220, alignment: .trailing)
                }
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
            }
        }
        .tint(.primary)
        .accessibilityIdentifier("edit.\(field.name)")
        .sheet(isPresented: $isPicking) {
            OptionPicker(field: field, allowsMultiple: true, selected: Set(selected)) { newSelection in
                // Keep the field's option order so the diff is stable.
                let ordered = field.sortedOptions.map(\.value).filter(newSelection.contains)
                // Values no longer in the option list (renamed/deleted options) are kept until cleared.
                let unknown = selected.filter { newSelection.contains($0) && field.option(for: $0) == nil }
                value = .array((ordered + unknown).map(JSONValue.string))
            }
        }
    }
}

/// SELECT editor: single choice from the field's options, or none.
struct SelectEditor: View {
    let field: FieldMetadata
    @Binding var value: JSONValue
    @State private var isPicking = false

    var body: some View {
        Button { isPicking = true } label: {
            HStack {
                Text(field.label).foregroundStyle(.primary)
                Spacer()
                if let key = value.stringValue {
                    let option = field.option(for: key)
                    TagChip(label: option?.label ?? key, colorName: option?.color)
                } else {
                    Text("None").foregroundStyle(.secondary)
                }
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
            }
        }
        .tint(.primary)
        .accessibilityIdentifier("edit.\(field.name)")
        .sheet(isPresented: $isPicking) {
            OptionPicker(field: field, allowsMultiple: false, selected: Set([value.stringValue].compactMap { $0 })) { newSelection in
                value = newSelection.first.map(JSONValue.string) ?? .null
            }
        }
    }
}

/// Searchable checklist of a field's options, shared by SELECT and MULTI_SELECT.
struct OptionPicker: View {
    let field: FieldMetadata
    let allowsMultiple: Bool
    @State var selected: Set<String>
    let onDone: (Set<String>) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    init(field: FieldMetadata, allowsMultiple: Bool, selected: Set<String>, onDone: @escaping (Set<String>) -> Void) {
        self.field = field
        self.allowsMultiple = allowsMultiple
        self._selected = State(initialValue: selected)
        self.onDone = onDone
    }

    private var options: [FieldOption] {
        let all = field.sortedOptions
        guard !query.isEmpty else { return all }
        return all.filter { $0.label.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        NavigationStack {
            List {
                if !allowsMultiple {
                    row(label: "None", color: nil, isOn: selected.isEmpty) {
                        selected = []
                        finish()
                    }
                }
                ForEach(options) { option in
                    row(label: option.label, color: option.color, isOn: selected.contains(option.value)) {
                        if allowsMultiple {
                            if selected.contains(option.value) { selected.remove(option.value) } else { selected.insert(option.value) }
                        } else {
                            selected = [option.value]
                            finish()
                        }
                    }
                }
                if field.sortedOptions.isEmpty {
                    Text("This field has no options. Add them in Twenty's data model settings.")
                        .foregroundStyle(.secondary)
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always))
            .navigationTitle(field.label)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                if allowsMultiple {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { finish() }.bold()
                    }
                    ToolbarItem(placement: .bottomBar) {
                        Button("Clear all", role: .destructive) { selected = [] }
                            .disabled(selected.isEmpty)
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func row(label: String, color: String?, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                if let color {
                    TagChip(label: label, colorName: color)
                } else {
                    Text(label).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: isOn ? (allowsMultiple ? "checkmark.circle.fill" : "checkmark") : (allowsMultiple ? "circle" : ""))
                    .foregroundStyle(isOn ? Color.accentColor : Color.secondary.opacity(0.5))
                    .font(.title3)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("option.\(label)")
    }

    private func finish() {
        onDone(selected)
        dismiss()
    }
}
