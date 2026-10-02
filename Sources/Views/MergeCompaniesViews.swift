#if DEBUG
import SwiftUI

/// The deck's merge window: which company survives, and for each field that
/// differs, whose value it keeps (Claude's picks in orange). "Add to Recent
/// actions" only stages it; Merge… there runs it.
struct MergeCompaniesSheet: View {
    typealias Row = ClaudeGuesses.MergeRow

    let suggestion: ClaudeGuesses.MergeSuggestion
    /// Staged in Recent actions.
    let onStaged: (RecentAction) -> Void
    /// "Not duplicates": dismissed for good.
    let onNotDuplicates: () -> Void

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    /// Depth 1 (for people and other related lists), in the suggestion's order.
    @State private var records: [Record] = []
    @State private var rows: [Row] = []
    @State private var survivor: String
    /// Field name → record id, for options tapped; the rest use the default.
    @State private var chosen: [String: String] = [:]
    @State private var isLoading = true
    @State private var error: String?

    init(suggestion: ClaudeGuesses.MergeSuggestion, onStaged: @escaping (RecentAction) -> Void, onNotDuplicates: @escaping () -> Void) {
        self.suggestion = suggestion
        self.onStaged = onStaged
        self.onNotDuplicates = onNotDuplicates
        _survivor = State(initialValue: suggestion.merge.keep)
    }

    private var merge: ClaudeGuesses.Merge { suggestion.merge }
    private var object: ObjectMetadata? { app.object(named: "company") }
    private var others: [Record] { records.filter { $0.id != survivor } }

    var body: some View {
        NavigationStack {
            Form {
                header
                if isLoading {
                    Section { HStack { Spacer(); ProgressView(); Spacer() } }
                } else if let error {
                    Section { Text(error).foregroundStyle(.red) }
                } else {
                    keepSection
                    ForEach(rows) { fieldSection($0) }
                    movesSection
                    actionSection
                }
            }
            .navigationTitle("Claude's suggestion")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .task { await load() }
        }
        .presentationDetents([.large])
    }

    private var header: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Label {
                        Text("Merge \(merge.ids.count) companies")
                    } icon: {
                        Image(systemName: "arrow.triangle.merge").foregroundStyle(.orange)
                    }
                        .font(.title3.bold())
                        .accessibilityIdentifier("merge.title")
                    Spacer()
                    if let confidence = merge.confidence { ConfidenceBadge(confidence: confidence) }
                }
                if let reason = merge.reason {
                    Text(reason).font(.subheadline).foregroundStyle(.secondary)
                }
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4))
        }
    }

    // MARK: Keep

    private var keepSection: some View {
        Section {
            ForEach(records, id: \.id) { record in
                let selected = survivor == record.id
                Button {
                    withAnimation(.snappy) { survivor = record.id }
                } label: {
                    HStack(spacing: 12) {
                        Check(selected: selected)
                        if let object { RecordAvatar(object: object, record: record, size: 34) }
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 4) {
                                Text(suggestion.title(of: record.id)).fontWeight(.semibold)
                                if record.id == merge.keep {
                                    Image(systemName: "sparkles").foregroundStyle(.orange).accessibilityLabel("Claude's pick")
                                }
                            }
                            Text(subtitle(record)).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(selected ? .isSelected : [])
                .accessibilityValue(selected ? "Kept" : "")
                .accessibilityIdentifier("merge.keep.\(record.id)")
            }
        } header: {
            Text("Keep")
        } footer: {
            Text("The one kept keeps its id and links; the rest move to it.")
        }
    }

    /// "cobaltcustody.example · 1 person"
    private func subtitle(_ record: Record) -> String {
        let website = FieldFormatter.links(record["domainName"]).first.map { ClaudeGuesses.host(from: $0.url) ?? $0.url } ?? "No website"
        let count = peopleField.map { record[$0.name].arrayValue?.count ?? 0 }
        let people = count.map { $0 == 0 ? "No people" : $0 == 1 ? "1 person" : "\($0) people" }
        return [website, people].compactMap { $0 }.joined(separator: " · ")
    }

    private var peopleField: FieldMetadata? {
        object?.relatedLists(in: app.objects).first { $0.target.nameSingular == "person" }?.field
    }

    // MARK: Fields

    private func selection(_ row: Row) -> String? {
        chosen[row.id] ?? ClaudeGuesses.defaultChoice(for: row, survivor: survivor)
    }

    /// "Cobalt Custody (kept)", "Cobalt Custody Ltd (deleted)": clear even when the names match.
    private func source(_ id: String) -> String {
        suggestion.title(of: id) + (id == survivor ? " (kept)" : " (deleted)")
    }

    private func fieldSection(_ row: Row) -> some View {
        Section {
            if row.kind == .combined, let combined = row.combined {
                VStack(alignment: .leading, spacing: 6) {
                    if combined.chips.isEmpty {
                        Text(combined.display)
                    } else {
                        FlowLayout(spacing: 4) {
                            ForEach(combined.chips, id: \.self) { chip in
                                Text(chip).font(.subheadline).padding(.horizontal, 8).padding(.vertical, 3)
                                    .background(Color.secondary.opacity(0.12), in: Capsule())
                            }
                        }
                    }
                    if let reason = row.pick?.reason {
                        Label(reason, systemImage: "sparkles").font(.caption).foregroundStyle(.orange)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("merge.combined.\(row.id)")
            } else {
                ForEach(row.values, id: \.recordID) { value in option(value, in: row) }
            }
        } header: {
            Text(row.field.label)
        } footer: {
            switch row.kind {
            case .combined: Text("Combined: Twenty keeps every value from both.")
            case .primary:
                Text(others.count > 1 ? "The others are kept as secondary \(row.secondaryNoun)s." : "The other is kept as a secondary \(row.secondaryNoun).")
            case .choice: EmptyView()
            }
        }
    }

    private func option(_ value: ClaudeGuesses.MergeValue, in row: Row) -> some View {
        let selected = selection(row) == value.recordID
        let isClaudesPick = row.pick?.from == value.recordID
        return Button {
            withAnimation(.snappy) { chosen[row.id] = value.recordID }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Check(selected: selected)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(value.isEmpty ? "Empty" : value.display)
                            .foregroundStyle(value.isEmpty ? Color.secondary : isClaudesPick ? Color.orange : Color.primary)
                            .fontWeight(isClaudesPick ? .semibold : .regular)
                            .lineLimit(4)
                        if isClaudesPick {
                            Image(systemName: "sparkles").font(.caption).foregroundStyle(.orange).accessibilityLabel("Claude's pick")
                        }
                    }
                    Text(source(value.recordID)).font(.caption).foregroundStyle(.secondary)
                    if isClaudesPick, let reason = row.pick?.reason {
                        Text(reason).font(.caption).foregroundStyle(.orange)
                    }
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(value.isEmpty)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityValue(selected ? "Selected" : "")
        .accessibilityIdentifier("merge.option.\(row.id).\(value.recordID)")
    }

    // MARK: Moves and actions

    private var movesSection: some View {
        let kept = suggestion.title(of: survivor)
        let moves = object.flatMap { ClaudeGuesses.moves(from: others, object: $0, objects: app.objects) }
        return Section {
            Label {
                Text(moves.map { "Moves to \(kept): \($0)" } ?? "Nothing else to move to \(kept)")
            } icon: {
                Image(systemName: "arrow.right.circle").foregroundStyle(.secondary)
            }
                .accessibilityIdentifier("merge.moves")
        }
    }

    private var actionSection: some View {
        Section {
            VStack(spacing: 14) {
                Label("\(ClaudeGuesses.list(others.map { suggestion.title(of: $0.id) })) will be permanently deleted. Twenty can't undo a merge.",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("merge.warning")
                Button(action: stage) {
                    Label("Add to Recent actions", systemImage: "tray.and.arrow.down")
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .accessibilityIdentifier("merge.stage")
                Button {
                    onNotDuplicates()
                    dismiss()
                } label: {
                    Text("Not duplicates").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("merge.dismiss")
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4))
        } footer: {
            Text("Nothing changes in Twenty until you merge it from Settings → Recent actions. **Not duplicates** stops Claude suggesting it.")
        }
    }

    private func stage() {
        guard let object, let kept = records.first(where: { $0.id == survivor }) else { return }
        let overrides = ClaudeGuesses.mergeOverrides(rows: rows, selection: chosen, records: records, survivor: survivor)
        let action = app.stageMerge(keep: kept, merging: others, of: object, overrides: overrides)
        dismiss()
        onStaged(action)
    }

    private func load() async {
        guard isLoading, let service = app.service, let object else { return }
        var loaded: [Record] = []
        for record in suggestion.records {
            do {
                loaded.append(try await service.fetchRecord(object, id: record.id))
            } catch {
                self.error = "Couldn't load \(suggestion.title(of: record.id)): \(error.localizedDescription)"
                isLoading = false
                return
            }
        }
        records = loaded
        rows = ClaudeGuesses.mergeRows(records: loaded, object: object, picks: merge.fields, members: app.members,
                                       memberObject: app.object(named: "workspaceMember"))
        isLoading = false
    }
}

/// Recent actions → Merge…: what's kept, what's deleted for good and what
/// moves, confirmed with a slide because Twenty can't undo it.
struct MergeConfirmSheet: View {
    let action: RecentAction
    /// "Merged Cobalt Custody Ltd into Cobalt Custody", after it's done.
    /// The caller then drops the action from Recent actions.
    let onMerged: (String) -> Void

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var moves: String?
    @State private var isWorking = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                if let merge = action.pendingMerge {
                    Section("Keeps") {
                        Label(merge.keepTitle, systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.primary)
                        ForEach(merge.overrides, id: \.field) { change in
                            LabeledContent(change.label, value: change.summary)
                                .font(.subheadline)
                        }
                    }
                    Section("Deletes for good") {
                        ForEach(Array(zip(merge.mergeIDs, merge.mergeTitles)), id: \.0) { _, title in
                            Label(title, systemImage: "trash").foregroundStyle(.red)
                        }
                    }
                    Section("Moves to \(merge.keepTitle)") {
                        Text(moves ?? "Nothing else to move").accessibilityIdentifier("merge.confirm.moves")
                    }
                    Section {
                        Label("Twenty deletes \(ClaudeGuesses.list(merge.mergeTitles)) outright: not to the trash, and a merge can't be undone. A copy of every record is saved to merge-log.jsonl on this device first.",
                              systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                    if let error {
                        Section { Text(error).foregroundStyle(.red).accessibilityIdentifier("merge.confirm.error") }
                    }
                    Section {
                        SlideToConfirm(title: "Slide to merge", systemImage: "arrow.triangle.merge", isWorking: isWorking) {
                            Task { await run() }
                        }
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                    }
                }
            }
            .navigationTitle("Merge into \(action.pendingMerge?.keepTitle ?? "company")?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(isWorking) }
            }
            .task { await loadMoves() }
        }
        .presentationDetents([.large])
        .interactiveDismissDisabled(isWorking)
    }

    /// From the records as they are now (depth 1).
    private func loadMoves() async {
        guard let merge = action.pendingMerge, let service = app.service, let object = app.object(named: merge.object) else { return }
        var records: [Record] = []
        for id in merge.mergeIDs {
            guard let record = try? await service.fetchRecord(object, id: id) else { continue }
            records.append(record)
        }
        moves = ClaudeGuesses.moves(from: records, object: object, objects: app.objects)
    }

    private func run() async {
        guard let merge = action.pendingMerge else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            // The row presenting this sheet goes with the action, so it's dropped after dismissal (onMerged).
            let skipped = try await app.applyMerge(action, discarding: false)
            dismiss()
            onMerged((["Merged \(ClaudeGuesses.list(merge.mergeTitles)) into \(merge.keepTitle)"] + skipped.map(\.message)).joined(separator: " · "))
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// A radio-style check for one-of-several choices.
private struct Check: View {
    let selected: Bool

    var body: some View {
        Image(systemName: selected ? "checkmark.circle.fill" : "circle")
            .font(.title3)
            .foregroundStyle(selected ? Color.orange : Color.secondary)
            .accessibilityHidden(true)
    }
}
#endif
