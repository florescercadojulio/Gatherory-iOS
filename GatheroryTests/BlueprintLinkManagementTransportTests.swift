import Foundation
import Testing
@testable import Gatherory

@Suite(.serialized)
@MainActor
struct BlueprintLinkManagementTransportTests {
    @Test("All management actions POST strict bodies with bearer authorization")
    func actionBodiesAndAuthorization() async throws {
        let eventID = UUID()
        let templateID = UUID()
        let linkID = UUID()
        let session = makeSession()
        defer { session.invalidateAndCancel() }
        let transport = makeTransport(session: session)

        BlueprintSharingHTTPProtocol.configure(body: try json(["templates": [[
            "id": templateID.uuidString, "title": "Wedding", "publishedRevision": 3, "retired": false, "listedRevision": 3
        ]]]))
        let templates = try await transport.templates(eventID: eventID)
        #expect(templates == [BlueprintManagedTemplate(id: templateID, title: "Wedding", publishedRevision: 3, retired: false, listedRevision: 3)])
        #expect(lastRequest(action: "templates", expected: ["action", "eventId"], eventID: eventID))

        BlueprintSharingHTTPProtocol.configure(body: try json(["templates": [[
            "id": templateID.uuidString, "title": "Wedding", "publishedRevision": 3,
            "retired": false, "listedRevision": 3, "creatorName": "Garden Hosts",
            "activeShareLinkCount": 2
        ]]]))
        let attributedTemplates = try await transport.templates(eventID: eventID)
        #expect(attributedTemplates.first?.creatorName == "Garden Hosts")
        #expect(attributedTemplates.first?.activeShareLinkCount == 2)

        BlueprintSharingHTTPProtocol.configure(body: try json(["links": [[
            "id": linkID.uuidString, "revision": 3,
            "createdAt": "2026-10-15T18:30:12.125Z", "revokedAt": NSNull()
        ]]]))
        let links = try await transport.links(eventID: eventID, templateID: templateID)
        #expect(links.count == 1)
        #expect(abs(links[0].createdAt.timeIntervalSince1970 - 1_792_089_012.125) < 0.001)
        #expect(links[0].revokedAt == nil)
        #expect(lastRequest(action: "list", expected: ["action", "eventId", "templateId"], eventID: eventID, templateID: templateID))

        let token = String(repeating: "ab", count: 32)
        BlueprintSharingHTTPProtocol.configure(body: try json(["link": [
            "id": linkID.uuidString, "revision": 3,
            "createdAt": "2026-10-15T18:30:12Z", "revokedAt": NSNull()
        ], "token": token]))
        let created = try await transport.createLink(eventID: eventID, templateID: templateID, revision: 3)
        #expect(created.token == token)
        #expect(lastRequest(action: "create", expected: ["action", "eventId", "templateId", "revision"], eventID: eventID, templateID: templateID, revision: 3))

        BlueprintSharingHTTPProtocol.configure(body: try json(["revoked": true]))
        try await transport.revokeLink(eventID: eventID, templateID: templateID, linkID: linkID)
        #expect(lastRequest(action: "revoke", expected: ["action", "eventId", "templateId", "linkId"], eventID: eventID, templateID: templateID, linkID: linkID))

        BlueprintSharingHTTPProtocol.configure(body: try json(["listedRevision": 4]))
        let listedRevision = try await transport.setTemplateListing(eventID: eventID, templateID: templateID, revision: 4)
        #expect(listedRevision == 4)
        #expect(lastRequest(action: "listing", expected: ["action", "eventId", "templateId", "revision"], eventID: eventID, templateID: templateID, revision: 4))
        var listingBody = try JSONSerialization.jsonObject(with: BlueprintSharingHTTPProtocol.lastBody) as? [String: Any]
        #expect(Set(listingBody?.keys.map { $0 } ?? []) == ["action", "eventId", "templateId", "revision"])
        #expect(listingBody?["action"] as? String == "listing")
        #expect(listingBody?["revision"] as? Int == 4)

        BlueprintSharingHTTPProtocol.configure(body: try json(["listedRevision": 5, "creatorName": "Garden Hosts"]))
        let attributedListing = try await transport.setTemplateListing(
            eventID: eventID,
            templateID: templateID,
            revision: 5,
            creatorName: "Garden Hosts"
        )
        #expect(attributedListing == BlueprintTemplateListingResult(listedRevision: 5, creatorName: "Garden Hosts"))
        listingBody = try JSONSerialization.jsonObject(with: BlueprintSharingHTTPProtocol.lastBody) as? [String: Any]
        #expect(listingBody?["creatorName"] as? String == "Garden Hosts")

        BlueprintSharingHTTPProtocol.configure(body: try json(["listedRevision": NSNull()]))
        let withdrawnRevision = try await transport.setTemplateListing(eventID: eventID, templateID: templateID, revision: nil)
        #expect(withdrawnRevision == nil)
        listingBody = try JSONSerialization.jsonObject(with: BlueprintSharingHTTPProtocol.lastBody) as? [String: Any]
        #expect(listingBody?["revision"] is NSNull)
    }

    @Test("Withdrawing a listing requires an explicit server acknowledgement")
    func missingListingAcknowledgementFails() async throws {
        let session = makeSession()
        defer { session.invalidateAndCancel() }
        let transport = makeTransport(session: session)
        BlueprintSharingHTTPProtocol.configure(body: try json([:]))

        do {
            _ = try await transport.setTemplateListing(eventID: UUID(), templateID: UUID(), revision: nil)
            Issue.record("Expected an invalid-response failure")
        } catch CloudSyncFailure.invalidResponse {
            // Missing is not equivalent to an acknowledged null revision.
        } catch {
            Issue.record("Unexpected listing error: \(error)")
        }
    }

    @Test("Created tokens must be lowercase hex and share URLs require HTTPS outside local development")
    func tokenAndURLValidation() async throws {
        let session = makeSession()
        defer { session.invalidateAndCancel() }
        let transport = makeTransport(session: session)
        let token = String(repeating: "f0", count: 32)

        #expect(transport.shareURL(token: token)?.absoluteString == "https://links.example.test/templates/shared/\(token)")
        #expect(transport.shareURL(token: token)?.scheme == "https")
        #expect(transport.shareURL(token: String(repeating: "F0", count: 32)) == nil)

        let local = PostgresSyncTransport(baseURL: URL(string: "http://localhost:3000")!, urlSession: session, tokenStore: BlueprintSharingTokenStore())
        #expect(local.shareURL(token: token)?.absoluteString == "http://localhost:3000/templates/shared/\(token)")
        let insecure = PostgresSyncTransport(baseURL: URL(string: "http://public.example.test")!, urlSession: session, tokenStore: BlueprintSharingTokenStore())
        #expect(insecure.shareURL(token: token) == nil)
    }

    @Test("Management requests require a bearer session")
    func missingSessionFailsBeforeRequest() async {
        BlueprintSharingHTTPProtocol.configure(body: Data())
        let session = makeSession()
        defer { session.invalidateAndCancel() }
        let transport = PostgresSyncTransport(baseURL: URL(string: "https://links.example.test")!, urlSession: session, tokenStore: BlueprintSharingMissingTokenStore())

        do {
            _ = try await transport.templates(eventID: UUID())
            Issue.record("Expected a missing-session failure")
        } catch CloudSyncFailure.invalidSession {
            // Expected: no request is sent without the bearer session.
        } catch {
            Issue.record("Unexpected missing-session error: \(error)")
        }
        #expect(BlueprintSharingHTTPProtocol.lastPath == nil)
    }

    private func lastRequest(
        action: String,
        expected keys: Set<String>,
        eventID: UUID,
        templateID: UUID? = nil,
        revision: Int? = nil,
        linkID: UUID? = nil
    ) -> Bool {
        guard BlueprintSharingHTTPProtocol.lastPath == "/api/blueprints/sharing",
              BlueprintSharingHTTPProtocol.lastMethod == "POST",
              BlueprintSharingHTTPProtocol.lastAuthorization == "Bearer blueprint-management-test",
              BlueprintSharingHTTPProtocol.lastContentType == "application/json",
              let body = try? JSONSerialization.jsonObject(with: BlueprintSharingHTTPProtocol.lastBody) as? [String: Any],
              Set(body.keys) == keys,
              body["action"] as? String == action,
              body["eventId"] as? String == eventID.uuidString else { return false }
        if let templateID, body["templateId"] as? String != templateID.uuidString { return false }
        if let revision, body["revision"] as? Int != revision { return false }
        if let linkID, body["linkId"] as? String != linkID.uuidString { return false }
        return true
    }

    private func makeTransport(session: URLSession) -> PostgresSyncTransport {
        PostgresSyncTransport(
            baseURL: URL(string: "https://links.example.test")!,
            urlSession: session,
            tokenStore: BlueprintSharingTokenStore()
        )
    }

    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [BlueprintSharingHTTPProtocol.self]
        configuration.httpShouldSetCookies = false
        return URLSession(configuration: configuration)
    }

    private func json(_ value: Any) throws -> Data {
        try JSONSerialization.data(withJSONObject: value)
    }
}

private struct BlueprintSharingTokenStore: SessionTokenStore {
    func read() throws -> String? { "blueprint-management-test" }
    func save(_ token: String) throws {}
    func delete() {}
}

private struct BlueprintSharingMissingTokenStore: SessionTokenStore {
    func read() throws -> String? { nil }
    func save(_ token: String) throws {}
    func delete() {}
}

private final class BlueprintSharingHTTPProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    private static var responseBody = Data()
    private static var pathValue: String?
    private static var methodValue: String?
    private static var authorizationValue: String?
    private static var contentTypeValue: String?
    private static var bodyValue = Data()

    static var lastPath: String? { read { pathValue } }
    static var lastMethod: String? { read { methodValue } }
    static var lastAuthorization: String? { read { authorizationValue } }
    static var lastContentType: String? { read { contentTypeValue } }
    static var lastBody: Data { read { bodyValue } }

    static func configure(body: Data) {
        lock.lock()
        responseBody = body
        pathValue = nil
        methodValue = nil
        authorizationValue = nil
        contentTypeValue = nil
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
        Self.contentTypeValue = request.value(forHTTPHeaderField: "Content-Type")
        Self.bodyValue = requestBody
        let body = Self.responseBody
        Self.lock.unlock()
        guard let url = request.url,
              let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"]) else {
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
