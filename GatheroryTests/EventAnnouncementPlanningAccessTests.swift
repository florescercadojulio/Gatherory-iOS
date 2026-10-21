import Foundation
import Testing
@testable import Gatherory

@MainActor struct EventAnnouncementPlanningAccessTests {
    @Test("Only the current exact-event planner can see private legacy history")
    func accountAndExactEventIsolation() {
        let workspace = makeWorkspace()
        let principal = NotificationPrincipal.account(id: "planner")
        #expect(EventAnnouncementPlanningAccess.reference(in: workspace, eventID: workspace.mainEventID, principal: principal) == .main)
        #expect(EventAnnouncementPlanningAccess.reference(in: workspace, eventID: workspace.mainEventID, principal: .account(id: "another")) == nil)
        #expect(EventAnnouncementPlanningAccess.reference(in: workspace, eventID: workspace.mainEventID, principal: nil) == nil)
        #expect(EventAnnouncementPlanningAccess.reference(in: workspace, eventID: UUID(), principal: principal) == nil)
        let child = TimelineItem(title: "Private dinner", category: .other, scheduledAt: .now, location: "", participantIDs: [],
                                 parentEventID: workspace.mainEventID, status: .approved)
        workspace.timeline = [child]
        workspace.notes = [EventNote(eventID: child.id, body: "Private child note")]
        #expect(EventAnnouncementPlanningAccess.reference(in: workspace, eventID: child.id, principal: principal) == nil)
        #expect(ManageNoteHistory.notes(in: workspace, reference: .subevent(child.id), isBlocked: { _ in false }).isEmpty)
    }

    @Test("Explicit server access denial hides legacy history while offline failures preserve it")
    func serverDenialOverridesCache() {
        let workspace = makeWorkspace()
        let principal = NotificationPrincipal.account(id: "planner")
        #expect(EventAnnouncementPlanningAccess.reference(in: workspace, eventID: workspace.mainEventID,
            principal: principal, loadFailure: .unavailable) == .main)
        #expect(EventAnnouncementPlanningAccess.reference(in: workspace, eventID: workspace.mainEventID,
            principal: principal, loadFailure: .accessDenied) == nil)
    }

    @Test("Guest roles and invitation projections never expose legacy planning notes")
    func guestAndProjectionPrivacy() {
        let guest = makeWorkspace(role: .guest)
        #expect(EventAnnouncementPlanningAccess.reference(in: guest, eventID: guest.mainEventID, principal: .account(id: "planner")) == nil)
        let projected = makeWorkspace()
        projected.notes = [EventNote(body: "Legacy secret")]
        projected.isInvitationProjection = true
        #expect(EventAnnouncementPlanningAccess.reference(in: projected, eventID: projected.mainEventID, principal: .account(id: "planner")) == nil)
        #expect(ManageNoteHistory.notes(in: projected, reference: .main, isBlocked: { _ in false }).isEmpty)
    }

    @Test("View-only planners retain read-only legacy history and inactive membership is rejected")
    func readOnlyAndInactive() {
        let workspace = makeWorkspace(role: .collaborator, permission: .viewOnly)
        #expect(EventAnnouncementPlanningAccess.reference(in: workspace, eventID: workspace.mainEventID, principal: .account(id: "planner")) == .main)
        #expect(!workspace.canSendNote(to: .main))
        let inactive = makeWorkspace(role: .collaborator, permission: .viewOnly, invitationStatus: .invited)
        #expect(EventAnnouncementPlanningAccess.reference(in: inactive, eventID: inactive.mainEventID, principal: .account(id: "planner")) == nil)
    }

    @Test("Device planning history stays available only to the owning device guest")
    func localGuestOwnPlanning() {
        let profile = LocalGuestProfile(displayName: "Morgan")
        let workspace = makeWorkspace(userID: profile.storageID)
        workspace.configureLocalGuestViewer(profile)
        workspace.notes = [EventNote(body: "Device planning history")]
        #expect(EventAnnouncementPlanningAccess.reference(in: workspace, eventID: workspace.mainEventID, principal: .guest(id: profile.id)) == .main)
        #expect(EventAnnouncementPlanningAccess.reference(in: workspace, eventID: workspace.mainEventID, principal: .guest(id: UUID())) == nil)
        #expect(EventAnnouncementPlanningAccess.reference(in: workspace, eventID: workspace.mainEventID, principal: .account(id: profile.storageID)) == nil)
        #expect(workspace.sendNote("Saved locally", to: .main) != nil)
        #expect(ManageNoteHistory.notes(in: workspace, reference: .main, isBlocked: { _ in false }).count == 2)
    }

    private func makeWorkspace(userID: String = "planner", role: WorkspaceRole = .host,
                               permission: PlanningPermission = .manage,
                               invitationStatus: CollaborationInvitationStatus = .active) -> PlanningWorkspace {
        let workspace = PlanningWorkspace(title: "Weekend", mainEventStartsAt: .now.addingTimeInterval(86_400), venueName: "", location: "",
            planningMode: .openToIdeas, members: [WorkspaceMember(userID: userID, name: "Planner", participantRole: role,
                initials: "P", planningPermission: permission, invitationStatus: invitationStatus)], ideas: [], timeline: [], registry: [])
        workspace.configureViewer(UserAccount(id: userID, email: "planner@example.test", displayName: "Planner", role: .planner,
                                             authenticationProvider: .password, createdAt: .now))
        return workspace
    }
}
