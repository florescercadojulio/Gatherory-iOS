import Foundation

enum ExploreAdFeedPolicy {
    static func allowsAds(content: ExploreContentKind, mode: BlueprintSearchMode) -> Bool {
        switch content {
        case .all, .blueprints, .ideas:
            return mode != .recent
        }
    }

    /// Keep organic relevance order intact and leave breathing room between ads.
    static func slotID(afterOrganicCount count: Int) -> String? {
        guard count >= 6, (count - 6).isMultiple(of: 12) else { return nil }
        return "explore-ad-\(count)"
    }
}
