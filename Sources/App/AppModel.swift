import AuthenticationServices
import Foundation
import Observation

/// App-wide state: the connection settings, the live service and the
/// workspace's object metadata (schema), loaded once per connection.
@MainActor
@Observable
final class AppModel {
    enum Phase: Equatable { case disconnected, loading, ready, failed(String) }

    private(set) var phase: Phase = .disconnected
    private(set) var objects: [ObjectMetadata] = []
    private(set) var service: TwentyService?

    /// Latest saved copy of each edited record, so lists reflect edits made
    /// on detail screens without a refetch.
    private(set) var savedRecords: [String: Record] = [:]
    /// Bumped when a record of an object is created; lists reload on change.
    private(set) var listRevision: [String: Int] = [:]

    func didSave(_ record: Record) { savedRecords[record.id] = record }

    // MARK: Deleting

    /// Records deleted this session; lists hide them before they reload.
    private(set) var deletedIDs: Set<String> = []

    /// Twenty's email/calendar-sync blocklist, when the workspace has one
    /// and we know who's signed in (entries belong to a workspace member).
    var canBlockImports: Bool { currentMember != nil && object(named: "blocklist") != nil }

    /// Soft-deletes `record` (and optionally `people` first), and optionally
    /// blocklists `blockHandle` so the next inbox/calendar sync doesn't
    /// import it again. Logged in Recent actions so it can be undone.
    @discardableResult
    func delete(_ record: Record, of object: ObjectMetadata, alsoDeleting people: [Record] = [], blockHandle: String? = nil) async throws -> RecentAction {
        guard let service else { throw TwentyError(message: "Not connected") }
        var action = RecentAction()
        // Log each step as it succeeds, so a failure midway is still undoable.
        defer {
            if !action.items.isEmpty {
                recentActions.insert(action, at: 0)
                undoBanner = action
                saveRecentActions()
            }
        }
        if let blockHandle, let blocklist = self.object(named: "blocklist"), let me = currentMember {
            var values: [String: JSONValue] = ["handle": .string(blockHandle), "workspaceMemberId": .string(me.id)]
            if blocklist.field(named: "scope") != nil { values["scope"] = "WORKSPACE_MEMBER" }
            let entry = try await service.createRecord(blocklist, values: values)
            action.items.append(.blocked(id: entry.id, handle: blockHandle))
        }
        if !people.isEmpty, let person = self.object(named: "person") {
            for p in people {
                try await service.deleteRecord(person, id: p.id)
                deletedIDs.insert(p.id)
                action.items.append(.deleted(object: person.nameSingular, id: p.id, title: p.title(in: person)))
            }
            listRevision[person.nameSingular, default: 0] += 1
        }
        try await service.deleteRecord(object, id: record.id)
        deletedIDs.insert(record.id)
        action.items.append(.deleted(object: object.nameSingular, id: record.id, title: record.title(in: object)))
        listRevision[object.nameSingular, default: 0] += 1
        return action
    }

    // MARK: Recent actions (undo)

    /// Deletes from the last 24 hours, newest first, saved per workspace.
    private(set) var recentActions: [RecentAction] = []
    /// The action the bottom "Undo" banner offers, just after it happened.
    var undoBanner: RecentAction?

    /// Restores what `action` deleted and removes the blocklist entry it
    /// added, newest step first.
    func undo(_ action: RecentAction) async throws {
        guard let service else { throw TwentyError(message: "Not connected") }
        var remaining = action.items
        defer {
            if let index = recentActions.firstIndex(where: { $0.id == action.id }) {
                if remaining.isEmpty { recentActions.remove(at: index) } else { recentActions[index].items = remaining }
                saveRecentActions()
            }
            if undoBanner?.id == action.id { undoBanner = nil }
        }
        for item in action.items.reversed() {
            switch item {
            case .deleted(let name, let id, _):
                guard let object = self.object(named: name) else { continue }
                try await service.restoreRecord(object, id: id)
                deletedIDs.remove(id)
                listRevision[name, default: 0] += 1
            case .blocked(let id, _):
                if let blocklist = self.object(named: "blocklist") {
                    // Our own entry; removing it for good lets sync resume.
                    try await service.deleteRecord(blocklist, id: id, permanently: true)
                }
            #if DEBUG
            case .pendingUpdate, .pendingMerge:
                break // never written, so nothing to restore
            #endif
            }
            remaining.removeAll { $0 == item }
        }
    }

    /// Makes `action` final: permanently deletes its records from Twenty's
    /// trash and drops it from Recent actions. Blocks it added stay.
    func commit(_ action: RecentAction) async throws {
        guard let service else { throw TwentyError(message: "Not connected") }
        var remaining = action.items
        defer {
            if let index = recentActions.firstIndex(where: { $0.id == action.id }) {
                let left = remaining.filter { if case .deleted = $0 { true } else { false } }
                if left.isEmpty { recentActions.remove(at: index) } else { recentActions[index].items = remaining }
                saveRecentActions()
            }
            if undoBanner?.id == action.id { undoBanner = nil }
        }
        for item in action.items {
            guard case .deleted(let name, let id, _) = item, let object = self.object(named: name) else { continue }
            // Destroy works on trashed records: it's how Twenty empties its trash.
            try await service.deleteRecord(object, id: id, permanently: true)
            remaining.removeAll { $0 == item }
        }
    }

    /// Commits every delete. Staged updates (Debug) aren't touched.
    func commitAll() async throws {
        for action in recentActions where action.hasDeletes { try await commit(action) }
    }

    #if DEBUG
    // MARK: Claude's educated guesses (Debug only)

    /// Guesses swiped away in this workspace (`ClaudeGuesses.declineKey`).
    private(set) var declinedGuesses: Set<String> = []
    private var declineStore: GuessDeclineStore { GuessDeclineStore(workspaceKey: workspaceKey) }

    func declineGuesses(_ keys: [String]) {
        declinedGuesses.formUnion(keys)
        declineStore.save(declinedGuesses)
    }

    func undeclineGuesses(_ keys: [String]) {
        declinedGuesses.subtract(keys)
        declineStore.save(declinedGuesses)
    }

    /// Cards sent to the bottom of the deck, and when.
    private(set) var skippedGuesses: [String: Date] = [:]
    private var skipStore: GuessSkipStore { GuessSkipStore(workspaceKey: workspaceKey) }

    /// Sends a card to the bottom of the deck. Returns the previous skip time,
    /// so the deck's undo can put it back exactly.
    @discardableResult
    func skipGuess(_ companyID: String) -> Date? {
        let previous = skippedGuesses[companyID]
        skippedGuesses[companyID] = Date()
        skipStore.save(skippedGuesses)
        return previous
    }

    func unskipGuess(_ companyID: String, restoring previous: Date?) {
        skippedGuesses[companyID] = previous
        skipStore.save(skippedGuesses)
    }

    /// Companies with a staged update, which the deck leaves out.
    var stagedGuessIDs: Set<String> { Set(recentActions.compactMap { $0.pendingUpdate?.id }) }

    /// Staged merges, by `ClaudeGuesses.mergeKey`.
    var stagedMergeKeys: Set<String> { Set(recentActions.compactMap { $0.pendingMerge.map { ClaudeGuesses.mergeKey($0.ids) } }) }
    /// Companies a staged merge will delete, which the deck leaves out.
    var mergedAwayIDs: Set<String> { Set(recentActions.compactMap(\.pendingMerge).flatMap(\.mergeIDs)) }

    /// The deck: the bundled guesses (demo ones in demo mode), checked
    /// against each company as it is now. Throws `.missing` without a file.
    func loadGuessCards() async throws -> (file: ClaudeGuesses.File, cards: [ClaudeGuesses.Card]) {
        guard let service, let company = object(named: "company") else { throw TwentyError(message: "Not connected") }
        let file = isDemo ? try ClaudeGuesses.parse(Data(DemoData.guessesJSON.utf8)) : try ClaudeGuesses.bundled()
        if members.isEmpty { await loadMembers() }
        let records = try await service.fetchRecords(company, ids: file.companyIDs)
        let cards = ClaudeGuesses.cards(for: file.entries, records: records, object: company, members: members,
                                        memberObject: object(named: "workspaceMember"),
                                        declined: declinedGuesses, staged: stagedGuessIDs.union(mergedAwayIDs),
                                        merges: file.merges, stagedMerges: stagedMergeKeys)
        return (file, ClaudeGuesses.skippedLast(cards, skips: skippedGuesses))
    }

    /// Accepting a card: logs the changes in Recent actions without writing
    /// them. No undo banner; the deck has its own undo.
    @discardableResult
    func stage(_ changes: [PendingChange], for record: Record, of object: ObjectMetadata) -> RecentAction {
        let action = RecentAction(items: [.pendingUpdate(object: object.nameSingular, id: record.id, title: record.title(in: object), changes: changes)])
        recentActions.insert(action, at: 0)
        saveRecentActions()
        return action
    }

    /// The merge window's "Add to Recent actions": logs the merge without
    /// running it. Merge… in Recent actions runs it.
    @discardableResult
    func stageMerge(keep: Record, merging others: [Record], of object: ObjectMetadata, overrides: [PendingChange]) -> RecentAction {
        let merge = PendingMerge(object: object.nameSingular, keepID: keep.id, keepTitle: keep.title(in: object),
                                 mergeIDs: others.map(\.id), mergeTitles: others.map { $0.title(in: object) }, overrides: overrides)
        let action = RecentAction(items: [.pendingMerge(merge: merge)])
        recentActions.insert(action, at: 0)
        saveRecentActions()
        return action
    }

    /// Runs a staged merge, for good: refetches every record (failing if one
    /// is gone), logs them all to Documents/merge-log.jsonl, PATCHes the
    /// survivor with the overrides still valid, then merges. Returns the
    /// overrides skipped because the survivor changed since. With
    /// `discarding` off, the caller drops the action itself (once the sheet
    /// presented from its row is gone).
    @discardableResult
    func applyMerge(_ action: RecentAction, discarding: Bool = true) async throws -> [ClaudeGuesses.Skipped] {
        guard let service else { throw TwentyError(message: "Not connected") }
        guard let merge = action.pendingMerge, let object = object(named: merge.object) else { return [] }
        var records: [Record] = []
        for (id, title) in zip(merge.ids, [merge.keepTitle] + merge.mergeTitles) {
            do {
                records.append(try await service.fetchRecord(object, id: id))
            } catch {
                throw TwentyError(message: "Couldn't find \(title) in Twenty (\(error.localizedDescription)). Nothing was merged; discard this one.")
            }
        }
        do { try MergeLog.append(merge, records: records) } catch {
            throw TwentyError(message: "Couldn't save the backup to merge-log.jsonl (\(error.localizedDescription)). Nothing was merged.")
        }
        let (patch, skipped) = ClaudeGuesses.mergePatch(for: merge.overrides, survivor: records[0], object: object,
                                                        members: members, memberObject: self.object(named: "workspaceMember"))
        if !patch.isEmpty { _ = try await service.updateRecord(object, id: merge.keepID, patch: patch) }
        let survivor = try await service.mergeRecords(object, ids: merge.ids, conflictPriorityIndex: 0, dryRun: false)
        didSave(survivor)
        deletedIDs.formUnion(merge.mergeIDs)
        listRevision[object.nameSingular, default: 0] += 1
        // People and the rest moved to the survivor.
        for list in object.relatedLists(in: objects) { listRevision[list.target.nameSingular, default: 0] += 1 }
        if discarding { discard(action.id) }
        return skipped
    }

    /// Drops a staged update without touching Twenty (Discard, or the deck's undo).
    func discard(_ actionID: UUID) {
        recentActions.removeAll { $0.id == actionID }
        saveRecentActions()
    }

    /// Writes a staged update: refetches the record and PATCHes only the
    /// fields still empty, so it never overwrites a value set since.
    /// Returns what was skipped.
    @discardableResult
    func apply(_ action: RecentAction) async throws -> [ClaudeGuesses.Skipped] {
        guard let service else { throw TwentyError(message: "Not connected") }
        guard let pending = action.pendingUpdate, let object = object(named: pending.object) else { return [] }
        let current = try await service.fetchRecord(object, id: pending.id)
        let (patch, skipped) = ClaudeGuesses.patch(for: pending.changes, current: current, object: object)
        let updated = patch.isEmpty ? current : try await service.updateRecord(object, id: pending.id, patch: patch)
        didSave(updated)
        discard(action.id)
        return skipped
    }
    #endif

    private var actionsKey: String { "recentActions." + workspaceKey }

    private func loadRecentActions() {
        recentActions = (UserDefaults.standard.data(forKey: actionsKey).map(RecentAction.decodeList) ?? [])
            .filter { !$0.isExpired }
    }

    private func saveRecentActions() {
        recentActions.removeAll(where: \.isExpired)
        if let data = try? JSONEncoder().encode(recentActions) { UserDefaults.standard.set(data, forKey: actionsKey) }
    }

    // MARK: List filters

    /// Each list's filters, by object name, for the current workspace. Saved
    /// on every change so they survive quitting and relaunching the app.
    private(set) var listFilters: [String: ListFilter] = [:]

    func filter(for object: ObjectMetadata) -> ListFilter { listFilters[object.nameSingular] ?? ListFilter() }

    func setFilter(_ filter: ListFilter, for object: ObjectMetadata) {
        listFilters[object.nameSingular] = filter.isEmpty ? nil : filter
        guard let data = try? JSONEncoder().encode(listFilters) else { return }
        UserDefaults.standard.set(data, forKey: filtersKey)
    }

    /// Filters hold option keys and member ids, which only mean something
    /// in one workspace, so each workspace (and demo mode) keeps its own.
    private var filtersKey: String { "listFilters." + workspaceKey }
    private var workspaceKey: String { isDemo ? "demo" : serverURL + "|" + workspaceURL }

    private func loadFilters() {
        listFilters = UserDefaults.standard.data(forKey: filtersKey)
            .flatMap { try? JSONDecoder().decode([String: ListFilter].self, from: $0) } ?? [:]
    }

    func didCreate(_ record: Record, in object: ObjectMetadata) {
        savedRecords[record.id] = record
        listRevision[object.nameSingular, default: 0] += 1
    }

    var serverURL: String = UserDefaults.standard.string(forKey: Keys.serverURL) ?? "https://api.twenty.com"
    private(set) var isDemo: Bool = UserDefaults.standard.bool(forKey: Keys.demo)
    /// The workspace's own web address; sign-in opens there so Twenty logs
    /// straight into it instead of offering to create a workspace.
    var workspaceURL: String = UserDefaults.standard.string(forKey: Keys.workspaceURL) ?? "https://tokenisedgbp.twenty.com"
    /// The signed-in person (a `workspaceMember` record). New records name
    /// them as owner; nil with an API key or demo data.
    private(set) var currentMember: Record?
    private var oauth: OAuthCredential?

    var isSignedIn: Bool { oauth != nil }

    nonisolated private enum Keys {
        static let serverURL = "serverURL"
        static let demo = "demoMode"
        static let apiKey = "apiKey"
        static let oauthTokens = "oauthTokens"
        static let workspaceURL = "workspaceURL"
    }

    init() {
        if ProcessInfo.processInfo.arguments.contains("-demo") { isDemo = true }
        // UI tests start from default preferences.
        if ProcessInfo.processInfo.arguments.contains("-resetPreferences") {
            UserDefaults.standard.removeObject(forKey: CreateFlowView.advancedModeKey)
            UserDefaults.standard.removeObject(forKey: "listFilters.demo")
            UserDefaults.standard.removeObject(forKey: "recentActions.demo")
            #if DEBUG
            GuessDeclineStore(workspaceKey: "demo").save([])
            GuessSkipStore(workspaceKey: "demo").save([:])
            #endif
        }
        if isDemo {
            service = DemoTwentyService()
        } else if let url = normalizedURL(serverURL) {
            if let tokens = Self.storedTokens() {
                let credential = Self.credential(tokens)
                oauth = credential
                service = LiveTwentyService(baseURL: url, auth: credential)
            } else if let key = Keychain.read(Keys.apiKey) {
                service = LiveTwentyService(baseURL: url, auth: APIKeyCredential(key: key))
            }
        }
        if service != nil { Task { await loadSchema() } }
    }

    /// Signs in through Twenty's own login page (Google, as on the web) and
    /// acts as that person from then on.
    func signIn(serverURL: String, workspaceURL: String) async {
        guard let url = normalizedURL(serverURL) else {
            phase = .failed("Enter a valid server URL, e.g. https://crm.example.com")
            return
        }
        let workspace = workspaceURL.trimmingCharacters(in: .whitespaces).isEmpty ? nil : normalizedURL(workspaceURL)
        self.workspaceURL = workspace?.absoluteString ?? ""
        UserDefaults.standard.set(self.workspaceURL, forKey: Keys.workspaceURL)
        do {
            let server = try await TwentyOAuth.discover(baseURL: url)
            let redirectURI = LoopbackReceiver.redirectURI
            let clientID = try await TwentyOAuth.clientID(for: server, redirectURI: redirectURI)
            let pkce = PKCE()
            let state = TwentyOAuth.randomURLSafeString(bytes: 16)
            let receiver = try LoopbackReceiver()
            receiver.start()
            defer { receiver.stop() }
            let callback = try await BrowserSignIn.authorize(
                url: TwentyOAuth.authorizationURL(server: server, clientID: clientID, redirectURI: redirectURI, pkce: pkce, state: state, workspace: workspace),
                receiver: receiver
            )
            let code = try TwentyOAuth.code(fromCallback: callback, state: state, issuer: server.issuer)
            phase = .loading
            let tokens = try await TwentyOAuth.exchange(code: code, pkce: pkce, clientID: clientID, redirectURI: redirectURI, server: server)
            let credential = Self.credential(tokens)
            let candidate = LiveTwentyService(baseURL: url, auth: credential)
            let loaded = try await candidate.fetchObjects()
            Self.persist(tokens)
            Keychain.write(nil, for: Keys.apiKey)
            oauth = credential
            activate(candidate, url: url, objects: loaded)
            currentMember = try? await candidate.fetchCurrentMember()
        } catch is CancellationError {
            // Closed the sign-in sheet.
        } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    func connect(serverURL: String, apiKey: String) async {
        guard let url = normalizedURL(serverURL) else {
            phase = .failed("Enter a valid server URL, e.g. https://crm.example.com")
            return
        }
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            phase = .failed("Paste an API key from Settings → APIs & Webhooks in Twenty.")
            return
        }
        let candidate = LiveTwentyService(baseURL: url, auth: APIKeyCredential(key: key))
        phase = .loading
        do {
            let loaded = try await candidate.fetchObjects()
            Keychain.write(key, for: Keys.apiKey)
            Keychain.write(nil, for: Keys.oauthTokens)
            oauth = nil
            currentMember = nil
            activate(candidate, url: url, objects: loaded)
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    private func activate(_ candidate: LiveTwentyService, url: URL, objects loaded: [ObjectMetadata]) {
        serverURL = url.absoluteString
        UserDefaults.standard.set(serverURL, forKey: Keys.serverURL)
        UserDefaults.standard.set(false, forKey: Keys.demo)
        isDemo = false
        service = candidate
        objects = Self.withInferences(loaded)
        loadFilters()
        loadRecentActions()
        #if DEBUG
        declinedGuesses = declineStore.load()
        skippedGuesses = skipStore.load()
        #endif
        phase = .ready
        Task { await loadMembers() }
    }

    func startDemo() async {
        UserDefaults.standard.set(true, forKey: Keys.demo)
        isDemo = true
        service = DemoTwentyService()
        await loadSchema()
    }

    func disconnect() {
        if let oauth { Task { await TwentyOAuth.revoke(await oauth.current) } }
        Keychain.write(nil, for: Keys.apiKey)
        Keychain.write(nil, for: Keys.oauthTokens)
        UserDefaults.standard.set(false, forKey: Keys.demo)
        isDemo = false
        oauth = nil
        currentMember = nil
        service = nil
        objects = []
        phase = .disconnected
    }

    nonisolated private static func storedTokens() -> OAuthTokens? {
        Keychain.read(Keys.oauthTokens).flatMap { try? JSONDecoder().decode(OAuthTokens.self, from: Data($0.utf8)) }
    }

    nonisolated private static func persist(_ tokens: OAuthTokens) {
        guard let data = try? JSONEncoder().encode(tokens) else { return }
        Keychain.write(String(decoding: data, as: UTF8.self), for: Keys.oauthTokens)
    }

    /// Saves each rotated refresh token, so a relaunch keeps the session.
    private static func credential(_ tokens: OAuthTokens) -> OAuthCredential {
        OAuthCredential(tokens: tokens) { renewed in persist(renewed) }
    }

    func loadSchema() async {
        guard let service else { phase = .disconnected; return }
        loadFilters()
        loadRecentActions()
        #if DEBUG
        declinedGuesses = declineStore.load()
        skippedGuesses = skipStore.load()
        #endif
        phase = .loading
        do {
            objects = Self.withInferences(try await service.fetchObjects())
            phase = .ready
            await loadMembers()
            if currentMember == nil { currentMember = try? await service.fetchCurrentMember() }
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    /// Marks objects whose owner can be inferred (people: company owner,
    /// else whoever added them).
    nonisolated static func withInferences(_ objects: [ObjectMetadata]) -> [ObjectMetadata] {
        objects.map { object in
            var copy = object
            copy.pointOfContact = PointOfContactSources.infer(for: object, in: objects)
            return copy
        }
    }

    /// Workspace members (the team), for owner filters and point-of-contact names.
    private(set) var members: [Record] = []

    func memberName(_ id: String?) -> String? {
        guard let id, let object = object(named: "workspaceMember"), let member = members.first(where: { $0.id == id }) else { return nil }
        return member.title(in: object)
    }

    private func loadMembers() async {
        guard let service, let object = object(named: "workspaceMember") else { return }
        members = (try? await service.fetchRecords(object, search: "", after: nil).records) ?? members
    }

    func object(named nameSingular: String) -> ObjectMetadata? {
        objects.first { $0.nameSingular == nameSingular }
    }

    /// Objects for the "More" tab: active, user-facing, excluding the tabs we pin.
    var otherObjects: [ObjectMetadata] {
        let pinned: Set<String> = ["person", "company"]
        let hidden: Set<String> = ["workspaceMember", "timelineActivity", "attachment", "favorite", "favoriteFolder",
                                   "noteTarget", "taskTarget", "messageThread", "message", "messageParticipant",
                                   "calendarEvent", "calendarEventParticipant", "connectedAccount", "blocklist",
                                   "viewField", "viewFilter", "viewSort", "view", "viewGroup", "workflowVersion",
                                   "workflowRun", "workflowAutomatedTrigger", "messageChannel", "calendarChannel",
                                   "messageFolder", "messageChannelMessageAssociation", "calendarChannelEventAssociation",
                                   "auditLog", "dashboard"]
        return objects
            .filter { $0.isActive != false && $0.isSystem != true }
            .filter { !pinned.contains($0.nameSingular) && !hidden.contains($0.nameSingular) }
            .sorted { $0.labelPlural.localizedCaseInsensitiveCompare($1.labelPlural) == .orderedAscending }
    }

    private func normalizedURL(_ text: String) -> URL? {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.hasSuffix("/") { trimmed.removeLast() }
        if !trimmed.contains("://") { trimmed = "https://" + trimmed }
        guard let url = URL(string: trimmed), url.host() != nil else { return nil }
        return url
    }
}
