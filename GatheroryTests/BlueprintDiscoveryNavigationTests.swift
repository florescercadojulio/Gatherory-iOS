import Foundation
import Testing
@testable import Gatherory

@MainActor
struct BlueprintDiscoveryNavigationTests {
    @Test("Search focus loss cannot remove the selected masonry source during preview navigation")
    func retainsSearchSource() throws {
        let entry = try fixture()
        var navigation = BlueprintDiscoveryNavigation()
        navigation.open(entry, from: .results, entries: [entry], mode: .results, query: "wedding")
        #expect(BlueprintSearchMode.resolve(isFocused: false, query: "wedding") == .browse)
        #expect(navigation.mode(isFocused: false, query: "wedding") == .results)
        #expect(navigation.entries(for: .results, fallback: []).map(\.id) == [entry.id])
        #expect(navigation.selection?.id == BlueprintPreviewTransitionID(source: .results, entryID: entry.id))
        #expect(navigation.selection?.entry.definition == entry.definition)
        navigation.completeReturn()
        #expect(navigation.retainedQuery == "wedding") // Still presented, not ready to clear.
    }

    @Test("Recent-history reordering and catalog refresh do not move or replace the zoom source")
    func retainsRecentOrder() throws {
        let entry = try fixture()
        let other = BlueprintCatalogEntry(catalogKey: "other", revision: 1, contentHash: entry.contentHash,
                                          definition: entry.definition, discovery: entry.discovery)
        var navigation = BlueprintDiscoveryNavigation()
        navigation.open(entry, from: .recent, entries: [other, entry], mode: .recent, query: "")
        #expect(navigation.entries(for: .recent, fallback: [entry, other]).map(\.id) == [other.id, entry.id])
        #expect(navigation.mode(isFocused: false, query: "") == .recent)
        #expect(navigation.restoresSearchFocus)
        navigation.selection = nil
        #expect(navigation.mode(isFocused: false, query: "") == .recent)
        navigation.completeReturn()
        #expect(navigation.entries(for: .recent, fallback: []).isEmpty)
        #expect(navigation.mode(isFocused: true, query: "") == .recent)
        #expect(navigation.retainedQuery == nil)
    }

    @Test("Catalog surfaces and revisions cannot accidentally match each other's tiles")
    func transitionIdentity() throws {
        let entry = try fixture()
        let revision = BlueprintCatalogEntry(catalogKey: entry.catalogKey, revision: entry.revision + 1,
                                             contentHash: entry.contentHash, definition: entry.definition, discovery: entry.discovery)
        let result = BlueprintPreviewSelection(entry: entry, source: .results)
        #expect(result == BlueprintPreviewSelection(entry: entry, source: .results))
        #expect(result != BlueprintPreviewSelection(entry: entry, source: .recent))
        #expect(result != BlueprintPreviewSelection(entry: entry, source: .category("weddings")))
        #expect(result != BlueprintPreviewSelection(entry: revision, source: .results))
        #expect(Set([result, .init(entry: entry, source: .recent), .init(entry: revision, source: .results)]).count == 3)
    }

    @Test("Returning releases snapshots and category navigation does not activate Search")
    func completeReturn() throws {
        let entry = try fixture()
        var navigation = BlueprintDiscoveryNavigation()
        navigation.open(entry, from: .category("weddings"), entries: [entry], mode: .browse, query: "old query")
        #expect(!navigation.restoresSearchFocus)
        #expect(navigation.entries(for: .results, fallback: []).isEmpty)
        navigation.selection = nil
        navigation.completeReturn()
        #expect(navigation.entries(for: .category("weddings"), fallback: []).isEmpty)
        #expect(navigation.mode(isFocused: false, query: "old query") == .browse)
        #expect(navigation.retainedQuery == nil)
        navigation.open(entry, from: .results, entries: [entry], mode: .results, query: "new query")
        #expect(navigation.retainedQuery == "new query")
    }

    @Test("Category preview navigation stays independent of Search and other categories")
    func categoryOwnsPreview() throws {
        let entry = try fixture()
        var search = BlueprintDiscoveryNavigation()
        var category = BlueprintDiscoveryNavigation()
        let otherCategory = BlueprintDiscoveryNavigation()
        category.open(entry, from: .category("weddings"), entries: [entry], mode: .browse, query: "")

        #expect(search.selection == nil)
        #expect(otherCategory.selection == nil)
        #expect(category.selection?.id == BlueprintPreviewTransitionID(source: .category("weddings"), entryID: entry.id))
        #expect(category.entries(for: .category("weddings"), fallback: []).map(\.id) == [entry.id])
        #expect(!category.restoresSearchFocus)

        search.open(entry, from: .results, entries: [entry], mode: .results, query: "wedding")
        category.selection = nil
        category.completeReturn()
        #expect(category.entries(for: .category("weddings"), fallback: []).isEmpty)
        #expect(search.selection?.entry.id == entry.id)
        #expect(search.retainedQuery == "wedding")
    }

    private func fixture() throws -> BlueprintCatalogEntry {
        let url = try #require(Bundle(for: DiscoveryNavigationFixtureBundle.self).url(forResource: "wedding-catalog.v1", withExtension: "json"))
        return try JSONDecoder().decode(BlueprintCatalogResponse.self, from: Data(contentsOf: url)).entries[0]
    }
}

private final class DiscoveryNavigationFixtureBundle: NSObject {}
