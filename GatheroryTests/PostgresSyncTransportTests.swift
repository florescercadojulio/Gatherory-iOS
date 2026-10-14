import Foundation
import Testing
@testable import Gatherory

@MainActor
struct PostgresSyncTransportTests {
    @Test("Sync reads the current bearer token on every request, including account switches")
    func tokenIsNotCached() async throws {
        let fixture = SyncHTTPFixture("bootstrap")
        defer { fixture.session.invalidateAndCancel() }
        let first = try await fixture.transport.bootstrap()
        #expect(first.account?.hasCompletedOnboarding == false)
        fixture.tokens.save("account-b")
        let second = try await fixture.transport.bootstrap()
        #expect(second.account?.hasCompletedOnboarding == true)
        #expect(second.snapshots.isEmpty)
        #expect(second.entitySnapshots.isEmpty)
        fixture.tokens.delete()
        await #expect {
            try await fixture.transport.bootstrap()
        } throws: { error in
            if case CloudSyncFailure.invalidSession = error { return true }
            return false
        }
    }

    @Test("Missing or empty credentials fail locally for every sync operation", arguments: [nil, ""] as [String?])
    func requiresToken(token: String?) async {
        // Any HTTP request to this fixture records a test failure.
        let fixture = SyncHTTPFixture("no-request", token: token)
        defer { fixture.session.invalidateAndCancel() }
        for operation in ["bootstrap", "push", "pull"] {
            await #expect {
                switch operation {
                case "push": _ = try await fixture.transport.push([])
                case "pull": _ = try await fixture.transport.pull(scopeID: UUID(), after: nil)
                default: _ = try await fixture.transport.bootstrap()
                }
            } throws: { error in
                if case CloudSyncFailure.invalidSession = error { return true }
                return false
            }
        }
    }

    @Test("Bootstrap remains compatible with servers omitting optional account and entity fields")
    func legacyBootstrap() async throws {
        let fixture = SyncHTTPFixture("legacy")
        defer { fixture.session.invalidateAndCancel() }
        let response = try await fixture.transport.bootstrap()
        #expect(response.account == nil)
        #expect(response.snapshots.isEmpty)
        #expect(response.entitySnapshots.isEmpty)
    }

    @Test("Push preserves durable mutation identity and decodes each server disposition",
          arguments: ["applied", "duplicate", "conflict", "rejected"])
    func pushContract(disposition: String) async throws {
        let fixture = SyncHTTPFixture(disposition)
        defer { fixture.session.invalidateAndCancel() }
        let mutation = PendingMutationSnapshot(PendingMutation(
            id: UUID(uuidString: "11111111-1111-4111-8111-111111111111")!,
            scopeID: UUID(uuidString: "22222222-2222-4222-8222-222222222222")!,
            entityType: .event,
            entityID: UUID(uuidString: "33333333-3333-4333-8333-333333333333")!,
            operation: .update,
            payload: Data("{\"title\":\"Dinner\"}".utf8),
            baseVersion: 7,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        ))
        // Retrying must send the same ID and payload, not create another logical mutation.
        for _ in 0..<2 {
            let response = try await fixture.transport.push([mutation])
            #expect(response.results.count == 1)
            let result = try #require(response.results.first)
            #expect(result.mutationID == mutation.id)
            #expect(result.disposition.rawValue == disposition)
            #expect(result.serverVersion == (disposition == "rejected" ? nil : 8))
            let expectedFailure = switch disposition {
            case "rejected": "EVENT_PERMISSION_REQUIRED"
            case "conflict": "SERVER_VERSION_CONFLICT"
            default: nil as String?
            }
            #expect(result.failureCode == expectedFailure)
        }
    }

    @Test("Pull encodes its scope and cursor and decodes remote changes", arguments: [nil, "cursor/+?=&"] as [String?])
    func pullContract(cursor: String?) async throws {
        let fixture = SyncHTTPFixture(cursor == nil ? "pull-initial" : "pull-next")
        defer { fixture.session.invalidateAndCancel() }
        let scope = UUID(uuidString: "22222222-2222-4222-8222-222222222222")!
        let page = try await fixture.transport.pull(scopeID: scope, after: cursor)
        #expect(page.nextCursor == "42")
        #expect(page.hasMore)
        #expect(page.changes.count == 1)
        let change = try #require(page.changes.first)
        #expect(change.scopeID == scope)
        #expect(change.entityID == UUID(uuidString: "33333333-3333-4333-8333-333333333333"))
        #expect(change.entityType == .event)
        #expect(change.operation == .delete)
        #expect(change.serverVersion == 8)
        #expect(change.effectivePayloadSchemaVersion == 1)
        #expect(change.payload == Data("{}".utf8))
        #expect(change.occurredAt == Date(timeIntervalSince1970: 1_700_000_000))
    }

    @Test("HTTP, decoding, and network failures retain actionable classifications",
          arguments: ["unauthorized", "too-large", "forbidden", "legacy-error", "server-error", "malformed", "network"])
    func failureContract(scenario: String) async {
        let fixture = SyncHTTPFixture(scenario)
        defer { fixture.session.invalidateAndCancel() }
        await #expect {
            try await fixture.transport.bootstrap()
        } throws: { error in
            switch (scenario, error) {
            case ("unauthorized", CloudSyncFailure.invalidSession),
                 ("too-large", CloudSyncFailure.payloadTooLarge),
                 ("malformed", CloudSyncFailure.invalidResponse): return true
            case ("forbidden", CloudSyncFailure.server(let code)): return code == "EVENT_PERMISSION_REQUIRED"
            case ("legacy-error", CloudSyncFailure.server(let code)): return code == "SYNC_SCOPE_NOT_FOUND"
            case ("server-error", CloudSyncFailure.server(let code)): return code == "HTTP_500"
            case ("network", let error as URLError): return error.code == .notConnectedToInternet
            default: return false
            }
        }
    }
}

@MainActor
private struct SyncHTTPFixture {
    let session: URLSession
    let tokens: SyncHTTPTokenStore
    let transport: PostgresSyncTransport

    init(_ scenario: String, token: String? = "account-a") {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SyncHTTPProtocol.self]
        session = URLSession(configuration: configuration)
        tokens = SyncHTTPTokenStore(token)
        transport = PostgresSyncTransport(
            baseURL: URL(string: "https://\(scenario).invalid")!,
            urlSession: session,
            tokenStore: tokens
        )
    }
}

@MainActor
private final class SyncHTTPTokenStore: SessionTokenStore {
    private var token: String?
    init(_ token: String?) { self.token = token }
    func read() -> String? { token }
    func save(_ token: String) { self.token = token }
    func delete() { token = nil }
}

/// All requests are intercepted; fixture selection is per URL, without shared mutable handlers.
private final class SyncHTTPProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        do {
            let url = try #require(request.url)
            let scenario = url.host?.components(separatedBy: ".").first ?? ""
            #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
            #expect(UUID(uuidString: request.value(forHTTPHeaderField: "X-Request-ID") ?? "") != nil)
            let bearer = request.value(forHTTPHeaderField: "Authorization")
            #expect(bearer == "Bearer account-a" || bearer == "Bearer account-b")
            var status = 200
            var payload: [String: Any] = ["snapshots": []]
            switch scenario {
            case "bootstrap":
                payload["account"] = ["hasCompletedOnboarding": bearer == "Bearer account-b"]
            case "legacy": break
            case "applied", "duplicate", "conflict", "rejected":
                #expect(url.path == "/api/sync/push")
                #expect(request.httpMethod == "POST")
                #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
                let body = try #require(try JSONSerialization.jsonObject(with: bodyData()) as? [String: Any])
                let mutations = try #require(body["mutations"] as? [[String: Any]])
                #expect(mutations.count == 1)
                let mutation = try #require(mutations.first)
                #expect(mutation["id"] as? String == "11111111-1111-4111-8111-111111111111")
                #expect(mutation["scopeID"] as? String == "22222222-2222-4222-8222-222222222222")
                #expect(mutation["entityID"] as? String == "33333333-3333-4333-8333-333333333333")
                #expect(mutation["entityType"] as? String == "event")
                #expect(mutation["operation"] as? String == "update")
                #expect(mutation["payloadSchemaVersion"] as? Int == 1)
                #expect(mutation["baseVersion"] as? Int == 7)
                #expect(mutation["attemptCount"] as? Int == 0)
                #expect(mutation["createdAt"] as? String == "2023-11-14T22:13:20Z")
                #expect(mutation["payload"] as? String == Data("{\"title\":\"Dinner\"}".utf8).base64EncodedString())
                var result: [String: Any] = [
                    "mutationID": "11111111-1111-4111-8111-111111111111",
                    "disposition": scenario, "serverVersion": 8
                ]
                if scenario == "rejected" {
                    result["failureCode"] = "EVENT_PERMISSION_REQUIRED"
                    result["serverVersion"] = NSNull()
                } else if scenario == "conflict" {
                    result["failureCode"] = "SERVER_VERSION_CONFLICT"
                }
                payload = ["results": [result]]
            case "pull-initial", "pull-next":
                #expect(url.path == "/api/sync/pull")
                #expect(request.httpMethod == "GET")
                let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
                #expect(query.first(where: { $0.name == "scopeID" })?.value == "22222222-2222-4222-8222-222222222222")
                #expect(query.first(where: { $0.name == "after" })?.value == (scenario == "pull-initial" ? "0" : "cursor/+?=&"))
                payload = ["nextCursor": "42", "hasMore": true, "changes": [[
                    "id": "11111111-1111-4111-8111-111111111111",
                    "scopeID": "22222222-2222-4222-8222-222222222222",
                    "entityID": "33333333-3333-4333-8333-333333333333",
                    "entityType": "event", "operation": "delete", "payload": "e30=",
                    "serverVersion": 8, "occurredAt": "2023-11-14T22:13:20Z"
                ]]]
            case "unauthorized": status = 401
            case "too-large": status = 413
            case "forbidden":
                status = 403
                payload = ["error": ["code": "EVENT_PERMISSION_REQUIRED", "errorId": "test-error"]]
            case "legacy-error":
                status = 404
                payload = ["error": "SYNC_SCOPE_NOT_FOUND"]
            case "server-error":
                status = 500
                payload = [:]
            case "malformed": payload = ["snapshots": "not-an-array"]
            case "network": throw URLError(.notConnectedToInternet)
            default:
                Issue.record("Unexpected HTTP request to \(scenario)")
                throw URLError(.badURL)
            }
            if !["applied", "duplicate", "conflict", "rejected", "pull-initial", "pull-next"].contains(scenario) {
                #expect(url.path == "/api/sync/bootstrap")
                #expect(request.httpMethod == "GET")
            }
            let response = try #require(HTTPURLResponse(url: url, statusCode: status, httpVersion: nil,
                                                       headerFields: ["Content-Type": "application/json"]))
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: try JSONSerialization.data(withJSONObject: payload))
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    private func bodyData() throws -> Data {
        if let body = request.httpBody { return body }
        let stream = try #require(request.httpBodyStream)
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1024)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count < 0 { throw stream.streamError ?? URLError(.cannotDecodeContentData) }
            if count == 0 { break }
            data.append(contentsOf: buffer.prefix(count))
        }
        return data
    }
}
