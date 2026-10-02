import SwiftUI

extension Record {
    /// What to blocklist so inbox/calendar sync stops importing this record:
    /// a company's website domain ("@lakecomo-hotel.it"), a person's email
    /// domain, or their exact address on webmail (blocking "@gmail.com"
    /// would hide everyone).
    func importBlockHandle(in object: ObjectMetadata) -> String? {
        switch object.nameSingular {
        case "company":
            return (self["domainName"]["primaryLinkUrl"]?.stringValue).flatMap(Self.domain(fromURL:)).map { "@\($0)" }
        case "person":
            guard let email = self["emails"]["primaryEmail"]?.stringValue?.lowercased(),
                  let at = email.lastIndex(of: "@") else { return nil }
            let domain = String(email[email.index(after: at)...])
            guard !domain.isEmpty else { return nil }
            return Self.webmailDomains.contains(domain) ? email : "@\(domain)"
        default:
            return nil
        }
    }

    static func domain(fromURL text: String) -> String? {
        var t = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !t.isEmpty else { return nil }
        if !t.contains("://") { t = "https://" + t }
        guard var host = URL(string: t)?.host(), host.contains(".") else { return nil }
        if host.hasPrefix("www.") { host.removeFirst(4) }
        return host
    }

    static let webmailDomains: Set<String> = [
        "gmail.com", "googlemail.com", "outlook.com", "hotmail.com", "hotmail.co.uk", "live.com", "msn.com",
        "yahoo.com", "yahoo.co.uk", "icloud.com", "me.com", "mac.com", "proton.me", "protonmail.com",
        "aol.com", "gmx.com", "gmx.de", "mail.com", "zoho.com",
    ]
}

/// Confirms a delete: says it goes to Twenty's trash, and offers to take a
/// company's people with it and to stop the inbox sync re-importing it.
struct DeleteRecordSheet: View {
    let object: ObjectMetadata
    let record: Record
    /// Confirm with a slide instead of a tap (deletes Claude suggested).
    var slideToConfirm = false
    /// Start with "also delete its people" and "stop importing" on: for
    /// inbox noise, where both are what you'd want.
    var preselectExtras = false
    let onDeleted: () -> Void

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var people: [Record] = []
    @State private var deletePeople = false
    @State private var block = false
    @State private var isWorking = false
    @State private var error: String?

    private var title: String { record.title(in: object) }
    private var blockHandle: String? { app.canBlockImports ? record.importBlockHandle(in: object) : nil }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label {
                        Text("Moves it to Twenty's trash. You can restore it from **Deleted** in Twenty on the web.")
                    } icon: {
                        Image(systemName: "trash").foregroundStyle(.red)
                    }
                    .font(.subheadline)
                }
                if !people.isEmpty {
                    Section {
                        Toggle(isOn: $deletePeople) {
                            Text("Also delete \(people.count == 1 ? "its 1 person" : "its \(people.count) people")")
                            Text(people.prefix(3).map { $0.title(in: app.object(named: "person") ?? object) }.joined(separator: ", ")
                                 + (people.count > 3 ? " +\(people.count - 3)" : ""))
                        }
                        .accessibilityIdentifier("delete.people")
                    }
                }
                if let blockHandle {
                    Section {
                        Toggle(isOn: $block) {
                            Text("Stop importing \(blockHandle)")
                            Text("Adds it to your Twenty blocklist, so your inbox and calendar sync won't add it back. Twenty also hides emails already synced from it.")
                        }
                        .accessibilityIdentifier("delete.block")
                    }
                }
                if let error {
                    Section { Text(error).foregroundStyle(.red) }
                }
                if slideToConfirm {
                    Section {
                        SlideToConfirm(title: "Slide to " + confirmLabel.lowercased(), isWorking: isWorking) { Task { await run() } }
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                    }
                } else {
                    Section {
                        Button(role: .destructive) {
                            Task { await run() }
                        } label: {
                            HStack {
                                Spacer()
                                if isWorking { ProgressView() } else { Text(confirmLabel).fontWeight(.semibold) }
                                Spacer()
                            }
                        }
                        .disabled(isWorking)
                        .accessibilityIdentifier("delete.confirm")
                    }
                }
            }
            .navigationTitle("Delete \(title)?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(isWorking) }
            }
            .task {
                if preselectExtras { block = blockHandle != nil }
                await loadPeople()
                if preselectExtras { deletePeople = !people.isEmpty }
            }
        }
        .presentationDetents([.medium, .large])
        .interactiveDismissDisabled(isWorking)
    }

    private var confirmLabel: String {
        let noun = object.labelSingular.lowercased()
        guard deletePeople, !people.isEmpty else { return "Delete \(noun)" }
        return "Delete \(noun) and \(people.count == 1 ? "1 person" : "\(people.count) people")"
    }

    /// A company's people come from the depth-1 record (lists fetch depth 0).
    private func loadPeople() async {
        guard object.nameSingular == "company", let service = app.service, let person = app.object(named: "person"),
              let full = try? await service.fetchRecord(object, id: record.id) else { return }
        people = (full["people"].arrayValue ?? []).compactMap { Record(json: $0) }
            .filter { !app.deletedIDs.contains($0.id) }
            .sorted { $0.title(in: person) < $1.title(in: person) }
    }

    private func run() async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await app.delete(record, of: object, alsoDeleting: deletePeople ? people : [], blockHandle: block ? blockHandle : nil)
            dismiss()
            onDeleted()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
