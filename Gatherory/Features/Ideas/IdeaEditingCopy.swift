import Foundation

enum IdeaEditingCopy {
    static var eventName: String {
        String(localized: "idea.editor.eventName", defaultValue: "Event name")
    }
}

@MainActor
enum IdeaEventEditing {
    static func canEdit(_ idea: PlanningIdea, in workspace: PlanningWorkspace) -> Bool {
        guard idea.category == .event,
              !workspace.isInvitationProjection,
              workspace.showsPlanningInterface,
              !workspace.isMainEventDeleted,
              !workspace.currentMainEventStatus.isReadOnly,
              workspace.currentViewerMember(for: .main)?.planningPermission != .viewOnly else {
            return false
        }

        let eventID = idea.eventID ?? workspace.mainEventID
        let reference: EventReference = eventID == workspace.mainEventID ? .main : .subevent(eventID)
        guard let viewer = workspace.currentViewerMember(for: reference),
              viewer.participantRole != .guest,
              viewer.planningPermission != .viewOnly,
              viewer.invitationStatus == .active else {
            return false
        }

        return workspace.canManageEvent(reference)
    }
}
