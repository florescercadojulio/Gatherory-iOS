import Testing
@testable import Gatherory

@MainActor
struct ExploreAdFeedPolicyTests {
    @Test("Every Explore channel supports browse and typed-search monetization")
    func channelEligibility() {
        for content in ExploreContentKind.allCases {
            #expect(ExploreAdFeedPolicy.allowsAds(content: content, mode: .browse))
            #expect(ExploreAdFeedPolicy.allowsAds(content: content, mode: .results))
            #expect(!ExploreAdFeedPolicy.allowsAds(content: content, mode: .recent))
        }
    }

    @Test("Slot spacing counts either type of organic result and remains stable when pages append")
    func spacingAcrossContent() {
        let rows = ExploreFeedProjection.project(
            blueprintIDs: (1...20).map { "blueprint-\($0)" },
            ideaIDs: (1...20).map { "idea-\($0)" }
        )
        let slots = rows.enumerated().compactMap { index, _ in
            ExploreAdFeedPolicy.slotID(afterOrganicCount: index + 1)
        }
        #expect(slots == ["explore-ad-6", "explore-ad-18", "explore-ad-30"])
        let ideasOnly = ExploreFeedProjection.project(blueprintIDs: [], ideaIDs: (1...40).map(String.init))
        #expect(ideasOnly.count == rows.count)
        #expect(ideasOnly.enumerated().compactMap { index, _ in
            ExploreAdFeedPolicy.slotID(afterOrganicCount: index + 1)
        } == slots)
        #expect(ExploreAdFeedPolicy.slotID(afterOrganicCount: 0) == nil)
        #expect(ExploreAdFeedPolicy.slotID(afterOrganicCount: -6) == nil)
        #expect((1...5).allSatisfy { ExploreAdFeedPolicy.slotID(afterOrganicCount: $0) == nil })
    }
}
