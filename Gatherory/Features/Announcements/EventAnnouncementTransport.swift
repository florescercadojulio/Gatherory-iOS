import Foundation

/// Each instance belongs to one principal generation. Credentials are resolved
/// immediately before a request, after checking that the same session is active.
@MainActor final class HTTPEventAnnouncementTransport: EventAnnouncementTransport {
    enum Credential {
        case account(bearer: String)
        case guest(id: UUID, proof: String)
    }
    private let baseURL: URL
    private let credential: () throws -> Credential
    private let session: URLSession

    init(baseURL: URL, configuration: URLSessionConfiguration? = nil,
         credential: @escaping () throws -> Credential) {
        self.baseURL = baseURL
        self.credential = credential
        let config = configuration ?? .ephemeral
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.httpAdditionalHeaders = nil
        config.urlCredentialStorage = nil
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: config, delegate: AnnouncementRedirectBlocker(), delegateQueue: nil)
    }

    func load(eventID: UUID) async throws -> EventAnnouncementFeed {
        let auth = try credential()
        let result: EventAnnouncementFeed = try await request(eventID: eventID, auth: auth)
        guard result.announcements.allSatisfy({ $0.eventId == eventID }) else {
            throw EventAnnouncementFailure.invalidResponse
        }
        // Guest proof can never grant a composer, even for a malformed response.
        let canSend: Bool
        switch auth { case .account: canSend = result.canSend && !result.allowedAudiences.isEmpty; case .guest: canSend = false }
        return EventAnnouncementFeed(announcements: result.announcements, canSend: canSend,
                                     allowedAudiences: canSend ? result.allowedAudiences : [])
    }

    func send(eventID: UUID, requestID: UUID, message: String, audience: EventAnnouncementAudience = .all) async throws -> EventAnnouncement {
        guard EventAnnouncementMessage.isValid(message) else { throw EventAnnouncementFailure.invalidMessage }
        let auth = try credential()
        guard case .account = auth else { throw EventAnnouncementFailure.accessDenied }
        struct Acknowledgement: Decodable { let announcement: EventAnnouncement }
        let result: Acknowledgement = try await request(eventID: eventID, auth: auth, body: [
            "requestId": requestID.uuidString.lowercased(), "message": EventAnnouncementMessage.normalized(message), "audience": audience.rawValue
        ])
        guard result.announcement.eventId == eventID, result.announcement.audience == audience else { throw EventAnnouncementFailure.invalidResponse }
        return result.announcement
    }

    private func request<Value: Decodable>(eventID: UUID, auth: Credential,
                                           body: [String: String]? = nil) async throws -> Value {
        guard Self.safeOrigin(baseURL) else { throw EventAnnouncementFailure.unavailable }
        let prefix: String
        switch auth { case .account: prefix = "api/events"; case .guest: prefix = "api/guest/events" }
        var request = URLRequest(url: baseURL.appending(path: "\(prefix)/\(eventID.uuidString.lowercased())/announcements"))
        request.httpMethod = body == nil ? "GET" : "POST"
        request.httpShouldHandleCookies = false
        request.timeoutInterval = 30
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(UUID().uuidString.lowercased(), forHTTPHeaderField: "X-Request-ID")
        switch auth {
        case .account(let token):
            guard !token.isEmpty else { throw EventAnnouncementFailure.accessDenied }
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        case .guest(let id, let proof):
            guard LocalGuestCredentialToken.isValid(proof) else { throw EventAnnouncementFailure.accessDenied }
            request.setValue(id.uuidString.lowercased(), forHTTPHeaderField: "X-Gatherory-Guest-Id")
            request.setValue(proof, forHTTPHeaderField: "X-Gatherory-Guest-Token")
        }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(body)
        }
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw EventAnnouncementFailure.invalidResponse }
        if response.statusCode == 401 || response.statusCode == 403 || response.statusCode == 404 {
            throw EventAnnouncementFailure.accessDenied
        }
        if response.statusCode == 409 { throw EventAnnouncementFailure.requestConflict }
        guard (200..<300).contains(response.statusCode) else { throw EventAnnouncementFailure.unavailable }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: value) { return date }
            formatter.formatOptions = [.withInternetDateTime]
            guard let date = formatter.date(from: value) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date")
            }
            return date
        }
        guard let envelope = try? decoder.decode(AnnouncementEnvelope<Value>.self, from: data),
              envelope.ok, let value = envelope.data else { throw EventAnnouncementFailure.invalidResponse }
        return value
    }

    private static func safeOrigin(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased(), url.user == nil, url.password == nil,
              url.query == nil, url.fragment == nil else { return false }
        return url.scheme == "https" || (url.scheme == "http" && ["localhost", "127.0.0.1", "::1"].contains(host))
    }
}

private struct AnnouncementEnvelope<Value: Decodable>: Decodable { let ok: Bool; let data: Value? }

private final class AnnouncementRedirectBlocker: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
