import Foundation
import Testing
@testable import Gatherory

@MainActor
struct ScopedPlanningTests {
    @Test("Join-request navigation uses the displayed child and its own permission",
          arguments: [PlanningPermission.manage, .contribute, .viewOnly])
    func childJoinRequestDestination(permission: PlanningPermission) {
        let host = WorkspaceMember(name: "Host", participantRole: .host, initials: "H")
        let child = TimelineItem(title: "Dinner", category: .other, scheduledAt: .now,
                                 location: "", participantIDs: [host.id])
        let sibling = TimelineItem(title: "Brunch", category: .other, scheduledAt: .now,
                                   location: "", participantIDs: [host.id])
        let mainEventID = UUID()
        let participations = [
            EventParticipation(eventID: mainEventID, memberID: host.id,
                               role: .host, planningPermission: .manage,
                               attendance: .invited, invitationStatus: .active),
            EventParticipation(eventID: child.id, memberID: host.id,
                               role: .collaborator, planningPermission: permission,
                               attendance: .invited, invitationStatus: .active),
            EventParticipation(eventID: sibling.id, memberID: host.id,
                               role: .guest, planningPermission: .manage,
                               attendance: .invited, invitationStatus: .active)
        ]
        let workspace = PlanningWorkspace(
            mainEventID: mainEventID, title: "Weekend", mainEventStartsAt: .now,
            venueName: "", location: "", planningMode: .openToIdeas,
            members: [host], eventParticipations: participations, ideas: [],
            timeline: [child, sibling], registry: []
        )
        workspace.selectedEventReference = .subevent(sibling.id)
        #expect(workspace.joinRequestReviewEventID(for: .main) == workspace.mainEventID)
        #expect(workspace.joinRequestReviewEventID(for: .subevent(child.id)) == (permission == .manage ? child.id : nil))
        #expect(workspace.joinRequestReviewEventID(for: .subevent(sibling.id)) == nil)
        #expect(workspace.joinRequestReviewEventID(for: .subevent(UUID())) == nil)
        #expect(workspace.joinRequestReviewEventID(for: .idea(child.id)) == nil)
    }

    @Test("Child-only planners can review only with manage permission",
          arguments: [PlanningPermission.manage, .contribute, .viewOnly])
    func scopedJoinRequestDestination(permission: PlanningPermission) {
        let workspace = PlanningWorkspace(
            isScopedEvent: true, title: "Dinner", mainEventStartsAt: .now,
            venueName: "", location: "", planningMode: .openToIdeas,
            members: [WorkspaceMember(name: "Collaborator", participantRole: .collaborator,
                                      initials: "C", planningPermission: permission)],
            ideas: [], timeline: [], registry: []
        )
        #expect(workspace.joinRequestReviewEventID(for: .main) == (permission == .manage ? workspace.mainEventID : nil))
        #expect(workspace.joinRequestReviewEventID(for: .subevent(UUID())) == nil)
        workspace.mainEventStatus = .cancelled
        #expect(workspace.joinRequestReviewEventID(for: .main) == nil)
    }

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
