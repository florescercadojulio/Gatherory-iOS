import Foundation

enum MediaSyncFailure: LocalizedError {
    case invalidSession
    case invalidResponse
    case imageTooLarge
    case server(String)

    var errorDescription: String? {
        switch self {
        case .invalidSession:
            "Sign in again to synchronize photos."
        case .invalidResponse:
            "Gatherory received an unexpected media response."
        case .imageTooLarge:
            "This image is larger than the 20 MB upload limit."
        case .server(let message):
            message
        }
    }
}

@MainActor
struct MediaUploadRunSummary {
    var changed = false
    var deferredError: Error?
}

struct R2MediaTransport: Sendable {
    private let baseURL: URL
    private let urlSession: URLSession
    private let tokenStore: any SessionTokenStore
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(
        baseURL: URL,
        urlSession: URLSession? = nil,
        tokenStore: any SessionTokenStore = KeychainSessionTokenStore()
    ) {
        self.baseURL = baseURL
        self.tokenStore = tokenStore
        if let urlSession {
            self.urlSession = urlSession
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.httpShouldSetCookies = false
            configuration.waitsForConnectivity = true
            configuration.timeoutIntervalForRequest = 60
            configuration.timeoutIntervalForResource = 180
            self.urlSession = URLSession(configuration: configuration)
        }
    }

    func upload(_ transfer: PendingMediaTransferSnapshot) async throws -> UUID {
        let values = try transfer.localFileURL.resourceValues(forKeys: [.fileSizeKey])
        guard let byteSize = values.fileSize else { throw MediaSyncFailure.invalidResponse }
        guard byteSize <= 20 * 1024 * 1024 else { throw MediaSyncFailure.imageTooLarge }

        let prepared: PreparedUpload = try await post(
            path: ["api", "media", "native", "prepare"],
            body: PrepareUploadRequest(
                scopeId: transfer.scopeID,
                mediaAssetId: transfer.id,
                originalFilename: transfer.localFileURL.lastPathComponent,
                contentType: transfer.contentType,
                byteSize: byteSize
            )
        )
        guard prepared.mediaAssetId == transfer.id,
              let uploadURL = URL(string: prepared.uploadUrl) else {
            throw MediaSyncFailure.invalidResponse
        }

        var uploadRequest = URLRequest(url: uploadURL)
        uploadRequest.httpMethod = prepared.method
        for (name, value) in prepared.requiredHeaders {
            uploadRequest.setValue(value, forHTTPHeaderField: name)
        }
        let (_, rawUploadResponse) = try await urlSession.upload(
            for: uploadRequest,
            fromFile: transfer.localFileURL
        )
        guard let uploadResponse = rawUploadResponse as? HTTPURLResponse,
              (200..<300).contains(uploadResponse.statusCode) else {
            throw MediaSyncFailure.server("The image could not be uploaded.")
        }

        let finalized: FinalizedUpload = try await post(
            path: ["api", "media", "native", "finalize"],
            body: MediaAssetRequest(mediaAssetId: transfer.id)
        )
        guard finalized.mediaAssetId == transfer.id else {
            throw MediaSyncFailure.invalidResponse
        }
        return finalized.mediaAssetId
    }

    func download(mediaAssetID: UUID) async throws -> Data {
        var components = URLComponents(
            url: endpointURL(path: ["api", "media", "native", "url"]),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "mediaAssetId", value: mediaAssetID.uuidString)
        ]
        guard let url = components?.url else { throw MediaSyncFailure.invalidResponse }
        let response: FinalizedUpload = try await get(url: url)
        guard let downloadURL = URL(string: response.url) else {
            throw MediaSyncFailure.invalidResponse
        }
        let (data, rawResponse) = try await urlSession.data(from: downloadURL)
        guard let response = rawResponse as? HTTPURLResponse,
              (200..<300).contains(response.statusCode),
              !data.isEmpty else {
            throw MediaSyncFailure.invalidResponse
        }
        return data
    }

    private func post<Body: Encodable, Response: Decodable>(
        path: [String],
        body: Body
    ) async throws -> Response {
        var request = try authenticatedRequest(url: endpointURL(path: path))
        request.httpMethod = "POST"
        request.httpBody = try encoder.encode(body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return try await perform(request)
    }

    private func get<Response: Decodable>(url: URL) async throws -> Response {
        var request = try authenticatedRequest(url: url)
        request.httpMethod = "GET"
        return try await perform(request)
    }

    private func authenticatedRequest(url: URL) throws -> URLRequest {
        guard let token = try tokenStore.read(), !token.isEmpty else {
            throw MediaSyncFailure.invalidSession
        }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    private func perform<Response: Decodable>(_ request: URLRequest) async throws -> Response {
        let (data, rawResponse) = try await urlSession.data(for: request)
        guard let response = rawResponse as? HTTPURLResponse else {
            throw MediaSyncFailure.invalidResponse
        }
        guard (200..<300).contains(response.statusCode) else {
            if response.statusCode == 401 { throw MediaSyncFailure.invalidSession }
            let error = try? decoder.decode(SimpleErrorResponse.self, from: data)
            throw MediaSyncFailure.server(error?.error ?? "HTTP_\(response.statusCode)")
        }
        let envelope = try decoder.decode(ServerResult<Response>.self, from: data)
        guard envelope.ok, let value = envelope.data else {
            throw MediaSyncFailure.server(
                envelope.error?.userMessage ?? "The media operation failed."
            )
        }
        return value
    }

    private func endpointURL(path: [String]) -> URL {
        path.reduce(baseURL) { $0.appending(path: $1) }
    }
}

private struct PrepareUploadRequest: Encodable {
    let scopeId: UUID
    let mediaAssetId: UUID
    let originalFilename: String
    let contentType: String
    let byteSize: Int
}

private struct MediaAssetRequest: Encodable {
    let mediaAssetId: UUID
}

private struct PreparedUpload: Decodable {
    let mediaAssetId: UUID
    let uploadUrl: String
    let method: String
    let requiredHeaders: [String: String]
}

private struct FinalizedUpload: Decodable {
    let mediaAssetId: UUID
    let url: String
}

private struct ServerResult<Value: Decodable>: Decodable {
    let ok: Bool
    let data: Value?
    let error: ServerResultError?
}

private struct ServerResultError: Decodable {
    let userMessage: String
}

private struct SimpleErrorResponse: Decodable {
    let error: String
}

@MainActor
struct WorkspaceMediaSyncCoordinator {
    let persistence: WorkspacePersistenceController
    let library: WorkspaceLibrary
    let transport: R2MediaTransport

    /// Media uses its own durable outbox. A photo retry must never make the
    /// already-successful workspace mutation look unsynchronized.
    func uploadPendingMedia(scopeID: UUID) async throws -> MediaUploadRunSummary {
        try persistence.prepareMediaTransfers(from: library)
        var summary = MediaUploadRunSummary()
        for transfer in try persistence.pendingMediaTransfers(scopeID: scopeID) {
            do {
                try persistence.markMediaTransferUploading(transfer.id)
                let mediaAssetID = try await transport.upload(transfer)
                guard let workspace = library.workspaces.first(where: {
                    $0.mainEventID == transfer.scopeID
                }), workspace.applyMediaAssetID(mediaAssetID, to: transfer.entityID) else {
                    try persistence.completeMediaTransfer(transfer.id)
                    continue
                }
                try persistence.completeMediaTransfer(transfer.id)
                summary.changed = true
            } catch {
                try? persistence.failMediaTransfer(transfer.id)
                // Continue with the remaining attachments. Each transfer is
                // independently durable and will retry from the outbox.
                summary.deferredError = summary.deferredError ?? error
            }
        }
        if summary.changed { persistence.flush(library) }
        return summary
    }

    func downloadMissingMedia(scopeID: UUID) async {
        guard let workspace = library.workspaces.first(where: {
            $0.mainEventID == scopeID
        }) else { return }
        var changed = false
        for attachment in workspace.mediaAttachments
        where attachment.imageData?.isEmpty != false {
            guard let mediaAssetID = attachment.mediaAssetID else { continue }
            guard let data = try? await transport.download(mediaAssetID: mediaAssetID) else {
                continue
            }
            changed = workspace.applyDownloadedMedia(data, to: attachment.entityID) || changed
        }
        if changed { persistence.flush(library) }
    }
}
