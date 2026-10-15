import Foundation
import Testing
@testable import Gatherory

@Suite(.serialized) @MainActor
struct BlueprintCreateShareTransportTests {
    @Test("Native capture sends strict authenticated actions and canonical UUIDs")
    func serializedActions() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [NativeCaptureHTTPProtocol.self]
        config.httpShouldSetCookies = false
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let transport = PostgresSyncTransport(baseURL: URL(string: "https://example.test")!,
            urlSession: session, tokenStore: NativeCaptureTokenStore())
        let event = UUID()
        let idea = UUID()
        let requestID = UUID()
        let sourceHash = String(repeating: "a", count: 64)
        let reviewHash = String(repeating: "b", count: 64)
        NativeCaptureHTTPProtocol.configure(["source": [
            "event": ["id": event.uuidString.lowercased(), "title": "Party", "startsAt": NSNull(),
                      "timeZone": "America/Detroit", "experienceType": "birthday"],
            "children": [], "ideas": [], "instructions": []
        ], "sourceHash": sourceHash, "workspaces": [["id": "owned", "name": "Personal", "personal": true]]])
        let source = try await transport.captureSource(eventID: event)
        #expect(source.source.event.id == event)
        var body = try NativeCaptureHTTPProtocol.lastBody()
        #expect(Set(body.keys) == ["action", "eventId"])
        #expect(body["action"] as? String == "source")
        #expect(body["eventId"] as? String == event.uuidString.lowercased())

        let input = BlueprintNativeReviewInput(eventId: event,
            selection: .init(childIds: [], ideaIds: [idea], instructionIds: [], includeIdeaNotes: false),
            expectedSourceHash: sourceHash, name: "Reusable Party")
        NativeCaptureHTTPProtocol.configure(["content": [
            "name": input.name, "description": "", "experienceType": "birthday",
            "children": [], "ideas": [["key": "idea_example", "title": "Cake", "category": "food",
                "target": ["kind": "main"], "configuration": ["version": 1]]], "instructions": []
        ], "sourceHash": sourceHash, "reviewHash": reviewHash, "discoverable": true])
        let review = try await transport.reviewCapture(input)
        #expect(review.content.ideas[0].notes == nil && review.content.ideas[0].target.kind == "main")
        body = try NativeCaptureHTTPProtocol.lastBody()
        #expect(Set(body.keys) == ["action", "eventId", "selection", "expectedSourceHash", "name", "discoverable"])
        #expect(body["action"] as? String == "review")
        #expect(body["discoverable"] as? Bool == true)
        let selection = try #require(body["selection"] as? [String: Any])
        #expect(selection["ideaIds"] as? [String] == [idea.uuidString.lowercased()])
        #expect(selection["includeIdeaNotes"] as? Bool == false)

        let template = UUID()
        NativeCaptureHTTPProtocol.configure(["templateId": template.uuidString.lowercased(), "revision": 1])
        let creation = try await transport.createTemplate(.init(eventId: event, selection: input.selection,
            expectedSourceHash: sourceHash, name: input.name,
            requestId: requestID, expectedReviewHash: reviewHash))
        #expect(creation.templateId == template && creation.revision == 1)
        body = try NativeCaptureHTTPProtocol.lastBody()
        #expect(Set(body.keys) == ["action", "eventId", "selection", "expectedSourceHash", "name", "requestId", "expectedReviewHash", "discoverable"])
        #expect(body["requestId"] as? String == requestID.uuidString.lowercased())
        #expect(body["expectedReviewHash"] as? String == reviewHash)
        #expect(body["discoverable"] as? Bool == true)
        #expect(body["organizationId"] == nil)
    }

    @Test("No native capture request is sent without a bearer session")
    func missingSession() async {
        NativeCaptureHTTPProtocol.configure([:])
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [NativeCaptureHTTPProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let transport = PostgresSyncTransport(baseURL: URL(string: "https://example.test")!,
            urlSession: session, tokenStore: NativeCaptureTokenStore(token: nil))
        do {
            _ = try await transport.captureSource(eventID: UUID())
            Issue.record("Expected authentication to fail")
        } catch CloudSyncFailure.invalidSession {} catch { Issue.record("Unexpected error: \(error)") }
        #expect(NativeCaptureHTTPProtocol.requestCount == 0)
    }
}

private struct NativeCaptureTokenStore: SessionTokenStore {
    var token: String? = "capture-test"
    func read() throws -> String? { token }
    func save(_ token: String) throws {}
    func delete() {}
}

private final class NativeCaptureHTTPProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    private static var body = Data()
    private static var capturedBody = Data()
    private static var count = 0
    static var requestCount: Int { lock.withLock { count } }
    static func configure(_ response: [String: Any]) {
        lock.withLock {
            body = try! JSONSerialization.data(withJSONObject: response)
            capturedBody = Data()
            count = 0
        }
    }
    static func lastBody() throws -> [String: Any] {
        let data = lock.withLock { capturedBody }
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}
    override func startLoading() {
        guard request.url?.path == "/api/blueprints/create-template",
              request.httpMethod == "POST", request.value(forHTTPHeaderField: "Authorization") == "Bearer capture-test",
              request.value(forHTTPHeaderField: "Content-Type") == "application/json" else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        var data = request.httpBody ?? Data()
        if data.isEmpty, let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var bytes = [UInt8](repeating: 0, count: 1024)
            while true {
                let length = stream.read(&bytes, maxLength: bytes.count)
                if length <= 0 { break }
                data.append(contentsOf: bytes.prefix(length))
            }
        }
        let responseData = Self.lock.withLock {
            Self.capturedBody = data
            Self.count += 1
            return Self.body
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil,
            headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: responseData)
        client?.urlProtocolDidFinishLoading(self)
    }
}
