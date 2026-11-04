import Foundation

/// Immutable idea, parent event, and authority snapshot captured when a
/// planner opens the explicit approval confirmation.
struct IdeaApprovalRequest: Identifiable, Hashable {
    enum ParentStatus: Hashable {
        case main(MainEventStatus)
        case subevent(EventStatus)
    }

    let rootEventID: UUID
    let ideaSnapshot: PlanningIdea
    let parentEventID: UUID
    let parentEventName: String
    let parentStatus: ParentStatus
    let viewerGeneration: UInt64
    let viewerMemberID: UUID
    let viewerMemberSnapshot: WorkspaceMember

    var id: UUID { ideaSnapshot.id }
    var ideaID: UUID { ideaSnapshot.id }
}
