import Foundation

/// Event-only guest access. It uses a device-scoped proof header and a
/// cookieless session; this credential is never sent as a Better Auth bearer.
@MainActor
final class DeviceGuestInvitationClient: LocalGuestInvitationTransport {
    let baseURL: URL?
    let profile: LocalGuestProfile
    private let credentialStore: any LocalGuestCredentialStore
    private let accountTokenStore: any SessionTokenStore
    private let session: URLSession
    private var registered = false

    init(
        baseURL: URL?,
        profile: LocalGuestProfile,
        credentialStore: (any LocalGuestCredentialStore)? = nil,
        accountTokenStore: (any SessionTokenStore)? = nil,
        sessionConfiguration: URLSessionConfiguration? = nil
    ) {
        self.baseURL = baseURL
        self.profile = profile
        self.credentialStore = credentialStore ?? KeychainLocalGuestCredentialStore()
        self.accountTokenStore = accountTokenStore ?? KeychainSessionTokenStore()
        self.session = Self.makeSession(baseURL: baseURL, configuration: sessionConfiguration)
    }

    func invalidate() { session.invalidateAndCancel() }

    func invitations() async throws -> GuestInvitationFeed {
        try await ensureRegistered()
        return try await request("api/guest/events")
    }

    func join(token: UUID) async throws -> InvitationAcceptance {
        try await ensureRegistered()
        return try await request("api/guest/events", method: "POST", body: ["token": token.uuidString.lowercased()])
    }

    func respond(eventID: UUID, response: EventResponse) async throws -> AttendanceAcknowledgement {
        try await ensureRegistered()
        let attendance: String
        switch response {
        case .going: attendance = "going"
        case .notSure: attendance = "not_sure"
        case .notGoing: attendance = "not_going"
        }
        return try await request("api/guest/events", method: "PATCH", body: [
            "eventId": eventID.uuidString.lowercased(),
            "attendance": attendance
        ])
    }

    func leaveInvitation(eventID: UUID) async throws -> UUID {
        try await ensureRegistered()
        struct Acknowledgement: Decodable { let eventId: UUID }
        let result: Acknowledgement = try await request("api/guest/events", method: "DELETE", body: [
            "eventId": eventID.uuidString.lowercased()
        ])
        return result.eventId
    }

    /// Claim is authenticated by Better Auth in addition to the guest proof.
    /// The local guest credential remains in Keychain until workspace import is
    /// durably completed by the caller.
    func claim() async throws -> GuestClaimAcknowledgement {
        try await ensureRegistered()
        return try await request("api/guest/claim", method: "POST", requiresAccount: true)
    }

    private func ensureRegistered() async throws {
        guard !registered else { return }
        guard let baseURL, Self.isSafeOrigin(baseURL), profile.hasValidDisplayName else {
            throw EventInvitationFailure.unavailable
        }
        let credential = try credentialStore.loadOrCreateToken(profileID: profile.id)
        guard Self.isValidCredential(credential) else { throw EventInvitationFailure.unavailable }
        let acknowledgement: GuestRegistrationAcknowledgement = try await request("api/guest/session", method: "POST", body: [
            "id": profile.id.uuidString.lowercased(),
            "name": profile.displayName,
            "credential": credential
        ])
        guard acknowledgement.id == profile.id, acknowledgement.name == profile.displayName else {
            throw EventInvitationFailure.invalidResponse
        }
        registered = true
    }

    private func request<Value: Decodable>(
        _ path: String,
        method: String = "GET",
        body: [String: String]? = nil,
        requiresAccount: Bool = false
    ) async throws -> Value {
        guard let baseURL, Self.isSafeOrigin(baseURL),
              ["api/guest/session", "api/guest/events", "api/guest/claim"].contains(path) else {
            throw EventInvitationFailure.unavailable
        }
        let credential = try credentialStore.loadOrCreateToken(profileID: profile.id)
        guard Self.isValidCredential(credential) else { throw EventInvitationFailure.unavailable }

        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = method
        request.timeoutInterval = 30
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.httpShouldHandleCookies = false
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(profile.id.uuidString.lowercased(), forHTTPHeaderField: "X-Gatherory-Guest-Id")
        request.setValue(credential, forHTTPHeaderField: "X-Gatherory-Guest-Token")
        request.setValue(UUID().uuidString.lowercased(), forHTTPHeaderField: "X-Request-ID")
        if requiresAccount {
            guard let token = try accountTokenStore.read(), !token.isEmpty else {
                throw CloudSyncFailure.invalidSession
            }
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body { request.httpBody = try JSONEncoder().encode(body) }

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw EventInvitationFailure.unavailable
        }
        guard let response = response as? HTTPURLResponse else { throw EventInvitationFailure.unavailable }
        let decoder = JSONDecoder()
        let envelope: GuestEnvelope<Value>
        do { envelope = try decoder.decode(GuestEnvelope<Value>.self, from: data) }
        catch { throw EventInvitationFailure.invalidResponse }
        guard (200..<300).contains(response.statusCode), envelope.ok, let value = envelope.data else {
            if response.statusCode == 401 && requiresAccount { throw CloudSyncFailure.invalidSession }
            throw EventInvitationFailure.server(envelope.error?.userMessage ?? "The invitation could not be loaded. Try again.")
        }
        return value
    }

    private static func isSafeOrigin(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), let host = url.host?.lowercased(),
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil else { return false }
        if scheme == "https" { return true }
        guard scheme == "http" else { return false }
        return ["localhost", "127.0.0.1", "::1"].contains(host)
    }

    private static func isValidCredential(_ value: String) -> Bool {
        let bytes = Array(value.utf8)
        return bytes.count == 43 && bytes.allSatisfy {
            (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 45 || $0 == 95
        }
    }

    private static func makeSession(baseURL: URL?, configuration supplied: URLSessionConfiguration?) -> URLSession {
        let configuration = supplied ?? URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        let delegate = GuestSameOriginRedirectDelegate(origin: baseURL)
        return URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
    }
}

final class GuestSameOriginRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let origin: URL?

    init(origin: URL?) { self.origin = origin }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        guard let origin,
              let target = request.url,
              target.user == nil,
              target.password == nil,
              Self.sameOrigin(origin, target) else {
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }

    private static func sameOrigin(_ lhs: URL, _ rhs: URL) -> Bool {
        lhs.scheme?.lowercased() == rhs.scheme?.lowercased()
            && lhs.host?.lowercased() == rhs.host?.lowercased()
            && (lhs.port ?? Self.defaultPort(lhs.scheme)) == (rhs.port ?? Self.defaultPort(rhs.scheme))
    }

    private static func defaultPort(_ scheme: String?) -> Int? {
        switch scheme?.lowercased() { case "https": 443; case "http": 80; default: nil }
    }
}

private struct GuestRegistrationAcknowledgement: Decodable {
    let id: UUID
    let name: String
}

private struct GuestEnvelope<Value: Decodable>: Decodable {
    let ok: Bool
    let data: Value?
    let error: GuestSafeError?
}

private struct GuestSafeError: Decodable {
    let userMessage: String?
}
