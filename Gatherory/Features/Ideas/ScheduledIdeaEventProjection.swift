import Foundation

/// Resolves the one visible, direct child event created for a scheduled idea.
/// Stale or ambiguous linkage is unavailable; callers must not guess another
/// event or fall back to the root invitation.
@MainActor
enum ScheduledIdeaEventProjection {
    static func resolve(ideaID: UUID, in workspace: PlanningWorkspace) -> TimelineItem? {
        guard !workspace.isScopedEvent,
              !workspace.isInvitationProjection,
              !workspace.isMainEventDeleted,
              let idea = workspace.ideas.first(where: { $0.id == ideaID }),
              idea.category == .event else { return nil }

        let linkedItems = workspace.timeline.filter { $0.linkedIdeaID == idea.id }
        guard linkedItems.count == 1,
              let item = linkedItems.first,
              item.parentEventID == workspace.mainEventID,
              item.status != .archived,
              workspace.currentViewerMember(for: .subevent(item.id))?.invitationStatus == .active else {
            return nil
        }
        return item
    }
}
