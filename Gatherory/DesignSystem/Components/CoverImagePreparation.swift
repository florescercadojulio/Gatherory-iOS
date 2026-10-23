import ImageIO
import UIKit

/// Normalizes picked images to bounded, orientation-correct JPEGs without changing their framing.
nonisolated enum CoverImagePreparation {
    static let maximumInputBytes = 20 * 1024 * 1024
    static let maximumDimension = 2_000

    static func normalizeJPEG(_ data: Data) -> Data? {
        guard data.count <= maximumInputBytes,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(
                source,
                0,
                [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: maximumDimension,
                    kCGImageSourceShouldCacheImmediately: true,
                ] as CFDictionary
              )
        else { return nil }

        let normalized = UIImage(cgImage: image, scale: 1, orientation: .up)
        return normalized.jpegData(compressionQuality: 0.88)
    }
}
