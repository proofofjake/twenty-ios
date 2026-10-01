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
struct RecentActionsSection: View {
    @Environment(AppModel.self) private var app
    @State private var working: UUID?
    @State private var isCommittingAll = false
    @State private var confirming: RecentAction?
    @State private var confirmingAll = false
    @State private var error: String?

    private var busy: Bool { working != nil || isCommittingAll }

    var body: some View {
        Section {
            if app.recentActions.isEmpty {
                Text("Nothing in the last 24 hours").foregroundStyle(.secondary)
            }
            ForEach(app.recentActions) { action in
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
            if let error { Text(error).font(.footnote).foregroundStyle(.red) }
        } header: {
            HStack {
                Text("Recent actions")
                Spacer()
                if app.recentActions.count > 1 {
                    if isCommittingAll { ProgressView() } else {
                        Button("Commit all") { confirmingAll = true }
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.red)
                            .textCase(nil)
                            .disabled(busy)
                            .accessibilityIdentifier("commit.all")
                    }
                }
            }
        } footer: {
            Text("Deletes from the last 24 hours on this device. **Undo** restores them from Twenty's trash and removes any block they added. **Commit** permanently deletes them from Twenty (blocks stay) and can't be undone. Older deletions stay in Twenty's trash: restore or empty them from **Deleted** on the web.")
        }
        .confirmationDialog("Permanently delete from Twenty?", isPresented: Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } }), titleVisibility: .visible, presenting: confirming) { action in
            Button("Delete permanently", role: .destructive) { Task { await run(action) { try await app.commit(action) } } }
                .accessibilityIdentifier("commit.confirm")
        } message: { action in
            Text("\(action.summary). This empties it from Twenty's trash and can't be undone.")
        }
        .confirmationDialog("Permanently delete everything here?", isPresented: $confirmingAll, titleVisibility: .visible) {
            Button("Delete \(app.recentActions.count) permanently", role: .destructive) { Task { await commitAll() } }
                .accessibilityIdentifier("commit.allConfirm")
        } message: {
            Text("Empties these from Twenty's trash. This can't be undone.")
        }
    }

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
