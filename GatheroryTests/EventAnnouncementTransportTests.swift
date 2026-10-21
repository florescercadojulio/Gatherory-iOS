import Foundation
import Testing
@testable import Gatherory

@Suite(.serialized) @MainActor
struct EventAnnouncementTransportTests {
    @Test("Account requests use only bearer authorization and strict online send bodies")
    func accountTransport() async throws {
        let event = UUID()
        let requestID = UUID()
        AnnouncementHTTPProtocol.configure { request in
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer account-token")
            #expect(request.value(forHTTPHeaderField: "X-Gatherory-Guest-Id") == nil)
            #expect(request.value(forHTTPHeaderField: "X-Gatherory-Guest-Token") == nil)
            #expect(request.value(forHTTPHeaderField: "Cookie") == nil)
            #expect(request.url?.path == "/api/events/\(event.uuidString.lowercased())/announcements")
            if request.httpMethod == "POST" {
                let body = try #require(JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: String])
                #expect(Set(body.keys) == ["requestId", "message", "audience"])
                #expect(body["requestId"] == requestID.uuidString.lowercased())
                #expect(body["message"] == "Hello")
                #expect(body["audience"] == "all")
                return (200, ["announcement": Self.message(event: event, id: requestID)])
            }
            return (200, ["announcements": [Self.message(event: event)], "canSend": true, "allowedAudiences": ["all", "planning", "guests"]])
        }
        let transport = makeTransport { .account(bearer: "account-token") }
        let feed = try await transport.load(eventID: event)
        #expect(feed.canSend)
        #expect(feed.announcements.count == 1)
        #expect(feed.announcements[0].createdAt.timeIntervalSince1970 == 1_792_089_012.125)
        #expect(try await transport.send(eventID: event, requestID: requestID, message: "  Hello\n").id == requestID)
        #expect(AnnouncementHTTPProtocol.requests.count == 2)
    }

    @Test("Device guest requests use only exact guest proof, no cookies, and cannot send")
    func guestBoundary() async throws {
        let guest = UUID()
        let event = UUID()
        let proof = LocalGuestCredentialToken.make()
        AnnouncementHTTPProtocol.configure { request in
            #expect(request.url?.path == "/api/guest/events/\(event.uuidString.lowercased())/announcements")
            #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
            #expect(request.value(forHTTPHeaderField: "Cookie") == nil)
            #expect(request.value(forHTTPHeaderField: "X-Gatherory-Guest-Id") == guest.uuidString.lowercased())
            #expect(request.value(forHTTPHeaderField: "X-Gatherory-Guest-Token") == proof)
            return (200, ["announcements": [], "canSend": true, "allowedAudiences": ["all", "planning", "guests"]])
        }
        let transport = makeTransport { .guest(id: guest, proof: proof) }
        #expect(!(try await transport.load(eventID: event).canSend))
        await #expect(throws: EventAnnouncementFailure.accessDenied) {
            try await transport.send(eventID: event, requestID: UUID(), message: "No")
        }
        #expect(AnnouncementHTTPProtocol.requests.count == 1)
    }

    @Test("Current session check runs before every request, so stale sessions send nothing")
    func staleCredentialBoundary() async throws {
        AnnouncementHTTPProtocol.configure { _ in (200, ["announcements": [], "canSend": true, "allowedAudiences": ["all", "planning", "guests"]]) }
        var current = true
        let transport = makeTransport {
            guard current else { throw EventAnnouncementFailure.staleSession }
            return .account(bearer: "a")
        }
        _ = try await transport.load(eventID: UUID())
        current = false
        await #expect(throws: EventAnnouncementFailure.staleSession) { try await transport.load(eventID: UUID()) }
        await #expect(throws: EventAnnouncementFailure.staleSession) {
            try await transport.send(eventID: UUID(), requestID: UUID(), message: "Hello")
        }
        #expect(AnnouncementHTTPProtocol.requests.count == 1)
    }

    @Test("Unexpected event data, invalid guest proof, and access loss are rejected")
    func invalidResponsesAndProof() async throws {
        let event = UUID()
        AnnouncementHTTPProtocol.configure { _ in
            (200, ["announcements": [Self.message(event: UUID())], "canSend": true, "allowedAudiences": ["all", "planning", "guests"]])
        }
        let account = makeTransport { .account(bearer: "a") }
        await #expect(throws: EventAnnouncementFailure.invalidResponse) { try await account.load(eventID: event) }
        let guest = makeTransport { .guest(id: UUID(), proof: String(repeating: "x", count: 43)) }
        await #expect(throws: EventAnnouncementFailure.accessDenied) { try await guest.load(eventID: event) }
        #expect(AnnouncementHTTPProtocol.requests.count == 1)
        AnnouncementHTTPProtocol.configure { _ in (403, [:]) }
        await #expect(throws: EventAnnouncementFailure.accessDenied) { try await account.load(eventID: event) }
        AnnouncementHTTPProtocol.configure { _ in (409, [:]) }
        await #expect(throws: EventAnnouncementFailure.requestConflict) {
            try await account.send(eventID: event, requestID: UUID(), message: "Hello")
        }
    }

    @Test("Acknowledgements for another event and missing success envelopes are rejected")
    func invalidAcknowledgement() async {
        let account = makeTransport { .account(bearer: "a") }
        AnnouncementHTTPProtocol.configure { _ in
            (200, ["announcement": Self.message(event: UUID())])
        }
        await #expect(throws: EventAnnouncementFailure.invalidResponse) {
            try await account.send(eventID: UUID(), requestID: UUID(), message: "Hello")
        }
        AnnouncementHTTPProtocol.configure { _ in (200, [:]) }
        await #expect(throws: EventAnnouncementFailure.invalidResponse) { try await account.load(eventID: UUID()) }
        AnnouncementHTTPProtocol.configure { _ in (401, [:]) }
        await #expect(throws: EventAnnouncementFailure.accessDenied) { try await account.load(eventID: UUID()) }
    }

    @Test("Planning audience is explicit on the wire and missing audience capabilities cannot enable sending")
    func audienceWireContract() async throws {
        let event = UUID()
        AnnouncementHTTPProtocol.configure { request in
            if request.httpMethod == "POST" {
                let body = try #require(JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: String])
                #expect(body["audience"] == "planning")
                var message = Self.message(event: event)
                message["audience"] = "planning"
                return (200, ["announcement": message])
            }
            return (200, ["announcements": [Self.message(event: event)], "canSend": true])
        }
        let account = makeTransport { .account(bearer: "a") }
        let oldFeed = try await account.load(eventID: event)
        #expect(oldFeed.announcements.first?.audience == .all)
        #expect(!oldFeed.canSend)
        #expect(oldFeed.allowedAudiences.isEmpty)
        let sent = try await account.send(eventID: event, requestID: UUID(), message: "Hello", audience: .planning)
        #expect(sent.audience == .planning)
        AnnouncementHTTPProtocol.configure { _ in
            (200, ["announcement": Self.message(event: event)])
        }
        await #expect(throws: EventAnnouncementFailure.invalidResponse) {
            try await account.send(eventID: event, requestID: UUID(), message: "Hello", audience: .planning)
        }
    }

    @Test("Unsafe origins and invalid messages never issue a request")
    func unsafeRequests() async {
        AnnouncementHTTPProtocol.configure { _ in (200, [:]) }
        let transport = makeTransport(origin: "http://outside.test") { .account(bearer: "a") }
        await #expect(throws: EventAnnouncementFailure.unavailable) { try await transport.load(eventID: UUID()) }
        await #expect(throws: EventAnnouncementFailure.invalidMessage) {
            try await transport.send(eventID: UUID(), requestID: UUID(), message: "\n ")
        }
        #expect(AnnouncementHTTPProtocol.requests.isEmpty)
    }

    private func makeTransport(origin: String = "https://announcements.test",
                               credential: @escaping () throws -> HTTPEventAnnouncementTransport.Credential) -> HTTPEventAnnouncementTransport {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [AnnouncementHTTPProtocol.self]
        config.httpAdditionalHeaders = ["Cookie": "bad-cookie", "Authorization": "bad-bearer", "X-Gatherory-Guest-Token": "bad-proof"]
        return HTTPEventAnnouncementTransport(baseURL: URL(string: origin)!, configuration: config, credential: credential)
    }
    nonisolated private static func message(event: UUID, id: UUID = UUID()) -> [String: Any] {
        ["id": id.uuidString, "eventId": event.uuidString, "message": "Hello", "authorName": "Host", "createdAt": "2026-10-15T18:30:12.125Z"]
    }
}

private final class AnnouncementHTTPProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var handler: ((URLRequest) throws -> (Int, [String: Any]))?
    nonisolated(unsafe) private static var captured: [URLRequest] = []
    static var requests: [URLRequest] { lock.lock(); defer { lock.unlock() }; return captured }
    static func configure(_ handler: @escaping (URLRequest) throws -> (Int, [String: Any])) {
        lock.lock(); defer { lock.unlock() }
        self.handler = handler
        captured = []
    }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}
    override func startLoading() {
        var normalized = request
        if normalized.httpBody == nil, let stream = normalized.httpBodyStream {
            stream.open(); defer { stream.close() }
            var body = Data()
            var bytes = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&bytes, maxLength: bytes.count)
                if count <= 0 { break }
                body.append(bytes, count: count)
            }
            normalized.httpBodyStream = nil
            normalized.httpBody = body
        }
        Self.lock.lock()
        let handler = Self.handler
        Self.captured.append(normalized)
        Self.lock.unlock()
        do {
            guard let handler else { throw EventAnnouncementFailure.unavailable }
            let (status, payload) = try handler(normalized)
            let data = try JSONSerialization.data(withJSONObject: ["ok": status == 200, "data": payload])
            let response = HTTPURLResponse(url: normalized.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
}
