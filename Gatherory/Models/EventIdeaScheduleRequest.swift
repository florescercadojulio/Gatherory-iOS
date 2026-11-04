import Foundation

/// Immutable authority and proposal snapshot captured when a planner opens
/// the explicit Schedule flow for an event idea.
struct EventIdeaScheduleRequest: Hashable {
    let rootEventID: UUID
    let ideaSnapshot: PlanningIdea
    let viewerGeneration: UInt64
    let viewerMemberID: UUID
    let viewerMemberSnapshot: WorkspaceMember

    var ideaID: UUID { ideaSnapshot.id }
}
