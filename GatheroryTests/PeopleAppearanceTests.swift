import SwiftUI
import Testing
import UIKit
@testable import Gatherory

@MainActor
struct PeopleAppearanceTests {
    @Test("People destinations render in both appearances and accessibility settings")
    func peopleLayouts() async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).isEmpty,
              ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let persistence = try WorkspacePersistenceController(isStoredInMemoryOnly: true)
        let library = WorkspaceLibrary.sample
        let workspace = try #require(library.workspaces.first)
        workspace.configureViewer(DevelopmentAccountFixtures.planner)
        let child = TimelineItem(
            title: "Final venue walkthrough", category: .venue, purpose: .planning,
            scheduledAt: workspace.mainEventStartsAt,
            eventLocation: workspace.mainEventLocation,
            participantIDs: workspace.mainEventParticipantIDs,
            parentEventID: workspace.mainEventID
        )
        workspace.addTimelineItem(child)
        #expect(workspace.canManageInvitations(for: .subevent(child.id)))
        let sync = WorkspaceCloudSyncController(persistence: persistence, library: library, baseURL: nil)
        // No signed-in client: these renders must not fetch live join requests.
        let authentication = AuthenticationSession(environment: .development, skipsAuthentication: false)

        for (name, scheme, typeSize, section) in [
            ("guests-light", ColorScheme.light, DynamicTypeSize.large, EventPeopleSection.guests),
            ("guests-dark", .dark, .large, .guests),
            ("guests-large-text", .light, .accessibility3, .guests),
            ("collaborators-light", .light, .large, .collaborators),
        ] {
            let content = NavigationStack {
                EventPeopleView(reference: .subevent(child.id), section: section)
            }
            .environment(workspace)
            .environment(sync)
            .environment(authentication)
            .environment(\.colorScheme, scheme)
            .environment(\.appContentColorScheme, scheme)
            .environment(\.dynamicTypeSize, typeSize)
            let controller = UIHostingController(rootView: content)
            let previousKeyWindow = scene.keyWindow
            let window = UIWindow(windowScene: scene)
            window.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
            window.overrideUserInterfaceStyle = scheme == .dark ? .dark : .light
            window.rootViewController = controller
            window.makeKeyAndVisible()
            defer {
                window.isHidden = true
                window.rootViewController = nil
                previousKeyWindow?.makeKey()
            }
            controller.view.frame = window.bounds
            controller.view.setNeedsLayout()
            controller.view.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(200))
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            let image = UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { _ in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            let pixels = try #require(image.cgImage?.dataProvider?.data) as Data
            #expect(Set(pixels).count > 20, "The destination must render its content")
            Attachment.record(try #require(image.pngData()), named: "people-\(name).png")
        }
    }
}
