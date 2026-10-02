import SwiftUI

/// "Deleted Lake Como Villas · Undo", shown above the tab bar for a few
/// seconds after a delete. Recent actions in Settings keeps it for 24 hours.
struct UndoBanner: View {
    let action: RecentAction
    @Environment(AppModel.self) private var app
    @State private var isUndoing = false
    @State private var error: String?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: error == nil ? "trash" : "exclamationmark.triangle.fill")
                .foregroundStyle(error == nil ? Color.secondary : Color.red)
            Text(error ?? action.summary).font(.subheadline).lineLimit(2)
            Spacer(minLength: 8)
            if isUndoing {
                ProgressView()
            } else {
                Button("Undo") { Task { await undo() } }
                    .fontWeight(.semibold)
                    .accessibilityIdentifier("undo.banner")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
        .padding(.horizontal)
        .task(id: action.id) {
            try? await Task.sleep(for: .seconds(6))
            if !isUndoing, app.undoBanner?.id == action.id { app.undoBanner = nil }
        }
    }

    private func undo() async {
        isUndoing = true
        defer { isUndoing = false }
        do { try await app.undo(action) } catch { self.error = "Couldn't undo: \(error.localizedDescription)" }
    }
}

/// Settings section listing the last 24 hours of deletes. Each can be
/// undone, or committed: permanently deleted from Twenty so it's done.
/// Debug builds also list Claude's staged guesses, to apply or discard.
struct RecentActionsSection: View {
    @Environment(AppModel.self) private var app
    @State private var working: UUID?
    @State private var isCommittingAll = false
    @State private var confirming: RecentAction?
    @State private var confirmingAll = false
    @State private var error: String?
    #if DEBUG
    @State private var isApplyingAll = false
    /// What the last Apply did, e.g. "Applied Aberdeenplc · Skipped website: already set".
    @State private var notice: String?
    /// The staged merge being confirmed (Merge…).
    @State private var merging: RecentAction?
    /// Merged: dropped from Recent actions once its sheet is dismissed.
    @State private var merged: UUID?
    #endif

    private var busy: Bool {
        #if DEBUG
        if isApplyingAll { return true }
        #endif
        return working != nil || isCommittingAll
    }

    /// Commit and Commit all only apply to deletes.
    private var deleteCount: Int { app.recentActions.filter(\.hasDeletes).count }

    var body: some View {
        Section {
            if app.recentActions.isEmpty {
                Text("Nothing in the last 24 hours").foregroundStyle(.secondary)
            }
            ForEach(app.recentActions) { action in
                #if DEBUG
                if action.isPendingMerge {
                    mergeRow(action)
                } else if action.isPendingUpdate {
                    pendingRow(action)
                } else {
                    deleteRow(action)
                }
                #else
                deleteRow(action)
                #endif
            }
            #if DEBUG
            if let notice { Text(notice).font(.footnote).foregroundStyle(.secondary).accessibilityIdentifier("guess.notice") }
            #endif
            if let error { Text(error).font(.footnote).foregroundStyle(.red) }
        } header: {
            HStack {
                Text("Recent actions")
                Spacer()
                #if DEBUG
                if pendingActions.count > 1 {
                    if isApplyingAll { ProgressView() } else {
                        Button("Apply all guesses") { Task { await applyAll() } }
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.orange)
                            .textCase(nil)
                            .disabled(busy)
                            .accessibilityIdentifier("guess.applyAll")
                    }
                }
                #endif
                if deleteCount > 1 {
                    if isCommittingAll { ProgressView() } else {
                        Button(deleteCount == app.recentActions.count ? "Commit all" : "Commit all deletes") { confirmingAll = true }
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.red)
                            .textCase(nil)
                            .disabled(busy)
                            .accessibilityIdentifier("commit.all")
                    }
                }
            }
        } footer: {
            #if DEBUG
            Text("Deletes from the last 24 hours on this device. **Undo** restores them from Twenty's trash and removes any block they added. **Commit** permanently deletes them from Twenty (blocks stay) and can't be undone. Older deletions stay in Twenty's trash: restore or empty them from **Deleted** on the web.\n\nClaude's guesses you accepted wait here, without expiring, until you **Apply** them, which writes only the fields that are still empty. **Discard** drops one without touching Twenty, and it can come back in the deck. Merges wait for **Merge…**, which can't be undone; **Apply all guesses** leaves them out.")
            #else
            Text("Deletes from the last 24 hours on this device. **Undo** restores them from Twenty's trash and removes any block they added. **Commit** permanently deletes them from Twenty (blocks stay) and can't be undone. Older deletions stay in Twenty's trash: restore or empty them from **Deleted** on the web.")
            #endif
        }
        .confirmationDialog("Permanently delete from Twenty?", isPresented: Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } }), titleVisibility: .visible, presenting: confirming) { action in
            Button("Delete permanently", role: .destructive) { Task { await run(action) { try await app.commit(action) } } }
                .accessibilityIdentifier("commit.confirm")
        } message: { action in
            Text("\(action.summary). This empties it from Twenty's trash and can't be undone.")
        }
        .confirmationDialog("Commit all \(deleteCount) deletes?", isPresented: $confirmingAll, titleVisibility: .visible) {
            Button("Delete \(deleteCount) permanently", role: .destructive) { Task { await commitAll() } }
                .accessibilityIdentifier("commit.allConfirm")
        } message: {
            Text(deleteCount == app.recentActions.count
                 ? "Empties these from Twenty's trash. This can't be undone."
                 : "Empties the deleted records here from Twenty's trash; staged guesses stay. This can't be undone.")
        }
    }

    private func deleteRow(_ action: RecentAction) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(action.summary).lineLimit(3)
                Text(action.date, format: .relative(presentation: .named))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            if working == action.id {
                ProgressView()
            } else {
                Button("Undo") { Task { await run(action) { try await app.undo(action) } } }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("undo.recent")
                Button("Commit") { confirming = action }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .accessibilityIdentifier("commit.recent")
            }
        }
        .disabled(busy && working != action.id)
    }


    #if DEBUG
    private var pendingActions: [RecentAction] { app.recentActions.filter(\.isPendingUpdate) }

    /// A staged guess: Discard drops it (the card can come back in the
    /// deck); Apply writes the fields that are still empty.
    private func pendingRow(_ action: RecentAction) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "sparkles").foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text(action.summary).lineLimit(3)
                    Text(action.date, format: .relative(presentation: .named))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            HStack {
                Spacer()
                if working == action.id {
                    ProgressView()
                } else {
                    Button("Discard") {
                        app.discard(action.id)
                        notice = nil
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("guess.discard")
                    Button("Apply") { Task { await run(action) { notice = try await applied(action) } } }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                        .accessibilityIdentifier("guess.apply")
                }
            }
        }
        .disabled(busy && working != action.id)
    }

    /// A staged merge: Discard drops it (the suggestion can come back in the
    /// deck); Merge… confirms and runs it, for good.
    private func mergeRow(_ action: RecentAction) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "arrow.triangle.merge").foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text(action.summary).lineLimit(3)
                    Text(action.date, format: .relative(presentation: .named))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            HStack {
                Spacer()
                Button("Discard") {
                    app.discard(action.id)
                    notice = nil
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("merge.discard")
                Button("Merge…") { merging = action }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .accessibilityIdentifier("merge.open")
            }
        }
        .disabled(busy)
        // On the row: a sheet on the Section doesn't present inside a Form.
        .sheet(isPresented: Binding(get: { merging?.id == action.id }, set: { if !$0 { merging = nil } }), onDismiss: {
            if let id = merged {
                app.discard(id)
                merged = nil
            }
        }) {
            MergeConfirmSheet(action: action) { message in
                notice = message
                error = nil
                merged = action.id
            }
        }
    }

    /// "Applied Aberdeenplc · Skipped website: already set"
    private func applied(_ action: RecentAction) async throws -> String {
        let skipped = try await app.apply(action)
        let title = action.pendingUpdate?.title ?? "guess"
        if skipped.count == action.pendingUpdate?.changes.count { return "Nothing to apply for \(title) · " + skipped.map(\.message).joined(separator: " · ") }
        return (["Applied \(title)"] + skipped.map(\.message)).joined(separator: " · ")
    }

    private func applyAll() async {
        isApplyingAll = true
        defer { isApplyingAll = false }
        var lines: [String] = []
        do {
            for action in pendingActions { lines.append(try await applied(action)) }
            error = nil
        } catch {
            self.error = "Couldn't finish: \(error.localizedDescription)"
        }
        notice = lines.isEmpty ? nil : lines.joined(separator: "\n")
    }
    #endif

    private func run(_ action: RecentAction, _ work: () async throws -> Void) async {
        working = action.id
        defer { working = nil }
        do {
            try await work()
            error = nil
        } catch {
            self.error = "Couldn't finish: \(error.localizedDescription)"
        }
    }

    private func commitAll() async {
        isCommittingAll = true
        defer { isCommittingAll = false }
        do {
            try await app.commitAll()
            error = nil
        } catch {
            self.error = "Couldn't finish: \(error.localizedDescription)"
        }
    }
}
