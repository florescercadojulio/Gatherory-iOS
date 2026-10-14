import Foundation

enum CloudSyncFailure: LocalizedError {
    case invalidSession
    case invalidResponse
    case payloadTooLarge
    case forbidden(String?)
    case server(String)

    var errorDescription: String? {
        switch self {
        case .invalidSession:
            "Sign in again to synchronize your Gatherory data."
        case .invalidResponse:
            "Gatherory received an unexpected synchronization response."
        case .payloadTooLarge:
            "This workspace contains media that must upload separately before it can synchronize."
        case .forbidden:
            "Gatherory can no longer synchronize this workspace."
        case .server(let code):
            "Gatherory couldn’t synchronize this workspace (\(code))."
        }
    }
}

struct PostgresSyncTransport: WorkspaceSnapshotTransport {
    private let baseURL: URL
    private let urlSession: URLSession
    private let tokenStore: any SessionTokenStore
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(
        baseURL: URL,
        urlSession: URLSession? = nil,
        tokenStore: any SessionTokenStore = KeychainSessionTokenStore()
    ) {
        self.baseURL = baseURL
        self.tokenStore = tokenStore

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder

        if let urlSession {
            self.urlSession = urlSession
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.httpShouldSetCookies = false
            configuration.waitsForConnectivity = true
            configuration.timeoutIntervalForRequest = 30
            self.urlSession = URLSession(configuration: configuration)
        }
    }

    func push(_ mutations: [PendingMutationSnapshot]) async throws -> SyncPushResponse {
        var request = try authenticatedRequest(path: ["api", "sync", "push"])
        request.httpMethod = "POST"
        request.httpBody = try encoder.encode(SyncPushRequest(mutations: mutations))
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return try await perform(request)
    }

    func pull(scopeID: UUID, after cursor: String?) async throws -> SyncPullPage {
        var components = URLComponents(
            url: endpointURL(path: ["api", "sync", "pull"]),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "scopeID", value: scopeID.uuidString),
            URLQueryItem(name: "after", value: cursor ?? "0")
        ]
        guard let url = components?.url else { throw CloudSyncFailure.invalidResponse }
        var request = try authenticatedRequest(url: url)
        request.httpMethod = "GET"
        return try await perform(request)
    }

    func bootstrap() async throws -> SyncBootstrapResponse {
        var request = try authenticatedRequest(path: ["api", "sync", "bootstrap"])
        request.httpMethod = "GET"
        return try await perform(request)
    }

    private func authenticatedRequest(path: [String]) throws -> URLRequest {
        try authenticatedRequest(url: endpointURL(path: path))
    }

    private func authenticatedRequest(url: URL) throws -> URLRequest {
        guard let token = try tokenStore.read(), !token.isEmpty else {
            throw CloudSyncFailure.invalidSession
        }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    private func perform<Response: Decodable>(_ request: URLRequest) async throws -> Response {
        var request = request
        let requestID = UUID().uuidString
        request.setValue(requestID, forHTTPHeaderField: "X-Request-ID")
        let started = Date()
        var fields = ["request_id": requestID, "operation": request.url?.lastPathComponent ?? "sync"]
        let data: Data
        let rawResponse: URLResponse
        do {
            (data, rawResponse) = try await urlSession.data(for: request)
        } catch {
            SyncDiagnostics.record("sync_request_failed", fields: fields, error: error)
            throw error
        }
        guard let response = rawResponse as? HTTPURLResponse else {
            throw CloudSyncFailure.invalidResponse
        }
        fields["http_status"] = String(response.statusCode)
        fields["duration_ms"] = String(Int(Date().timeIntervalSince(started) * 1000))
        guard (200..<300).contains(response.statusCode) else {
            let failure = SyncDiagnostics.serverFailure(in: data)
            fields["failure_code"] = failure.code
            fields["server_error_id"] = failure.errorID
            SyncDiagnostics.record("sync_request_failed", fields: fields, error: CloudSyncFailure.server(failure.code ?? "HTTP_\(response.statusCode)"))
            if response.statusCode == 401 { throw CloudSyncFailure.invalidSession }
            if response.statusCode == 413 { throw CloudSyncFailure.payloadTooLarge }
            if response.statusCode == 403 { throw CloudSyncFailure.forbidden(failure.code) }
            throw CloudSyncFailure.server(failure.code ?? "HTTP_\(response.statusCode)")
        }
        do {
            let decoded = try decoder.decode(Response.self, from: data)
            SyncDiagnostics.record("sync_request_completed", fields: fields)
            return decoded
        } catch {
            fields["coding_path"] = SyncDiagnostics.decodePath(error)
            SyncDiagnostics.record("sync_response_decode_failed", fields: fields, error: error)
            throw CloudSyncFailure.invalidResponse
        }
    }

    private func endpointURL(path: [String]) -> URL {
        path.reduce(baseURL) { url, component in
            url.appending(path: component)
        }
    }
}

private struct SyncPushRequest: Encodable {
    let mutations: [PendingMutationSnapshot]
}
