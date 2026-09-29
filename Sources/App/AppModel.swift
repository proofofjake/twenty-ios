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
        objects = loaded
        phase = .ready
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
        phase = .loading
        do {
            objects = try await service.fetchObjects()
            phase = .ready
            if currentMember == nil { currentMember = try? await service.fetchCurrentMember() }
        } catch {
            phase = .failed(error.localizedDescription)
        }
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
