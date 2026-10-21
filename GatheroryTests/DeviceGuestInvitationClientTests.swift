import Foundation
import Testing
@testable import Gatherory

@Suite(.serialized)
@MainActor
struct DeviceGuestInvitationClientTests {
    @Test("Device guest requests register once and never use an account bearer or cookies")
    func guestProofAndEventLifecycle() async throws {
        let profile = LocalGuestProfile(id: UUID(), displayName: "  Morgan  ")
        let credentialStore = MemoryLocalGuestCredentialStore()
        let accountTokens = GuestAccountTokenStore(token: "signed-in-token")
        let eventID = UUID()
        GuestInvitationHTTPProtocol.configure { request in
            switch (request.httpMethod, request.url?.path) {
            case ("POST", "/api/guest/session"):
                let body = try Self.body(request)
                let id = try #require(body["id"])
                let name = try #require(body["name"])
                return (200, ["ok": true, "data": ["id": id, "name": name]])
            case ("GET", "/api/guest/events"):
                return (200, ["ok": true, "data": ["events": []]])
            case ("POST", "/api/guest/events"):
                return (200, ["ok": true, "data": ["eventId": eventID.uuidString, "role": "guest", "status": "accepted"]])
            case ("PATCH", "/api/guest/events"):
                let body = try Self.body(request)
                let eventId = try #require(body["eventId"])
                let attendance = try #require(body["attendance"])
                return (200, ["ok": true, "data": ["eventId": eventId, "attendance": attendance]])
            case ("DELETE", "/api/guest/events"):
                let body = try Self.body(request)
                let eventId = try #require(body["eventId"])
                return (200, ["ok": true, "data": ["eventId": eventId]])
            case ("POST", "/api/guest/claim"):
                return (200, ["ok": true, "data": ["claimedEventIds": [eventID.uuidString]]])
            default:
                return (404, ["ok": false, "error": ["userMessage": "Unavailable"]])
            }
        }
        let configuration = Self.makeSessionConfiguration()
        let client = DeviceGuestInvitationClient(
            baseURL: URL(string: "https://guest-client.test")!,
            profile: profile,
            credentialStore: credentialStore,
            accountTokenStore: accountTokens,
            sessionConfiguration: configuration
        )
        defer { client.invalidate() }

        #expect(try await client.invitations().events.isEmpty)
        let joined = try await client.join(token: UUID())
        #expect(joined.eventId == eventID)
        #expect(joined.destination == .guest(eventID))
        let attendance = try await client.respond(eventID: eventID, response: .notSure)
        #expect(attendance.attendance == "not_sure")
        #expect(try await client.leaveInvitation(eventID: eventID) == eventID)
        #expect(try await client.claim().claimedEventIds == [eventID])

        let requests = GuestInvitationHTTPProtocol.requests
        #expect(requests.filter { $0.path == "/api/guest/session" }.count == 1)
        #expect(requests.map(\.path) == [
            "/api/guest/session", "/api/guest/events", "/api/guest/events",
            "/api/guest/events", "/api/guest/events", "/api/guest/claim"
        ])
        let expectedCredential = try #require(credentialStore.tokens[profile.id])
        #expect(expectedCredential.count == 43)
        for request in requests {
            #expect(request.headers["X-Gatherory-Guest-Id"] == profile.id.uuidString.lowercased())
            #expect(request.headers["X-Gatherory-Guest-Token"] == expectedCredential)
            #expect(request.headers["Cookie"] == nil)
            #expect(request.headers["Authorization"] == (request.path == "/api/guest/claim" ? "Bearer signed-in-token" : nil))
        }
        let registrationBody = try Self.body(requests[0].body)
        #expect(registrationBody["name"] as? String == "Morgan")
        #expect(registrationBody["credential"] as? String == expectedCredential)
        let joinBody = try Self.body(requests[2].body)
        #expect(Set(joinBody.keys) == ["token"])
        let responseBody = try Self.body(requests[3].body)
        #expect(responseBody["attendance"] as? String == "not_sure")
        #expect(requests[5].body.isEmpty)
    }

    @Test("A failed guest registration retries with the same device identity and secret")
    func registrationRetryUsesStableProof() async throws {
        let profile = LocalGuestProfile(id: UUID(), displayName: "Morgan")
        let credentials = MemoryLocalGuestCredentialStore()
        GuestInvitationHTTPProtocol.configure { request in
            if request.url?.path == "/api/guest/session" {
                if GuestInvitationHTTPProtocol.registrationAttempts == 1 {
                    return (503, ["ok": false, "error": ["userMessage": "Try again"]])
                }
                let body = try Self.body(request)
                let id = try #require(body["id"])
                let name = try #require(body["name"])
                return (200, ["ok": true, "data": ["id": id, "name": name]])
            }
            return (200, ["ok": true, "data": ["events": []]])
        }
        let configuration = Self.makeSessionConfiguration()
        let client = DeviceGuestInvitationClient(
            baseURL: URL(string: "https://guest-client.test")!, profile: profile,
            credentialStore: credentials, accountTokenStore: GuestAccountTokenStore(token: nil), sessionConfiguration: configuration
        )
        defer { client.invalidate() }

        await #expect(throws: EventInvitationFailure.self) { try await client.invitations() }
        #expect(try await client.invitations().events.isEmpty)
        let registrations = GuestInvitationHTTPProtocol.requests.filter { $0.path == "/api/guest/session" }
        #expect(registrations.count == 2)
        let firstRegistration = try Self.body(registrations[0].body)
        let secondRegistration = try Self.body(registrations[1].body)
        let firstID = try #require(firstRegistration["id"] as? String)
        let secondID = try #require(secondRegistration["id"] as? String)
        let firstName = try #require(firstRegistration["name"] as? String)
        let secondName = try #require(secondRegistration["name"] as? String)
        let firstCredential = try #require(firstRegistration["credential"] as? String)
        let secondCredential = try #require(secondRegistration["credential"] as? String)
        #expect(firstID == secondID)
        #expect(firstName == secondName)
        #expect(firstCredential == secondCredential)
        #expect(registrations[0].headers["X-Gatherory-Guest-Token"] == registrations[1].headers["X-Gatherory-Guest-Token"])
    }

    @Test("Claim requires a signed-in account and does not send a guest token as bearer")
    func claimRequiresAccountSession() async throws {
        let profile = LocalGuestProfile(displayName: "Morgan")
        let credentials = MemoryLocalGuestCredentialStore()
        GuestInvitationHTTPProtocol.configure { request in
            let body = try Self.body(request)
            let id = try #require(body["id"])
            let name = try #require(body["name"])
            return (200, ["ok": true, "data": ["id": id, "name": name]])
        }
        let configuration = Self.makeSessionConfiguration()
        let client = DeviceGuestInvitationClient(
            baseURL: URL(string: "https://guest-client.test")!, profile: profile,
            credentialStore: credentials, accountTokenStore: GuestAccountTokenStore(token: nil), sessionConfiguration: configuration
        )
        defer { client.invalidate() }
        do {
            _ = try await client.claim()
            Issue.record("Claim without a signed-in session unexpectedly succeeded")
        } catch CloudSyncFailure.invalidSession {
            // The guest proof is not an account credential.
        }
        #expect(GuestInvitationHTTPProtocol.requests.map(\.path) == ["/api/guest/session"])
    }

    @Test("Guest credentials reject Unicode lookalikes and cleartext non-loopback origins")
    func rejectsUnsafeCredentialsAndOrigins() async throws {
        GuestInvitationHTTPProtocol.configure { _ in (200, ["ok": true, "data": ["events": []]]) }
        let configuration = Self.makeSessionConfiguration()
        let invalidCredential = DeviceGuestInvitationClient(
            baseURL: URL(string: "https://guest-client.test")!,
            profile: LocalGuestProfile(displayName: "Morgan"),
            credentialStore: FixedGuestCredentialStore(token: String(repeating: "A", count: 42) + "é"),
            accountTokenStore: GuestAccountTokenStore(token: nil),
            sessionConfiguration: configuration
        )
        defer { invalidCredential.invalidate() }
        await #expect(throws: EventInvitationFailure.self) { try await invalidCredential.invitations() }
        #expect(GuestInvitationHTTPProtocol.requests.isEmpty)

        let unsafeOrigin = DeviceGuestInvitationClient(
            baseURL: URL(string: "http://guest-client.test")!,
            profile: LocalGuestProfile(displayName: "Morgan"),
            credentialStore: MemoryLocalGuestCredentialStore(),
            accountTokenStore: GuestAccountTokenStore(token: nil),
            sessionConfiguration: Self.makeSessionConfiguration()
        )
        defer { unsafeOrigin.invalidate() }
        await #expect(throws: EventInvitationFailure.self) { try await unsafeOrigin.invitations() }
        #expect(GuestInvitationHTTPProtocol.requests.isEmpty)
    }

    @Test("Guest redirect delegate accepts exact origin only and rejects URL credentials")
    func redirectDelegateEnforcesOriginDirectly() throws {
        let origin = try #require(URL(string: "https://guest-client.test"))
        let delegate = GuestSameOriginRedirectDelegate(origin: origin)
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let originalRequest = URLRequest(url: origin.appending(path: "api/guest/events"))
        let task = session.dataTask(with: originalRequest)
        let response = try #require(
            HTTPURLResponse(url: originalRequest.url!, statusCode: 302, httpVersion: nil, headerFields: nil)
        )

        func redirectedRequest(_ value: String) throws -> URLRequest? {
            let target = URLRequest(url: try #require(URL(string: value)))
            var result: URLRequest?
            delegate.urlSession(
                session,
                task: task,
                willPerformHTTPRedirection: response,
                newRequest: target,
                completionHandler: { result = $0 }
            )
            return result
        }

        #expect(try redirectedRequest("https://guest-client.test/api/guest/events")?.url?.host == "guest-client.test")
        #expect(try redirectedRequest("https://other.test/api/guest/events") == nil)
        #expect(try redirectedRequest("http://guest-client.test/api/guest/events") == nil)
        #expect(try redirectedRequest("https://guest-client.test:444/api/guest/events") == nil)
        #expect(try redirectedRequest("https://user:secret@guest-client.test/api/guest/events") == nil)
    }

    private static func makeSessionConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [GuestInvitationHTTPProtocol.self]
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        return configuration
    }

    nonisolated private static func body(_ request: URLRequest) throws -> [String: Any] {
        try body(request.httpBody ?? readBodyStream(request.httpBodyStream) ?? Data())
    }

    nonisolated fileprivate static func readBodyStream(_ stream: InputStream?) -> Data? {
        guard let stream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count < 0 { return nil }
            if count == 0 { break }
            data.append(buffer, count: count)
        }
        return data
    }

    nonisolated private static func body(_ data: Data) throws -> [String: Any] {
        guard !data.isEmpty else { return [:] }
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}

private struct GuestCapturedRequest: Sendable {
    let method: String?
    let path: String
    let host: String
    let headers: [String: String]
    let body: Data
}

private final class GuestInvitationHTTPProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var handler: ((URLRequest) throws -> (Int, [String: Any]))?
    nonisolated(unsafe) private static var captured: [GuestCapturedRequest] = []
    nonisolated(unsafe) private static var registrationCount = 0

    static var requests: [GuestCapturedRequest] {
        lock.lock(); defer { lock.unlock() }
        return captured
    }

    static var registrationAttempts: Int {
        lock.lock(); defer { lock.unlock() }
        return registrationCount
    }

    static func configure(handler: @escaping (URLRequest) throws -> (Int, [String: Any])) {
        lock.lock()
        self.handler = handler
        captured = []
        registrationCount = 0
        lock.unlock()
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        let handler: ((URLRequest) throws -> (Int, [String: Any]))?
        var normalizedRequest = request
        let body = request.httpBody ?? DeviceGuestInvitationClientTests.readBodyStream(request.httpBodyStream)
        normalizedRequest.httpBodyStream = nil
        normalizedRequest.httpBody = body
        Self.lock.lock()
        handler = Self.handler
        if normalizedRequest.url?.path == "/api/guest/session" { Self.registrationCount += 1 }
        Self.captured.append(GuestCapturedRequest(
            method: normalizedRequest.httpMethod,
            path: normalizedRequest.url?.path ?? "",
            host: normalizedRequest.url?.host ?? "",
            headers: normalizedRequest.allHTTPHeaderFields ?? [:],
            body: body ?? Data()
        ))
        Self.lock.unlock()
        do {
            guard let handler else { throw EventInvitationFailure.unavailable }
            let (status, payload) = try handler(normalizedRequest)
            let data = try JSONSerialization.data(withJSONObject: payload)
            let headers = ["Content-Type": "application/json"]
            let response = HTTPURLResponse(url: normalizedRequest.url!, statusCode: status, httpVersion: nil,
                headerFields: headers )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }
}

private struct GuestAccountTokenStore: SessionTokenStore {
    let token: String?
    func read() throws -> String? { token }
    func save(_ token: String) throws {}
    func delete() {}
}

@MainActor private struct FixedGuestCredentialStore: LocalGuestCredentialStore {
    let token: String
    func loadOrCreateToken(profileID: UUID) throws -> String { token }
    func removeSecret(profileID: UUID) throws {}
}
