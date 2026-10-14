import Foundation
import Testing
@testable import Gatherory

@MainActor
struct ScopedPlanningTests {
    @Test("Scoped permissions separate contribution, management, and read-only access")
    func scopedCollaboratorControls() throws {
        let member = WorkspaceMember(
            name: "Collaborator", participantRole: .collaborator,
            initials: "C", planningPermission: .contribute
        )
        let workspace = PlanningWorkspace(
            isScopedEvent: true,
            title: "Welcome dinner",
            mainEventStartsAt: .now,
            venueName: "",
            location: "",
            planningMode: .openToIdeas,
            members: [member],
            ideas: [],
            timeline: [],
            registry: []
        )
        #expect(workspace.showsPlanningInterface)
        #expect(!workspace.canManageMainEvent)
        #expect(!workspace.canManageRegistry)
        #expect(workspace.canAddEventMoments(to: .main))
        #expect(!workspace.canDeleteMainEvent)
        #expect(!workspace.canAddChildEvent(to: workspace.mainEventID))
        workspace.addRegistryItem(RegistryItem(
            eventID: workspace.mainEventID, title: "Gift", note: "",
            category: .home, price: 20
        ))
        #expect(workspace.registry.isEmpty)

        workspace.addTimelineItem(TimelineItem(
            title: "Grandchild", category: .other, scheduledAt: .now,
            location: "", participantIDs: [], parentEventID: workspace.mainEventID
        ))
        #expect(workspace.timeline.isEmpty)

        let eventIdea = PlanningIdea(
            eventID: workspace.mainEventID, title: "Another event", note: "",
            category: .event, submittedBy: "Collaborator", status: .new
        )
        workspace.addIdea(eventIdea)
        workspace.updateIdea(eventIdea, status: .chosen)
        #expect(workspace.ideas.first?.status == .new)
        #expect(workspace.timeline.isEmpty)

        let manager = PlanningWorkspace(
            isScopedEvent: true,
            title: "Welcome dinner",
            mainEventStartsAt: .now,
            venueName: "",
            location: "",
            planningMode: .openToIdeas,
            members: [WorkspaceMember(
                name: "Manager", participantRole: .collaborator,
                initials: "M", planningPermission: .manage
            )],
            ideas: [], timeline: [], registry: []
        )
        #expect(manager.canManageMainEvent)
        #expect(manager.canManageRegistry)
        manager.addRegistryItem(RegistryItem(
            eventID: manager.mainEventID, title: "Gift", note: "",
            category: .home, price: 20
        ))
        #expect(manager.registry.count == 1)

        let viewOnly = PlanningWorkspace(
            isScopedEvent: true,
            title: "Welcome dinner",
            mainEventStartsAt: .now,
            venueName: "",
            location: "",
            planningMode: .openToIdeas,
            members: [WorkspaceMember(
                name: "Reader", participantRole: .collaborator,
                initials: "R", planningPermission: .viewOnly
            )],
            ideas: [], timeline: [], registry: []
        )
        #expect(!viewOnly.canManageMainEvent)
        #expect(!viewOnly.canManageRegistry)
        #expect(!viewOnly.canAddEventMoments(to: .main))
    }
}
