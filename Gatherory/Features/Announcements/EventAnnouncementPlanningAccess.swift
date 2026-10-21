import Foundation

/// Old notes remain private planning history. They are never converted into
/// announcements or included in a guest invitation projection.
@MainActor enum EventAnnouncementPlanningAccess {
    static func reference(in workspace: PlanningWorkspace, eventID: UUID,
                          principal: NotificationPrincipal?, loadFailure: EventAnnouncementFailure? = nil) -> EventReference? {
        guard loadFailure != .accessDenied, !workspace.isInvitationProjection else { return nil }
        let reference: EventReference = eventID == workspace.mainEventID ? .main : .subevent(eventID)
        guard ManageEventSummary(workspace: workspace, reference: reference) != nil,
              workspace.canReadTodos(for: reference),
              let viewer = workspace.currentViewerMember(for: reference) else { return nil }
        switch principal {
        case .account(let id):
            guard !workspace.isLocalGuestViewer, viewer.userID == id else { return nil }
        case .guest(let id):
            guard workspace.localGuestProfileID == id else { return nil }
        case nil:
            return nil
        }
        return reference
    }
}
