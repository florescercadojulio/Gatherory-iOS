import SwiftUI
import UIKit
import Testing
@testable import Gatherory

struct AccountLoadingPresentationTests {
    @Test("Account loading renders in light, dark, and accessible compact layouts")
    @MainActor func loadingLayouts() async throws {
        for (name, width, height, scheme, typeSize) in [
            ("light", 390.0, 844.0, ColorScheme.light, DynamicTypeSize.large),
            ("dark", 390.0, 844.0, .dark, .large),
            ("large-text", 320.0, 568.0, .light, .accessibility3),
        ] {
            let controller = UIHostingController(rootView: AccountOnboardingLoadingView()
                .environment(\.colorScheme, scheme)
                .environment(\.dynamicTypeSize, typeSize)
                .frame(width: width, height: height))
            let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
            let previousKeyWindow = scene.keyWindow
            let window = UIWindow(windowScene: scene)
            window.frame = CGRect(x: 0, y: 0, width: width, height: height)
            window.rootViewController = controller
            window.makeKeyAndVisible()
            defer { window.isHidden = true; window.rootViewController = nil; previousKeyWindow?.makeKey() }
            controller.view.frame = window.bounds
            controller.view.setNeedsLayout()
            controller.view.layoutIfNeeded()
            // Hosting renders native ProgressView and ScrollView; ImageRenderer
            // cannot flatten these UIKit-backed views into a useful screenshot.
            try await Task.sleep(for: .milliseconds(100))
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            let image = UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { _ in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            let pixels = try #require(image.cgImage)
            #expect(pixels.width == Int(width))
            #expect(pixels.height == Int(height))
            let pixelData = try #require(pixels.dataProvider?.data) as Data
            #expect(Set(pixelData).count > 20, "The preview must contain rendered content, not an empty surface")
            let data = try #require(image.pngData())
            Attachment.record(data, named: "account-loading-\(name).png")
        }
    }
}
