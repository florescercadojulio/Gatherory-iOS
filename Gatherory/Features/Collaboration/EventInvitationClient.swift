import Foundation

struct GeneratedEventInvitation: Decodable {
    let eventId: UUID
    let email: String?
    let expiresAt: String
    let url: URL

    func isValid(for eventID: UUID, baseURL: URL) -> Bool {
        guard eventId == eventID,
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
        guard let token = try tokenStore.read(), !token.isEmpty else { throw CloudSyncFailure.invalidSession }
        var request = URLRequest(url: baseURL.appending(path: "api/invitations"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 30
        request.httpBody = try JSONEncoder().encode(InvitationInput(
            eventId: eventID, name: name, email: email?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            role: role.rawValue, planningPermission: permission.rawValue
        ))
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw EventInvitationFailure.unavailable }
        if response.statusCode == 401 { throw CloudSyncFailure.invalidSession }
        let result = try JSONDecoder().decode(InvitationResult.self, from: data)
        guard (200..<300).contains(response.statusCode), result.ok, let invitation = result.data else {
            throw EventInvitationFailure.server(result.error?.userMessage ?? String(localized: "The invitation could not be created. Try again."))
        }
        guard invitation.isValid(for: eventID, baseURL: baseURL) else { throw EventInvitationFailure.unavailable }
        return invitation
    }

    func revoke(eventID: UUID) async throws {
        guard let token = try tokenStore.read(), !token.isEmpty else { throw CloudSyncFailure.invalidSession }
        var request = URLRequest(url: baseURL.appending(path: "api/invitations"))
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30
        request.httpBody = try JSONEncoder().encode(["eventId": eventID.uuidString])
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw EventInvitationFailure.unavailable }
        if response.statusCode == 401 { throw CloudSyncFailure.invalidSession }
        let result = try JSONDecoder().decode(RevocationResult.self, from: data)
        guard (200..<300).contains(response.statusCode), result.ok else {
            throw EventInvitationFailure.server(result.error?.userMessage ?? String(localized: "The invitation could not be disabled. Try again."))
        }
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
