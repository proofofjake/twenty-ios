import XCTest
@testable import TwentyCRM

final class OAuthTests: XCTestCase {
    private let server = OAuthServerMetadata(
        issuer: "https://api.twenty.com",
        authorizationEndpoint: URL(string: "https://app.twenty.com/authorize?iss=https%3A%2F%2Fapi.twenty.com")!,
        tokenEndpoint: URL(string: "https://api.twenty.com/oauth/token")!,
        registrationEndpoint: URL(string: "https://api.twenty.com/oauth/register")!,
        revocationEndpoint: URL(string: "https://api.twenty.com/oauth/revoke")!
    )

    func testPKCEChallengeIsBase64URLSHA256() {
        // base64url(SHA-256(verifier)), cross-checked with Python hashlib.
        XCTAssertEqual(PKCE.challenge(for: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWjOEjXk"), "VYFANLqdx_HDV6BqEhluZJ63rtrIPROSSFdB3P6G83I")
        let generated = PKCE()
        XCTAssertGreaterThanOrEqual(generated.verifier.count, 43)
        XCTAssertNil(generated.verifier.rangeOfCharacter(from: CharacterSet(charactersIn: "+/=")))
    }

    func testDecodesTwentyCloudDiscoveryDocument() throws {
        let json = #"{"issuer":"https://api.twenty.com","authorization_endpoint":"https://app.twenty.com/authorize?iss=https%3A%2F%2Fapi.twenty.com","token_endpoint":"https://api.twenty.com/oauth/token","registration_endpoint":"https://api.twenty.com/oauth/register","revocation_endpoint":"https://api.twenty.com/oauth/revoke","scopes_supported":["api","profile"],"code_challenge_methods_supported":["S256"]}"#
        XCTAssertEqual(try JSONDecoder().decode(OAuthServerMetadata.self, from: Data(json.utf8)), server)
    }

    func testAuthorizationURLKeepsServerQueryAndAddsPKCE() throws {
        let pkce = PKCE(verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWjOEjXk")
        let url = TwentyOAuth.authorizationURL(server: server, clientID: "client-1", redirectURI: LoopbackReceiver.redirectURI, pkce: pkce, state: "s1")
        let items = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
        XCTAssertEqual(url.host(), "app.twenty.com")
        XCTAssertEqual(value("iss"), "https://api.twenty.com")
        XCTAssertEqual(value("client_id"), "client-1")
        XCTAssertEqual(value("redirect_uri"), "http://127.0.0.1:47823/callback")
        XCTAssertEqual(value("code_challenge"), "VYFANLqdx_HDV6BqEhluZJ63rtrIPROSSFdB3P6G83I")
        XCTAssertEqual(value("code_challenge_method"), "S256")
        XCTAssertEqual(value("response_type"), "code")
        XCTAssertEqual(value("state"), "s1")
    }

    func testAuthorizationURLOpensOnWorkspaceDomain() throws {
        let url = TwentyOAuth.authorizationURL(server: server, clientID: "c", redirectURI: LoopbackReceiver.redirectURI,
                                               pkce: PKCE(), state: "s", workspace: URL(string: "https://tokenisedgbp.twenty.com")!)
        XCTAssertEqual(url.host(), "tokenisedgbp.twenty.com")
        XCTAssertEqual(url.path(), "/authorize")
        let items = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        XCTAssertEqual(items.first { $0.name == "iss" }?.value, "https://api.twenty.com")
    }

    func testCallbackChecksStateAndIssuer() throws {
        func callback(_ query: String) -> URLComponents { URLComponents(string: "/callback?\(query)")! }
        let ok = callback("code=abc&iss=https%3A%2F%2Fapi.twenty.com&state=s1&theme=light")
        XCTAssertEqual(try TwentyOAuth.code(fromCallback: ok, state: "s1", issuer: server.issuer), "abc")
        XCTAssertThrowsError(try TwentyOAuth.code(fromCallback: ok, state: "other", issuer: server.issuer))
        XCTAssertThrowsError(try TwentyOAuth.code(fromCallback: callback("code=abc&state=s1&iss=https%3A%2F%2Fevil.example"), state: "s1", issuer: server.issuer))
        XCTAssertThrowsError(try TwentyOAuth.code(fromCallback: callback("error=access_denied&state=s1"), state: "s1", issuer: nil))
    }

    func testReadsRequestTargetFromHTTPRequestLine() {
        XCTAssertEqual(LoopbackReceiver.requestTarget("GET /callback?code=a&state=b HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n"), "/callback?code=a&state=b")
        XCTAssertNil(LoopbackReceiver.requestTarget("POST /callback HTTP/1.1\r\n"))
        XCTAssertNil(LoopbackReceiver.requestTarget(""))
    }

    func testReadsUserIDFromApplicationTokenButNotAPIKey() {
        func jwt(_ payload: String) -> String { "eyJhbGciOiJIUzI1NiJ9.\(TwentyOAuth.base64URL(Data(payload.utf8))).sig" }
        let user = jwt(#"{"sub":"app-1","type":"APPLICATION_ACCESS","workspaceId":"w1","applicationId":"app-1","userId":"u-42","userWorkspaceId":"uw1"}"#)
        XCTAssertEqual(TwentyOAuth.claim("userId", inJWT: user), "u-42")
        let apiKey = jwt(#"{"sub":"w1","type":"API_KEY","workspaceId":"w1"}"#)
        XCTAssertNil(TwentyOAuth.claim("userId", inJWT: apiKey))
        XCTAssertNil(TwentyOAuth.claim("userId", inJWT: "not-a-jwt"))
    }

    func testDecodesTokenResponse() throws {
        let json = #"{"access_token":"a","token_type":"Bearer","expires_in":1800,"refresh_token":"r","scope":"api profile"}"#
        let response = try JSONDecoder().decode(TwentyOAuth.TokenResponse.self, from: Data(json.utf8))
        XCTAssertEqual(response.accessToken, "a")
        XCTAssertEqual(response.refreshToken, "r")
        XCTAssertEqual(response.expiresAt.timeIntervalSinceNow, 1800, accuracy: 5)
    }

    // MARK: Owner prefill

    private func company() throws -> ObjectMetadata {
        let json = #"""
        {"data":{"objects":{"edges":[{"node":{"id":"o1","nameSingular":"company","namePlural":"companies","labelSingular":"Company","labelPlural":"Companies",
          "isActive":true,"isSystem":false,"fieldsList":[
            {"id":"f1","type":"TEXT","name":"name","label":"Name","isActive":true,"isSystem":false,"writability":"OPEN"},
            {"id":"f2","type":"RELATION","name":"accountOwner","label":"Account Owner","isActive":true,"isSystem":false,"writability":"OPEN",
             "settings":{"relationType":"MANY_TO_ONE","joinColumnName":"accountOwnerId"},
             "relation":{"type":"MANY_TO_ONE","targetObjectMetadata":{"id":"o9","nameSingular":"workspaceMember","namePlural":"workspaceMembers"}}},
            {"id":"f3","type":"RELATION","name":"reviewer","label":"Reviewer","isActive":true,"isSystem":false,"writability":"OPEN",
             "settings":{"relationType":"MANY_TO_ONE","joinColumnName":"reviewerId"},
             "relation":{"type":"MANY_TO_ONE","targetObjectMetadata":{"id":"o9","nameSingular":"workspaceMember","namePlural":"workspaceMembers"}}}
          ]}}],"pageInfo":{"hasNextPage":false}}}}
        """#
        return try XCTUnwrap(LiveTwentyService.decodeGraphQLObjects(Data(json.utf8)).objects.first)
    }

    private let me = Record(id: "m1", values: ["id": "m1", "name": ["firstName": "Jake", "lastName": "Galvin"]])

    func testPrefillsAccountOwnerWithSignedInMember() throws {
        let object = try company()
        XCTAssertEqual(object.ownerFields.map(\.name), ["accountOwner"])
        let draft = object.draft(titled: "Acme").prefillingOwner(me, in: object)
        XCTAssertEqual(draft["accountOwnerId"], "m1")
        XCTAssertEqual(FieldFormatter.relationTitle(draft["accountOwner"]), "Jake Galvin")
        XCTAssertTrue(draft["reviewerId"].isNull)
        // Only the foreign key is posted.
        XCTAssertEqual(draft.createPayload(for: object), ["name": "Acme", "accountOwnerId": "m1"])
    }

    func testKeepsOwnerAlreadyChosen() throws {
        let object = try company()
        let chosen = Record(id: "", values: ["accountOwnerId": "m2"])
        XCTAssertEqual(chosen.prefillingOwner(me, in: object)["accountOwnerId"], "m2")
    }
}
