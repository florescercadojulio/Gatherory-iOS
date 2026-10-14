import Foundation
import Testing
@testable import Gatherory

@MainActor
struct ManageNoteTests {
    @Test("Manage summary exposes note permission for hosts and contributors, but not view-only members or guests")
    func summaryNotePermissions() throws {
        for (role, permission, expected) in [
            (WorkspaceRole.host, PlanningPermission.manage, true),
            (.collaborator, .contribute, true),
            (.collaborator, .viewOnly, false)
        ] {
            let workspace = makeWorkspace(role: role, permission: permission)
            let summary = try #require(ManageEventSummary(workspace: workspace, reference: .main))
            #expect(summary.canSendNote == expected)
            #expect(summary.id == summary.eventID)
        }

        let guestWorkspace = makeWorkspace(role: .guest, permission: .viewOnly)
        #expect(ManageEventSummary(workspace: guestWorkspace, reference: .main) == nil)
    }

    @Test("Finished events remain summarized but cannot send notes")
    func finishedEventCannotSendNote() throws {
        let workspace = makeWorkspace()
        workspace.mainEventStatus = .finished

        let summary = try #require(ManageEventSummary(workspace: workspace, reference: .main))
        #expect(!summary.canSendNote)
        #expect(workspace.sendNote("Planning update", to: summary.reference) == nil)
    }

    @Test("Manage child target receives the note while Home selection stays on main")
    func explicitChildTargetDoesNotChangeSelection() throws {
        let workspace = makeWorkspace()
        let child = makeChild("Dinner", parentEventID: workspace.mainEventID)
        workspace.timeline = [child]
        workspace.selectEventContext(.main)

        let summary = try #require(ManageEventSummary(workspace: workspace, reference: .subevent(child.id)))
        let note = try #require(workspace.sendNote("Meet at the entrance.", to: summary.reference))

        #expect(note.eventID == summary.eventID)
        #expect(note.body == "Meet at the entrance.")
        #expect(workspace.selectedEventReference == .main)
    }

    @Test("Scoped Manage summary cannot expose a sibling event")
    func scopedSummaryCannotExposeSibling() {
        let workspace = makeWorkspace(isScoped: true)
        let sibling = makeChild("Sibling", parentEventID: workspace.mainEventID)
        workspace.timeline = [sibling]

        #expect(ManageEventSummary(workspace: workspace, reference: .main) != nil)
        #expect(ManageEventSummary(workspace: workspace, reference: .subevent(sibling.id)) == nil)
    }

    private func makeWorkspace(
        isScoped: Bool = false,
        role: WorkspaceRole = .host,
        permission: PlanningPermission = .manage
    ) -> PlanningWorkspace {
        let userID = "manage-note-user"
        let member = WorkspaceMember(
            userID: userID,
            name: "Planner",
            participantRole: role,
            initials: "P",
            planningPermission: permission
        )
        let workspace = PlanningWorkspace(
            isScopedEvent: isScoped,
            title: "Weekend",
            mainEventStartsAt: .now,
            venueName: "Venue",
            location: "Address",
            planningMode: .openToIdeas,
            members: [member],
            ideas: [],
            timeline: [],
            registry: []
        )
        workspace.configureViewer(UserAccount(
            id: userID,
            email: "planner@example.test",
            displayName: member.name,
            role: .planner,
            authenticationProvider: .password,
            createdAt: .now
        ))
        return workspace
    }

    private func makeChild(_ title: String, parentEventID: UUID) -> TimelineItem {
        TimelineItem(
            title: title,
            category: .other,
            scheduledAt: .now,
            location: "",
            participantIDs: [],
            parentEventID: parentEventID,
            status: .approved
        )
    }
}
