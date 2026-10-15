import Foundation

enum CloudSyncFailure: LocalizedError {
    case invalidSession
    case invalidResponse
    case payloadTooLarge
    case clientUpgradeRequired(String?)
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
        case .clientUpgradeRequired:
            BlueprintCopy.clientUpgradeRequired
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
        encoder.outputFormatting = [.sortedKeys]
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

    /// Sends the already-durable request body. The caller retains its intent
    /// until the created scope has been imported through normal bootstrap.
    func installBlueprint(requestID: UUID, requestBody: Data) async throws -> Data {
        var request = try authenticatedRequest(path: ["api", "blueprints", "install"])
        request.httpMethod = "POST"
        request.httpBody = requestBody
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(requestID.uuidString.lowercased(), forHTTPHeaderField: "Idempotency-Key")
        guard let data = try await performData(request) else {
            throw CloudSyncFailure.invalidResponse
        }
        return data
    }

    func blueprintCatalog() async throws -> BlueprintCatalogResponse {
        var request = try authenticatedRequest(path: ["api", "blueprints", "catalog"])
        request.httpMethod = "GET"
        return try await perform(request)
    }

    func blueprintSchedule(_ input: BlueprintScheduleInput) async throws -> BlueprintScheduleResponse {
        var request = try authenticatedRequest(path: ["api", "blueprints", "schedule"])
        request.httpMethod = "POST"
        request.httpBody = try encoder.encode(input)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return try await perform(request)
    }

    func previewBlueprint(_ input: BlueprintInstallInput) async throws -> BlueprintPreviewResponse {
        var request = try authenticatedRequest(path: ["api", "blueprints", "preview"])
        request.httpMethod = "POST"
        request.httpBody = try encoder.encode(input)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return try await perform(request)
    }

    func installBlueprint(_ input: BlueprintInstallInput) async throws -> BlueprintInstallationResult {
        let body = try encoder.encode(input)
        let data = try await installBlueprint(requestID: input.requestID, requestBody: body)
        do {
            return try decoder.decode(BlueprintInstallationResult.self, from: data)
        } catch {
            SyncDiagnostics.record(
                "blueprint_install_response_decode_failed",
                fields: ["coding_path": SyncDiagnostics.decodePath(error)],
                error: error
            )
            throw CloudSyncFailure.invalidResponse
        }
    }

    func blueprintInstallationStatus(requestID: UUID) async throws -> BlueprintInstallationStatus? {
        var request = try authenticatedRequest(path: [
            "api", "blueprints", "installations", requestID.uuidString.lowercased()
        ])
        request.httpMethod = "GET"
        guard let data = try await performData(request, notFoundIsEmpty: true) else { return nil }
        do {
            return try decoder.decode(BlueprintInstallationStatus.self, from: data)
        } catch {
            SyncDiagnostics.record(
                "blueprint_install_status_decode_failed",
                fields: ["coding_path": SyncDiagnostics.decodePath(error)],
                error: error
            )
            throw CloudSyncFailure.invalidResponse
        }
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
        request.setValue(
            SyncClientCapabilities.headerValue,
            forHTTPHeaderField: SyncClientCapabilities.headerName
        )
        return request
    }

    private func perform<Response: Decodable>(_ request: URLRequest) async throws -> Response {
        guard let data = try await performData(request) else {
            throw CloudSyncFailure.invalidResponse
        }
        var fields = ["operation": request.url?.lastPathComponent ?? "sync"]
        do {
            let decoded = try decoder.decode(Response.self, from: data)
            return decoded
        } catch {
            fields["coding_path"] = SyncDiagnostics.decodePath(error)
            SyncDiagnostics.record("sync_response_decode_failed", fields: fields, error: error)
            throw CloudSyncFailure.invalidResponse
        }
    }

    private func performData(
        _ request: URLRequest,
        notFoundIsEmpty: Bool = false
    ) async throws -> Data? {
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
        if response.statusCode == 404, notFoundIsEmpty {
            SyncDiagnostics.record("sync_request_completed", fields: fields)
            return nil
        }
        guard (200..<300).contains(response.statusCode) else {
            let failure = SyncDiagnostics.serverFailure(in: data)
            fields["failure_code"] = failure.code
            fields["server_error_id"] = failure.errorID
            SyncDiagnostics.record("sync_request_failed", fields: fields, error: CloudSyncFailure.server(failure.code ?? "HTTP_\(response.statusCode)"))
            if response.statusCode == 401 { throw CloudSyncFailure.invalidSession }
            if response.statusCode == 413 { throw CloudSyncFailure.payloadTooLarge }
            if response.statusCode == 403 { throw CloudSyncFailure.forbidden(failure.code) }
            if response.statusCode == 426 || failure.code == SyncClientCapabilities.upgradeRequiredCode ||
                failure.code == SyncClientCapabilities.legacyUpgradeRequiredCode {
                throw CloudSyncFailure.clientUpgradeRequired(failure.code)
            }
            throw CloudSyncFailure.server(failure.code ?? "HTTP_\(response.statusCode)")
        }
        SyncDiagnostics.record("sync_request_completed", fields: fields)
        return data
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
