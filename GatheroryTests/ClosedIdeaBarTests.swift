import SwiftUI
import Testing
import UIKit
@testable import Gatherory

@MainActor
@Suite(.serialized)
struct ClosedIdeaBarTests {
    @Test("Only finalized shared statuses replace responses with a status bar",
          arguments: IdeaStatus.allCases)
    func presentation(status: IdeaStatus) {
        let summary = TeamResponseSummary(love: 1, maybe: 2, pass: 1, unanswered: 4)
        let bar = TeamResponseBar(summary: summary, ideaStatus: status)
        let isClosed = [IdeaStatus.chosen, .passed, .archived].contains(status)
        #expect(bar.closedIdeaStatus == (isClosed ? status : nil))
        #expect(bar.summary == summary, "Presentation must not manufacture or erase responses")
    }

    @Test("Closed bars are solid blue in light and dark mode, including no-response seed ideas")
    func closedBarRendering() async throws {
        for scheme in [ColorScheme.light, .dark] {
            for status in [IdeaStatus.chosen, .passed, .archived] {
                for summary in [TeamResponseSummary(), .init(unanswered: 4), .init(love: 1, maybe: 1, pass: 1, unanswered: 1)] {
                    let image = try await render(status: status, summary: summary, scheme: scheme)
                    let bluePixels = try bluePixelCount(image)
                    if status == .chosen && summary.unanswered == 4 {
                        Attachment.record(try #require(image.pngData()), named: "approved-bar-\(scheme).png")
                    }
                    #expect(bluePixels > 2_000,
                            "Closed ideas must fill the bar independently of response counts")
                }
            }
        }
    }

    @Test("Reopening an idea returns its bar to the original response colors")
    func activeBarRendering() async throws {
        for scheme in [ColorScheme.light, .dark] {
            for status in [IdeaStatus.new, .maybe, .shortlisted] {
                let image = try await render(status: status, summary: .init(unanswered: 4), scheme: scheme)
                #expect(try bluePixelCount(image) == 0)
            }
        }
    }

    private func render(status: IdeaStatus, summary: TeamResponseSummary, scheme: ColorScheme) async throws -> UIImage {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).isEmpty,
              ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let controller = UIHostingController(rootView:
            TeamResponseBar(summary: summary, ideaStatus: status,
                            showsTitle: false, showsSymbols: false)
                .frame(width: 240, height: 18)
                .environment(\.colorScheme, scheme)
        )
        let previousKeyWindow = scene.keyWindow
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 320, height: 240)
        window.overrideUserInterfaceStyle = scheme == .dark ? .dark : .light
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
            previousKeyWindow?.makeKey()
        }
        controller.view.frame = window.bounds
        try await Task.sleep(for: .milliseconds(500))
        window.layoutIfNeeded()
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.preferredRange = .standard
        return UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
    }

    private func bluePixelCount(_ image: UIImage) throws -> Int {
        let image = try #require(image.cgImage)
        let width = image.width
        let height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let count = try bytes.withUnsafeMutableBytes { storage in
            let context = try #require(CGContext(data: storage.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            let pixels = storage.bindMemory(to: UInt8.self)
            return stride(from: 0, to: pixels.count, by: 4).filter { offset in
                Int(pixels[offset + 2]) > 120
                    && Int(pixels[offset + 2]) > Int(pixels[offset]) + 70
                    && Int(pixels[offset + 2]) > Int(pixels[offset + 1]) + 25
            }.count
        }
        return count
    }
}
