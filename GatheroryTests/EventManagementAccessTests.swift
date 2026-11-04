import Foundation
import Testing
@testable import Gatherory

@MainActor
struct EventManagementAccessTests {
    @Test("Management destinations stay within the visible exact event")
    func exactReferenceAndChildScope() throws {
        let host = WorkspaceMember(name: "Host", participantRole: .host, initials: "H")
        let child = TimelineItem(title: "Dinner", category: .other, scheduledAt: .now,
                                 location: "", participantIDs: [host.id])
        let sibling = TimelineItem(title: "Brunch", category: .other, scheduledAt: .now,
                                   location: "", participantIDs: [host.id])
        let workspace = PlanningWorkspace(
            title: "Weekend", mainEventStartsAt: .now, venueName: "", location: "",
            planningMode: .openToIdeas, members: [host], ideas: [],
            timeline: [child, sibling], registry: []
        )
        workspace.selectedEventReference = .subevent(sibling.id)

        #expect(EventManagementAccess.canOpen(reference: .main, in: workspace))
        #expect(EventManagementAccess.canOpen(.settings, for: .main, in: workspace))
        #expect(EventManagementAccess.canOpen(reference: .subevent(child.id), in: workspace))
        #expect(EventManagementAccess.canOpen(.settings, for: .subevent(child.id), in: workspace))
        #expect(!EventManagementAccess.canOpen(reference: .subevent(UUID()), in: workspace))
        #expect(!EventManagementAccess.canOpen(reference: .idea(UUID()), in: workspace))
        #expect(EventManagementAccess.destinations(reference: .subevent(child.id), in: workspace).contains(.settings))

        var archivedChild = TimelineItem(title: "Old dinner", category: .other, scheduledAt: .now,
                                         location: "", participantIDs: [host.id], status: .archived)
        let archivedWorkspace = PlanningWorkspace(
            title: "Weekend", mainEventStartsAt: .now, venueName: "", location: "",
            planningMode: .openToIdeas, members: [host], ideas: [],
            timeline: [archivedChild], registry: []
        )
        #expect(!EventManagementAccess.canOpen(reference: .subevent(archivedChild.id), in: archivedWorkspace))

        archivedChild.status = .approved
        archivedChild.parentEventID = UUID()
        let detachedWorkspace = PlanningWorkspace(
            title: "Weekend", mainEventStartsAt: .now, venueName: "", location: "",
            planningMode: .openToIdeas, members: [host], ideas: [],
            timeline: [archivedChild], registry: []
        )
        detachedWorkspace.timeline[0].parentEventID = UUID()
        #expect(!EventManagementAccess.canOpen(reference: .subevent(archivedChild.id), in: detachedWorkspace))

        let deletedWorkspace = PlanningWorkspace(
            title: "Deleted", mainEventStartsAt: .now, venueName: "", location: "",
            planningMode: .openToIdeas, members: [host], ideas: [], timeline: [], registry: []
        )
        deletedWorkspace.isMainEventDeleted = true
        #expect(!EventManagementAccess.canOpen(reference: .main, in: deletedWorkspace))

        let scoped = PlanningWorkspace(
            isScopedEvent: true, title: "Dinner", mainEventStartsAt: .now, venueName: "", location: "",
            planningMode: .openToIdeas,
            members: [WorkspaceMember(name: "Manager", participantRole: .collaborator,
                                      initials: "M", planningPermission: .manage)],
            ideas: [], timeline: [], registry: []
        )
        #expect(EventManagementAccess.canOpen(reference: .main, in: scoped))
        #expect(EventManagementAccess.canOpen(.settings, for: .main, in: scoped))
        #expect(!EventManagementAccess.canOpen(reference: .subevent(child.id), in: scoped))

        let readOnlyScoped = PlanningWorkspace(
            isScopedEvent: true, title: "Dinner", mainEventStartsAt: .now, venueName: "", location: "",
            planningMode: .openToIdeas,
            members: [WorkspaceMember(name: "Viewer", participantRole: .collaborator,
                                      initials: "V", planningPermission: .viewOnly)],
            ideas: [], timeline: [], registry: []
        )
        #expect(!EventManagementAccess.canOpen(.settings, for: .main, in: readOnlyScoped))

        let invitationProjection = PlanningWorkspace(
            title: "Invitation", mainEventStartsAt: .now, venueName: "", location: "",
            planningMode: .openToIdeas, members: [host], ideas: [], timeline: [], registry: []
        )
        invitationProjection.isInvitationProjection = true
        #expect(!EventManagementAccess.canOpen(.settings, for: .main, in: invitationProjection))
    }

    @Test("Guest-only projections cannot open the planning management view")
    func guestDestinations() throws {
        let guest = WorkspaceMember(name: "Guest", participantRole: .guest, initials: "G")
        let workspace = PlanningWorkspace(
            title: "Weekend", mainEventStartsAt: .now, venueName: "", location: "",
            planningMode: .openToIdeas, members: [guest], ideas: [], timeline: [], registry: []
        )

        #expect(!EventManagementAccess.canOpen(reference: .main, in: workspace))
        let destinations = EventManagementAccess.destinations(reference: .main, in: workspace)
        #expect(destinations.isEmpty)
    }

    @Test("Read-only planners can open management but cannot edit settings or review requests")
    func readOnlyPlannerBoundaries() {
        let viewer = WorkspaceMember(name: "Viewer", participantRole: .collaborator,
                                     initials: "V", planningPermission: .viewOnly)
        let workspace = PlanningWorkspace(
            title: "Weekend", mainEventStartsAt: .now, venueName: "", location: "",
            planningMode: .openToIdeas, members: [viewer], ideas: [], timeline: [], registry: []
        )

        #expect(EventManagementAccess.canOpen(reference: .main, in: workspace))
        let destinations = EventManagementAccess.destinations(reference: .main, in: workspace)
        #expect(destinations.contains(.people))
        #expect(destinations.contains(.budget))
        #expect(!destinations.contains(.settings))
        #expect(!destinations.contains(.requests))
    }

    @Test("Pending collaborators cannot open the planning management view")
    func pendingViewerBoundary() {
        let pending = WorkspaceMember(name: "Pending", participantRole: .collaborator, initials: "P",
                                      planningPermission: .manage, invitationStatus: .invited)
        let workspace = PlanningWorkspace(
            title: "Weekend", mainEventStartsAt: .now, venueName: "", location: "",
            planningMode: .openToIdeas, members: [pending], ideas: [], timeline: [], registry: []
        )

        #expect(!EventManagementAccess.canOpen(reference: .main, in: workspace))
        #expect(EventManagementAccess.destinations(reference: .main, in: workspace).isEmpty)
    }

    @Test("Configured accounts can manage legacy email matched memberships while offline")
    func configuredAccountLegacyEmailMembership() {
        let workspace = makeConfiguredAccountWorkspace(memberUserID: nil)
        let child = TimelineItem(title: "Dinner", category: .other, scheduledAt: .now,
                                 location: "", participantIDs: [workspace.members[0].id],
                                 parentEventID: workspace.mainEventID, status: .approved)
        workspace.timeline = [child]
        workspace.addParticipant(workspace.members[0].id, to: .subevent(child.id))

        #expect(EventManagementAccess.canOpen(reference: .main, in: workspace,
                                               accountID: "account-1", localGuestProfileID: nil))
        #expect(EventManagementAccess.canOpen(reference: .subevent(child.id), in: workspace,
                                               accountID: "account-1", localGuestProfileID: nil))
        // Notification history still requires the linked account principal.
        #expect(EventAnnouncementPlanningAccess.reference(in: workspace, eventID: workspace.mainEventID,
                                                           principal: .account(id: "account-1")) == nil)
    }

    @Test("Account management access stays bound to the configured account and linked member")
    func accountIdentityBoundaries() {
        let legacy = makeConfiguredAccountWorkspace(memberUserID: nil)
        #expect(!EventManagementAccess.canOpen(reference: .main, in: legacy,
                                                accountID: "another-account", localGuestProfileID: nil))

        let linkedToOtherAccount = makeConfiguredAccountWorkspace(memberUserID: "different-account")
        #expect(!EventManagementAccess.canOpen(reference: .main, in: linkedToOtherAccount,
                                                accountID: "account-1", localGuestProfileID: nil))

        let unconfigured = PlanningWorkspace(
            title: "Weekend", mainEventStartsAt: .now, venueName: "", location: "",
            planningMode: .openToIdeas,
            members: [WorkspaceMember(name: "Planner", participantRole: .host, initials: "P",
                                      email: "planner@example.test")], ideas: [], timeline: [], registry: []
        )
        #expect(!EventManagementAccess.canOpen(reference: .main, in: unconfigured,
                                                accountID: "account-1", localGuestProfileID: nil))
        #expect(!EventManagementAccess.canOpen(reference: .main, in: legacy,
                                                accountID: nil, localGuestProfileID: nil))
    }

    @Test("Local guest management access is limited to the configured host profile")
    func localGuestIdentityBoundaries() {
        let profile = LocalGuestProfile(displayName: "Device planner")
        let workspace = PlanningWorkspace(
            title: "Weekend", mainEventStartsAt: .now, venueName: "", location: "",
            planningMode: .openToIdeas,
            members: [WorkspaceMember(userID: profile.storageID, name: "Device planner",
                                      participantRole: .host, initials: "D")],
            ideas: [], timeline: [], registry: []
        )
        workspace.configureLocalGuestViewer(profile)

        #expect(EventManagementAccess.canOpen(reference: .main, in: workspace,
                                               accountID: nil, localGuestProfileID: profile.id))
        #expect(!EventManagementAccess.canOpen(reference: .main, in: workspace,
                                                accountID: nil, localGuestProfileID: UUID()))
        #expect(!EventManagementAccess.canOpen(reference: .main, in: workspace,
                                                accountID: "account-1", localGuestProfileID: profile.id))

        let attendee = PlanningWorkspace(
            title: "Weekend", mainEventStartsAt: .now, venueName: "", location: "",
            planningMode: .openToIdeas,
            members: [WorkspaceMember(userID: profile.storageID, name: "Device planner",
                                      participantRole: .guest, initials: "D")],
            ideas: [], timeline: [], registry: []
        )
        attendee.configureLocalGuestViewer(profile)
        #expect(!EventManagementAccess.canOpen(reference: .main, in: attendee,
                                                accountID: nil, localGuestProfileID: profile.id))
    }

    private func makeConfiguredAccountWorkspace(memberUserID: String?) -> PlanningWorkspace {
        let member = WorkspaceMember(userID: memberUserID, name: "Planner", participantRole: .host,
                                     initials: "P", email: "planner@example.test")
        let workspace = PlanningWorkspace(
            title: "Weekend", mainEventStartsAt: .now, venueName: "", location: "",
            planningMode: .openToIdeas, members: [member], ideas: [], timeline: [], registry: []
        )
        workspace.configureViewer(UserAccount(id: "account-1", email: "planner@example.test",
                                              displayName: "Planner", role: .planner,
                                              authenticationProvider: .password, createdAt: .now))
        return workspace
    }
}
