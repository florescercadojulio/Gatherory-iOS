import Foundation
import Testing
@testable import Gatherory

@MainActor
struct GuestPlanningSignInTests {
    @Test("Public collaborator previews ask guests to sign in to help plan")
    func publicCollaboratorSignInPurpose() throws {
        let contribute = try preview(#"{"requiresSignIn":false,"role":"collaborator","planningPermission":"contribute"}"#)
        #expect(contribute.signInPurpose == .helpPlan)
        #expect(!contribute.permitsDeviceGuestAttendance)

        let viewOnly = try preview(#"{"requiresSignIn":false,"role":"collaborator","planningPermission":"view_only"}"#)
        #expect(viewOnly.signInPurpose == .viewPlans)
        #expect(!viewOnly.permitsDeviceGuestAttendance)
    }

    @Test("Only public guest invitations permit device guest attendance")
    func publicGuestAttendancePolicy() throws {
        let publicGuest = try preview(#"{"requiresSignIn":false,"role":"guest"}"#)
        #expect(publicGuest.signInPurpose == .join)
        #expect(publicGuest.permitsDeviceGuestAttendance)

        for json in [
            #"{"requiresSignIn":true,"role":"guest"}"#,
            #"{"requiresSignIn":false,"role":"collaborator"}"#,
            #"{"requiresSignIn":false,"role":"unknown"}"#,
            #"{"requiresSignIn":false}"#
        ] {
            let value = try preview(json)
            #expect(!value.permitsDeviceGuestAttendance)
            #expect(value.signInPurpose == .join)
        }
    }

    @Test("Guest and signed-in invitation previews use the appropriate account credential")
    @MainActor
    func previewTransportUsesAccountCredential() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [GuestPlanningPreviewProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let credentials = GuestPlanningPreviewTokens()
        let api = InvitationAPIClient(
            baseURL: URL(string: "https://guest-planning-preview.invalid")!,
            session: session,
            tokenStore: credentials,
            recordDiagnostic: { _, _, _ in }
        )

        // Guest mode must ignore a leftover account token, not just an empty store.
        credentials.token = "stale-account-bearer"
        let publicPreview: InvitationPreview = try await api.request(
            "api/invitations/preview",
            query: [URLQueryItem(name: "token", value: "public-guest-token")],
            authenticated: false
        )
        #expect(GuestPlanningPreviewProtocol.lastAuthorization == nil)
        #expect(publicPreview.role == "guest")
        #expect(publicPreview.permitsDeviceGuestAttendance)

        credentials.token = "existing-account-bearer"
        let accountPreview: InvitationPreview = try await api.request(
            "api/invitations/preview",
            query: [URLQueryItem(name: "token", value: "email-invitation-token")],
            authenticated: true
        )
        #expect(GuestPlanningPreviewProtocol.lastAuthorization == "Bearer existing-account-bearer")
        #expect(accountPreview.role == "guest")
        #expect(accountPreview.requiresSignIn == false)
        #expect(accountPreview.title == "Email invitation")
    }

    private func preview(_ json: String) throws -> InvitationPreview {
        try JSONDecoder().decode(InvitationPreview.self, from: Data(json.utf8))
    }


}

@MainActor
private final class GuestPlanningPreviewTokens: SessionTokenStore {
    var token: String?
    func read() throws -> String? { token }
    func save(_ token: String) throws { self.token = token }
    func delete() { token = nil }
}

private final class GuestPlanningPreviewProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var lastAuthorization: String?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard !request.httpShouldHandleCookies else {
            client?.urlProtocol(self, didFailWithError: URLError(.userAuthenticationRequired))
            return
        }
        Self.lastAuthorization = request.value(forHTTPHeaderField: "Authorization")
        let title = request.value(forHTTPHeaderField: "Authorization") == nil ? "Public invitation" : "Email invitation"
        let body = #"{"ok":true,"data":{"requiresSignIn":false,"title":"\#(title)","role":"guest","status":"pending"}}"#
        let response = HTTPURLResponse(
            url: request.url!, statusCode: 200, httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
