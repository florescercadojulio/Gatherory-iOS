import Foundation
import Testing
@testable import Gatherory

@Suite(.serialized)
@MainActor
struct BlueprintSharedTemplateTransportTests {
    @Test("A shared link resolves to one pinned catalog entry without sending session credentials")
    func anonymousPinnedEntryResolution() async throws {
        let token = String(repeating: "d4", count: 32)
        let fixtureURL = try #require(Bundle(for: SharedBlueprintFixtureBundle.self)
            .url(forResource: "wedding-catalog.v1", withExtension: "json"))
        let catalogData = try Data(contentsOf: fixtureURL)
        let catalogObject = try #require(JSONSerialization.jsonObject(with: catalogData) as? [String: Any])
        let entries = try #require(catalogObject["entries"] as? [[String: Any]])
        let entryData = try JSONSerialization.data(withJSONObject: try #require(entries.first))
        SharedBlueprintURLProtocol.configure(status: 200, body: entryData)
        let session = makeSession()
        defer { session.invalidateAndCancel() }
        let transport = PostgresSyncTransport(
            baseURL: URL(string: "https://dev.gatherory.com")!,
            urlSession: session,
            tokenStore: SharedBlueprintTokenStore()
        )

        let entry = try await transport.sharedBlueprint(token: token)

        #expect(entry.catalogKey == "wedding")
        #expect(entry.revision == 1)
        #expect(entry.discovery?.categories == ["weddings"])
        #expect(SharedBlueprintURLProtocol.lastPath == "/api/blueprints/shared/\(token)")
        #expect(SharedBlueprintURLProtocol.lastMethod == "GET")
        #expect(SharedBlueprintURLProtocol.lastAuthorization == nil)
        #expect(SharedBlueprintURLProtocol.lastCookie == nil)
    }

    @Test("A revoked shared link's 404 is surfaced as resolution failure")
    func revokedLinkReturnsFailure() async throws {
        SharedBlueprintURLProtocol.configure(status: 404, body: Data(#"{"error":"NOT_FOUND"}"#.utf8))
        let session = makeSession()
        defer { session.invalidateAndCancel() }
        let transport = PostgresSyncTransport(
            baseURL: URL(string: "https://dev.gatherory.com")!,
            urlSession: session,
            tokenStore: SharedBlueprintTokenStore()
        )

        await #expect {
            try await transport.sharedBlueprint(token: String(repeating: "e5", count: 32))
        } throws: { error in
            guard let failure = error as? CloudSyncFailure else { return false }
            if case .server = failure { return true }
            return false
        }
    }

    @Test("Preview carries the same shared token used to open the template")
    func previewCarriesShareToken() async throws {
        let token = String(repeating: "a9", count: 32)
        let fixtureURL = try #require(Bundle(for: SharedBlueprintFixtureBundle.self)
            .url(forResource: "wedding-preview.v1", withExtension: "json"))
        SharedBlueprintURLProtocol.configure(status: 200, body: try Data(contentsOf: fixtureURL))
        let session = makeSession()
        defer { session.invalidateAndCancel() }
        let transport = PostgresSyncTransport(
            baseURL: URL(string: "https://dev.gatherory.com")!,
            urlSession: session,
            tokenStore: SharedBlueprintTokenStore()
        )
        let input = BlueprintInstallInput(
            requestID: UUID(), catalogKey: "wedding", revision: 1,
            contentHash: "24518a2d4795d62a7d0ed5d349cd0bb7ed7a2883a7dec7bf9c522a8e5119878a",
            mainEvent: .init(name: "Shared plan", startsAt: Date(timeIntervalSince1970: 1_811_923_200), timeZone: "America/Detroit"),
            selectedChildren: [], selectedIdeaKeys: [], capabilities: [], shareToken: token
        )

        let preview = try await transport.previewBlueprint(input)

        #expect(preview.plan.main.name == "Riley and Jordan")
        #expect(SharedBlueprintURLProtocol.lastPath == "/api/blueprints/preview")
        #expect(SharedBlueprintURLProtocol.lastMethod == "POST")
        #expect(SharedBlueprintURLProtocol.lastAuthorization == "Bearer must-not-be-sent")
        let sentObject = try #require(JSONSerialization.jsonObject(with: SharedBlueprintURLProtocol.lastBody) as? [String: Any])
        #expect(sentObject["shareToken"] as? String == token)
    }

    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SharedBlueprintURLProtocol.self]
        configuration.httpShouldSetCookies = false
        return URLSession(configuration: configuration)
    }
}

private struct SharedBlueprintTokenStore: SessionTokenStore {
    func read() throws -> String? { "must-not-be-sent" }
    func save(_ token: String) throws {}
    func delete() {}
}

private final class SharedBlueprintURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    private static var responseStatus = 200
    private static var responseBody = Data()
    private static var pathValue: String?
    private static var methodValue: String?
    private static var authorizationValue: String?
    private static var cookieValue: String?
    private static var bodyValue = Data()

    static var lastPath: String? { read { pathValue } }
    static var lastMethod: String? { read { methodValue } }
    static var lastAuthorization: String? { read { authorizationValue } }
    static var lastCookie: String? { read { cookieValue } }
    static var lastBody: Data { read { bodyValue } }

    static func configure(status: Int, body: Data) {
        lock.lock()
        responseStatus = status
        responseBody = body
        pathValue = nil
        methodValue = nil
        authorizationValue = nil
        cookieValue = nil
        bodyValue = Data()
        lock.unlock()
    }

    private static func read<Value>(_ value: () -> Value) -> Value {
        lock.lock()
        defer { lock.unlock() }
        return value()
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        let requestBody: Data
        do { requestBody = try bodyData() }
        catch {
            client?.urlProtocol(self, didFailWithError: error)
            return
        }
        Self.lock.lock()
        Self.pathValue = request.url?.path
        Self.methodValue = request.httpMethod
        Self.authorizationValue = request.value(forHTTPHeaderField: "Authorization")
        Self.cookieValue = request.value(forHTTPHeaderField: "Cookie")
        Self.bodyValue = requestBody
        let status = Self.responseStatus
        let body = Self.responseBody
        Self.lock.unlock()

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

    private func bodyData() throws -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count < 0 { throw stream.streamError ?? URLError(.cannotDecodeRawData) }
            if count == 0 { break }
            data.append(contentsOf: buffer.prefix(count))
        }
        return data
    }
}

private final class SharedBlueprintFixtureBundle: NSObject {}
