import Foundation
import Testing
@testable import Gatherory

struct MovieNightTourExplorePolicyTests {
    @Test("Guided Explore loads the pinned Movie Night bundle entry locally")
    func loadsBundledEntry() throws {
        let entry = try #require(MovieNightTourExplorePolicy.bundledEntry(bundle: .main))
        #expect(entry.catalogKey == "movie_night")
        #expect(entry.revision == 1)
        #expect(entry.definition.blueprint.id == "movie_night")
        #expect(entry.creator?.displayName == "Gatherory")
    }

    @Test("Guided Explore prepends the bundle and deduplicates feed entries by key")
    func mergesAndDeduplicates() throws {
        let movieNight = try #require(MovieNightTourExplorePolicy.bundledEntry(bundle: .main))
        let other = BlueprintCatalogEntry(
            catalogKey: "other_blueprint",
            revision: 1,
            contentHash: "other-hash",
            definition: movieNight.definition
        )

        let merged = MovieNightTourExplorePolicy.merge(
            bundled: movieNight,
            catalogEntries: [other, movieNight, other]
        )
        #expect(merged.map(\.catalogKey) == ["movie_night", "other_blueprint"])

        let withoutBundle = MovieNightTourExplorePolicy.merge(
            bundled: nil,
            catalogEntries: [movieNight, other]
        )
        #expect(withoutBundle.map(\.catalogKey) == ["other_blueprint"])
    }

    @Test("Only Movie Night is selectable during the guided Explore step")
    func guidedSelectionIsRestricted() {
        #expect(MovieNightTourExplorePolicy.isSelectable(
            catalogKey: "movie_night", guidedTourActive: true, guidedSelectionKey: "movie_night"
        ))
        #expect(!MovieNightTourExplorePolicy.isSelectable(
            catalogKey: "other_blueprint", guidedTourActive: true, guidedSelectionKey: "movie_night"
        ))
        #expect(!MovieNightTourExplorePolicy.isSelectable(
            catalogKey: "movie_night", guidedTourActive: true, guidedSelectionKey: nil
        ))
        #expect(MovieNightTourExplorePolicy.isSelectable(
            catalogKey: "other_blueprint", guidedTourActive: false, guidedSelectionKey: nil
        ))
    }
}
