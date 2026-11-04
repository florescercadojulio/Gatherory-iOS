import Testing
@testable import Gatherory

struct ExploreFeedProjectionTests {
    @Test("All feed interleaves ideas in source order and appends remaining ideas")
    func interleavesAndAppends() {
        let rows = ExploreFeedProjection.project(
            blueprintIDs: ["b1", "b2", "b3", "b4", "b5", "b6", "b7", "b8", "b9"],
            ideaIDs: ["i1", "i2", "i3", "i4", "i5"]
        )

        #expect(rows == [
            .blueprint("b1"), .blueprint("b2"), .blueprint("b3"), .blueprint("b4"), .idea("i1"),
            .blueprint("b5"), .blueprint("b6"), .blueprint("b7"), .blueprint("b8"), .idea("i2"),
            .blueprint("b9"), .idea("i3"), .idea("i4"), .idea("i5")
        ])
        #expect(rows.map(\.id).allSatisfy { !$0.isEmpty })
    }

    @Test("Blueprint-only projection keeps blueprint order and stable identities")
    func blueprintOnlyAndStableIDs() {
        let initial = ExploreFeedProjection.project(blueprintIDs: ["b1", "b2"], ideaIDs: [])
        let appended = ExploreFeedProjection.project(blueprintIDs: ["b1", "b2", "b3"], ideaIDs: ["i1"])

        #expect(initial == [.blueprint("b1"), .blueprint("b2")])
        #expect(Array(appended.prefix(2)) == initial)
        #expect(initial.map(\.id) == ["blueprint:b1", "blueprint:b2"])
        #expect(appended.contains(.idea("i1")))
    }

    @Test("Projection removes duplicate IDs within each content type")
    func deduplicates() {
        let rows = ExploreFeedProjection.project(
            blueprintIDs: ["b1", "b1", "b2"], ideaIDs: ["i1", "i1", "i2"]
        )

        #expect(rows.filter { $0 == .blueprint("b1") }.count == 1)
        #expect(rows.filter { $0 == .idea("i1") }.count == 1)
        #expect(Set(rows.map(\.id)).count == rows.count)
    }

    @Test("Page arrivals append rows without moving visible idea or blueprint identities")
    func pageArrivalsKeepExistingPrefix() {
        var cache = ExploreFeedProjectionCache()
        cache.update(context: "results|all", blueprintIDs: ["b1", "b2", "b3", "b4"],
                     ideaIDs: ["i1", "i2", "i3"])
        let firstPageOrder = cache.identities

        cache.update(context: "results|all", blueprintIDs: ["b1", "b2", "b3", "b4", "b5", "b6", "b7", "b8"],
                     ideaIDs: ["i1", "i2", "i3"])
        let afterBlueprintPage = cache.identities
        #expect(Array(afterBlueprintPage.prefix(firstPageOrder.count)) == firstPageOrder)
        #expect(Array(afterBlueprintPage.suffix(4)) == [.blueprint("b5"), .blueprint("b6"), .blueprint("b7"), .blueprint("b8")])

        cache.update(context: "results|all", blueprintIDs: ["b1", "b2", "b3", "b4", "b5", "b6", "b7", "b8"],
                     ideaIDs: ["i1", "i2", "i3", "i4", "i5"])
        #expect(Array(cache.identities.prefix(afterBlueprintPage.count)) == afterBlueprintPage)
        #expect(Array(cache.identities.suffix(2)) == [.idea("i4"), .idea("i5")])
    }

    @Test("Projection cache resets when the feed context or page prefix changes")
    func cacheResetsForNewFeed() {
        var cache = ExploreFeedProjectionCache()
        cache.update(context: "results|query-a", blueprintIDs: ["a1", "a2"], ideaIDs: ["i1"])
        cache.update(context: "results|query-b", blueprintIDs: ["b1"], ideaIDs: ["j1"])
        #expect(cache.identities == [.blueprint("b1"), .idea("j1")])
        cache.update(context: "results|query-b", blueprintIDs: ["replacement"], ideaIDs: ["j1"])
        #expect(cache.identities == [.blueprint("replacement"), .idea("j1")])
    }
}
