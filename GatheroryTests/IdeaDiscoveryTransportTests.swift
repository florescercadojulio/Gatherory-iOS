import Foundation
import Testing
@testable import Gatherory

@Suite(.serialized)
@MainActor
struct IdeaDiscoveryTransportTests {
    @Test("Idea search sends the authenticated GET query and decodes the server v1 response shape")
    func authenticatedIdeaSearchMatchesContract() async throws {
        IdeaDiscoveryHTTPProtocol.configure(status: 200, body: Self.responseBody)
        let session = makeSession()
        defer { session.invalidateAndCancel() }
        let transport = makeTransport(session: session, token: "catalog-session")

        let page = try await transport.ideaCatalogPage(cursor: "cursor_A_1", limit: 27, query: "tea & toast")

        #expect(page.ideas.count == 1)
        let entry = try #require(page.ideas.first)
        #expect(entry.id == "birthday-party:3:activity_ideas")
        #expect(entry.sourceBlueprintId == "birthday_party")
        #expect(entry.sourceVersion == 3)
        #expect(entry.sourceTitle == "Birthday Party")
        #expect(entry.creator?.displayName == "Gatherory")
        #expect(entry.idea.key == "activity_ideas")
        #expect(entry.idea.title == "Choose activities")
        #expect(entry.idea.category == "other")
        #expect(entry.idea.notes == "Collect activities everyone can enjoy.")
        #expect(entry.idea.target == .main)
        #expect(entry.idea.configuration == ["version": .integer(1)])
        #expect(entry.coverAssetId == UUID(uuidString: "A0A0A0A0-0000-4000-8000-000000000001"))
        #expect(entry.coverImageURL == "https://cdn.gatherory.com/explore/covers/birthday-party/\(String(repeating: "b", count: 64))/card.jpg")
        #expect(page.nextCursor == "next_cursor")

        #expect(IdeaDiscoveryHTTPProtocol.lastPath == "/api/blueprints/ideas")
        #expect(IdeaDiscoveryHTTPProtocol.lastMethod == "GET")
        #expect(IdeaDiscoveryHTTPProtocol.lastAuthorization == "Bearer catalog-session")
        #expect(IdeaDiscoveryHTTPProtocol.lastBody.isEmpty)
        let requestURL = try #require(IdeaDiscoveryHTTPProtocol.lastURL)
        let queryItems = try #require(URLComponents(url: requestURL, resolvingAgainstBaseURL: false)?.queryItems)
        #expect(queryItems.first { $0.name == "limit" }?.value == "27")
        #expect(queryItems.first { $0.name == "cursor" }?.value == "cursor_A_1")
        #expect(queryItems.first { $0.name == "q" }?.value == "tea & toast")

        let root = try #require(JSONSerialization.jsonObject(with: Self.responseBody) as? [String: Any])
        #expect(Set(root.keys) == ["ideas", "nextCursor"])
        let rows = try #require(root["ideas"] as? [[String: Any]])
        let row = try #require(rows.first)
        #expect(Set(row.keys) == ["id", "sourceBlueprintId", "sourceVersion", "sourceTitle", "creator", "idea", "coverAssetId", "coverImageURL"])
        #expect(Set(try #require(row["idea"] as? [String: Any]).keys) == ["key", "title", "category", "notes", "target", "configuration"])
    }

    @Test("Missing local session rejects search without making an HTTP request")
    func missingSessionDoesNotRequest() async throws {
        IdeaDiscoveryHTTPProtocol.configure(status: 200, body: Self.responseBody)
        let session = makeSession()
        defer { session.invalidateAndCancel() }
        let transport = makeTransport(session: session, token: nil)

        await #expect {
            try await transport.ideaCatalogPage(query: "picnic")
        } throws: { error in
            Self.isInvalidSession(error)
        }
        #expect(IdeaDiscoveryHTTPProtocol.requestCount == 0)
    }

    @Test("A server 401 clears the idea search session error path")
    func serverUnauthorizedSession() async throws {
        IdeaDiscoveryHTTPProtocol.configure(status: 401, body: Data(#"{"error":"UNAUTHORIZED"}"#.utf8))
        let session = makeSession()
        defer { session.invalidateAndCancel() }
        let transport = makeTransport(session: session, token: "expired-session")

        await #expect {
            try await transport.ideaCatalogPage(query: "picnic")
        } throws: { error in
            Self.isInvalidSession(error)
        }
        #expect(IdeaDiscoveryHTTPProtocol.lastPath == "/api/blueprints/ideas")
        #expect(IdeaDiscoveryHTTPProtocol.lastAuthorization == "Bearer expired-session")
    }

    @Test("An in-flight idea search is rejected after an A to B to A account generation change")
    func accountGenerationRejectsInFlightResponse() async throws {
        IdeaDiscoveryHTTPProtocol.configure(status: 200, body: Self.responseBody, holdResponse: true)
        let session = makeSession()
        defer { session.invalidateAndCancel() }
        let persistence = try WorkspacePersistenceController(isStoredInMemoryOnly: true)
        let library = persistence.restoreLibrary(seedData: false, ownerUserID: "account-a")
        let transport = makeTransport(session: session, token: "account-a-session")
        let coordinator = BlueprintInstallationCoordinator(
            baseURL: URL(string: "https://ideas.invalid")!,
            persistence: persistence,
            library: library,
            transport: transport
        )

        let request = Task { try await coordinator.ideaCatalogPage(query: "picnic") }
        #expect(await waitForRequest())
        persistence.activate(userID: "account-b", in: library)
        persistence.activate(userID: "account-a", in: library)
        IdeaDiscoveryHTTPProtocol.releaseResponse()

        await #expect {
            try await request.value
        } throws: { error in
            Self.isInvalidSession(error) || error is CancellationError
        }
    }

    private static func isInvalidSession(_ error: Error) -> Bool {
        guard let failure = error as? CloudSyncFailure else { return false }
        if case .invalidSession = failure { return true }
        return false
    }

    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [IdeaDiscoveryHTTPProtocol.self]
        configuration.httpShouldSetCookies = false
        return URLSession(configuration: configuration)
    }

    private func makeTransport(session: URLSession, token: String?) -> PostgresSyncTransport {
        PostgresSyncTransport(
            baseURL: URL(string: "https://ideas.invalid")!,
            urlSession: session,
            tokenStore: IdeaDiscoveryTokenStore(token: token)
        )
    }

    private func waitForRequest() async -> Bool {
        for _ in 0..<200 {
            if IdeaDiscoveryHTTPProtocol.hasStartedRequest { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return false
    }

    private static var responseBody: Data {
        Data(
            """
            {
              "ideas": [
                {
                  "id": "birthday-party:3:activity_ideas",
                  "sourceBlueprintId": "birthday_party",
                  "sourceVersion": 3,
                  "sourceTitle": "Birthday Party",
                  "creator": { "displayName": "Gatherory" },
                  "coverAssetId": "a0a0a0a0-0000-4000-8000-000000000001",
                  "idea": {
                    "key": "activity_ideas",
                    "title": "Choose activities",
                    "category": "other",
                    "notes": "Collect activities everyone can enjoy.",
                    "target": { "kind": "main" },
                    "configuration": { "version": 1 }
                  },
                  "coverImageURL": "https://cdn.gatherory.com/explore/covers/birthday-party/\(String(repeating: "b", count: 64))/card.jpg"
                }
              ],
              "nextCursor": "next_cursor"
            }
            """.utf8
        )
    }
}

private struct IdeaDiscoveryTokenStore: SessionTokenStore {
    let token: String?
    func read() throws -> String? { token }
    func save(_ token: String) throws {}
    func delete() {}
}

private final class IdeaDiscoveryHTTPProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    private static var responseStatus = 200
    private static var responseBody = Data()
    private static var requestCountValue = 0
    private static var pathValue: String?
    private static var methodValue: String?
    private static var authorizationValue: String?
    private static var bodyValue = Data()
    private static var urlValue: URL?
    private static var holdResponseValue = false
    private static var requestStartedValue = false
    private static let responseGate = DispatchSemaphore(value: 0)

    static var requestCount: Int { read { requestCountValue } }
    static var lastPath: String? { read { pathValue } }
    static var lastMethod: String? { read { methodValue } }
    static var lastAuthorization: String? { read { authorizationValue } }
    static var lastBody: Data { read { bodyValue } }
    static var lastURL: URL? { read { urlValue } }
    static var hasStartedRequest: Bool { read { requestStartedValue } }

    static func configure(status: Int, body: Data, holdResponse: Bool = false) {
        lock.lock()
        responseStatus = status
        responseBody = body
        requestCountValue = 0
        pathValue = nil
        methodValue = nil
        authorizationValue = nil
        bodyValue = Data()
        urlValue = nil
        holdResponseValue = holdResponse
        requestStartedValue = false
        lock.unlock()
        _ = responseGate.wait(timeout: .now())
    }

    static func releaseResponse() { responseGate.signal() }

    private static func read<Value>(_ value: () -> Value) -> Value {
        lock.lock()
        defer { lock.unlock() }
        return value()
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        Self.lock.lock()
        Self.requestCountValue += 1
        Self.requestStartedValue = true
        Self.pathValue = request.url?.path
        Self.urlValue = request.url
        Self.methodValue = request.httpMethod
        Self.authorizationValue = request.value(forHTTPHeaderField: "Authorization")
        Self.bodyValue = request.httpBody ?? Data()
        let status = Self.responseStatus
        let body = Self.responseBody
        let holdResponse = Self.holdResponseValue
        Self.lock.unlock()

        if holdResponse {
            _ = Self.responseGate.wait(timeout: .now() + 10)
        }
        guard let url = request.url,
              let response = HTTPURLResponse(
                url: url,
                statusCode: status,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
              ) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }
}
