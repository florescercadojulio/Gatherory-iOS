import Foundation

struct GeneratedEventInvitation: Decodable {
    let eventId: UUID
    let email: String?
    let role: String?
    let expiresAt: String?
    let url: URL

    init(eventId: UUID, email: String?, expiresAt: String?, url: URL, role: String? = nil) {
        self.eventId = eventId
        self.email = email
        self.role = role
        self.expiresAt = expiresAt
        self.url = url
    }

    func isValid(for eventID: UUID, baseURL: URL) -> Bool {
        guard eventId == eventID,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              ["http", "https"].contains(components.scheme?.lowercased() ?? ""),
              url.scheme == baseURL.scheme,
              url.host == baseURL.host,
              url.port == baseURL.port,
              url.user == nil, url.password == nil,
              url.query == nil, url.fragment == nil else { return false }
        let parts = url.path.split(separator: "/")
        return parts.count == 2 && parts[0] == "join" && UUID(uuidString: String(parts[1])) != nil
    }
}

enum EventInvitationFailure: LocalizedError {
    case unavailable
    case invalidResponse
    case server(String)

    var errorDescription: String? {
        switch self {
        case .unavailable: String(localized: "An invitation link could not be prepared. Synchronize your event and try again.")
        case .invalidResponse: String(localized: "The invitation could not be loaded. Try again.")
        case .server(let message): NSLocalizedString(message, comment: "Safe invitation server message")
        }
    }
}

struct EventInvitationClient {
    let baseURL: URL
    var session: URLSession = .shared
    var tokenStore: any SessionTokenStore = KeychainSessionTokenStore()

    func create(eventID: UUID, name: String?, email: String?, role: WorkspaceRole, permission: PlanningPermission) async throws -> GeneratedEventInvitation {
        try await create(eventID: eventID, name: name, email: email, role: role, permission: permission, isShareLink: false)
    }

    /// Creates or retrieves the stable public link for one role. Name and email
    /// are omitted so the API cannot interpret this as an email-bound invite.
    func createShareLink(eventID: UUID, role: WorkspaceRole, permission: PlanningPermission) async throws -> GeneratedEventInvitation {
        guard role == .guest || role == .collaborator else { throw EventInvitationFailure.unavailable }
        return try await create(eventID: eventID, name: nil, email: nil, role: role, permission: permission, isShareLink: true)
    }

    func shareLinks(eventID: UUID) async throws -> [GeneratedEventInvitation] {
        let result = try await requestShareLinks("api/invitations", query: [
            URLQueryItem(name: "eventId", value: eventID.uuidString.lowercased()),
            URLQueryItem(name: "kind", value: "share-links")
        ])
        guard result.ok, let links = result.data?.links else {
            throw EventInvitationFailure.server(result.error?.userMessage ?? String(localized: "The invitation could not be loaded. Try again."))
        }
        return links.filter {
            $0.email == nil
                && ($0.role == WorkspaceRole.guest.rawValue || $0.role == WorkspaceRole.collaborator.rawValue)
                && $0.isValid(for: eventID, baseURL: baseURL)
        }
    }

    private func create(eventID: UUID, name: String?, email: String?, role: WorkspaceRole,
                        permission: PlanningPermission, isShareLink: Bool) async throws -> GeneratedEventInvitation {
        guard let token = try tokenStore.read(), !token.isEmpty else { throw CloudSyncFailure.invalidSession }
        var request = URLRequest(url: baseURL.appending(path: "api/invitations"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 30
        if isShareLink {
            request.httpBody = try JSONEncoder().encode(ShareLinkInvitationInput(
                eventId: eventID, role: role.rawValue, planningPermission: permission.rawValue
            ))
        } else {
            request.httpBody = try JSONEncoder().encode(InvitationInput(
                eventId: eventID, name: name, email: email?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                role: role.rawValue, planningPermission: permission.rawValue
            ))
        }
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw EventInvitationFailure.unavailable }
        if response.statusCode == 401 { throw CloudSyncFailure.invalidSession }
        let result = try JSONDecoder().decode(InvitationResult.self, from: data)
        guard (200..<300).contains(response.statusCode), result.ok, let invitation = result.data else {
            throw EventInvitationFailure.server(result.error?.userMessage ?? String(localized: "The invitation could not be created. Try again."))
        }
        guard invitation.isValid(for: eventID, baseURL: baseURL),
              invitation.role == nil || invitation.role == role.rawValue,
              !isShareLink || (invitation.email == nil && invitation.role == role.rawValue) else {
            throw EventInvitationFailure.unavailable
        }
        return GeneratedEventInvitation(eventId: invitation.eventId, email: invitation.email,
            expiresAt: invitation.expiresAt, url: invitation.url, role: role.rawValue)
    }

    func revoke(eventID: UUID, role: WorkspaceRole? = nil) async throws {
        guard let token = try tokenStore.read(), !token.isEmpty else { throw CloudSyncFailure.invalidSession }
        var request = URLRequest(url: baseURL.appending(path: "api/invitations"))
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30
        var body = ["eventId": eventID.uuidString]
        if let role { body["role"] = role.rawValue }
        request.httpBody = try JSONEncoder().encode(body)
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw EventInvitationFailure.unavailable }
        if response.statusCode == 401 { throw CloudSyncFailure.invalidSession }
        let result = try JSONDecoder().decode(RevocationResult.self, from: data)
        guard (200..<300).contains(response.statusCode), result.ok else {
            throw EventInvitationFailure.server(result.error?.userMessage ?? String(localized: "The invitation could not be disabled. Try again."))
        }
    }

    private func requestShareLinks(_ path: String, query: [URLQueryItem]) async throws -> ShareLinksResult {
        guard let token = try tokenStore.read(), !token.isEmpty else { throw CloudSyncFailure.invalidSession }
        var components = URLComponents(url: baseURL.appending(path: path), resolvingAgainstBaseURL: false)!
        components.queryItems = query
        var request = URLRequest(url: components.url!)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 30
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw EventInvitationFailure.unavailable }
        if response.statusCode == 401 { throw CloudSyncFailure.invalidSession }
        let result = try JSONDecoder().decode(ShareLinksResult.self, from: data)
        guard (200..<300).contains(response.statusCode), result.ok else {
            throw EventInvitationFailure.server(result.error?.userMessage ?? String(localized: "The invitation could not be loaded. Try again."))
        }
        return result
    }

    /// Query items escape ampersands and other characters in event titles.
    static func messageURL(scheme: String, title: String, invitationURL: URL) -> URL? {
        var components = URLComponents()
        components.scheme = scheme
        components.path = ""
        components.queryItems = scheme == "mailto" ? [URLQueryItem(name: "subject", value: title)] : []
        components.queryItems?.append(URLQueryItem(name: "body", value: "\(title): \(invitationURL.absoluteString)"))
        return components.url
    }
}

private struct InvitationInput: Encodable {
    let eventId: UUID
    let name: String?
    let email: String?
    let role: String
    let planningPermission: String
}

private struct ShareLinkInvitationInput: Encodable {
    let eventId: UUID
    let role: String
    let planningPermission: String
}

private struct InvitationResult: Decodable {
    let ok: Bool
    let data: GeneratedEventInvitation?
    let error: SafeInvitationError?
}

private struct SafeInvitationError: Decodable {
    let userMessage: String
}

private struct RevocationResult: Decodable {
    let ok: Bool
    let error: SafeInvitationError?
}

private struct ShareLinksResult: Decodable {
    let ok: Bool
    let data: ShareLinksData?
    let error: SafeInvitationError?
}

private struct ShareLinksData: Decodable {
    let links: [GeneratedEventInvitation]
}
