import SwiftUI

/// One screen of the add flow: a question and the fields that answer it.
struct CreateStep: Identifiable {
    enum Kind {
        case title                      // the record's name; required
        case fields                     // one or more field editors
        case relationSearch(FieldMetadata) // inline search-or-create (e.g. Company)
        case rest                       // every editable field not asked about
    }

    let id: String
    let question: String
    let kind: Kind
    var fields: [FieldMetadata] = []
}

extension ObjectMetadata {
    /// The questions asked when adding a record. People and companies get a
    /// curated order; fields missing from the workspace are skipped, and
    /// anything not asked about lands on a final optional "Anything else?" step.
    func createSteps() -> [CreateStep] {
        let editable = visibleFields.filter { FieldEditorKind(field: $0) != .readOnly }
        func existing(_ names: [String]) -> [FieldMetadata] {
            names.compactMap { name in editable.first { $0.name == name } }
        }

        var steps: [CreateStep] = []
        var asked = Set<String>()
        if let title = labelIdentifierField, editable.contains(where: { $0.id == title.id }) {
            let question = switch nameSingular {
            case "person": "What's their name?"
            case "company": "What's the company called?"
            default: "\(labelSingular) name"
            }
            steps.append(CreateStep(id: "title", question: question, kind: .title, fields: [title]))
            asked.insert(title.name)
        }

        let plan: [(id: String, question: String, names: [String])] = switch nameSingular {
        case "person": [
            ("company", "Where do they work?", ["company"]),
            ("contact", "How do you reach them?", ["emails", "phones"]),
            ("role", "What do they do?", ["jobTitle", "tghandle", "subTeam", "city"]),
            ("linkedin", "LinkedIn profile?", ["linkedinLink"]),
        ]
        case "company": [
            ("website", "What's their website?", ["domainName"]),
            ("profile", "Tier, owner and type", ["tier", "accountOwner", "companyType", "tag"]),
            ("relationship", "How do you work with them?", ["primaryContactChannel", "source", "currentStatus"]),
        ]
        default: []
        }
        for item in plan {
            let fields = existing(item.names)
            guard !fields.isEmpty else { continue }
            if fields.count == 1, FieldEditorKind(field: fields[0]) == .relation {
                steps.append(CreateStep(id: item.id, question: item.question, kind: .relationSearch(fields[0]), fields: fields))
            } else {
                steps.append(CreateStep(id: item.id, question: item.question, kind: .fields, fields: fields))
            }
            asked.formUnion(fields.map(\.name))
        }

        let rest = pinnedFirst(editable).filter { !asked.contains($0.name) }
        if !rest.isEmpty {
            steps.append(CreateStep(id: "rest", question: steps.count > 1 ? "Anything else?" : "Details", kind: .rest, fields: rest))
        }
        return steps
    }

    /// A draft with its title set from typed search text (split for FULL_NAME).
    func draft(titled text: String, base: Record = Record(id: "", values: [:])) -> Record {
        var record = base
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let title = labelIdentifierField, !trimmed.isEmpty else { return record }
        if title.type == .fullName {
            let parts = trimmed.split(separator: " ", maxSplits: 1).map(String.init)
            record[title.name] = ["firstName": .string(parts[0]), "lastName": .string(parts.count > 1 ? parts[1] : "")]
        } else {
            record[title.name] = .string(trimmed)
        }
        return record
    }
}

/// Typeform-style add flow: one question per screen, then POST.
struct CreateFlowView: View {
    let object: ObjectMetadata
    let onCreated: (Record) -> Void

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var draft: Record
    @State private var stepIndex = 0
    @State private var goingForward = true
    @State private var isSaving = false
    @State private var error: String?
    @State private var didPrefillOwner = false
    /// Every field on one page instead of one question per screen; remembered.
    @AppStorage(CreateFlowView.advancedModeKey) private var advancedMode = false
    private let steps: [CreateStep]

    static let advancedModeKey = "createFlow.advancedMode"

    init(object: ObjectMetadata, prefill: Record = Record(id: "", values: [:]), onCreated: @escaping (Record) -> Void) {
        self.object = object
        self.onCreated = onCreated
        self.steps = object.createSteps()
        self._draft = State(initialValue: prefill)
    }

    private var step: CreateStep? { steps.indices.contains(stepIndex) ? steps[stepIndex] : nil }
    private var isLast: Bool { stepIndex >= steps.count - 1 }

    private var hasTitle: Bool {
        let title = draft.title(in: object)
        return !title.isEmpty && title != "Untitled"
    }

    var body: some View {
        NavigationStack {
            Group {
                if advancedMode { advancedForm } else { questions }
            }
            .navigationTitle("New \(object.labelSingular.lowercased())")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                if hasTitle, advancedMode || !isLast {
                    // Enough to save; the rest can be filled in later.
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Create") { Task { await create() } }.bold().disabled(isSaving)
                            .accessibilityIdentifier("flow.\(object.nameSingular).createNow")
                    }
                }
            }
            .interactiveDismissDisabled(hasTitle)
            .onAppear {
                // Credit new records to whoever is signed in; they can still pick someone else.
                guard !didPrefillOwner, let me = app.currentMember else { return }
                didPrefillOwner = true
                draft = draft.prefillingOwner(me, in: object)
            }
        }
    }

    private var advancedToggle: some View {
        Toggle(isOn: $advancedMode.animation()) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Advanced mode")
                Text("Every field on one page").font(.caption).foregroundStyle(.secondary)
            }
        }
        .accessibilityIdentifier("flow.advanced")
    }

    /// The full card, like the edit screen.
    private var advancedForm: some View {
        Form {
            Section { advancedToggle }
            if let error {
                Section { Text(error).foregroundStyle(.red) }
            }
            RecordFormSections(object: object, draft: $draft)
        }
    }

    private var questions: some View {
        VStack(alignment: .leading, spacing: 0) {
            ProgressView(value: Double(stepIndex + 1), total: Double(max(steps.count, 1)))
                .padding(.horizontal)
                .animation(.easeInOut, value: stepIndex)
            if let step {
                StepView(object: object, step: step, draft: $draft, onAdvance: advance)
                    .id(step.id)
                    .transition(.asymmetric(
                        insertion: .move(edge: goingForward ? .trailing : .leading).combined(with: .opacity),
                        removal: .move(edge: goingForward ? .leading : .trailing).combined(with: .opacity)
                    ))
            }
            if stepIndex == 0 {
                advancedToggle
                    .padding(.horizontal)
                    .padding(.vertical, 10)
                    .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                    .padding(.horizontal)
            }
            if let error {
                Text(error).foregroundStyle(.red).font(.footnote).padding(.horizontal)
            }
            footer
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if stepIndex > 0 {
                Button { move(by: -1) } label: {
                    Image(systemName: "chevron.left").font(.title3.weight(.semibold)).frame(width: 52, height: 52)
                }
                .buttonStyle(.bordered).buttonBorderShape(.circle)
                .accessibilityLabel("Back")
            }
            Spacer()
            if case .title = step?.kind {} else if !isLast {
                Button("Skip") { move(by: 1) }.foregroundStyle(.secondary).accessibilityIdentifier("flow.\(object.nameSingular).skip")
            }
            Button {
                if isLast { Task { await create() } } else { advance() }
            } label: {
                HStack {
                    if isSaving { ProgressView().tint(.white) }
                    Text(isLast ? "Create \(object.labelSingular.lowercased())" : "Next")
                    if !isLast { Image(systemName: "arrow.right") }
                }
                .font(.headline)
                .padding(.horizontal, 22).frame(height: 52)
            }
            .buttonStyle(.borderedProminent).buttonBorderShape(.capsule)
            .disabled(!hasTitle || isSaving)
            .accessibilityIdentifier(isLast ? "flow.\(object.nameSingular).create" : "flow.\(object.nameSingular).next")
        }
        .padding()
    }

    private func advance() {
        guard hasTitle else { return }
        if isLast { Task { await create() } } else { move(by: 1) }
    }

    private func move(by delta: Int) {
        goingForward = delta > 0
        withAnimation(.snappy) { stepIndex = min(max(stepIndex + delta, 0), steps.count - 1) }
    }

    private func create() async {
        guard let service = app.service, hasTitle else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            let created = try await service.createRecord(object, values: draft.createPayload(for: object))
            app.didCreate(created, in: object)
            dismiss()
            onCreated(created)
        } catch {
            self.error = error.localizedDescription
        }
    }
}

extension Record {
    /// Body for POST: every writable field that has a value.
    func createPayload(for object: ObjectMetadata) -> [String: JSONValue] {
        values.filter { object.writableFieldNames.contains($0.key) && !$0.value.isNull }
    }

    /// Sets empty owner fields to `member`: the foreign key for the POST and
    /// the expanded member for display.
    func prefillingOwner(_ member: Record, in object: ObjectMetadata) -> Record {
        var copy = self
        for field in object.ownerFields where copy[field.joinColumnName].isNull {
            copy[field.joinColumnName] = .string(member.id)
            copy[field.name] = .object(member.values)
        }
        return copy
    }
}

extension ObjectMetadata {
    /// Editable links to a workspace member that mean "who owns this", like
    /// `company.accountOwner` and `opportunity.owner`. Add an `accountOwner`
    /// relation to People in Twenty and it is picked up here too.
    var ownerFields: [FieldMetadata] {
        visibleFields.filter { field in
            Self.ownerFieldNames.contains(field.name)
                && field.relation?.targetObjectMetadata?.nameSingular == "workspaceMember"
                && FieldEditorKind(field: field) == .relation
        }
    }

    static let ownerFieldNames: Set<String> = ["accountOwner", "owner"]
}

private struct StepView: View {
    let object: ObjectMetadata
    let step: CreateStep
    @Binding var draft: Record
    let onAdvance: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(step.question)
                .font(.largeTitle.bold())
                .padding(.horizontal)
                .padding(.top, 24)
                .accessibilityIdentifier("flow.question")
            switch step.kind {
            case .title:
                TitleStep(field: step.fields[0], draft: $draft, onSubmit: onAdvance)
            case .relationSearch(let field):
                RelationSearchStep(field: field, draft: $draft, onPicked: onAdvance)
            case .fields where step.fields.count == 1 && [.select, .multiSelect].contains(FieldEditorKind(field: step.fields[0])):
                InlineOptionsStep(field: step.fields[0], draft: $draft, onPicked: onAdvance)
            case .fields, .rest:
                Form {
                    ForEach(step.fields) { field in
                        if FieldEditorKind(field: field).needsSection {
                            Section(field.label) { FieldEditor(field: field, record: $draft) }
                        } else {
                            Section { FieldEditor(field: field, record: $draft) }
                        }
                    }
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

/// Big, auto-focused name input; Return moves on.
private struct TitleStep: View {
    let field: FieldMetadata
    @Binding var draft: Record
    let onSubmit: () -> Void
    @FocusState private var focus: Int?

    var body: some View {
        let value = Binding<JSONValue>(get: { draft[field.name] }, set: { draft[field.name] = $0 })
        VStack(spacing: 14) {
            if field.type == .fullName {
                bigField("First name", text: value.string("firstName"), tag: 0, id: "\(field.name).firstName")
                    .textContentType(.givenName)
                    .onSubmit { focus = 1 }
                bigField("Last name", text: value.string("lastName"), tag: 1, id: "\(field.name).lastName")
                    .textContentType(.familyName)
                    .onSubmit(onSubmit)
            } else {
                bigField(field.label, text: value.text(nullable: true), tag: 0, id: field.name)
                    .onSubmit(onSubmit)
            }
        }
        .padding(.horizontal)
        .onAppear { focus = 0 }
    }

    private func bigField(_ prompt: String, text: Binding<String>, tag: Int, id: String) -> some View {
        TextField(prompt, text: text)
            .font(.title2)
            .padding(.vertical, 12)
            .overlay(alignment: .bottom) { Rectangle().frame(height: 2).foregroundStyle(focus == tag ? Color.accentColor : Color.secondary.opacity(0.3)) }
            .focused($focus, equals: tag)
            .submitLabel(.next)
            .accessibilityIdentifier("flow.\(id)")
    }
}

/// Single select / multi-select answered by tapping big option rows.
private struct InlineOptionsStep: View {
    let field: FieldMetadata
    @Binding var draft: Record
    let onPicked: () -> Void

    private var isMulti: Bool { field.type == .multiSelect }
    private var selected: [String] {
        isMulti ? (draft[field.name].arrayValue ?? []).compactMap(\.stringValue) : [draft[field.name].stringValue].compactMap { $0 }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                ForEach(field.sortedOptions) { option in
                    let isOn = selected.contains(option.value)
                    Button {
                        if isMulti {
                            let next = isOn ? selected.filter { $0 != option.value } : selected + [option.value]
                            draft[field.name] = .array(field.sortedOptions.map(\.value).filter(next.contains).map(JSONValue.string))
                        } else {
                            draft[field.name] = isOn ? .null : .string(option.value)
                            if !isOn { onPicked() }
                        }
                    } label: {
                        HStack {
                            TagChip(label: option.label, colorName: option.color)
                            Spacer()
                            Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                                .font(.title2).foregroundStyle(isOn ? Color.accentColor : Color.secondary.opacity(0.4))
                        }
                        .padding(14)
                        .background(RoundedRectangle(cornerRadius: 14).fill(isOn ? Color.accentColor.opacity(0.1) : Color.secondary.opacity(0.08)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("option.\(option.label)")
                }
            }
            .padding(.horizontal)
        }
    }
}

/// Search the target object (e.g. companies); pick one, or create a new one
/// right here with its own add flow.
private struct RelationSearchStep: View {
    let field: FieldMetadata
    @Binding var draft: Record
    let onPicked: () -> Void

    @Environment(AppModel.self) private var app
    @State private var query = ""
    @State private var results: [Record] = []
    @State private var creatingTitle: String?
    @FocusState private var searchFocused: Bool

    private var target: ObjectMetadata? {
        field.relation?.targetObjectMetadata.flatMap { app.object(named: $0.nameSingular) }
    }

    private var current: String {
        FieldFormatter.relationTitle(draft[field.name])
    }

    var body: some View {
        if let target {
            VStack(spacing: 0) {
                List {
                    if !current.isEmpty {
                        Section {
                            HStack {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                                Text(current).font(.headline)
                                Spacer()
                                Button("Remove") {
                                    draft[field.joinColumnName] = .null
                                    draft[field.name] = .null
                                }
                                .font(.subheadline)
                            }
                        }
                    }
                    Section {
                        ForEach(results) { record in
                            Button { pick(record) } label: {
                                RecordRow(object: target, record: record)
                            }
                            .foregroundStyle(.primary)
                        }
                        if target.isWritable, target.isSystem != true {
                            let typed = query.trimmingCharacters(in: .whitespaces)
                            let exact = results.contains { $0.title(in: target).caseInsensitiveCompare(typed) == .orderedSame }
                            if !exact {
                                Button {
                                    creatingTitle = typed
                                } label: {
                                    Label(typed.isEmpty ? "Add a new \(target.labelSingular.lowercased())" : "Add “\(typed)” as a new \(target.labelSingular.lowercased())",
                                          systemImage: "plus.circle.fill")
                                        .font(.body.weight(.semibold))
                                }
                                .accessibilityIdentifier("flow.addRelated")
                            }
                        }
                    }
                }
                // Sits directly above the Back / Skip / Next buttons.
                searchField(prompt: "Search \(target.labelPlural.lowercased())")
            }
            .onAppear { searchFocused = current.isEmpty }
            .task(id: query) {
                if !query.isEmpty { try? await Task.sleep(for: .milliseconds(250)) }
                guard !Task.isCancelled, let service = app.service else { return }
                results = (try? await service.fetchRecords(target, search: query, after: nil).records.prefix(20).map { $0 }) ?? results
            }
            .sheet(item: Binding(get: { creatingTitle.map(Titled.init) }, set: { creatingTitle = $0?.text })) { item in
                CreateFlowView(object: target, prefill: target.draft(titled: item.text)) { created in
                    pick(created)
                }
            }
        }
    }

    private struct Titled: Identifiable { let text: String; var id: String { text } }

    private func searchField(prompt: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField(prompt, text: $query)
                .focused($searchFocused)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .accessibilityIdentifier("flow.search")
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 48)
        .background(Color.secondary.opacity(0.12), in: Capsule())
        .padding(.horizontal)
        .padding(.top, 8)
    }

    private func pick(_ record: Record) {
        draft[field.joinColumnName] = .string(record.id)
        draft[field.name] = .object(record.values)
        onPicked()
    }
}
