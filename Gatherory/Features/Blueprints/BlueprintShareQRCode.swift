import CoreImage
import CoreImage.CIFilterBuiltins
import CoreGraphics
import Foundation
import UIKit

/// A transient, locally rendered QR representation of an existing shared-template URL.
/// The URL is validated before it is encoded; no network or file access is performed.
nonisolated struct BlueprintShareQRCode {
    enum RenderError: Error, Equatable {
        case invalidSharedTemplateURL
        case generationFailed
    }

    static let modulePixelSize = 16
    static let quietZoneModules = 4

    let cgImage: CGImage
    let pixelSize: CGSize
    let moduleCount: Int
    let modulePixelSize: Int = Self.modulePixelSize
    let quietZoneModules: Int = Self.quietZoneModules

    var image: UIImage { UIImage(cgImage: cgImage, scale: 1, orientation: .up) }

    var pngData: Data? { image.pngData() }

    init(url: URL, baseURL: URL?) throws {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == "https",
              BlueprintSharedTemplateLink.token(from: url, baseURL: baseURL) != nil else {
            throw RenderError.invalidSharedTemplateURL
        }

        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(url.absoluteString.utf8)
        filter.correctionLevel = "M"

        guard let generated = filter.outputImage,
              generated.extent.width.isFinite,
              generated.extent.height.isFinite,
              generated.extent.width == generated.extent.height,
              generated.extent.width.rounded(.down) == generated.extent.width,
              let moduleCount = Int(exactly: generated.extent.width),
              moduleCount > 0,
              let rawQR = Self.context.createCGImage(generated, from: generated.extent) else {
            throw RenderError.generationFailed
        }

        let margin = Self.quietZoneModules * Self.modulePixelSize
        let dimension = (moduleCount + 2 * Self.quietZoneModules) * Self.modulePixelSize
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil,
                width: dimension,
                height: dimension,
                bitsPerComponent: 8,
                bytesPerRow: dimension * 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
              ) else {
            throw RenderError.generationFailed
        }

        context.setFillColor(UIColor.white.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: dimension, height: dimension))
        context.interpolationQuality = .none
        context.setShouldAntialias(false)
        context.draw(
            rawQR,
            in: CGRect(x: margin, y: margin, width: moduleCount * Self.modulePixelSize, height: moduleCount * Self.modulePixelSize)
        )

        guard let rendered = context.makeImage() else {
            throw RenderError.generationFailed
        }

        self.cgImage = rendered
        self.pixelSize = CGSize(width: dimension, height: dimension)
        self.moduleCount = moduleCount
    }

    private static let context = CIContext(options: [.useSoftwareRenderer: false])
}
