import SwiftUI
import Testing
import UIKit
@testable import Gatherory

@MainActor
struct BlueprintPreviewHomeScrollTests {
    @Test("Preview Home observes the visible event as its real scroll view moves")
    func scrollingUpdatesRailSelection() async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).isEmpty,
              ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let url = try #require(Bundle(for: PreviewHomeFixture.self).url(forResource: "wedding-catalog.v1", withExtension: "json"))
        let entries = try JSONDecoder().decode(BlueprintCatalogResponse.self, from: Data(contentsOf: url)).entries
        let entry = try #require(entries.first)
        let content = try #require(BlueprintPreviewContent(entry: entry))
        var selections: [BlueprintPreviewEventID] = []
        let controller = UIHostingController(rootView: BlueprintWorkspaceHomeView(
            content: content, category: .weddings, usesSavedPreview: false
        ) { selections.append($0) })
        let previousKeyWindow = scene.keyWindow
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
            previousKeyWindow?.makeKey()
        }
        controller.view.frame = window.bounds
        try await Task.sleep(for: .milliseconds(400))
        window.layoutIfNeeded()
        let scroll = try #require(scrollView(in: controller.view))
        for index in [1, 2, 0] {
            scroll.setContentOffset(CGPoint(
                x: 0,
                y: CGFloat(index) * (640 + AppTheme.Spacing.standard) - scroll.adjustedContentInset.top
            ), animated: false)
            try await Task.sleep(for: .milliseconds(250))
            window.layoutIfNeeded()
            #expect(selections.last == content.eventIDs[index], "The rail and idea scope must follow the actual visible card")
        }
    }

    private func scrollView(in view: UIView) -> UIScrollView? {
        if let scroll = view as? UIScrollView, scroll.contentSize.height > scroll.bounds.height { return scroll }
        return view.subviews.lazy.compactMap { scrollView(in: $0) }.first
    }
}

private final class PreviewHomeFixture: NSObject {}
