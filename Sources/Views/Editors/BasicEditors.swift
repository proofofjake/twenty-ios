import SwiftUI

extension Binding where Value == JSONValue {
    /// String binding into a key of a composite value; empty string is stored as "".
    func string(_ key: String) -> Binding<String> {
        Binding<String>(
            get: { wrappedValue[key]?.stringValue ?? "" },
            set: { wrappedValue = wrappedValue.setting(key, to: .string($0)) }
        )
    }

    /// Whole-value string binding; empty text is stored as null (or "" when not nullable).
    func text(nullable: Bool) -> Binding<String> {
        Binding<String>(
            get: { wrappedValue.stringValue ?? "" },
            set: { wrappedValue = $0.isEmpty && nullable ? .null : .string($0) }
        )
    }
}

struct TextFieldEditor: View {
    let field: FieldMetadata
    @Binding var value: JSONValue
    var showsLabel = true

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if showsLabel { Text(field.label).font(.caption).foregroundStyle(.secondary) }
            TextField(field.label, text: $value.text(nullable: field.isNullable != false), axis: .vertical)
                .lineLimit(1...6)
                .accessibilityIdentifier("edit.\(field.name)")
        }
    }
}

struct NumberFieldEditor: View {
    let field: FieldMetadata
    @Binding var value: JSONValue
    @State private var text = ""

    var body: some View {
        LabeledContent(field.label) {
            TextField("0", text: $text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .accessibilityIdentifier("edit.\(field.name)")
        }
        .onAppear { text = value.doubleValue.map { $0.formatted(.number.grouping(.never)) } ?? "" }
        .onChange(of: text) { _, newText in
            let normalized = newText.replacingOccurrences(of: ",", with: ".")
            if newText.isEmpty { value = .null } else if let number = Double(normalized) { value = .number(number) }
        }
    }
}

struct BooleanEditor: View {
    let field: FieldMetadata
    @Binding var value: JSONValue

    var body: some View {
        Toggle(field.label, isOn: Binding(get: { value.boolValue ?? false }, set: { value = .bool($0) }))
            .accessibilityIdentifier("edit.\(field.name)")
    }
}

struct DateEditor: View {
    let field: FieldMetadata
    let includesTime: Bool
    @Binding var value: JSONValue

    private var date: Date? { FieldFormatter.parseDate(value.stringValue) }

    var body: some View {
        if let date {
            HStack {
                DatePicker(
                    field.label,
                    selection: Binding(get: { date }, set: { store($0) }),
                    displayedComponents: includesTime ? [.date, .hourAndMinute] : [.date]
                )
                Button { value = .null } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        } else {
            LabeledContent(field.label) {
                Button("Set date") { store(Date()) }
            }
        }
    }

    private func store(_ date: Date) {
        value = .string(includesTime ? FieldFormatter.dateTimeString(date) : FieldFormatter.dayString(date))
    }
}

struct RatingEditor: View {
    let field: FieldMetadata
    @Binding var value: JSONValue

    var body: some View {
        let current = FieldFormatter.rating(value) ?? 0
        LabeledContent(field.label) {
            HStack(spacing: 6) {
                ForEach(1...5, id: \.self) { star in
                    Image(systemName: star <= current ? "star.fill" : "star")
                        .foregroundStyle(star <= current ? Color.yellow : Color.secondary)
                        .onTapGesture {
                            // Tapping the current rating clears it, like Twenty's web UI.
                            value = star == current ? .null : .string("RATING_\(star)")
                        }
                }
            }
            .font(.title3)
        }
    }
}

/// ARRAY: a free-form list of strings.
struct StringListEditor: View {
    let field: FieldMetadata
    @Binding var value: JSONValue
    @State private var draft = ""

    private var items: [String] { (value.arrayValue ?? []).compactMap(\.stringValue) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(field.label).font(.caption).foregroundStyle(.secondary)
            if !items.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                        HStack(spacing: 4) {
                            Text(item)
                            Button { remove(at: index) } label: { Image(systemName: "xmark").font(.caption2.bold()) }
                                .buttonStyle(.plain)
                        }
                        .font(.subheadline)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Color.secondary.opacity(0.15), in: Capsule())
                    }
                }
            }
            HStack {
                TextField("Add item", text: $draft).onSubmit(add)
                Button("Add", action: add).disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private func add() {
        let item = draft.trimmingCharacters(in: .whitespaces)
        guard !item.isEmpty else { return }
        value = .array((items + [item]).map(JSONValue.string))
        draft = ""
    }

    private func remove(at index: Int) {
        var copy = items
        copy.remove(at: index)
        value = copy.isEmpty ? .null : .array(copy.map(JSONValue.string))
    }
}

/// Fallback for types the app can't edit yet.
struct ReadOnlyFieldRow: View {
    let field: FieldMetadata
    let value: JSONValue

    var body: some View {
        LabeledContent(field.label) {
            Text(FieldFormatter.plainText(value, field: field).nilIfEmpty ?? "—")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
