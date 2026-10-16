import Foundation
import ImageIO
import Observation
import Photos

enum AlbumSaveResult: Equatable {
    case saved(Int)
    case permissionDenied
    case invalidImage
    case failed
}

/// Adds only the photos explicitly chosen in Gatherory; never reads the user's library.
@MainActor @Observable
final class AlbumPhotoSaver {
    private(set) var isSaving = false

    @ObservationIgnored private let authorizationStatus: (PHAccessLevel) -> PHAuthorizationStatus
    @ObservationIgnored private let requestAuthorization: (PHAccessLevel) async -> PHAuthorizationStatus
    @ObservationIgnored private let writeImages: ([Data]) async throws -> Void

    init(
        authorizationStatus: @escaping (PHAccessLevel) -> PHAuthorizationStatus = {
            PHPhotoLibrary.authorizationStatus(for: $0)
        },
        requestAuthorization: @escaping (PHAccessLevel) async -> PHAuthorizationStatus = {
            await PHPhotoLibrary.requestAuthorization(for: $0)
        },
        writeImages: @escaping ([Data]) async throws -> Void = { images in
            // One transaction means an error cannot leave an unknown, partially saved batch.
            try await PHPhotoLibrary.shared().performChanges {
                for data in images {
                    PHAssetCreationRequest.forAsset().addResource(with: .photo, data: data, options: nil)
                }
            }
        }
    ) {
        self.authorizationStatus = authorizationStatus
        self.requestAuthorization = requestAuthorization
        self.writeImages = writeImages
    }

    func save(_ moments: [EventMoment]) async -> AlbumSaveResult {
        guard !isSaving else { return .failed }
        guard !moments.isEmpty else { return .saved(0) }
        isSaving = true
        defer { isSaving = false }

        // Selection is an ordered set of moment IDs. Avoid duplicate assets even if a
        // caller accidentally supplies the same selected moment more than once.
        var seen: Set<UUID> = []
        let images = moments.filter { seen.insert($0.id).inserted }.map(\.imageData)
        let valid = await Task.detached(priority: .userInitiated) {
            images.allSatisfy(Self.isDecodableImage)
        }.value
        guard valid else { return .invalidImage }
        guard !Task.isCancelled else { return .failed }

        var status = authorizationStatus(.addOnly)
        if status == .notDetermined {
            status = await requestAuthorization(.addOnly)
        }
        guard status == .authorized || status == .limited else { return .permissionDenied }
        guard !Task.isCancelled else { return .failed }

        do {
            // Preserve the stored bytes, orientation and image metadata without re-encoding.
            try await writeImages(images)
            return .saved(images.count)
        } catch {
            return .failed
        }
    }

    nonisolated private static func isDecodableImage(_ data: Data) -> Bool {
        guard !data.isEmpty,
              let source = CGImageSourceCreateWithData(data as CFData, [
                kCGImageSourceShouldCache: false
              ] as CFDictionary),
              CGImageSourceGetCount(source) > 0,
              CGImageSourceGetStatus(source) == .statusComplete else { return false }

        // A bounded decode catches corrupt resources without allocating a full-size
        // bitmap for every selected original. Validation runs away from the UI actor.
        return CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 16,
            kCGImageSourceShouldCacheImmediately: true
        ] as CFDictionary) != nil
    }
}
