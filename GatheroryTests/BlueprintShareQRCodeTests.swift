import CoreFoundation
import CoreImage
import Foundation
import Testing
import UIKit
@testable import Gatherory

struct BlueprintShareQRCodeTests {
    private let token = String(repeating: "a1", count: 32)
    private let baseURL = URL(string: "https://app.gatherory.com")!

    @Test("QR round trips the exact validated shared-template URL")
    func exactPayloadRoundTripsThroughNativeDecoder() throws {
        let url = try #require(URL(string: "https://app.gatherory.com/templates/shared/\(token)"))
        let code = try BlueprintShareQRCode(url: url, baseURL: baseURL)

        let decoded = try decodedPayload(in: code.cgImage)
        #expect(decoded == url.absoluteString)

        let png = try #require(code.pngData)
        let exportedImage = try #require(UIImage(data: png)?.cgImage)
        let exportedPayload = try decodedPayload(in: exportedImage)
        #expect(exportedPayload == url.absoluteString)
    }

    private func decodedPayload(in cgImage: CGImage) throws -> String {
        let context = CIContext(options: [.useSoftwareRenderer: true])
        let detector = try #require(CIDetector(
            ofType: CIDetectorTypeQRCode,
            context: context,
            options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]
        ))
        let feature = try #require(detector.features(in: CIImage(cgImage: cgImage)).compactMap {
            $0 as? CIQRCodeFeature
        }.first)
        return try #require(feature.messageString)
    }

    @Test("Only a configured HTTPS shared-template URL can be rendered")
    func rejectsInvalidURLs() throws {
        for string in [
            "gatherory://template/\(token)",
            "http://app.gatherory.com/templates/shared/\(token)",
            "https://other.gatherory.com/templates/shared/\(token)",
            "https://app.gatherory.com/templates/shared/\(token)?source=qr",
            "https://app.gatherory.com/templates/shared/\(token)#fragment",
            "https://app.gatherory.com/templates/shared/\(token)/extra",
            "https://user:secret@app.gatherory.com/templates/shared/\(token)",
            "https://app.gatherory.com/templates/shared/\(String(repeating: "g", count: 64))"
        ] {
            let url = try #require(URL(string: string))
            #expect(throws: BlueprintShareQRCode.RenderError.invalidSharedTemplateURL) {
                try BlueprintShareQRCode(url: url, baseURL: baseURL)
            }
        }

        let valid = try #require(URL(string: "https://app.gatherory.com/templates/shared/\(token)"))
        #expect(throws: BlueprintShareQRCode.RenderError.invalidSharedTemplateURL) {
            try BlueprintShareQRCode(url: valid, baseURL: URL(string: "http://app.gatherory.com"))
        }
        #expect(throws: BlueprintShareQRCode.RenderError.invalidSharedTemplateURL) {
            try BlueprintShareQRCode(url: valid, baseURL: nil)
        }
    }

    @Test("Output uses integer-scaled modules, a four-module white margin, and strong contrast")
    func renderDimensionsAndContrast() throws {
        let url = try #require(URL(string: "https://app.gatherory.com/templates/shared/\(token)"))
        let code = try BlueprintShareQRCode(url: url, baseURL: baseURL)
        let margin = code.quietZoneModules * code.modulePixelSize
        let dimension = Int(code.pixelSize.width)

        #expect(code.pixelSize.width == code.pixelSize.height)
        #expect(dimension == (code.moduleCount + 2 * code.quietZoneModules) * code.modulePixelSize)
        #expect(dimension >= 800)
        #expect(code.cgImage.width == dimension)
        #expect(code.cgImage.height == dimension)
        #expect(code.cgImage.alphaInfo == .noneSkipLast)

        let bytes = try #require(code.cgImage.dataProvider?.data)
        let pixels = CFDataGetBytePtr(bytes)
        let bytesPerPixel = code.cgImage.bitsPerPixel / 8
        #expect(bytesPerPixel == 4)

        func rgb(x: Int, y: Int) -> (UInt8, UInt8, UInt8) {
            let offset = (y * dimension + x) * bytesPerPixel
            return (pixels![offset], pixels![offset + 1], pixels![offset + 2])
        }

        var quietZoneIsWhite = true
        for y in 0..<dimension {
            for x in 0..<dimension where x < margin || x >= dimension - margin || y < margin || y >= dimension - margin {
                let pixel = rgb(x: x, y: y)
                quietZoneIsWhite = quietZoneIsWhite && pixel.0 == 255 && pixel.1 == 255 && pixel.2 == 255
            }
        }
        #expect(quietZoneIsWhite)

        var hasBlack = false
        var hasWhite = false
        var interiorIsBinaryAndModuleAligned = true
        for moduleY in 0..<code.moduleCount {
            for moduleX in 0..<code.moduleCount {
                let startX = margin + moduleX * code.modulePixelSize
                let startY = margin + moduleY * code.modulePixelSize
                let moduleColor = rgb(x: startX, y: startY)
                let isBlack = moduleColor.0 == 0 && moduleColor.1 == 0 && moduleColor.2 == 0
                let isWhite = moduleColor.0 == 255 && moduleColor.1 == 255 && moduleColor.2 == 255
                hasBlack = hasBlack || isBlack
                hasWhite = hasWhite || isWhite
                interiorIsBinaryAndModuleAligned = interiorIsBinaryAndModuleAligned && (isBlack || isWhite)

                for y in startY..<(startY + code.modulePixelSize) {
                    for x in startX..<(startX + code.modulePixelSize) {
                        interiorIsBinaryAndModuleAligned = interiorIsBinaryAndModuleAligned && rgb(x: x, y: y) == moduleColor
                    }
                }
            }
        }
        #expect(interiorIsBinaryAndModuleAligned)
        #expect(hasBlack)
        #expect(hasWhite)
    }
}
