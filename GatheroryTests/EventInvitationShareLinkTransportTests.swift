import Foundation
import Testing
@testable import Gatherory

@Suite(.serialized) @MainActor
struct EventInvitationShareLinkTransportTests {
    private let eventID = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
    private let token = UUID(uuidString: "22222222-2222-4222-8222-222222222222")!
    private let baseURL = URL(string: "https://app.gatherory.com")!

    private func client(baseURL: URL? = nil) -> EventInvitationClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ShareLinkProtocol.self]
        return EventInvitationClient(baseURL: baseURL ?? self.baseURL, session: URLSession(configuration: configuration),
            tokenStore: ShareLinkTokens())
    }

    @Test("Share-link creation omits email and name and accepts an indefinite role link")
    func creationContract() async throws {
        let generated = try await client().createShareLink(eventID: eventID, role: .guest, permission: .viewOnly)
        let request = try #require(ShareLinkProtocol.lastRequest)
        let body = try #require(request.httpBody)
        let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: String])
        #expect(request.httpMethod == "POST")
        #expect(Set(json.keys) == ["eventId", "role", "planningPermission"])
        #expect(json["eventId"] == eventID.uuidString)
        #expect(json["role"] == "guest")
        #expect(json["planningPermission"] == "viewOnly")
        #expect(generated.role == "guest")
        #expect(generated.expiresAt == nil)
        #expect(generated.isValid(for: eventID, baseURL: baseURL))
    }

    @Test("Share-link lookup uses the explicit discriminator and role revocation names its target")
    func lookupAndRevokeContract() async throws {
        let links = try await client().shareLinks(eventID: eventID)
        let lookup = try #require(ShareLinkProtocol.lastRequest)
        let query = URLComponents(url: try #require(lookup.url), resolvingAgainstBaseURL: false)?.queryItems
        #expect(lookup.httpMethod == "GET")
        #expect(query?.first(where: { $0.name == "kind" })?.value == "share-links")
        #expect(query?.first(where: { $0.name == "eventId" })?.value == eventID.uuidString.lowercased())
        #expect(links.map(\.role) == ["guest", "collaborator"])

        try await client().revoke(eventID: eventID, role: .guest)
        let revoke = try #require(ShareLinkProtocol.lastRequest)
        let body = try #require(revoke.httpBody)
        let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: String])
        #expect(revoke.httpMethod == "DELETE")
        #expect(json == ["eventId": eventID.uuidString, "role": "guest"])
    }

    @Test("Share-link creation rejects private or role-mismatched server responses")
    func rejectsPrivateOrMismatchedResponse() async throws {
        for (host, expectedRole) in [("email-mismatch.invalid", "guest"), ("role-mismatch.invalid", "collaborator")] {
            let api = client(baseURL: URL(string: "https://\(host)")!)
            do {
                _ = try await api.createShareLink(eventID: eventID, role: .guest, permission: .viewOnly)
                Issue.record("A response for \(expectedRole) was accepted as a guest share link")
            } catch EventInvitationFailure.unavailable {
                #expect(true)
            }
        }
    }
}

private struct ShareLinkTokens: SessionTokenStore {
    func read() -> String? { "test-session" }
    func save(_ token: String) {}
    func delete() {}
}

private final class ShareLinkProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    private static var storedRequest: URLRequest?
    static var lastRequest: URLRequest? {
        lock.lock()
        defer { lock.unlock() }
        return storedRequest
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        var captured = request
        if captured.httpBody == nil, let stream = captured.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var bytes = [UInt8](repeating: 0, count: 4096)
            var data = Data()
            while stream.hasBytesAvailable {
                let count = stream.read(&bytes, maxLength: bytes.count)
                if count <= 0 { break }
                data.append(bytes, count: count)
            }
            captured.httpBodyStream = nil
            captured.httpBody = data
        }
        Self.lock.lock()
        Self.storedRequest = captured
        Self.lock.unlock()

        let host = captured.url?.host ?? "app.gatherory.com"
        let joinURL = "https://\(host)/join/22222222-2222-4222-8222-222222222222"
        let body: Data
        switch captured.httpMethod {
        case "GET":
            body = try! JSONSerialization.data(withJSONObject: ["ok": true, "data": ["links": [
                ["eventId": "11111111-1111-4111-8111-111111111111", "email": NSNull(), "role": "guest", "expiresAt": NSNull(), "url": joinURL],
                ["eventId": "11111111-1111-4111-8111-111111111111", "email": NSNull(), "role": "collaborator", "expiresAt": NSNull(), "url": "https://\(host)/join/33333333-3333-4333-8333-333333333333"],
                ["eventId": "11111111-1111-4111-8111-111111111111", "email": NSNull(), "role": "host", "expiresAt": NSNull(), "url": "https://\(host)/join/44444444-4444-4444-8444-444444444444"],
                ["eventId": "11111111-1111-4111-8111-111111111111", "email": "person@example.com", "role": "guest", "expiresAt": NSNull(), "url": "https://\(host)/join/55555555-5555-4555-8555-555555555555"],
                ["eventId": "99999999-9999-4999-8999-999999999999", "email": NSNull(), "role": "guest", "expiresAt": NSNull(), "url": "https://\(host)/join/66666666-6666-4666-8666-666666666666"]
            ]]])
        case "POST":
            let email: Any = host == "email-mismatch.invalid" ? "person@example.com" : NSNull()
            let role = host == "role-mismatch.invalid" ? "collaborator" : "guest"
            body = try! JSONSerialization.data(withJSONObject: ["ok": true, "data": [
                "eventId": "11111111-1111-4111-8111-111111111111", "email": email,
                "role": role, "expiresAt": NSNull(), "url": joinURL
            ]])
        default:
            body = Data(#"{"ok":true}"#.utf8)
        }
        let response = HTTPURLResponse(url: captured.url!, statusCode: 200, httpVersion: nil,
            headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
