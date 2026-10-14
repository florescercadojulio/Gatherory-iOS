import Foundation

enum MediaSyncFailure: LocalizedError {
    case invalidSession
    case invalidResponse
    case imageTooLarge
    case invalidImage
    case server(String)

    var errorDescription: String? {
        switch self {
        case .invalidSession:
            "Sign in again to synchronize photos."
        case .invalidResponse:
            "Gatherory received an unexpected media response."
        case .imageTooLarge:
            "This image is larger than the 20 MB upload limit."
        case .invalidImage:
            String(localized: "This image could not be prepared for upload. Choose another photo and try again.")
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
        let preparation = Task.detached(priority: .utility) {
            try UploadImagePreparation.prepare(sourceURL: transfer.localFileURL)
        }
        let image = try await withTaskCancellationHandler {
            try await preparation.value
        } onCancel: {
            preparation.cancel()
        }
        defer { image.removeTemporaryFile() }
        try Task.checkCancellation()
        SyncDiagnostics.record("media_upload_prepared", fields: [
            "transfer_id": transfer.id.uuidString,
            "upload_bytes": String(image.byteSize),
            "content_type": image.contentType
        ])

        let prepared: PreparedUpload = try await post(
            path: ["api", "media", "native", "prepare"],
            body: PrepareUploadRequest(
                scopeId: transfer.scopeID,
                mediaAssetId: transfer.id,
                originalFilename: image.fileURL.lastPathComponent,
                contentType: image.contentType,
                byteSize: image.byteSize
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
        var fields = ["operation": "r2_put", "transfer_id": transfer.id.uuidString, "scope_id": transfer.scopeID.uuidString]
        let rawUploadResponse: URLResponse
        do { (_, rawUploadResponse) = try await urlSession.upload(for: uploadRequest, fromFile: image.fileURL) }
        catch {
            SyncDiagnostics.record("media_object_failed", fields: fields, error: error)
            throw error
        }
        guard let uploadResponse = rawUploadResponse as? HTTPURLResponse,
              (200..<300).contains(uploadResponse.statusCode) else {
            fields["http_status"] = (rawUploadResponse as? HTTPURLResponse).map { String($0.statusCode) }
            SyncDiagnostics.record("media_object_failed", fields: fields, error: MediaSyncFailure.invalidResponse)
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
        var fields = ["operation": "r2_get", "asset_id": mediaAssetID.uuidString]
        let data: Data
        let rawResponse: URLResponse
        do { (data, rawResponse) = try await urlSession.data(from: downloadURL) }
        catch {
            SyncDiagnostics.record("media_object_failed", fields: fields, error: error)
            throw error
        }
        guard let response = rawResponse as? HTTPURLResponse,
              (200..<300).contains(response.statusCode),
              !data.isEmpty else {
            fields["http_status"] = (rawResponse as? HTTPURLResponse).map { String($0.statusCode) }
            fields["empty_body"] = String(data.isEmpty)
            SyncDiagnostics.record("media_object_failed", fields: fields, error: MediaSyncFailure.invalidResponse)
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
        var request = request
        let requestID = UUID().uuidString
        request.setValue(requestID, forHTTPHeaderField: "X-Request-ID")
        var fields = ["request_id": requestID, "operation": "media_\(request.url?.lastPathComponent ?? "unknown")"]
        let data: Data
        let rawResponse: URLResponse
        do { (data, rawResponse) = try await urlSession.data(for: request) }
        catch {
            SyncDiagnostics.record("media_request_failed", fields: fields, error: error)
            throw error
        }
        guard let response = rawResponse as? HTTPURLResponse else {
            throw MediaSyncFailure.invalidResponse
        }
        fields["http_status"] = String(response.statusCode)
        guard (200..<300).contains(response.statusCode) else {
            let failure = SyncDiagnostics.serverFailure(in: data)
            fields["failure_code"] = failure.code
            fields["server_error_id"] = failure.errorID
            SyncDiagnostics.record("media_request_failed", fields: fields, error: MediaSyncFailure.invalidResponse)
            if response.statusCode == 401 { throw MediaSyncFailure.invalidSession }
            throw MediaSyncFailure.server(failure.code ?? "HTTP_\(response.statusCode)")
        }
        let envelope: ServerResult<Response>
        do { envelope = try decoder.decode(ServerResult<Response>.self, from: data) }
        catch {
            fields["coding_path"] = SyncDiagnostics.decodePath(error)
            SyncDiagnostics.record("media_response_decode_failed", fields: fields, error: error)
            throw error
        }
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
            try Task.checkCancellation()
            do {
                try persistence.markMediaTransferUploading(transfer.id)
                let mediaAssetID = try await transport.upload(transfer)
                try Task.checkCancellation()
                if try completeUploadedMedia(mediaAssetID, for: transfer) {
                    summary.changed = true
                }
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

    /// A workspace switch during upload must never retarget the completion
    /// to the currently selected workspace or its selected child event.
    func completeUploadedMedia(
        _ mediaAssetID: UUID,
        for transfer: PendingMediaTransferSnapshot
    ) throws -> Bool {
        let workspace = library.workspaces.first { $0.mainEventID == transfer.scopeID }
        let changed = workspace?.applyMediaAssetID(mediaAssetID, to: transfer.entityID) ?? false
        try persistence.completeMediaTransfer(transfer.id)
        return changed
    }

    func downloadMissingMedia(scopeID: UUID) async -> MediaUploadRunSummary {
        let ownerUserID = persistence.activeUserID
        var summary = MediaUploadRunSummary()
        guard let workspace = library.workspaces.first(where: {
            $0.mainEventID == scopeID
        }) else { return summary }
        for attachment in workspace.mediaAttachments
        where attachment.imageData?.isEmpty != false {
            guard let mediaAssetID = attachment.mediaAssetID else { continue }
            do {
                try Task.checkCancellation()
                let data = try await transport.download(mediaAssetID: mediaAssetID)
                guard persistence.activeUserID == ownerUserID, !Task.isCancelled else { return summary }
                // Pulling changes can replace the observable workspace while a
                // download is in flight. Apply to the current graph, and never
                // overwrite a cover that was changed during the request.
                guard let current = library.workspaces.first(where: { $0.mainEventID == scopeID }),
                      let target = current.mediaAttachments.first(where: { $0.entityID == attachment.entityID }),
                      target.mediaAssetID == mediaAssetID,
                      target.imageData?.isEmpty != false else { continue }
                summary.changed = current.applyDownloadedMedia(data, to: attachment.entityID) || summary.changed
            } catch {
                guard persistence.activeUserID == ownerUserID, !Task.isCancelled else { return summary }
                summary.deferredError = summary.deferredError ?? error
            }
        }
        if summary.changed { persistence.flush(library) }
        return summary
    }
}
