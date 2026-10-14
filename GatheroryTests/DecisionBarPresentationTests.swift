import Observation
import SwiftUI
import Testing
import UIKit
@testable import Gatherory

@MainActor
struct DecisionBarPresentationTests {
    @Test("Ideas cards show an offline Decide response after switching tabs")
    func returningFromDecideUpdatesCardBar() async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).isEmpty,
              ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let viewer = UserAccount(id: "reviewer", email: "reviewer@example.test", displayName: "Reviewer",
            role: .planner, authenticationProvider: .password, createdAt: .now)
        let workspace = PlanningWorkspace(title: "Seed-style team", mainEventStartsAt: .now,
            venueName: "", location: "", planningMode: .openToIdeas,
            members: ["reviewer", "host", "cohost", "contributor"].map {
                WorkspaceMember(userID: $0, name: $0, participantRole: .host, initials: "H", planningPermission: .manage)
            }, ideas: [PlanningIdea(title: "Garden formal attire", note: "", category: .attire, submittedBy: "Host")],
            timeline: [], registry: [])
        workspace.configureViewer(viewer)
        let idea = try #require(workspace.ideas.first)
        let selection = DecisionBarTabSelection()
        let controller = UIHostingController(rootView: DecisionBarTabPreview(selection: selection)
            .environment(workspace)
            .environment(ImageSafetyStore())
            .environment(\.currentUserAccount, viewer)
            .environment(\.colorScheme, .light))
        let previousKeyWindow = scene.keyWindow
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
        window.overrideUserInterfaceStyle = .light
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
            previousKeyWindow?.makeKey()
        }
        controller.view.frame = window.bounds
        try await Task.sleep(for: .milliseconds(800))
        let before = render(window)
        Attachment.record(try #require(before.pngData()), named: "idea-bar-before.png")
        selection.tab = 1
        try await Task.sleep(for: .milliseconds(200))
        workspace.decide(.love, on: idea)
        #expect(workspace.decisionQueue.isEmpty)
        #expect(workspace.teamResponseSummary(for: idea) == .init(love: 1, unanswered: 3))
        selection.tab = 0
        try await Task.sleep(for: .milliseconds(800))
        let after = render(window)
        Attachment.record(try #require(after.pngData()), named: "idea-bar-after.png")
        #expect(try greenPixelCount(after) > greenPixelCount(before) + 50,
            "The card's green response segment must appear without reloading or syncing")

        workspace.undoLastDecision()
        #expect(workspace.decisionQueue.map(\.id) == [idea.id])
        #expect(workspace.ideas.first?.status == .new)
        try await Task.sleep(for: .milliseconds(400))
        let undone = render(window)
        Attachment.record(try #require(undone.pngData()), named: "idea-bar-undone.png")
        #expect(try greenPixelCount(undone) <= greenPixelCount(before) + 20,
            "Undo must return the bar to unanswered input")
    }

    private func render(_ window: UIWindow) -> UIImage {
        window.layoutIfNeeded()
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.preferredRange = .standard
        return UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
    }

    private func greenPixelCount(_ image: UIImage) throws -> Int {
        let cgImage = try #require(image.cgImage)
        #expect(cgImage.bitsPerPixel == 32)
        let bytes = try #require(cgImage.dataProvider?.data) as Data
        return stride(from: 0, to: bytes.count - 3, by: 4).filter { offset in
            // Both RGBA and BGRA place green between red and blue.
            let green = Int(bytes[offset + 1])
            return green > 110 && green > Int(bytes[offset]) + 45 && green > Int(bytes[offset + 2]) + 45
        }.count
    }
}

@MainActor @Observable
private final class DecisionBarTabSelection {
    var tab = 0
}

private struct DecisionBarTabPreview: View {
    @Bindable var selection: DecisionBarTabSelection

    var body: some View {
        TabView(selection: $selection.tab) {
            Tab("Ideas", systemImage: "sparkles", value: 0) {
                NavigationStack { IdeasView() }
            }
            Tab("Decide", systemImage: "rectangle.stack", value: 1) {
                Text(verbatim: "Decide")
            }
        }
    }
}
