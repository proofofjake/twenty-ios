import AuthenticationServices
import CryptoKit
import Foundation
import Network
import UIKit

/// Supplies the bearer token for each request: a fixed API key, or a signed-in
/// user's OAuth access token that renews itself.
protocol AccessTokenProvider: Sendable {
    func accessToken() async throws -> String
    /// Called after a 401. Returns a fresh token to retry with, or nil.
    func tokenAfterRejection() async throws -> String?
}

struct APIKeyCredential: AccessTokenProvider {
    let key: String
    func accessToken() async throws -> String { key }
    func tokenAfterRejection() async throws -> String? { nil }
}

// MARK: - Twenty's OAuth server (verified against twenty main, 2026-09-29)
//
// Twenty publishes RFC 8414 metadata, accepts RFC 7591 dynamic registration
// of public clients (PKCE S256), and issues 30-minute access tokens with
// rotating 60-day refresh tokens. The access token carries the user, so the
// server applies that person's role and stamps `createdBy` with their
// workspace member. Redirect URIs must be https, loopback, or one of a few
// editor schemes, so the app catches the redirect on 127.0.0.1 (RFC 8252 §7.3).

struct OAuthServerMetadata: Codable, Sendable, Equatable {
    let issuer: String?
    let authorizationEndpoint: URL
    let tokenEndpoint: URL
    let registrationEndpoint: URL?
    let revocationEndpoint: URL?

    enum CodingKeys: String, CodingKey {
        case issuer
        case authorizationEndpoint = "authorization_endpoint"
        case tokenEndpoint = "token_endpoint"
        case registrationEndpoint = "registration_endpoint"
        case revocationEndpoint = "revocation_endpoint"
    }
}

/// What the app keeps in the Keychain for a signed-in user.
struct OAuthTokens: Codable, Sendable, Equatable {
    var accessToken: String
    var refreshToken: String?
    var expiresAt: Date
    let clientID: String
    let tokenEndpoint: URL
    let revocationEndpoint: URL?
}

struct PKCE: Sendable {
    let verifier: String
    var challenge: String { Self.challenge(for: verifier) }

    init(verifier: String = TwentyOAuth.randomURLSafeString(bytes: 32)) { self.verifier = verifier }

    static func challenge(for verifier: String) -> String {
        TwentyOAuth.base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
    }
}

enum TwentyOAuth {
    static let clientName = "CRM for iPhone"
    static let scope = "api profile"

    static func discover(baseURL: URL, session: URLSession = .shared) async throws -> OAuthServerMetadata {
        let url = baseURL.appending(path: ".well-known/oauth-authorization-server")
        let (data, response) = try await session.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let metadata = try? JSONDecoder().decode(OAuthServerMetadata.self, from: data) else {
            throw TwentyError(message: "This server doesn't support signing in. Update Twenty, or use an API key.")
        }
        return metadata
    }

    /// Registers this app once per server; the client id is remembered because
    /// registration is limited to 10 per hour per IP.
    static func clientID(for server: OAuthServerMetadata, redirectURI: String, session: URLSession = .shared) async throws -> String {
        let cacheKey = "oauthClientID:\(server.tokenEndpoint.absoluteString):\(redirectURI)"
        guard let endpoint = server.registrationEndpoint else {
            throw TwentyError(message: "This server doesn't allow new sign-in clients.")
        }
        if let cached = UserDefaults.standard.string(forKey: cacheKey) {
            // Twenty deletes registrations that were never used after 30 days.
            let (_, response) = try await session.data(from: endpoint.appending(path: cached))
            if (response as? HTTPURLResponse)?.statusCode != 404 { return cached }
        }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(RegistrationRequest(
            clientName: clientName,
            redirectURIs: [redirectURI],
            grantTypes: ["authorization_code", "refresh_token"],
            responseTypes: ["code"],
            tokenEndpointAuthMethod: "none",
            scope: scope
        ))
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status), let id = try JSONDecoder().decode(JSONValue.self, from: data)["client_id"]?.nonEmptyString else {
            throw TwentyError(message: oauthErrorMessage(data) ?? "Couldn't register the app with Twenty (\(status)).", status: status)
        }
        UserDefaults.standard.set(id, forKey: cacheKey)
        return id
    }

    /// The authorize URL, keeping any query the server already put on it
    /// (Twenty Cloud's includes `iss`). With `workspace` (e.g.
    /// `https://acme.twenty.com`) the page opens on that workspace's own
    /// domain, so login goes straight into it. The generic app.twenty.com
    /// login instead shows a workspace picker with "Create a workspace".
    static func authorizationURL(server: OAuthServerMetadata, clientID: String, redirectURI: String, pkce: PKCE, state: String,
                                 workspace: URL? = nil) -> URL {
        var components = URLComponents(url: server.authorizationEndpoint, resolvingAgainstBaseURL: false)!
        if let workspace, let host = workspace.host() {
            components.scheme = workspace.scheme ?? "https"
            components.host = host
            components.port = workspace.port
        }
        components.queryItems = (components.queryItems ?? []) + [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "code_challenge", value: pkce.challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "scope", value: scope),
            URLQueryItem(name: "state", value: state),
        ]
        return components.url!
    }

    /// The authorization code from the redirect, after checking `state` and `iss`.
    static func code(fromCallback components: URLComponents, state: String, issuer: String?) throws -> String {
        let items = components.queryItems ?? []
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
        if let error = value("error") {
            throw TwentyError(message: value("error_description") ?? "Sign-in failed (\(error)).")
        }
        guard value("state") == state else { throw TwentyError(message: "Sign-in response didn't match this request. Try again.") }
        if let issuer, let returned = value("iss"), returned != issuer {
            throw TwentyError(message: "Sign-in response came from an unexpected server.")
        }
        guard let code = value("code"), !code.isEmpty else { throw TwentyError(message: "Sign-in didn't return a code.") }
        return code
    }

    static func exchange(code: String, pkce: PKCE, clientID: String, redirectURI: String, server: OAuthServerMetadata,
                         session: URLSession = .shared) async throws -> OAuthTokens {
        let response = try await tokenRequest(server.tokenEndpoint, form: [
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": redirectURI,
            "client_id": clientID,
            "code_verifier": pkce.verifier,
        ], session: session)
        return OAuthTokens(accessToken: response.accessToken, refreshToken: response.refreshToken,
                           expiresAt: response.expiresAt, clientID: clientID,
                           tokenEndpoint: server.tokenEndpoint, revocationEndpoint: server.revocationEndpoint)
    }

    static func refresh(_ tokens: OAuthTokens, session: URLSession = .shared) async throws -> OAuthTokens {
        guard let refreshToken = tokens.refreshToken else { throw sessionExpired }
        let response = try await tokenRequest(tokens.tokenEndpoint, form: [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": tokens.clientID,
        ], session: session)
        var renewed = tokens
        renewed.accessToken = response.accessToken
        // Twenty rotates refresh tokens; keep the old one only if none came back.
        renewed.refreshToken = response.refreshToken ?? refreshToken
        renewed.expiresAt = response.expiresAt
        return renewed
    }

    /// Best effort: revoking the refresh token ends the grant on the server.
    static func revoke(_ tokens: OAuthTokens, session: URLSession = .shared) async {
        guard let endpoint = tokens.revocationEndpoint, let token = tokens.refreshToken else { return }
        _ = try? await session.data(for: formRequest(endpoint, form: ["token": token, "client_id": tokens.clientID]))
    }

    static let sessionExpired = TwentyError(message: "Your sign-in has expired. Sign out in Settings and sign in again.", status: 401)

    // MARK: Helpers

    struct TokenResponse: Decodable {
        let accessToken: String
        let refreshToken: String?
        let expiresIn: Double?
        var expiresAt: Date { Date().addingTimeInterval(expiresIn ?? 1800) }

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token", refreshToken = "refresh_token", expiresIn = "expires_in"
        }
    }

    private struct RegistrationRequest: Encodable {
        let clientName: String
        let redirectURIs: [String]
        let grantTypes: [String]
        let responseTypes: [String]
        let tokenEndpointAuthMethod: String
        let scope: String

        enum CodingKeys: String, CodingKey {
            case clientName = "client_name", redirectURIs = "redirect_uris", grantTypes = "grant_types"
            case responseTypes = "response_types", tokenEndpointAuthMethod = "token_endpoint_auth_method", scope
        }
    }

    private static func tokenRequest(_ endpoint: URL, form: [String: String], session: URLSession) async throws -> TokenResponse {
        let (data, response) = try await session.data(for: formRequest(endpoint, form: form))
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status), let tokens = try? JSONDecoder().decode(TokenResponse.self, from: data) else {
            // invalid_grant: the refresh token expired or the user revoked access.
            if status == 400 || status == 401 { throw sessionExpiredOr(oauthErrorMessage(data), status: status) }
            throw TwentyError(message: oauthErrorMessage(data) ?? "Sign-in failed (\(status)).", status: status)
        }
        return tokens
    }

    private static func sessionExpiredOr(_ message: String?, status: Int) -> TwentyError {
        guard let message else { return sessionExpired }
        return TwentyError(message: message, status: 401)
    }

    private static func formRequest(_ endpoint: URL, form: [String: String]) -> URLRequest {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=+")
        request.httpBody = form.sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed) ?? $0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)
        return request
    }

    static func oauthErrorMessage(_ data: Data) -> String? {
        guard let json = try? JSONDecoder().decode(JSONValue.self, from: data) else { return nil }
        return json["error_description"]?.nonEmptyString ?? json["error"]?.nonEmptyString
    }

    static func randomURLSafeString(bytes count: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: count)
        _ = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        return base64URL(Data(bytes))
    }

    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// A string claim from a JWT payload, unverified (the server checks it).
    /// User tokens carry `userId`; API keys don't.
    static func claim(_ name: String, inJWT token: String) -> String? {
        let parts = token.split(separator: ".")
        guard parts.count == 3 else { return nil }
        var payload = parts[1].replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
        guard let data = Data(base64Encoded: payload),
              let json = try? JSONDecoder().decode(JSONValue.self, from: data) else { return nil }
        return json[name]?.nonEmptyString
    }
}

// MARK: - Signed-in credential

/// A user's OAuth tokens. Renews the access token shortly before it expires
/// (or after a 401) and saves every rotation through `persist`.
actor OAuthCredential: AccessTokenProvider {
    private var tokens: OAuthTokens
    private var refreshing: Task<OAuthTokens, Error>?
    private let persist: @Sendable (OAuthTokens) -> Void

    init(tokens: OAuthTokens, persist: @escaping @Sendable (OAuthTokens) -> Void) {
        self.tokens = tokens
        self.persist = persist
    }

    var current: OAuthTokens { tokens }

    func accessToken() async throws -> String {
        if tokens.expiresAt.timeIntervalSinceNow > 60 { return tokens.accessToken }
        return try await renew().accessToken
    }

    func tokenAfterRejection() async throws -> String? {
        try await renew().accessToken
    }

    /// One refresh at a time: refresh tokens rotate, so parallel refreshes
    /// would race each other.
    private func renew() async throws -> OAuthTokens {
        if let refreshing { return try await refreshing.value }
        let task = Task { [tokens] in try await TwentyOAuth.refresh(tokens) }
        refreshing = task
        defer { refreshing = nil }
        let renewed = try await task.value
        tokens = renewed
        persist(renewed)
        return renewed
    }
}

// MARK: - Browser sign-in

/// Opens Twenty's authorize page in a browser sheet that shares Safari's
/// cookies, so an existing Twenty or Google login carries over. The sheet's
/// custom scheme is never hit: Twenty redirects to the loopback receiver,
/// and the sheet is closed from here once the code arrives.
@MainActor
enum BrowserSignIn {
    static func authorize(url: URL, receiver: LoopbackReceiver) async throws -> URLComponents {
        let anchor = PresentationAnchor()
        let session = ASWebAuthenticationSession(url: url, callbackURLScheme: "io.tgbp.twentycrm") { _, error in
            // Only reached when the user closes the sheet (or we cancel it below).
            receiver.fail(error ?? CancellationError())
        }
        session.presentationContextProvider = anchor
        session.prefersEphemeralWebBrowserSession = false
        guard session.start() else { throw TwentyError(message: "Couldn't open the sign-in page.") }
        defer {
            session.cancel()
            // The session holds its presentation provider weakly.
            withExtendedLifetime(anchor) {}
        }
        return try await receiver.callback()
    }

    private final class PresentationAnchor: NSObject, ASWebAuthenticationPresentationContextProviding {
        func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
            MainActor.assumeIsolated {
                let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
                return scenes.flatMap(\.windows).first(where: \.isKeyWindow) ?? ASPresentationAnchor()
            }
        }
    }
}

/// One-shot HTTP listener on 127.0.0.1 that receives the OAuth redirect.
/// Twenty matches redirect URIs exactly, so the port is fixed.
final class LoopbackReceiver: @unchecked Sendable {
    static let port: UInt16 = 47823
    static let redirectURI = "http://127.0.0.1:\(port)/callback"

    private let listener: NWListener
    private let queue = DispatchQueue(label: "io.tgbp.twentycrm.oauth-loopback")
    // Touched only on `queue`.
    private var result: Result<URLComponents, Error>?
    private var waiter: CheckedContinuation<URLComponents, Error>?

    init() throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: NWEndpoint.Port(rawValue: Self.port)!)
        parameters.allowLocalEndpointReuse = true
        listener = try NWListener(using: parameters)
    }

    func start() {
        listener.stateUpdateHandler = { [weak self] state in
            if case .failed(let error) = state {
                self?.finish(.failure(TwentyError(message: "Couldn't listen for the sign-in response: \(error.localizedDescription)")))
            }
        }
        listener.newConnectionHandler = { [weak self] connection in self?.handle(connection) }
        listener.start(queue: queue)
    }

    func stop() { listener.cancel() }

    func fail(_ error: Error) { queue.async { self.finish(.failure(error)) } }

    func callback() async throws -> URLComponents {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                if let result = self.result { continuation.resume(with: result) } else { self.waiter = continuation }
            }
        }
    }

    private func finish(_ outcome: Result<URLComponents, Error>) {
        guard result == nil else { return }
        result = outcome
        waiter?.resume(with: outcome)
        waiter = nil
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, _, _ in
            guard let self else { connection.cancel(); return }
            let target = data.flatMap { Self.requestTarget(String(decoding: $0, as: UTF8.self)) }
            guard let target, let components = URLComponents(string: target), components.path == "/callback" else {
                // Favicon requests and the like.
                self.respond(connection, status: "404 Not Found", body: "")
                return
            }
            self.respond(connection, status: "200 OK", body: Self.donePage)
            self.finish(.success(components))
        }
    }

    /// `/callback?code=…` from `GET /callback?code=… HTTP/1.1`.
    static func requestTarget(_ request: String) -> String? {
        let parts = request.prefix { $0 != "\r" && $0 != "\n" }.split(separator: " ")
        guard parts.count >= 2, parts[0] == "GET" else { return nil }
        return String(parts[1])
    }

    private func respond(_ connection: NWConnection, status: String, body: String) {
        let bytes = Data(body.utf8)
        let head = "HTTP/1.1 \(status)\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(bytes.count)\r\nConnection: close\r\n\r\n"
        connection.send(content: Data(head.utf8) + bytes, completion: .contentProcessed { _ in connection.cancel() })
    }

    private static let donePage = """
    <!doctype html><meta name="viewport" content="width=device-width,initial-scale=1">
    <body style="font:17px -apple-system;text-align:center;padding-top:30vh">Signed in. Returning to the app…</body>
    """
}
