import Foundation

/// Quick review shares the existing transient store, never the offline outbox.
@MainActor
enum ManageCollaboratorReview {
    static func isCaughtUp(in workspace: PlanningWorkspace, store: EventJoinRequestStore,
                           reference: EventReference, accountID: String?) -> Bool {
        guard let summary = ManageEventSummary(workspace: workspace, reference: reference),
              summary.canManageInvitations,
              !store.isLoading(eventID: summary.eventID),
              store.error(eventID: summary.eventID, accountID: accountID) == nil else { return false }
        return store.requestCount(eventID: summary.eventID, accountID: accountID) == 0
    }

    static func latestRequest(in workspace: PlanningWorkspace, store: EventJoinRequestStore,
                              reference: EventReference, accountID: String?) -> EventJoinRequest? {
        guard let summary = ManageEventSummary(workspace: workspace, reference: reference),
              summary.canManageInvitations else { return nil }
        // The invitation API orders pending requests by createdAt ascending.
        return store.requests(eventID: summary.eventID, accountID: accountID).last
    }

    static func review(_ request: EventJoinRequest, in workspace: PlanningWorkspace, store: EventJoinRequestStore,
                       reference: EventReference, accountID: String, action: JoinRequestReviewAction) async -> Bool {
        guard let summary = ManageEventSummary(workspace: workspace, reference: reference),
              summary.canManageInvitations,
              store.requests(eventID: summary.eventID, accountID: accountID)
                .contains(where: { $0.id == request.id }) else { return false }
        return await store.review(request, eventID: summary.eventID, accountID: accountID, action: action)
    }
}
