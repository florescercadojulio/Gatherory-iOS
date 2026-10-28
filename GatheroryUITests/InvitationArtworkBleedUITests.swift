import XCTest
import UIKit
import CoreGraphics

final class InvitationArtworkBleedUITests: XCTestCase {
    @MainActor
    func testHomeInvitationArtworkReachesSafeAreasInCardsAndOverview() throws {
        for appearance in ["Light", "Dark"] {
            for layout in ["Cards", "Overview"] {
                let app = XCUIApplication()
                app.launchArguments = [
                    "-DisableProductionFlowSimulation",
                    "-SkipAuthentication",
                    "-SeedDevelopmentData",
                    "-UseEphemeralDataStore",
                    "-UseBirthdayMarketingFixture",
                    "-UseProductionOnboarding",
                    "-AppleLanguages", "(en)",
                    "-AppleInterfaceStyle", appearance,
                    "-appAppearance", appearance.lowercased()
                ]
                app.launch()
                defer { app.terminate() }

                let workspace = app.buttons.matching(
                    NSPredicate(format: "label CONTAINS %@", "Maya’s Birthday Dinner")
                ).firstMatch
                XCTAssertTrue(workspace.waitForExistence(timeout: 8), "The birthday cover fixture should be available.")
                workspace.tap()

                HomeLayoutUITestSupport.select(layout, in: app)

                let mainEvent: XCUIElement = layout == "Cards"
                    ? app.buttons["home.event.main"]
                    : app.descendants(matching: .any)["home.overview.mainEvent"]
                XCTAssertTrue(mainEvent.waitForExistence(timeout: 5), "The main event should be visible in \(layout).")
                mainEvent.tap()
                XCTAssertTrue(app.navigationBars["Invitation"].waitForExistence(timeout: 8))

                let screenshot = waitForArtworkInSafeAreas(app)
                let pixels = try rgbaPixels(from: screenshot.image)
                let topSafeArea = Self.nonBlackPixelFraction(
                    in: CGRect(x: 0.05, y: 0.005, width: 0.10, height: 0.02),
                    pixels: pixels
                )
                let bottomSafeArea = Self.nonBlackPixelFraction(
                    in: CGRect(x: 0.02, y: 0.965, width: 0.06, height: 0.015),
                    pixels: pixels
                )
                XCTAssertGreaterThan(
                    topSafeArea,
                    0.25,
                    "Invitation artwork should fill the status-area strip in \(layout), \(appearance); nonblack fraction: \(topSafeArea)."
                )
                XCTAssertGreaterThan(
                    bottomSafeArea,
                    0.25,
                    "Invitation artwork should fill the bottom safe-area strip in \(layout), \(appearance); nonblack fraction: \(bottomSafeArea)."
                )

                let attachment = XCTAttachment(screenshot: screenshot)
                attachment.name = "Invitation full-bleed artwork — \(layout), \(appearance)"
                attachment.lifetime = .keepAlways
                add(attachment)
            }
        }
    }

    @MainActor
    private func waitForArtworkInSafeAreas(_ app: XCUIApplication) -> XCUIScreenshot {
        let deadline = Date(timeIntervalSinceNow: 10)
        var screenshot = app.screenshot()
        while Date() < deadline {
            guard let pixels = try? rgbaPixels(from: screenshot.image) else { return screenshot }
            if Self.nonBlackPixelFraction(
                in: CGRect(x: 0.05, y: 0.005, width: 0.10, height: 0.02),
                pixels: pixels
            ) > 0.25,
               Self.nonBlackPixelFraction(
                in: CGRect(x: 0.02, y: 0.965, width: 0.06, height: 0.015),
                pixels: pixels
               ) > 0.25 {
                return screenshot
            }
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.25))
            screenshot = app.screenshot()
        }
        return screenshot
    }

    private func rgbaPixels(from image: UIImage) throws -> (width: Int, height: Int, bytes: [UInt8]) {
        guard let cgImage = image.cgImage else {
            throw NSError(domain: "InvitationArtworkBleedUITests", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "The UI screenshot did not contain a CGImage."
            ])
        }

        let width = cgImage.width
        let height = cgImage.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let didRender = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let baseAddress = buffer.baseAddress,
                  let context = CGContext(
                    data: baseAddress,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: width * 4,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
                  ) else { return false }
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard didRender else {
            throw NSError(domain: "InvitationArtworkBleedUITests", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "The UI screenshot could not be normalized to RGBA pixels."
            ])
        }
        return (width, height, bytes)
    }

    private static func nonBlackPixelFraction(
        in normalizedRect: CGRect,
        pixels: (width: Int, height: Int, bytes: [UInt8])
    ) -> Double {
        let minX = max(0, Int(normalizedRect.minX * CGFloat(pixels.width)))
        let maxX = min(pixels.width, Int(normalizedRect.maxX * CGFloat(pixels.width)))
        let minY = max(0, Int(normalizedRect.minY * CGFloat(pixels.height)))
        let maxY = min(pixels.height, Int(normalizedRect.maxY * CGFloat(pixels.height)))
        var sampled = 0
        var nonBlack = 0

        for y in minY..<maxY {
            for x in minX..<maxX {
                let offset = (y * pixels.width + x) * 4
                sampled += 1
                if pixels.bytes[offset] > 3 || pixels.bytes[offset + 1] > 3 || pixels.bytes[offset + 2] > 3 {
                    nonBlack += 1
                }
            }
        }

        return sampled == 0 ? 0 : Double(nonBlack) / Double(sampled)
    }
}
