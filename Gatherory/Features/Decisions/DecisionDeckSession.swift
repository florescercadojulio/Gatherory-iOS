import Foundation

/// Presentation-only review progress. Keeping a response advances this pass without
/// retracting the saved response or showing the same card indefinitely.
struct DecisionDeckSession {
    private(set) var filter: DecisionQueueFilter = .unanswered
    private var reviewedIdeas: Set<UUID> = []

    func queue(in workspace: PlanningWorkspace, eventID: UUID? = nil) -> [PlanningIdea] {
        workspace.decisionQueue(for: eventID, filter: filter).filter {
            filter == .unanswered || !reviewedIdeas.contains($0.id)
        }
    }

    mutating func selectFilter(_ filter: DecisionQueueFilter) {
        self.filter = filter
        restartReview()
    }

    mutating func recordDecision(on ideaID: UUID) {
        if filter != .unanswered { reviewedIdeas.insert(ideaID) }
    }

    mutating func undoDecision(on ideaID: UUID) {
        reviewedIdeas.remove(ideaID)
    }

    mutating func restartReview() {
        reviewedIdeas.removeAll()
    }
}
