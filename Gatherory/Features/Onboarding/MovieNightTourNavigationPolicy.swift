import Foundation

/// Pure navigation rules for browsing guide instructions without changing the
/// action-derived progress saved in `MovieNightTourStore`.
enum MovieNightTourNavigationPolicy {
    private static let orderedSteps: [MovieNightTourStep] = [
        .previewUsed, .ideas, .loveIt, .approve, .schedule
    ]

    static func previousStep(from step: MovieNightTourStep) -> MovieNightTourStep? {
        guard let index = orderedSteps.firstIndex(of: step), index > 0 else { return nil }
        return orderedSteps[index - 1]
    }

    /// Returns the next instruction only when observed progress has reached it.
    /// The intro may advance to the first Ideas instruction without a planning
    /// action; every later transition is gated by the persisted action stage.
    static func nextStep(
        from step: MovieNightTourStep,
        actualProgress: MovieNightTourStep
    ) -> MovieNightTourStep? {
        guard actualProgress != .completed,
              let stepIndex = orderedSteps.firstIndex(of: step),
              stepIndex + 1 < orderedSteps.count,
              let progressIndex = unlockedIndex(for: actualProgress) else { return nil }
        let candidate = orderedSteps[stepIndex + 1]
        guard stepIndex + 1 <= progressIndex else { return nil }
        return candidate
    }

    /// Keeps an independently browsed instruction at or behind real progress.
    static func boundedStep(
        _ requested: MovieNightTourStep?,
        actualProgress: MovieNightTourStep
    ) -> MovieNightTourStep? {
        guard let requested, let requestedIndex = orderedSteps.firstIndex(of: requested),
              let progressIndex = unlockedIndex(for: actualProgress) else { return nil }
        return orderedSteps[min(requestedIndex, progressIndex)]
    }

    static func isReviewingEarlierStep(
        _ step: MovieNightTourStep,
        actualProgress: MovieNightTourStep
    ) -> Bool {
        guard let stepIndex = orderedSteps.firstIndex(of: step),
              let progressIndex = orderedSteps.firstIndex(of: actualProgress) else { return false }
        return stepIndex < progressIndex
    }

    static func canFinish(
        from step: MovieNightTourStep,
        actualProgress: MovieNightTourStep,
        actionsAreComplete: Bool
    ) -> Bool {
        step == .schedule && actualProgress == .schedule && actionsAreComplete
    }

    private static func unlockedIndex(for progress: MovieNightTourStep) -> Int? {
        guard progress != .completed else { return nil }
        // The first tap moves from the intro to Ideas; no vote or approval is
        // required to show that first instruction.
        if progress == .previewUsed { return orderedSteps.firstIndex(of: .ideas) }
        return orderedSteps.firstIndex(of: progress)
    }
}
