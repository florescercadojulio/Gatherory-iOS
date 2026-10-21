import Foundation

nonisolated enum NotificationAuth: Sendable {
    case accountBearer(String)
    case guest(id: UUID, proof: String)
}

nonisolated protocol NotificationRegistrationTransport: Sendable {
    func register(installation: NotificationInstallation, token: String, enabled: Bool, auth: NotificationAuth) async throws -> Int
    func detach(installation: NotificationInstallation) async throws -> Int
}

nonisolated struct URLSessionNotificationRegistrationTransport: NotificationRegistrationTransport {
    private let baseURL: URL
    private let session: URLSession

    init(baseURL: URL) {
        self.baseURL = baseURL
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        configuration.urlCredentialStorage = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.session = URLSession(configuration: configuration,
                                  delegate: NotificationSameOriginRedirectDelegate(origin: baseURL),
                                  delegateQueue: nil)
    }

    func register(installation: NotificationInstallation, token: String, enabled: Bool, auth: NotificationAuth) async throws -> Int {
        var request = try makeRequest()
        request.httpMethod = "POST"
        request.httpBody = try JSONEncoder().encode(RegisterBody(
            installationId: installation.installationID.uuidString.lowercased(),
            installationSecret: installation.secret,
            revision: installation.revision,
            token: token,
            platform: "ios",
            enabled: enabled,
            locale: Locale.current.language.languageCode?.identifier == "es" ? "es" : "en"
        ))
        apply(auth, to: &request)
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw NotificationRegistrationFailure.invalidResponse }
        if let stale = try? JSONDecoder().decode(StaleRevisionResponse.self, from: data), stale.accepted == false {
            throw NotificationRegistrationFailure.staleRevision(stale.revision)
        }
        guard (200..<300).contains(response.statusCode),
              let acknowledgement = try? JSONDecoder().decode(NotificationInstallationAcknowledgement.self, from: data) else {
            throw NotificationRegistrationFailure.invalidResponse
        }
        guard acknowledgement.accepted else { throw NotificationRegistrationFailure.staleRevision(acknowledgement.revision) }
        return acknowledgement.revision
    }

    func detach(installation: NotificationInstallation) async throws -> Int {
        var request = try makeRequest()
        request.httpMethod = "DELETE"
        request.httpBody = try JSONEncoder().encode(DetachBody(
            installationId: installation.installationID.uuidString.lowercased(),
            installationSecret: installation.secret,
            revision: installation.revision
        ))
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw NotificationRegistrationFailure.invalidResponse }
        if let stale = try? JSONDecoder().decode(StaleRevisionResponse.self, from: data), stale.accepted == false {
            throw NotificationRegistrationFailure.staleRevision(stale.revision)
        }
        guard (200..<300).contains(response.statusCode),
              let acknowledgement = try? JSONDecoder().decode(DetachAcknowledgement.self, from: data),
              acknowledgement.detached, acknowledgement.accepted else {
            throw NotificationRegistrationFailure.invalidResponse
        }
        return acknowledgement.revision
    }

    private func makeRequest() throws -> URLRequest {
        let url = baseURL.appending(path: "api/notifications/installations")
        guard url.scheme?.lowercased() == "https" || Self.isLoopbackHTTP(url) else {
            throw NotificationRegistrationFailure.insecureEndpoint
        }
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    private func apply(_ auth: NotificationAuth, to request: inout URLRequest) {
        switch auth {
        case .accountBearer(let token): request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        case .guest(let id, let proof):
            request.setValue("\(id.uuidString.lowercased())", forHTTPHeaderField: "x-gatherory-guest-id")
            request.setValue(proof, forHTTPHeaderField: "x-gatherory-guest-token")
        }
    }

    private static func isLoopbackHTTP(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "http", let host = url.host?.lowercased() else { return false }
        return host == "localhost" || host == "127.0.0.1" || host == "::1"
    }

    private struct RegisterBody: Encodable {
        let installationId: String; let installationSecret: String; let revision: Int; let token: String; let platform: String; let enabled: Bool; let locale: String
    }
    private struct DetachBody: Encodable { let installationId: String; let installationSecret: String; let revision: Int }
    private struct DetachAcknowledgement: Decodable { let detached: Bool; let revision: Int; let accepted: Bool }
    private struct StaleRevisionResponse: Decodable { let revision: Int; let accepted: Bool }
}

nonisolated enum NotificationRegistrationFailure: Error { case invalidResponse, insecureEndpoint, unavailableIdentity, staleRevision(Int), superseded }

private final class NotificationSameOriginRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let origin: URL
    init(origin: URL) { self.origin = origin }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        guard let target = request.url, target.user == nil, target.password == nil,
              target.scheme?.lowercased() == origin.scheme?.lowercased(),
              target.host?.lowercased() == origin.host?.lowercased(),
              (target.port ?? Self.defaultPort(target.scheme)) == (origin.port ?? Self.defaultPort(origin.scheme)) else {
            completionHandler(nil); return
        }
        completionHandler(request)
    }

    private static func defaultPort(_ scheme: String?) -> Int? {
        switch scheme?.lowercased() { case "https": 443; case "http": 80; default: nil }
    }
}
