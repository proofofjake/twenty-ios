import Foundation

/// Everything the UI needs from a Twenty workspace. `LiveTwentyService` talks
/// to a real server over REST; `DemoTwentyService` is in-memory sample data.
protocol TwentyService: Sendable {
    func fetchObjects() async throws -> [ObjectMetadata]
    /// A page of records matching the search text and list filters; `memberID`
    /// resolves the filter's "Me" token.
    func fetchRecords(_ object: ObjectMetadata, search: String, filter: ListFilter, memberID: String?, after cursor: String?) async throws -> RecordPage
    func fetchRecord(_ object: ObjectMetadata, id: String) async throws -> Record
    /// Records with the given ids (depth 0), e.g. to label rows with company names.
    func fetchRecords(_ object: ObjectMetadata, ids: [String]) async throws -> [Record]
    func updateRecord(_ object: ObjectMetadata, id: String, patch: [String: JSONValue]) async throws -> Record
    func createRecord(_ object: ObjectMetadata, values: [String: JSONValue]) async throws -> Record
    /// Moves a record to Twenty's trash (restorable from "Deleted" on the
    /// web), or removes it for good when `permanently` is set.
    func deleteRecord(_ object: ObjectMetadata, id: String, permanently: Bool) async throws
    /// Brings a soft-deleted record back out of the trash.
    func restoreRecord(_ object: ObjectMetadata, id: String) async throws
    /// The signed-in person's `workspaceMember` record; nil for API keys and demo data.
    func fetchCurrentMember() async throws -> Record?
    #if DEBUG
    /// Twenty's merge: `ids[conflictPriorityIndex]` survives with the merged
    /// values and everything related to the others; the others are
    /// HARD-deleted (no trash, no undo). `dryRun` writes nothing and returns
    /// the would-be merged record. Returns the survivor at depth 1.
    func mergeRecords(_ object: ObjectMetadata, ids: [String], conflictPriorityIndex: Int, dryRun: Bool) async throws -> Record
    #endif
}

extension TwentyService {
    func fetchRecords(_ object: ObjectMetadata, search: String, after cursor: String?) async throws -> RecordPage {
        try await fetchRecords(object, search: search, filter: ListFilter(), memberID: nil, after: cursor)
    }

    func deleteRecord(_ object: ObjectMetadata, id: String) async throws {
        try await deleteRecord(object, id: id, permanently: false)
    }
}

struct TwentyError: LocalizedError {
    let message: String
    var status: Int?
    var errorDescription: String? { message }
    var isAuthFailure: Bool { status == 401 || status == 403 }
}

extension ObjectMetadata {
    /// REST filter matching `query` against the record title (and email for people).
    func searchFilter(_ query: String) -> String? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let field = labelIdentifierField else { return nil }
        let escaped = trimmed.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let pattern = "\"%\(escaped)%\""
        var clauses: [String] = []
        switch field.type {
        case .fullName:
            clauses += ["\(field.name).firstName[ilike]:\(pattern)", "\(field.name).lastName[ilike]:\(pattern)"]
        case .text:
            clauses.append("\(field.name)[ilike]:\(pattern)")
        default:
            return nil
        }
        if let emails = fields.first(where: { $0.type == .emails && $0.isActive != false }) {
            clauses.append("\(emails.name).primaryEmail[ilike]:\(pattern)")
        }
        if let domain = fields.first(where: { $0.name == "domainName" && $0.type == .links }) {
            clauses.append("\(domain.name).primaryLinkUrl[ilike]:\(pattern)")
        }
        return clauses.count == 1 ? clauses[0] : "or(\(clauses.joined(separator: ",")))"
    }

    /// Sort field for list views: the title, falling back to creation date.
    var defaultOrderBy: String {
        guard let field = labelIdentifierField else { return "createdAt[DescNullsLast]" }
        switch field.type {
        case .fullName: return "\(field.name).firstName[AscNullsLast]"
        case .text: return "\(field.name)[AscNullsLast]"
        default: return "createdAt[DescNullsLast]"
        }
    }
}

struct LiveTwentyService: TwentyService {
    let baseURL: URL
    let auth: any AccessTokenProvider
    var session: URLSession = .shared

    static let pageSize = 60

    func fetchObjects() async throws -> [ObjectMetadata] {
        do {
            return try await fetchObjectsGraphQL()
        } catch let error as TwentyError where error.isAuthFailure {
            throw error
        } catch {
            // Older servers without `fieldsList`: REST works, minus relation pickers.
            return try await fetchObjectsREST()
        }
    }

    /// GraphQL schema: same as REST plus relation targets, which REST omits.
    /// Mirrors twenty-front's `ObjectMetadataItems` query (max page size 1000).
    private func fetchObjectsGraphQL() async throws -> [ObjectMetadata] {
        var all: [ObjectMetadata] = []
        var cursor: String?
        repeat {
            let after = cursor.map { ", after: \(JSONValue.string($0).jsonLiteral)" } ?? ""
            let query = """
            query ObjectMetadataItems {
              objects(paging: { first: 1000\(after) }) {
                edges { node {
                  id nameSingular namePlural labelSingular labelPlural icon isActive isSystem isUIEditable writability
                  labelIdentifierFieldMetadataId imageIdentifierFieldMetadataId
                  fieldsList {
                    id type name label description icon isActive isSystem isUIEditable writability isNullable options settings
                    relation { type targetObjectMetadata { id nameSingular namePlural } targetFieldMetadata { id name } }
                  }
                } }
                pageInfo { hasNextPage endCursor }
              }
            }
            """
            let body = try JSONEncoder().encode(["query": query])
            let page = try Self.decodeGraphQLObjects(try await send("POST", path: "metadata", query: [], body: body))
            all += page.objects
            cursor = page.nextCursor
        } while cursor != nil && all.count < 5_000
        return all
    }

    /// REST schema: complete except for relation targets.
    private func fetchObjectsREST() async throws -> [ObjectMetadata] {
        var all: [ObjectMetadata] = []
        var cursor: String?
        repeat {
            var query = [URLQueryItem(name: "limit", value: "200")]
            if let cursor { query.append(URLQueryItem(name: "starting_after", value: cursor)) }
            let page = try Self.decodeObjectsPage(try await send("GET", path: "rest/metadata/objects", query: query))
            all += page.objects
            cursor = page.nextCursor
        } while cursor != nil && all.count < 5_000
        return all
    }

    func fetchRecords(_ object: ObjectMetadata, search: String, filter: ListFilter, memberID: String?, after cursor: String?) async throws -> RecordPage {
        var query = [
            URLQueryItem(name: "limit", value: String(Self.pageSize)),
            // depth=1 would also inline every one-to-many list (all of a
            // company's people, notes, …); the detail view fetches that instead.
            URLQueryItem(name: "depth", value: "0"),
            URLQueryItem(name: "order_by", value: object.defaultOrderBy),
        ]
        if let cursor { query.append(URLQueryItem(name: "starting_after", value: cursor)) }
        if let clause = Self.combine(object.searchFilter(search), filter.restClause(for: object, currentMemberID: memberID)) {
            query.append(URLQueryItem(name: "filter", value: clause))
        }
        let data = try await send("GET", path: "rest/\(object.namePlural)", query: query)
        return try Self.decodePage(data, object: object)
    }

    /// Search text and list filters must both hold.
    static func combine(_ clauses: String?...) -> String? {
        let present = clauses.compactMap { $0 }
        switch present.count {
        case 0: return nil
        case 1: return present[0]
        default: return "and(\(present.joined(separator: ",")))"
        }
    }

    func fetchRecords(_ object: ObjectMetadata, ids: [String]) async throws -> [Record] {
        var found: [Record] = []
        // Max page size is 200.
        for start in stride(from: 0, to: ids.count, by: 200) {
            let chunk = ids[start..<min(start + 200, ids.count)]
            let data = try await send("GET", path: "rest/\(object.namePlural)", query: [
                URLQueryItem(name: "limit", value: "200"),
                URLQueryItem(name: "depth", value: "0"),
                URLQueryItem(name: "filter", value: "id[in]:[\(chunk.joined(separator: ","))]"),
            ])
            found += try Self.decodePage(data, object: object).records
        }
        return found
    }

    func fetchRecord(_ object: ObjectMetadata, id: String) async throws -> Record {
        let data = try await send("GET", path: "rest/\(object.namePlural)/\(id)", query: [URLQueryItem(name: "depth", value: "1")])
        return try Self.decodeRecord(data, object: object)
    }

    func updateRecord(_ object: ObjectMetadata, id: String, patch: [String: JSONValue]) async throws -> Record {
        let body = try JSONEncoder().encode(patch)
        let data = try await send("PATCH", path: "rest/\(object.namePlural)/\(id)", query: [URLQueryItem(name: "depth", value: "1")], body: body)
        return try Self.decodeRecord(data, object: object)
    }

    func createRecord(_ object: ObjectMetadata, values: [String: JSONValue]) async throws -> Record {
        let body = try JSONEncoder().encode(values)
        let data = try await send("POST", path: "rest/\(object.namePlural)", query: [URLQueryItem(name: "depth", value: "1")], body: body)
        return try Self.decodeRecord(data, object: object)
    }

    func deleteRecord(_ object: ObjectMetadata, id: String, permanently: Bool) async throws {
        // Without soft_delete=true, REST DELETE destroys the record for good
        // (twenty-server rest-api-core.service: destroyOne vs deleteOne).
        let query = permanently ? [] : [URLQueryItem(name: "soft_delete", value: "true")]
        _ = try await send("DELETE", path: "rest/\(object.namePlural)/\(id)", query: query)
    }

    func restoreRecord(_ object: ObjectMetadata, id: String) async throws {
        // Restore is the one three-segment REST path, PATCH only.
        _ = try await send("PATCH", path: "rest/\(object.namePlural)/\(id)/restore", query: [])
    }

    #if DEBUG
    func mergeRecords(_ object: ObjectMetadata, ids: [String], conflictPriorityIndex: Int, dryRun: Bool) async throws -> Record {
        let body = try JSONEncoder().encode([
            "ids": .array(ids.map(JSONValue.string)),
            "conflictPriorityIndex": .number(Double(conflictPriorityIndex)),
            "dryRun": .bool(dryRun),
        ] as [String: JSONValue])
        // `PATCH /rest/<plural>/merge` answers `{data: {mergeCompanies: …}}`; decodeRecord takes the first record under data.
        let data = try await send("PATCH", path: "rest/\(object.namePlural)/merge", query: [URLQueryItem(name: "depth", value: "1")], body: body)
        return try Self.decodeRecord(data, object: object)
    }
    #endif

    func fetchCurrentMember() async throws -> Record? {
        // Only user tokens name a user; API keys act as the workspace.
        guard let userID = TwentyOAuth.claim("userId", inJWT: try await auth.accessToken()) else { return nil }
        let data = try await send("GET", path: "rest/workspaceMembers", query: [
            URLQueryItem(name: "limit", value: "1"),
            URLQueryItem(name: "depth", value: "0"),
            URLQueryItem(name: "filter", value: "userId[eq]:\(userID)"),
        ])
        let json = try JSONDecoder().decode(JSONValue.self, from: data)
        return json["data"]?["workspaceMembers"]?.arrayValue?.first.flatMap(Record.init(json:))
    }

    // MARK: Transport

    private func send(_ method: String, path: String, query: [URLQueryItem], body: Data? = nil) async throws -> Data {
        var (data, http) = try await perform(method, path: path, query: query, body: body, token: try await auth.accessToken())
        // An OAuth access token can be revoked or expire early; renew once and retry.
        if http.statusCode == 401, let fresh = try await auth.tokenAfterRejection() {
            (data, http) = try await perform(method, path: path, query: query, body: body, token: fresh)
        }
        guard (200..<300).contains(http.statusCode) else {
            throw TwentyError(message: Self.errorMessage(data, status: http.statusCode), status: http.statusCode)
        }
        return data
    }

    private func perform(_ method: String, path: String, query: [URLQueryItem], body: Data?, token: String) async throws -> (Data, HTTPURLResponse) {
        var components = URLComponents(url: baseURL.appending(path: path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }
        // `+` is legal in a query but some servers decode it as a space.
        components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw TwentyError(message: "No response from server") }
        return (data, http)
    }

    // MARK: Decoding (static so tests can feed fixture JSON)

    static func errorMessage(_ data: Data, status: Int) -> String {
        if let json = try? JSONDecoder().decode(JSONValue.self, from: data) {
            let messages = (json["messages"]?.arrayValue ?? []).compactMap(\.stringValue)
            if !messages.isEmpty { return messages.joined(separator: "\n") }
            if let message = json["message"]?.nonEmptyString ?? json["error"]?.nonEmptyString { return "\(message) (\(status))" }
        }
        switch status {
        case 401: return "Twenty rejected the sign-in (401). Sign out in Settings and sign in again."
        case 403: return "Your account isn't allowed to do that (403)."
        case 404: return "Not found (404). Check the server URL."
        default: return "Server error \(status)"
        }
    }

    /// REST metadata comes in two envelopes depending on the workspace's
    /// `IS_REST_METADATA_API_NEW_FORMAT_DIRECT` flag: `{data:[...]}` (new
    /// workspaces) or `{data:{objects:[...]}}` (older ones).
    static func decodeObjectsPage(_ data: Data) throws -> (objects: [ObjectMetadata], nextCursor: String?) {
        struct Envelope: Decodable {
            struct Legacy: Decodable { let objects: [ObjectMetadata] }
            struct PageInfo: Decodable { let hasNextPage: Bool?; let endCursor: String? }
            let objects: [ObjectMetadata]
            let pageInfo: PageInfo?

            enum CodingKeys: String, CodingKey { case data, pageInfo }
            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                if let direct = try? c.decode([ObjectMetadata].self, forKey: .data) {
                    objects = direct
                } else {
                    objects = try c.decode(Legacy.self, forKey: .data).objects
                }
                pageInfo = try? c.decodeIfPresent(PageInfo.self, forKey: .pageInfo)
            }
        }
        let envelope = try JSONDecoder().decode(Envelope.self, from: data)
        let next = envelope.pageInfo?.hasNextPage == true ? envelope.pageInfo?.endCursor : nil
        return (envelope.objects, next)
    }

    static func decodeGraphQLObjects(_ data: Data) throws -> (objects: [ObjectMetadata], nextCursor: String?) {
        struct Response: Decodable {
            struct GQLError: Decodable { let message: String }
            struct Payload: Decodable {
                struct Connection: Decodable {
                    struct Edge: Decodable { let node: ObjectMetadata }
                    struct PageInfo: Decodable { let hasNextPage: Bool?; let endCursor: String? }
                    let edges: [Edge]
                    let pageInfo: PageInfo?
                }
                let objects: Connection
            }
            let data: Payload?
            let errors: [GQLError]?
        }
        let response = try JSONDecoder().decode(Response.self, from: data)
        guard let connection = response.data?.objects else {
            throw TwentyError(message: response.errors?.map(\.message).joined(separator: "\n") ?? "Unexpected GraphQL response")
        }
        let next = connection.pageInfo?.hasNextPage == true ? connection.pageInfo?.endCursor : nil
        return (connection.edges.map(\.node), next)
    }

    static func decodeObjects(_ data: Data) throws -> [ObjectMetadata] {
        try decodeObjectsPage(data).objects
    }

    static func decodePage(_ data: Data, object: ObjectMetadata) throws -> RecordPage {
        let json = try JSONDecoder().decode(JSONValue.self, from: data)
        let payload = json["data"]?.objectValue ?? [:]
        let list = payload[object.namePlural]?.arrayValue ?? payload.values.first(where: { $0.arrayValue != nil })?.arrayValue ?? []
        let pageInfo = json["pageInfo"]
        return RecordPage(
            records: list.compactMap(Record.init(json:)),
            hasNextPage: pageInfo?["hasNextPage"]?.boolValue ?? false,
            endCursor: pageInfo?["endCursor"]?.stringValue,
            totalCount: json["totalCount"]?.doubleValue.map { Int($0) }
        )
    }

    static func decodeRecord(_ data: Data, object: ObjectMetadata) throws -> Record {
        let json = try JSONDecoder().decode(JSONValue.self, from: data)
        let payload = json["data"]?.objectValue ?? [:]
        let candidate = payload[object.nameSingular] ?? payload.values.first(where: { $0["id"] != nil })
        guard let candidate, let record = Record(json: candidate) else {
            throw TwentyError(message: "Unexpected response from server")
        }
        return record
    }
}
