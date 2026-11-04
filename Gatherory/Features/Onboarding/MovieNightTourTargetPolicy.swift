import Foundation

enum MovieNightTourTargetPolicy {
    static func target(
        for step: MovieNightTourStep,
        selectedTab: WorkspaceTab,
        ideasFilter: String?,
        snackIdeaID: UUID?,
        eventIdeaID: UUID?,
        isReviewingEarlier: Bool
    ) -> MovieNightTourTarget? {
        guard !isReviewingEarlier else { return nil }

        switch step {
        case .previewUsed:
            return selectedTab == .decide ? nil : .decideTab
        case .ideas:
            guard selectedTab == .decide else { return .decideTab }
            return snackIdeaID.map(MovieNightTourTarget.decision)
        case .loveIt:
            guard selectedTab == .ideas else { return .ideasTab }
            guard ideasFilter == IdeaFilter.liked.rawValue else { return .ideasFilter }
            return snackIdeaID.map(MovieNightTourTarget.idea)
        case .approve:
            guard selectedTab == .ideas else { return .ideasTab }
            guard ideasFilter == IdeaFilter.all.rawValue else { return .ideasFilter }
            return eventIdeaID.map(MovieNightTourTarget.idea)
        case .schedule:
            return selectedTab == .home ? nil : .homeTab
        case .completed:
            return nil
        }
    }
}
