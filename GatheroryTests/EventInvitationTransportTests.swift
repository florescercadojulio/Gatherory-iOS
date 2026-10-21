import Foundation
import Testing
import UIKit
@testable import Gatherory

@MainActor
struct EventInvitationTransportTests {
    @Test("Existing hosts, collaborators, and guests open directly after an authenticated preview",
          arguments: ["host", "collaborator", "guest"])
    func existingMemberRouting(role: String) throws {
        let data = Data("{\"requiresSignIn\":false,\"role\":\"\(role)\",\"status\":\"accepted\"}".utf8)
        let preview = try JSONDecoder().decode(InvitationPreview.self, from: data)
        #expect(preview.shouldOpenExistingEvent(isAuthenticated: true))
        #expect(!preview.shouldOpenExistingEvent(isAuthenticated: false))
    }

    @Test("Unaccepted invitations never automatically join or bypass approval",
          arguments: ["pending", "awaiting_approval", "declined", "unknown"])
    func newInviteeStillChoosesToJoin(status: String) throws {
        let data = Data("{\"requiresSignIn\":false,\"role\":\"host\",\"status\":\"\(status)\"}".utf8)
        let preview = try JSONDecoder().decode(InvitationPreview.self, from: data)
        #expect(!preview.shouldOpenExistingEvent(isAuthenticated: true))
    }

    @Test("A sign-in-required or incomplete preview cannot open an event")
    func incompletePreviewDoesNotRoute() throws {
        for json in ["{\"requiresSignIn\":true,\"status\":\"accepted\"}", "{\"requiresSignIn\":false}"] {
            let preview = try JSONDecoder().decode(InvitationPreview.self, from: Data(json.utf8))
            #expect(!preview.shouldOpenExistingEvent(isAuthenticated: true))
        }
    }

    @Test("Guest invitation guides decode from newer feeds and remain optional for older caches")
    func guestGuidesAreBackwardCompatible() throws {
        let eventID = "10000000-0000-4000-8000-000000000001"
        let required = #""id":"\#(eventID)","title":"Wedding","isAllDay":false,"timeZone":"America/Detroit","complete":"incomplete","viewerPersonId":"70000000-0000-4000-8000-000000000001","role":"guest","attendance":"invited","people":[],"ideas":[],"moments":[]"#
        let legacy = Data("{\"events\":[{\(required)}]}".utf8)
        let oldFeed = try JSONDecoder().decode(GuestInvitationFeed.self, from: legacy)
        #expect(oldFeed.events.first?.guides == nil)
        let reloadedOldCache = try JSONDecoder().decode(
            GuestInvitationFeed.self,
            from: JSONEncoder().encode(oldFeed)
        )
        #expect(reloadedOldCache.events.first?.guides == nil)

        let guide = #"{"id":"30000000-0000-4000-8000-000000000001","eventID":"\#(eventID)","key":"ceremony_guidance","title":"Ceremony guidance","body":"Share arrival details with participants.","sortOrder":1,"visibility":"event_participants"}"#
        let current = Data("{\"events\":[{\(required),\"guides\":[\(guide)]}]}".utf8)
        let newFeed = try JSONDecoder().decode(GuestInvitationFeed.self, from: current)
        #expect(newFeed.events.first?.guides?.first?.key == "ceremony_guidance")
        #expect(newFeed.events.first?.guides?.first?.visibility == .eventParticipants)
        let reloadedNewCache = try JSONDecoder().decode(
            GuestInvitationFeed.self,
            from: JSONEncoder().encode(newFeed)
        )
        #expect(reloadedNewCache.events.first?.guides == newFeed.events.first?.guides)
    }

    @Test("Approval responses never become completed joins, even with a scope ID")
    func approvalDoesNotOpenEvent() throws {
        let id = UUID()
        let response = InvitationAcceptance(eventId: id, role: "collaborator", planningScopeId: id, status: "awaiting_approval")
        #expect(response.destination == .awaitingApproval)
        var progress = InvitationJoinProgress()
        progress.record(response, accountID: "invitee", principalGeneration: 4)
        #expect(progress.acceptedResponse(for: "invitee", principalGeneration: 4) == nil)
    }

    @Test("A failed destination load retries the accepted join only for its account")
    func acceptedJoinSurvivesLoadFailure() {
        let id = UUID()
        let response = InvitationAcceptance(eventId: id, role: "collaborator", planningScopeId: id, status: "accepted")
        var progress = InvitationJoinProgress()
        progress.record(response, accountID: "invitee", principalGeneration: 4)
        #expect(progress.acceptedResponse(for: "invitee", principalGeneration: 4)?.destination == .planning(id))
        #expect(progress.acceptedResponse(for: "host", principalGeneration: 4) == nil)
        #expect(progress.acceptedResponse(for: nil, principalGeneration: 4) == nil)
        #expect(progress.acceptedResponse(for: "invitee", principalGeneration: 6) == nil)
        let guest = InvitationAcceptance(eventId: id, role: "guest", planningScopeId: nil, status: "accepted")
        progress.record(guest, accountID: "guest", principalGeneration: 8)
        #expect(progress.acceptedResponse(for: "guest", principalGeneration: 8)?.destination == .guest(id))
        #expect(progress.acceptedResponse(for: "invitee", principalGeneration: 8) == nil)
    }

    @Test("Accepted invitation progress expires across an A to B to A session switch")
    func acceptedJoinRequiresSamePrincipalGeneration() {
        let response = InvitationAcceptance(eventId: UUID(), role: "guest", planningScopeId: nil, status: "accepted")
        var progress = InvitationJoinProgress()
        progress.record(response, accountID: "same-account", principalGeneration: 2)
        #expect(progress.acceptedResponse(for: "same-account", principalGeneration: 2) != nil)
        #expect(progress.acceptedResponse(for: "same-account", principalGeneration: 4) == nil)
    }

    @Test("Accepted collaborators without a returned scope bootstrap their event; guests stay guests")
    func acceptedRoleRoutingWithoutScope() {
        let id = UUID()
        let collaborator = InvitationAcceptance(eventId: id, role: "collaborator", planningScopeId: nil, status: "accepted")
        let guest = InvitationAcceptance(eventId: id, role: "guest", planningScopeId: id, status: "accepted")
        #expect(collaborator.destination == .planning(id))
        #expect(guest.destination == .guest(id))
    }

    @Test("Invitation decoding failures provide safe diagnostics and a localized retry message",
          arguments: ["missing", "null", "type", "malformed", "payload"])
    @MainActor
    func decodingDiagnostics(fixture: String) async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [InvitationDiagnosticProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        var captured: [String: String] = [:]
        var loggedEvent: String?
        let api = InvitationAPIClient(baseURL: URL(string: "https://invitation-diagnostics.invalid")!,
            session: session, tokenStore: InvitationDiagnosticTokens(), recordDiagnostic: { event, fields, _ in
                loggedEvent = event
                captured = fields
            })
        do {
            let _: GuestInvitationFeed = try await api.request("api/events/invitations",
                query: [URLQueryItem(name: "fixture", value: fixture), URLQueryItem(name: "token", value: "private-invite-token")])
            Issue.record("Invalid response unexpectedly decoded")
        } catch EventInvitationFailure.invalidResponse {
            #expect(EventInvitationFailure.invalidResponse.localizedDescription == String(localized: "The invitation could not be loaded. Try again."))
        }
        #expect(loggedEvent == "invitation_response_decode_failed")
        #expect(captured["endpoint"] == "api/events/invitations")
        #expect(captured["http_status"] == "200")
        #expect(UUID(uuidString: captured["request_id"] ?? "") != nil)
        let expected: (String, String) = switch fixture {
        case "missing": ("key_not_found", "data.events.[0].title")
        case "null": ("null_value", "data.events.[0].title")
        case "type": ("type_mismatch", "data.events.[0].title")
        case "payload": ("missing_payload", "data")
        default: ("invalid_value", "$")
        }
        #expect(captured["decode_kind"] == expected.0)
        #expect(captured["decode_path"] == expected.1)
        if fixture == "missing" { #expect(captured["missing_key"] == "title") }
        let diagnostic = String(describing: captured)
        #expect(!diagnostic.contains("private-"))
        #expect(!diagnostic.contains("https://"))
    }

    @Test("Invitation errors retain safe server messages and correlation identifiers")
    @MainActor
    func serverDiagnostics() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [InvitationDiagnosticProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        var captured: [String: String] = [:]
        let api = InvitationAPIClient(baseURL: URL(string: "https://invitation-diagnostics.invalid")!,
            session: session, tokenStore: InvitationDiagnosticTokens(), recordDiagnostic: { _, fields, _ in captured = fields })
        do {
            let _: GuestInvitationFeed = try await api.request("api/events/invitations", query: [URLQueryItem(name: "fixture", value: "server")])
            Issue.record("Forbidden response unexpectedly succeeded")
        } catch EventInvitationFailure.server(let message) {
            #expect(message == "Invitation unavailable")
        }
        #expect(captured["http_status"] == "403")
        #expect(captured["server_trace_id"] == "11111111-1111-4111-8111-111111111111")
        #expect(captured["server_error_id"] == "22222222-2222-4222-8222-222222222222")
        #expect(captured["decode_kind"] == nil)
    }

    @Test("Decoding diagnostics redact arbitrary dictionary keys and debug descriptions")
    @MainActor
    func diagnosticPrivacy() {
        struct Key: CodingKey {
            let stringValue: String
            var intValue: Int? { nil }
            init?(stringValue: String) { self.stringValue = stringValue }
            init?(intValue: Int) { return nil }
        }
        let error = DecodingError.keyNotFound(Key(stringValue: "private-email@example.com")!,
            .init(codingPath: [], debugDescription: "private-response-body"))
        let fields = InvitationDecodingDiagnostics.fields(for: error)
        #expect(fields["missing_key"] == "<redacted-key>")
        #expect(!String(describing: fields).contains("private-"))
    }

    @Test("Invitation scroll progress stops updating beyond the blur transition")
    func boundedScrollProgress() {
        #expect(InvitationScrollState.progress(for: -50) == 0)
        #expect(InvitationScrollState.progress(for: 110) == 0.5)
        #expect(InvitationScrollState.progress(for: 220) == 1)
        #expect(InvitationScrollState.progress(for: 5000) == 1)
    }

    @Test("Invitation images decode to a bounded display size without changing the source")
    @MainActor
    func displayImageDownsampling() throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let original = UIGraphicsImageRenderer(size: CGSize(width: 2400, height: 1200), format: format).image { context in
            UIColor.blue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 2400, height: 1200))
        }
        let data = try #require(original.pngData())
        let decoded = try #require(InvitationImageDecoder.thumbnail(data: data, maximumPixelSize: 800))
        #expect(decoded.cgImage?.width == 800)
        #expect(decoded.cgImage?.height == 400)
        #expect(UIImage(data: data)?.cgImage?.width == 2400)
        #expect(InvitationImageDecoder.thumbnail(data: Data([0, 1, 2])) == nil)
    }

    @Test("Invitation previews decode signed cover URLs and tolerate missing covers")
    func previewCoverDecoding() throws {
        let decoder = JSONDecoder()
        let covered = try decoder.decode(InvitationPreview.self, from: Data(#"{"requiresSignIn":false,"title":"Wedding","coverURL":"https://example.com/cover.png?signature=test"}"#.utf8))
        #expect(covered.coverURL?.host == "example.com")
        let missing = try decoder.decode(InvitationPreview.self, from: Data(#"{"requiresSignIn":true}"#.utf8))
        #expect(missing.coverURL == nil)
    }

    @Test("Pending invitations do not open a planning scope and configured access decodes")
    @MainActor
    func approvalContractDecodes() throws {
        let decoder = JSONDecoder()
        let id = UUID().uuidString
        let pending = try decoder.decode(InvitationAcceptance.self, from: Data("{\"eventId\":\"\(id)\",\"role\":\"collaborator\",\"status\":\"awaiting_approval\",\"planningScopeId\":null}".utf8))
        #expect(pending.awaitsApproval)
        #expect(pending.planningScopeId == nil)
        let accepted = try decoder.decode(InvitationAcceptance.self, from: Data("{\"eventId\":\"\(id)\",\"role\":\"collaborator\",\"planningScopeId\":\"\(id)\"}".utf8))
        #expect(!accepted.awaitsApproval)
        let preview = try decoder.decode(InvitationPreview.self, from: Data(#"{"requiresSignIn":false,"status":"awaiting_approval","requiresApproval":true,"planningPermission":"contribute"}"#.utf8))
        #expect(preview.requiresApproval == true)
        #expect(preview.status == "awaiting_approval")
        let requests = try decoder.decode(EventJoinRequests.self, from: Data("{\"requests\":[{\"id\":\"\(id)\",\"name\":\"Reader\",\"email\":\"reader@example.com\",\"planningPermission\":\"view_only\"}]}".utf8))
        #expect(requests.requests.first?.permission == .viewOnly)
    }

    @Test("The account-linked participant emitted by the server decodes in iOS")
    @MainActor
    func acceptedParticipantDecodes() throws {
        let personID = UUID()
        let data = try JSONSerialization.data(withJSONObject: [
            "id": personID.uuidString.lowercased(), "userID": "better-auth-user",
            "name": "New Collaborator", "email": "collaborator@example.com",
            "initials": "NC", "participantRole": "collaborator",
            "planningPermission": "manage", "attendance": "invited",
            "invitationStatus": "active", "profileImageURL": "https://example.com/avatar.jpg"
        ])
        let member = try JSONDecoder().decode(WorkspaceMember.self, from: data)
        #expect(member.id == personID)
        #expect(member.userID == "better-auth-user")
        #expect(member.invitationStatus == .active)
        #expect(member.planningPermission == .manage)
        #expect(member.profileImageURL?.absoluteString == "https://example.com/avatar.jpg")
    }
}

@MainActor
private final class InvitationDiagnosticTokens: SessionTokenStore {
    func read() -> String? { "private-auth-token" }
    func save(_ token: String) {}
    func delete() {}
}

private final class InvitationDiagnosticProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard UUID(uuidString: request.value(forHTTPHeaderField: "X-Request-ID") ?? "") != nil else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        let fixture = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "fixture" }?.value
        let body: String
        switch fixture {
        case "missing": body = #"{"ok":true,"data":{"events":[{"id":"11111111-1111-4111-8111-111111111111"}]}}"#
        case "null": body = #"{"ok":true,"data":{"events":[{"id":"11111111-1111-4111-8111-111111111111","title":null}]}}"#
        case "type": body = #"{"ok":true,"data":{"events":[{"id":"11111111-1111-4111-8111-111111111111","title":{"private-field":"private-value"}}]}}"#
        case "payload": body = #"{"ok":true,"data":null}"#
        case "server": body = #"{"ok":false,"error":{"userMessage":"Invitation unavailable","traceId":"11111111-1111-4111-8111-111111111111","errorId":"22222222-2222-4222-8222-222222222222"}}"#
        default: body = "<html>private-response-body</html>"
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: fixture == "server" ? 403 : 200,
            httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
