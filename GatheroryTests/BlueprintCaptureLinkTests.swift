import Foundation
import SwiftData
import Testing
@testable import Gatherory

@MainActor
struct BlueprintCaptureLinkTests {
    private let baseURL = URL(string: "https://app.example.test")!

    @Test("Sharing controls remain available after an event closes without restoring event edits")
    func sharingIsIndependentOfEventEditing() {
        let workspace = makeWorkspace()
        workspace.mainEventStatus = .cancelled
        #expect(BlueprintCaptureLink.workspaceURL(baseURL: baseURL, workspace: workspace) == nil)
        #expect(BlueprintCaptureLink.sharingURL(baseURL: baseURL, workspace: workspace)
                == BlueprintCaptureLink.url(baseURL: baseURL, eventID: workspace.mainEventID))
        workspace.isMainEventDeleted = true
        #expect(BlueprintCaptureLink.sharingURL(baseURL: baseURL, workspace: workspace) == nil)
    }

    @Test("Sharing menu permissions remain event-scoped and account-aware")
    func sharingMenuScope() {
        for permission in [PlanningPermission.manage, .contribute, .viewOnly] {
            let scoped = makeWorkspace(role: .collaborator, permission: permission, scoped: true)
            scoped.mainEventStatus = .cancelled
            #expect((BlueprintCaptureLink.sharingURL(baseURL: baseURL, workspace: scoped) != nil)
                    == (permission == .manage))
        }
        let workspace = makeWorkspace()
        workspace.configureViewer(account("host"))
        #expect(BlueprintCaptureLink.sharingURL(baseURL: baseURL, workspace: workspace) != nil)
        workspace.configureViewer(account("unrelated"))
        #expect(BlueprintCaptureLink.sharingURL(baseURL: baseURL, workspace: workspace) == nil)
        workspace.configureViewer(nil)
        #expect(BlueprintCaptureLink.sharingURL(baseURL: baseURL, workspace: workspace) == nil)
        workspace.isInvitationProjection = true
        #expect(BlueprintCaptureLink.sharingURL(baseURL: baseURL, workspace: workspace) == nil)
        #expect(BlueprintCaptureLink.sharingURL(baseURL: baseURL, workspace: makeWorkspace(role: .guest)) == nil)
    }

    @Test("Existing template authoring opens its editor, not a new capture")
    func editorTargetsSelectedTemplate() throws {
        let templateID = UUID(uuidString: "A1B2C3D4-E5F6-47A8-9012-3456789ABCDE")!
        let baseURL = try #require(URL(string: "https://user:secret@dev.example.test/team%20preview/?token=private#details"))
        let result = try #require(BlueprintCaptureLink.editorURL(baseURL: baseURL, templateID: templateID))
        #expect(result.absoluteString == "https://dev.example.test/team%20preview/blueprints/a1b2c3d4-e5f6-47a8-9012-3456789abcde")
        #expect(!result.absoluteString.contains("capture"))
    }

    @Test("Workspace card capture targets its root, not the selected child, and does not enqueue edits")
    func cardTargetDoesNotMutateWorkspace() async throws {
        let persistence = try WorkspacePersistenceController(isStoredInMemoryOnly: true)
        let library = persistence.restoreLibrary(seedData: false, ownerUserID: "host")
        let workspace = makeWorkspace()
        let child = TimelineItem(title: "Dinner", category: .other, scheduledAt: .now,
                                 location: "", participantIDs: [], parentEventID: workspace.mainEventID)
        workspace.timeline = [child]
        workspace.selectedEventReference = .subevent(child.id)
        library.add(workspace)
        try persistence.saveChanges(in: library)
        let beforeArchive = try WorkspaceArchiveCodec().encode(WorkspaceArchiveV1(workspace: workspace))
        let context = ModelContext(persistence.container)
        let beforeOutbox = try context.fetch(FetchDescriptor<PendingMutation>()).map(PendingMutationSnapshot.init)
        var notifications = 0
        persistence.onPendingMutations = { notifications += 1 }
        defer { persistence.onPendingMutations = nil }
        persistence.startObserving(library)

        let destination = try #require(BlueprintCaptureLink.workspaceURL(baseURL: baseURL, workspace: workspace))
        #expect(destination == BlueprintCaptureLink.url(baseURL: baseURL, eventID: workspace.mainEventID))
        #expect(workspace.selectedEventReference == .subevent(child.id))
        #expect(try WorkspaceArchiveCodec().encode(WorkspaceArchiveV1(workspace: workspace)) == beforeArchive)
        try await Task.sleep(for: .milliseconds(600))
        #expect(notifications == 0)
        #expect(try context.fetch(FetchDescriptor<PendingMutation>()).map(PendingMutationSnapshot.init) == beforeOutbox)
    }

    @Test("Only managers can capture from a workspace card",
          arguments: [PlanningPermission.manage, .contribute, .viewOnly])
    func scopedCardPermissions(permission: PlanningPermission) {
        let workspace = makeWorkspace(role: .collaborator, permission: permission, scoped: true)
        #expect(BlueprintCaptureLink.workspaceURL(baseURL: baseURL, workspace: workspace)
                == (permission == .manage ? BlueprintCaptureLink.url(baseURL: baseURL, eventID: workspace.mainEventID) : nil))
    }

    @Test("Guest, invitation-only, deleted and read-only cards have no template action")
    func unavailableCards() {
        let guest = makeWorkspace(role: .guest)
        #expect(BlueprintCaptureLink.workspaceURL(baseURL: baseURL, workspace: guest) == nil)
        let workspace = makeWorkspace()
        workspace.isInvitationProjection = true
        #expect(BlueprintCaptureLink.workspaceURL(baseURL: baseURL, workspace: workspace) == nil)
        workspace.isInvitationProjection = false
        workspace.isMainEventDeleted = true
        #expect(BlueprintCaptureLink.workspaceURL(baseURL: baseURL, workspace: workspace) == nil)
        workspace.isMainEventDeleted = false
        workspace.mainEventStatus = .cancelled
        #expect(BlueprintCaptureLink.workspaceURL(baseURL: baseURL, workspace: workspace) == nil)
        #expect(BlueprintCaptureLink.workspaceURL(baseURL: nil, workspace: makeWorkspace()) == nil)
    }

    @Test("Workspace card action is recomputed when the account changes")
    func accountSwitchRemovesAction() {
        let workspace = makeWorkspace()
        workspace.configureViewer(account("host"))
        #expect(BlueprintCaptureLink.workspaceURL(baseURL: baseURL, workspace: workspace) != nil)
        workspace.configureViewer(account("unrelated"))
        #expect(BlueprintCaptureLink.workspaceURL(baseURL: baseURL, workspace: workspace) == nil)
        workspace.configureViewer(nil)
        #expect(BlueprintCaptureLink.workspaceURL(baseURL: baseURL, workspace: workspace) == nil)
    }

    private func makeWorkspace(role: WorkspaceRole = .host,
                               permission: PlanningPermission = .manage,
                               scoped: Bool = false) -> PlanningWorkspace {
        PlanningWorkspace(isScopedEvent: scoped, title: "Weekend", mainEventStartsAt: .now,
                          venueName: "", location: "", planningMode: .openToIdeas,
                          members: [WorkspaceMember(userID: "host", name: "Host", participantRole: role,
                                                    initials: "H", planningPermission: permission)],
                          ideas: [], timeline: [], registry: [])
    }

    private func account(_ id: String) -> UserAccount {
        UserAccount(id: id, email: "\(id)@example.test", displayName: id,
                    role: .planner, authenticationProvider: .password, createdAt: .now)
    }

    @Test("Capture URL uses the configured origin, keeps its base path, and encodes the exact event ID")
    func configuredBaseURLAndEventID() throws {
        let eventID = UUID(uuidString: "A1B2C3D4-E5F6-47A8-9012-3456789ABCDE")!
        let baseURL = try #require(URL(string: "https://dev.example.test/team%20preview/"))

        let result = try #require(BlueprintCaptureLink.url(baseURL: baseURL, eventID: eventID))
        let components = try #require(URLComponents(url: result, resolvingAgainstBaseURL: false))

        #expect(components.scheme == "https")
        #expect(components.host == "dev.example.test")
        #expect(components.percentEncodedPath == "/team%20preview/blueprints/capture")
        #expect(components.queryItems == [URLQueryItem(name: "eventId", value: "a1b2c3d4-e5f6-47a8-9012-3456789abcde")])
        #expect(components.fragment == nil)
    }

    @Test("Capture URL never carries credentials, existing query values, or fragments")
    func doesNotLeakBaseURLData() throws {
        let baseURL = try #require(URL(string: "https://user:secret@dev.example.test/app?token=private&eventId=wrong#private"))
        let eventID = UUID(uuidString: "12345678-1234-4234-8234-123456789ABC")!

        let result = try #require(BlueprintCaptureLink.url(baseURL: baseURL, eventID: eventID))
        let components = try #require(URLComponents(url: result, resolvingAgainstBaseURL: false))

        #expect(components.user == nil)
        #expect(components.password == nil)
        #expect(components.queryItems == [URLQueryItem(name: "eventId", value: eventID.uuidString.lowercased())])
        #expect(components.fragment == nil)
        #expect(!result.absoluteString.contains("secret"))
        #expect(!result.absoluteString.contains("private"))
    }
}
