import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Produces an upload-only copy. The durable outbox original stays available for retries.
nonisolated struct PreparedUploadImage: Sendable {
    let fileURL: URL
    let contentType: String
    let byteSize: Int

    func removeTemporaryFile() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}

nonisolated enum UploadImagePreparation {
    static let maximumPixelSize = 2_560
    static let targetByteSize = 5 * 1_024 * 1_024

    static func prepare(sourceURL: URL) throws -> PreparedUploadImage {
        try Task.checkCancellation()
        guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, [
            kCGImageSourceShouldCache: false
        ] as CFDictionary),
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
        let width = properties[kCGImagePropertyPixelWidth] as? Int,
        let height = properties[kCGImagePropertyPixelHeight] as? Int,
        width > 0, height > 0 else { throw MediaSyncFailure.invalidImage }

        // Preserve transparent artwork instead of flattening it onto a JPEG background.
        let hasAlpha = properties[kCGImagePropertyHasAlpha] as? Bool ?? false
        let type = hasAlpha ? UTType.png : UTType.jpeg
        var pixelLimit = min(maximumPixelSize, max(width, height))
        while true {
            try Task.checkCancellation()
            guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: pixelLimit,
                kCGImageSourceShouldCacheImmediately: true
            ] as CFDictionary) else { throw MediaSyncFailure.invalidImage }

            for quality in hasAlpha ? [1.0] : [0.86, 0.76, 0.66] {
                try Task.checkCancellation()
                let output = NSMutableData()
                guard let destination = CGImageDestinationCreateWithData(output, type.identifier as CFString, 1, nil)
                else { throw MediaSyncFailure.invalidImage }
                // No source metadata is copied; orientation is baked into the thumbnail.
                CGImageDestinationAddImage(destination, image, [
                    kCGImageDestinationLossyCompressionQuality: quality
                ] as CFDictionary)
                guard CGImageDestinationFinalize(destination) else { throw MediaSyncFailure.invalidImage }
                guard output.length <= targetByteSize else { continue }
                let url = FileManager.default.temporaryDirectory
                    .appendingPathComponent("gatherory-upload-\(UUID().uuidString)")
                    .appendingPathExtension(hasAlpha ? "png" : "jpg")
                do {
                    try (output as Data).write(to: url, options: .atomic)
                    try Task.checkCancellation()
                    return PreparedUploadImage(fileURL: url, contentType: hasAlpha ? "image/png" : "image/jpeg", byteSize: output.length)
                } catch {
                    try? FileManager.default.removeItem(at: url)
                    throw error
                }
            }

            // No fixed quality setting guarantees a file size. Reduce dimensions if needed.
            guard pixelLimit > 640 else { throw MediaSyncFailure.imageTooLarge }
            pixelLimit = max(640, Int(Double(pixelLimit) * 0.75))
        }
    }
}
