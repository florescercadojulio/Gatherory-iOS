import CoreGraphics
import UIKit
import XCTest

final class IdeaArtworkBleedUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testIdeaDetailArtworkReachesSafeAreasFromIdeasAndDecide() throws {
        for appearance in ["Light", "Dark"] {
            for entryPoint in ["Ideas", "Decide"] {
                let app = fixtureApplication(appearance: appearance)
                app.launch()
                defer { app.terminate() }

                let workspace = app.buttons.matching(
                    NSPredicate(format: "label CONTAINS %@", "Maya’s Birthday Dinner")
                ).firstMatch
                XCTAssertTrue(workspace.waitForExistence(timeout: 8), "The birthday workspace fixture should be available.")
                workspace.tap()

                let entryControl = app.buttons.matching(identifier: entryPoint).firstMatch
                XCTAssertTrue(
                    entryControl.waitForExistence(timeout: 5),
                    "The \(entryPoint) workspace control should be available. Accessibility tree: \(app.debugDescription)"
                )
                entryControl.tap()

                let idea: XCUIElement
                if entryPoint == "Ideas" {
                    idea = app.buttons.matching(
                        NSPredicate(format: "label CONTAINS %@", "Candlelit birthday table")
                    ).firstMatch
                    XCTAssertTrue(idea.waitForExistence(timeout: 8), "The image-backed birthday idea should appear in Ideas.")
                    let ideasScroll = app.scrollViews.firstMatch
                    for _ in 0..<8 where !idea.isHittable { ideasScroll.swipeUp() }
                } else {
                    let candlelitIdea = app.buttons.matching(
                        NSPredicate(format: "label CONTAINS %@", "Candlelit birthday table")
                    ).firstMatch
                    if candlelitIdea.waitForExistence(timeout: 3), candlelitIdea.isHittable {
                        idea = candlelitIdea
                    } else {
                        // The fixture's unanswered image ideas still provide a stable detail source;
                        // opening the current card avoids changing any decision state.
                        idea = app.buttons.matching(
                            NSPredicate(format: "identifier BEGINSWITH %@", "decision-card-")
                        ).firstMatch
                        XCTAssertTrue(idea.waitForExistence(timeout: 5), "Decide should show its current fixture idea.")
                    }
                }
                XCTAssertTrue(idea.isHittable, "The seeded idea should be reachable without changing its status.")
                idea.tap()

                XCTAssertTrue(app.buttons["Edit idea"].waitForExistence(timeout: 8),
                              "The native idea detail should open from \(entryPoint).")
                try assertSafeAreaArtwork(in: app, entryPoint: entryPoint, appearance: appearance, position: "top")

                let detailScroll = app.scrollViews.firstMatch
                XCTAssertTrue(detailScroll.waitForExistence(timeout: 5), "The idea detail should retain its scrollable content.")
                detailScroll.swipeUp()
                try assertSafeAreaArtwork(in: app, entryPoint: entryPoint, appearance: appearance, position: "scrolled")
            }
        }
    }

    @MainActor
    private func fixtureApplication(appearance: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-DisableProductionFlowSimulation",
            "-SkipAuthentication",
            "-SeedDevelopmentData",
            "-UseEphemeralDataStore",
            "-UseBirthdayMarketingFixture",
            "-UseProductionOnboarding",
            "-hasSeenDecideTimelinePrimer", "YES",
            "-AppleLanguages", "(en)",
            "-AppleInterfaceStyle", appearance,
            "-appAppearance", appearance.lowercased()
        ]
        return app
    }

    @MainActor
    private func assertSafeAreaArtwork(
        in app: XCUIApplication,
        entryPoint: String,
        appearance: String,
        position: String
    ) throws {
        let screenshot = app.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "Idea full-bleed artwork — \(entryPoint), \(appearance), \(position)"
        attachment.lifetime = .keepAlways
        add(attachment)

        let pixels = try rgbaPixels(from: screenshot.image)
        let topSafeArea = nonBlackPixelFraction(
            in: CGRect(x: 0.05, y: 0.005, width: 0.10, height: 0.02),
            pixels: pixels
        )
        let bottomSafeArea = nonBlackPixelFraction(
            in: CGRect(x: 0.02, y: 0.965, width: 0.06, height: 0.015),
            pixels: pixels
        )
        XCTAssertGreaterThan(
            topSafeArea,
            0.25,
            "Idea artwork should fill the status-area strip from \(entryPoint) at \(position), \(appearance); nonblack fraction: \(topSafeArea)."
        )
        XCTAssertGreaterThan(
            bottomSafeArea,
            0.25,
            "Idea artwork should fill the bottom safe-area strip from \(entryPoint) at \(position), \(appearance); nonblack fraction: \(bottomSafeArea)."
        )
    }

    private func rgbaPixels(from image: UIImage) throws -> (width: Int, height: Int, bytes: [UInt8]) {
        guard let cgImage = image.cgImage else {
            throw NSError(domain: "IdeaArtworkBleedUITests", code: 1, userInfo: [
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
            throw NSError(domain: "IdeaArtworkBleedUITests", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "The UI screenshot could not be normalized to RGBA pixels."
            ])
        }
        return (width, height, bytes)
    }

    private func nonBlackPixelFraction(
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
