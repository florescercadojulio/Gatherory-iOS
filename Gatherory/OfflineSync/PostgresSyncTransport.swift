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

    /// Resolves a shared published revision without sending the viewer's
    /// session or workspace credentials. The token is also omitted from logs.
    func sharedBlueprint(token: String) async throws -> BlueprintCatalogEntry {
        guard BlueprintSharedTemplateLink.isValidToken(token) else {
            throw CloudSyncFailure.invalidResponse
        }
        var request = URLRequest(url: endpointURL(path: ["api", "blueprints", "shared", token]))
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        guard let data = try await performData(request, operation: "blueprints/shared") else {
            throw CloudSyncFailure.invalidResponse
        }
        do {
            return try decoder.decode(BlueprintCatalogEntry.self, from: data)
        } catch {
            SyncDiagnostics.record(
                "shared_blueprint_decode_failed",
                fields: ["operation": "blueprints/shared", "coding_path": SyncDiagnostics.decodePath(error)],
                error: error
            )
            throw CloudSyncFailure.invalidResponse
        }
    }

    func blueprintLibrary() async throws -> BlueprintLibraryResponse {
        var request = try authenticatedRequest(path: ["api", "blueprints", "library"])
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
        notFoundIsEmpty: Bool = false,
        operation: String? = nil
    ) async throws -> Data? {
        var request = request
        let requestID = UUID().uuidString
        request.setValue(requestID, forHTTPHeaderField: "X-Request-ID")
        let started = Date()
        var fields = ["request_id": requestID, "operation": operation ?? request.url?.lastPathComponent ?? "sync"]
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

extension PostgresSyncTransport: BlueprintCreateShareTransport {
    func captureSource(eventID: UUID) async throws -> BlueprintCaptureSourceResponse {
        try await postTemplateCreation(BlueprintCaptureReadAction(action: "source", eventId: eventID.uuidString.lowercased()))
    }

    func reviewCapture(_ input: BlueprintNativeReviewInput) async throws -> BlueprintCaptureReview {
        try await postTemplateCreation(input)
    }

    func createTemplate(_ input: BlueprintNativeCreateInput) async throws -> BlueprintNativeCreationResult {
        try await postTemplateCreation(input)
    }

    private func postTemplateCreation<Input: Encodable, Output: Decodable>(_ input: Input) async throws -> Output {
        var request = try authenticatedRequest(path: ["api", "blueprints", "create-template"])
        request.httpMethod = "POST"
        request.httpBody = try encoder.encode(input)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        guard let data = try await performData(request, operation: "blueprints/create-template") else {
            throw CloudSyncFailure.invalidResponse
        }
        do { return try decoder.decode(Output.self, from: data) }
        catch { throw CloudSyncFailure.invalidResponse }
    }

    private struct BlueprintCaptureReadAction: Encodable {
        let action: String
        let eventId: String
    }
}

extension PostgresSyncTransport: BlueprintPersonalLibraryTransport {
    private struct PersonalCommand: Encodable {
        let action: String
        var id: String? = nil
        var expectedVersion: Int? = nil
        var content: BlueprintDraftContent? = nil
    }
    private struct PersonalDeletion: Decodable { let deleted: Bool }

    func listPersonalBlueprints() async throws -> [BlueprintPersonalRecord] {
        let response: BlueprintPersonalListResponse = try await personalCommand(.init(action: "list"))
        return response.templates
    }
    func savePersonalBlueprint(id: UUID, expectedVersion: Int, content: BlueprintDraftContent) async throws -> BlueprintPersonalRecord {
        try await personalCommand(.init(action: "save", id: id.uuidString.lowercased(), expectedVersion: expectedVersion, content: content))
    }
    func deletePersonalBlueprint(id: UUID) async throws {
        let response: PersonalDeletion = try await personalCommand(.init(action: "delete", id: id.uuidString.lowercased()))
        guard response.deleted else { throw CloudSyncFailure.invalidResponse }
    }
    func publishPersonalBlueprint(id: UUID, expectedVersion: Int) async throws -> BlueprintPersonalRecord {
        try await personalCommand(.init(action: "publish", id: id.uuidString.lowercased(), expectedVersion: expectedVersion))
    }
    private func personalCommand<Output: Decodable>(_ command: PersonalCommand) async throws -> Output {
        var request = try authenticatedRequest(path: ["api", "blueprints", "personal"])
        request.httpMethod = "POST"
        request.httpBody = try encoder.encode(command)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        guard let data = try await performData(request, operation: "blueprints/personal") else {
            throw CloudSyncFailure.invalidResponse
        }
        return try decoder.decode(Output.self, from: data)
    }
}

extension PostgresSyncTransport: BlueprintSavedCopyTransport {
    private struct SnapshotCopyRequest: Encodable {
        let requestId: String
        let content: BlueprintDraftContent
    }

    func copyBlueprintSnapshot(requestID: UUID, content: BlueprintDraftContent) async throws -> BlueprintPersonalRecord {
        var request = try authenticatedRequest(path: ["api", "blueprints", "copies"])
        request.httpMethod = "POST"
        request.httpBody = try encoder.encode(SnapshotCopyRequest(requestId: requestID.uuidString.lowercased(), content: content))
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        guard let data = try await performData(request, operation: "blueprints/copies") else { throw CloudSyncFailure.invalidResponse }
        return try decoder.decode(BlueprintPersonalRecord.self, from: data)
    }
}

extension PostgresSyncTransport: BlueprintLinkManagementTransport {
    func templates(eventID: UUID) async throws -> [BlueprintManagedTemplate] {
        let data = try await postSharing(.templates(eventID: eventID))
        return try decodeSharing(BlueprintManagedTemplatesResponse.self, from: data).templates
    }

    func links(eventID: UUID, templateID: UUID) async throws -> [BlueprintManagedShareLink] {
        let data = try await postSharing(.list(eventID: eventID, templateID: templateID))
        return try decodeSharing(BlueprintManagedLinksResponse.self, from: data).links
    }

    func createLink(eventID: UUID, templateID: UUID, revision: Int) async throws -> BlueprintCreatedShareLink {
        let data = try await postSharing(.create(eventID: eventID, templateID: templateID, revision: revision))
        let created = try decodeSharing(BlueprintCreatedShareLink.self, from: data)
        guard Self.isValidBlueprintShareToken(created.token) else { throw CloudSyncFailure.invalidResponse }
        return created
    }

    func revokeLink(eventID: UUID, templateID: UUID, linkID: UUID) async throws {
        let data = try await postSharing(.revoke(eventID: eventID, templateID: templateID, linkID: linkID))
        struct Acknowledgement: Decodable { let revoked: Bool }
        guard try decodeSharing(Acknowledgement.self, from: data).revoked else {
            throw CloudSyncFailure.invalidResponse
        }
    }

    func setTemplateListing(eventID: UUID, templateID: UUID, revision: Int?) async throws -> Int? {
        let data = try await postSharing(.listing(eventID: eventID, templateID: templateID, revision: revision))
        struct Acknowledgement: Decodable {
            let listedRevision: Int?

            enum CodingKeys: String, CodingKey { case listedRevision }

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                // Explicit null acknowledges withdrawal; an absent key does not.
                listedRevision = try container.decode(Int?.self, forKey: .listedRevision)
            }
        }
        return try decodeSharing(Acknowledgement.self, from: data).listedRevision
    }

    func shareURL(token: String) -> URL? {
        guard Self.isValidBlueprintShareToken(token),
              var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false),
              let scheme = components.scheme?.lowercased(),
              let host = components.host?.lowercased(),
              components.user == nil, components.password == nil,
              scheme == "https" || (scheme == "http" && ["localhost", "127.0.0.1", "::1"].contains(host)) else {
            return nil
        }
        let basePath = components.percentEncodedPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.percentEncodedPath = "/" + [basePath, "templates/shared/\(token)"].filter { !$0.isEmpty }.joined(separator: "/")
        components.query = nil
        components.fragment = nil
        return components.url
    }

    private func postSharing(_ action: BlueprintLinkManagementAction) async throws -> Data {
        var request = try authenticatedRequest(path: ["api", "blueprints", "sharing"])
        request.httpMethod = "POST"
        request.httpBody = try encoder.encode(action)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        guard let data = try await performData(request, operation: "blueprints/sharing") else {
            throw CloudSyncFailure.invalidResponse
        }
        return data
    }

    private func decodeSharing<Value: Decodable>(_ type: Value.Type, from data: Data) throws -> Value {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            for options: ISO8601DateFormatter.Options in [
                [.withInternetDateTime, .withFractionalSeconds],
                [.withInternetDateTime]
            ] {
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = options
                if let date = formatter.date(from: value) { return date }
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid ISO-8601 timestamp")
        }
        do {
            return try decoder.decode(type, from: data)
        } catch {
            SyncDiagnostics.record(
                "blueprint_sharing_response_decode_failed",
                fields: ["operation": "blueprints/sharing", "coding_path": SyncDiagnostics.decodePath(error)],
                error: error
            )
            throw CloudSyncFailure.invalidResponse
        }
    }

    private static func isValidBlueprintShareToken(_ token: String) -> Bool {
        token.count == 64 && token.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }
}

private struct SyncPushRequest: Encodable {
    let mutations: [PendingMutationSnapshot]
}
