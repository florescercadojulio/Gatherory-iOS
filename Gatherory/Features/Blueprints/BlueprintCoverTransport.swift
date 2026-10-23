import Foundation

struct BlueprintCoverSource: Equatable, Sendable {
    let catalogKey: String
    let revision: Int
    let shareToken: String?

    init(catalogKey: String, revision: Int, shareToken: String? = nil) {
        self.catalogKey = catalogKey
        self.revision = revision
        self.shareToken = shareToken
    }
}

enum BlueprintCoverTransportFailure: LocalizedError {
    case invalidSession
    case invalidResponse
    case server(String)

    var errorDescription: String? {
        switch self {
        case .invalidSession: BlueprintCoverCopy.signInRequired
        case .invalidResponse: BlueprintCoverCopy.invalidResponse
        case .server(let message): message
        }
    }
}

struct BlueprintCoverTransport: Sendable {
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

    func upload(data: Data, mediaAssetID: UUID) async throws -> UUID {
        try Task.checkCancellation()
        guard !data.isEmpty, data.count <= CoverImagePreparation.maximumInputBytes else {
            throw BlueprintCoverTransportFailure.invalidResponse
        }

        let prepared: UploadReceipt
        do {
            prepared = try await post(
                action: "prepare",
                body: PrepareRequest(
                    mediaAssetId: mediaAssetID,
                    contentType: "image/jpeg",
                    byteSize: data.count,
                    originalFilename: "cover.jpg"
                ),
                requiresAuthentication: true
            )
        } catch {
            try Task.checkCancellation()
            // Finalize may have succeeded even if its response was lost. Treat
            // an already-ready asset with this id as a successful retry.
            let ready: UrlReceipt? = try? await post(
                action: "url",
                body: UrlRequest(
                    mediaAssetId: mediaAssetID,
                    catalogKey: nil,
                    revision: nil,
                    shareToken: nil,
                    variant: "hero"
                ),
                requiresAuthentication: true
            )
            if ready?.mediaAssetId == mediaAssetID { return mediaAssetID }
            throw error
        }
        try Task.checkCancellation()
        guard prepared.mediaAssetId == mediaAssetID,
              prepared.method == "PUT",
              let uploadURL = URL(string: prepared.uploadUrl),
              uploadURL.scheme == "https" else {
            throw BlueprintCoverTransportFailure.invalidResponse
        }

        var uploadRequest = URLRequest(url: uploadURL)
        uploadRequest.httpMethod = prepared.method
        for (name, value) in prepared.requiredHeaders {
            uploadRequest.setValue(value, forHTTPHeaderField: name)
        }
        let (_, uploadResponse) = try await urlSession.upload(for: uploadRequest, from: data)
        try Task.checkCancellation()
        guard let httpResponse = uploadResponse as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw BlueprintCoverTransportFailure.server(BlueprintCoverCopy.uploadFailed)
        }

        let finalized: ReadyReceipt = try await post(
            action: "finalize",
            body: AssetRequest(mediaAssetId: mediaAssetID),
            requiresAuthentication: true
        )
        try Task.checkCancellation()
        guard finalized.mediaAssetId == mediaAssetID, finalized.status == "ready" else {
            throw BlueprintCoverTransportFailure.invalidResponse
        }
        return finalized.mediaAssetId
    }

    func download(
        mediaAssetID: UUID,
        source: BlueprintCoverSource?,
        variant: String = "hero"
    ) async throws -> Data {
        try Task.checkCancellation()
        let receipt: UrlReceipt = try await post(
            action: "url",
            body: UrlRequest(
                mediaAssetId: mediaAssetID,
                catalogKey: source?.catalogKey,
                revision: source?.revision,
                shareToken: source?.shareToken,
                variant: variant
            ),
            // Catalog and share reads are authorized by their exact source
            // revision/token and work for signed-out viewers.
            requiresAuthentication: source?.catalogKey == nil
        )
        try Task.checkCancellation()
        guard receipt.mediaAssetId == mediaAssetID,
              receipt.variant == variant,
              let downloadURL = URL(string: receipt.url),
              downloadURL.scheme == "https" else {
            throw BlueprintCoverTransportFailure.invalidResponse
        }

        let (data, response) = try await urlSession.data(from: downloadURL)
        try Task.checkCancellation()
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode),
              !data.isEmpty else {
            throw BlueprintCoverTransportFailure.server(BlueprintCoverCopy.loadFailed)
        }
        return data
    }

    private func post<Body: Encodable, Response: Decodable>(
        action: String,
        body: Body,
        requiresAuthentication: Bool
    ) async throws -> Response {
        try Task.checkCancellation()
        let endpoint = ["api", "blueprints", "media", action].reduce(baseURL) { $0.appending(path: $1) }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.httpBody = try encoder.encode(body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(UUID().uuidString, forHTTPHeaderField: "X-Request-ID")

        if requiresAuthentication {
            guard let token = try tokenStore.read(), !token.isEmpty else {
                throw BlueprintCoverTransportFailure.invalidSession
            }
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        } else {
            do {
                if let token = try tokenStore.read(), !token.isEmpty {
                    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                }
            } catch {
                // A share token is sufficient for public blueprint cover access.
            }
        }

        let (data, rawResponse) = try await urlSession.data(for: request)
        try Task.checkCancellation()
        guard let response = rawResponse as? HTTPURLResponse else {
            throw BlueprintCoverTransportFailure.invalidResponse
        }
        guard (200..<300).contains(response.statusCode) else {
            if response.statusCode == 401 { throw BlueprintCoverTransportFailure.invalidSession }
            let errorEnvelope = try? decoder.decode(ServerResult<EmptyPayload>.self, from: data)
            throw BlueprintCoverTransportFailure.server(
                errorEnvelope?.error?.userMessage ?? BlueprintCoverCopy.requestFailed
            )
        }

        let envelope: ServerResult<Response>
        do { envelope = try decoder.decode(ServerResult<Response>.self, from: data) }
        catch { throw BlueprintCoverTransportFailure.invalidResponse }
        guard envelope.ok, let value = envelope.data else {
            throw BlueprintCoverTransportFailure.server(
                envelope.error?.userMessage ?? BlueprintCoverCopy.requestFailed
            )
        }
        return value
    }

    private struct PrepareRequest: Encodable {
        let mediaAssetId: UUID
        let contentType: String
        let byteSize: Int
        let originalFilename: String
    }

    private struct AssetRequest: Encodable {
        let mediaAssetId: UUID
    }

    private struct UrlRequest: Encodable {
        let mediaAssetId: UUID
        let catalogKey: String?
        let revision: Int?
        let shareToken: String?
        let variant: String
    }

    private struct UploadReceipt: Decodable {
        let mediaAssetId: UUID
        let uploadUrl: String
        let method: String
        let requiredHeaders: [String: String]
    }

    private struct ReadyReceipt: Decodable {
        let mediaAssetId: UUID
        let status: String
    }

    private struct UrlReceipt: Decodable {
        let mediaAssetId: UUID
        let url: String
        let variant: String
    }

    private struct EmptyPayload: Decodable {}

    private struct ServerResult<Value: Decodable>: Decodable {
        let ok: Bool
        let data: Value?
        let error: ServerResultError?
    }

    private struct ServerResultError: Decodable {
        let userMessage: String
    }
}
