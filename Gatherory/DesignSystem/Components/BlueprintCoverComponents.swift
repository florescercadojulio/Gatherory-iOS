import CryptoKit
import ImageIO
import SwiftUI
import UIKit

private struct BlueprintCoverSourceEnvironmentKey: EnvironmentKey {
    static let defaultValue: BlueprintCoverSource? = nil
}

extension EnvironmentValues {
    var blueprintCoverSource: BlueprintCoverSource? {
        get { self[BlueprintCoverSourceEnvironmentKey.self] }
        set { self[BlueprintCoverSourceEnvironmentKey.self] = newValue }
    }
}

extension View {
    func blueprintCoverSource(_ source: BlueprintCoverSource?) -> some View {
        environment(\.blueprintCoverSource, source)
    }
}

@MainActor
private enum BlueprintCoverImageCache {
    private static let images: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 24
        cache.totalCostLimit = 48 * 1_024 * 1_024
        return cache
    }()

    static func image(for key: String) -> UIImage? {
        images.object(forKey: key as NSString)
    }

    static func insert(_ image: UIImage, for key: String) {
        let cost = image.cgImage.map { $0.bytesPerRow * $0.height } ?? 0
        images.setObject(image, forKey: key as NSString, cost: cost)
    }
}

struct BlueprintCoverArtwork<Fallback: View>: View {
    let assetID: UUID?
    let publicImageURL: String?
    private let explicitSource: BlueprintCoverSource?
    private let onAspectRatioChange: ((CGFloat?) -> Void)?
    private let fallback: () -> Fallback

    @Environment(\.blueprintCoverSource) private var environmentSource
    @Environment(\.currentUserAccount) private var account
    @State private var image: UIImage?

    init(
        assetID: UUID?,
        publicImageURL: String? = nil,
        source: BlueprintCoverSource? = nil,
        onAspectRatioChange: ((CGFloat?) -> Void)? = nil,
        @ViewBuilder fallback: @escaping () -> Fallback
    ) {
        self.assetID = assetID
        self.publicImageURL = publicImageURL
        self.explicitSource = source
        self.onAspectRatioChange = onAspectRatioChange
        self.fallback = fallback
    }

    private var source: BlueprintCoverSource? { explicitSource ?? environmentSource }
    private var requestID: String {
        let components = [
            assetID?.uuidString ?? "none",
            publicImageURL ?? "",
            source?.catalogKey ?? "",
            String(source?.revision ?? 0),
            source?.shareToken ?? "",
            account?.id ?? "",
        ]
        let keyMaterial = Data(components.map { "\($0.utf8.count):\($0)" }.joined().utf8)
        return SHA256.hash(data: keyMaterial)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    var body: some View {
        GeometryReader { geometry in
            let size = LayoutDimensions.size(geometry.size)
            Group {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: size.width, height: size.height)
                        .clipped()
                        .overlay(alignment: .bottom) {
                            LinearGradient(
                                colors: [.clear, .black.opacity(0.32)],
                                startPoint: .center,
                                endPoint: .bottom
                            )
                            .frame(height: min(72, size.height))
                            .accessibilityHidden(true)
                        }
                        .accessibilityLabel(BlueprintCoverCopy.title)
                } else {
                    fallback()
                        .frame(width: size.width, height: size.height)
                        .clipped()
                }
            }
        }
        .task(id: requestID) {
            image = nil
            onAspectRatioChange?(nil)
            let publicURL = BlueprintPublicCoverURL.validated(publicImageURL)
            guard assetID != nil || publicURL != nil else {
                return
            }
            if let cachedImage = BlueprintCoverImageCache.image(for: requestID) {
                image = cachedImage
                reportAspectRatio(of: cachedImage)
                return
            }
            let expectedAccountID = account?.id
            do {
                var loadedImage: UIImage?
                if let assetID, let baseURL = AppRuntimeConfiguration.authenticationBaseURL {
                    // The private authorized cover remains the preferred source.
                    // A failed private read may fall back only to the separately
                    // pinned public curated card URL.
                    if let data = try? await BlueprintCoverTransport(baseURL: baseURL).download(
                        mediaAssetID: assetID,
                        source: source
                    ) {
                        loadedImage = UIImage(data: data)
                    }
                }
                guard !Task.isCancelled else { return }
                if loadedImage == nil, let publicURL {
                    let downloadTask = Task.detached(priority: .utility) {
                        try await BlueprintPublicCoverLoader.download(from: publicURL)
                    }
                    let decodedImage = try await withTaskCancellationHandler {
                        try await downloadTask.value
                    } onCancel: {
                        downloadTask.cancel()
                    }
                    loadedImage = decodedImage?.image
                }
                guard !Task.isCancelled,
                      account?.id == expectedAccountID,
                      let loadedImage else { return }
                BlueprintCoverImageCache.insert(loadedImage, for: requestID)
                image = loadedImage
                reportAspectRatio(of: loadedImage)
            } catch {
                guard !Task.isCancelled, account?.id == expectedAccountID else { return }
                image = nil
            }
        }
    }

    private func reportAspectRatio(of image: UIImage) {
        let size = image.size
        guard size.width.isFinite, size.height.isFinite,
              size.width > 0, size.height > 0 else { return }
        onAspectRatioChange?(size.width / size.height)
    }

}

private nonisolated struct SendableBlueprintCoverImage: @unchecked Sendable {
    let image: UIImage
}

private nonisolated final class BlueprintPublicCoverSessionDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

private nonisolated enum BlueprintPublicCoverLoader {
    static func download(from url: URL) async throws -> SendableBlueprintCoverImage? {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        request.setValue("image/jpeg", forHTTPHeaderField: "Accept")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.urlCache = URLCache(memoryCapacity: 8 * 1_024 * 1_024, diskCapacity: 0)
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        let session = URLSession(
            configuration: configuration,
            delegate: BlueprintPublicCoverSessionDelegate(),
            delegateQueue: nil
        )
        defer { session.invalidateAndCancel() }
        let (bytes, response) = try await session.bytes(for: request)
        guard let response = response as? HTTPURLResponse,
              (200..<300).contains(response.statusCode),
              response.url == url,
              response.mimeType == "image/jpeg",
              response.expectedContentLength <= 6 * 1_024 * 1_024 || response.expectedContentLength < 0 else {
            return nil
        }
        var data = Data()
        if response.expectedContentLength > 0 {
            data.reserveCapacity(Int(response.expectedContentLength))
        }
        for try await byte in bytes {
            guard data.count < 6 * 1_024 * 1_024 else { return nil }
            data.append(byte)
        }
        guard
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(
                source,
                0,
                [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceShouldCacheImmediately: true,
                    kCGImageSourceThumbnailMaxPixelSize: 1_600,
                ] as CFDictionary
              ) else { return nil }
        return SendableBlueprintCoverImage(image: UIImage(cgImage: cgImage))
    }
}

/// Copies only immutable, public Explore artwork through the same bounded,
/// redirect-free loader used by catalog cards. No session is sent to the CDN.
nonisolated enum BlueprintIdeaPublicImage {
    static func data(from value: String) async throws -> Data {
        guard let url = BlueprintPublicCoverURL.validated(value),
              let loaded = try await BlueprintPublicCoverLoader.download(from: url),
              let data = loaded.image.jpegData(compressionQuality: 0.86) else {
            throw BlueprintCoverTransportFailure.invalidResponse
        }
        try Task.checkCancellation()
        return data
    }
}

nonisolated enum BlueprintPublicCoverURL {
    static func validated(_ value: String?) -> URL? {
        guard let value,
              let components = URLComponents(string: value),
              components.scheme == "https",
              components.host == "cdn.gatherory.com",
              components.port == nil,
              components.user == nil,
              components.password == nil,
              components.query == nil,
              components.fragment == nil else { return nil }
        let segments = components.path.split(separator: "/", omittingEmptySubsequences: false)
        guard segments.count == 6,
              segments[1] == "explore",
              segments[2] == "covers",
              segments[3].description.range(of: "^[a-z0-9]+(?:-[a-z0-9]+)*$", options: .regularExpression) != nil,
              segments[4].description.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil,
              segments[5] == "card.jpg" else { return nil }
        return components.url
    }
}

struct BlueprintCoverField: View {
    @Binding var assetID: UUID?
    let source: BlueprintCoverSource?
    @Binding var isUploading: Bool
    var publicImageURL: String? = nil
    var onCoverRemoved: (() -> Void)? = nil

    @Environment(\.currentUserAccount) private var account
    @State private var selectedImageData: Data?
    @State private var pendingImageData: Data?
    @State private var pendingAssetID: UUID?
    @State private var uploadFailure: String?
    @State private var requestGeneration = UUID()
    @State private var uploadTask: Task<Void, Never>?

    static func shouldOfferRemoval(assetID: UUID?, hasPendingImage: Bool, publicImageURL: String?) -> Bool {
        assetID != nil || hasPendingImage || BlueprintPublicCoverURL.validated(publicImageURL) != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.standard) {
            BlueprintCoverArtwork(assetID: assetID, publicImageURL: publicImageURL, source: source) {
                ContentUnavailableView(
                    BlueprintCoverCopy.title,
                    systemImage: "photo",
                    description: Text(BlueprintCoverCopy.placeholder)
                )
                .frame(maxWidth: .infinity)
                .frame(height: 200)
                .background(AppTheme.ColorToken.elevatedSurface)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 200)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous))

            PhotoAttachmentPicker(
                imageData: $selectedImageData,
                emptySymbol: "photo",
                showsPreview: false,
                suggestedConcept: "Blueprint cover artwork",
                showsExistingImage: assetID != nil || BlueprintPublicCoverURL.validated(publicImageURL) != nil
            )

            if let uploadFailure {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.compact) {
                    Label(uploadFailure, systemImage: "exclamationmark.circle.fill")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.ColorToken.destructive)
                        .fixedSize(horizontal: false, vertical: true)
                    Button(BlueprintCoverCopy.retry, systemImage: "arrow.clockwise") {
                        retryUpload()
                    }
                    .frame(minHeight: AppTheme.Layout.minimumTouchTarget)
                }
                .accessibilityElement(children: .contain)
            } else if isUploading {
                HStack(spacing: AppTheme.Spacing.compact) {
                    ProgressView()
                    Text(BlueprintCoverCopy.uploading)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            if Self.shouldOfferRemoval(assetID: assetID, hasPendingImage: pendingImageData != nil,
                                       publicImageURL: publicImageURL) {
                Button(
                    uploadFailure == nil ? BlueprintCoverCopy.remove : BlueprintCoverCopy.discardPending,
                    systemImage: uploadFailure == nil ? "trash" : "xmark.circle",
                    role: .destructive
                ) {
                    if uploadFailure == nil {
                        removeCover()
                    } else {
                        discardPendingImage()
                    }
                }
                .frame(minHeight: AppTheme.Layout.minimumTouchTarget)
            }
        }
        .onChange(of: selectedImageData) { _, newValue in
            guard let newValue else { return }
            startUpload(newValue, mediaAssetID: UUID())
        }
        .onChange(of: account?.id) { _, _ in
            invalidateUpload(clearSelection: true)
        }
        .onDisappear {
            invalidateUpload(clearSelection: true)
        }
    }

    private func retryUpload() {
        guard let pendingImageData, let pendingAssetID else { return }
        startUpload(pendingImageData, mediaAssetID: pendingAssetID)
    }

    private func removeCover() {
        invalidateUpload(clearSelection: true)
        assetID = nil
        onCoverRemoved?()
    }

    private func discardPendingImage() {
        requestGeneration = UUID()
        uploadTask?.cancel()
        uploadTask = nil
        selectedImageData = nil
        pendingImageData = nil
        pendingAssetID = nil
        uploadFailure = nil
        isUploading = false
    }

    private func startUpload(_ data: Data, mediaAssetID: UUID) {
        uploadTask?.cancel()
        let generation = UUID()
        requestGeneration = generation
        pendingImageData = data
        pendingAssetID = mediaAssetID
        uploadFailure = nil
        isUploading = true

        guard let accountID = account?.id, !accountID.isEmpty,
              let baseURL = AppRuntimeConfiguration.authenticationBaseURL else {
            uploadFailure = BlueprintCoverCopy.signInRequired
            return
        }

        uploadTask = Task { @MainActor in
            do {
                guard account?.id == accountID,
                      requestGeneration == generation else { return }
                let uploadedAssetID = try await BlueprintCoverTransport(baseURL: baseURL).upload(
                    data: data,
                    mediaAssetID: mediaAssetID
                )
                try Task.checkCancellation()
                guard account?.id == accountID,
                      requestGeneration == generation else { return }
                assetID = uploadedAssetID
                pendingImageData = nil
                pendingAssetID = nil
                selectedImageData = nil
                uploadFailure = nil
                isUploading = false
            } catch {
                guard !Task.isCancelled,
                      account?.id == accountID,
                      requestGeneration == generation else { return }
                uploadFailure = (error as? LocalizedError)?.errorDescription ?? BlueprintCoverCopy.uploadFailed
                // Keep the draft locked until retry succeeds or the editor is dismissed.
                isUploading = true
            }
        }
    }

    private func invalidateUpload(clearSelection: Bool) {
        requestGeneration = UUID()
        uploadTask?.cancel()
        uploadTask = nil
        if clearSelection {
            selectedImageData = nil
            pendingImageData = nil
            pendingAssetID = nil
            uploadFailure = nil
            isUploading = false
        }
    }
}

struct BlueprintCoverEditor: View {
    let source: BlueprintCoverSource?
    let onSave: (UUID?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var assetID: UUID?
    @State private var isUploading = false

    init(assetID: UUID?, source: BlueprintCoverSource?, onSave: @escaping (UUID?) -> Void) {
        self.source = source
        self.onSave = onSave
        _assetID = State(initialValue: assetID)
    }

    var body: some View {
        Form {
            Section(BlueprintCoverCopy.title) {
                BlueprintCoverField(
                    assetID: $assetID,
                    source: source,
                    isUploading: $isUploading
                )
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppTheme.ColorToken.background)
        .navigationTitle(BlueprintCoverCopy.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(BlueprintCoverCopy.cancel) { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(BlueprintCoverCopy.save, systemImage: "checkmark") {
                    onSave(assetID)
                    dismiss()
                }
                .labelStyle(.iconOnly)
                .disabled(isUploading)
                .accessibilityLabel(BlueprintCoverCopy.save)
            }
        }
    }
}
