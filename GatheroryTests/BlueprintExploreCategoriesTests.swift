import Foundation
import Testing
@testable import Gatherory

@MainActor
struct BlueprintExploreCategoriesTests {
    @Test("Every native category is populated by the actual expanded server catalog")
    func expandedCatalog() throws {
        let url = try #require(Bundle(for: ExploreCategoryFixtureBundle.self).url(forResource: "explore-catalog.v1", withExtension: "json"))
        let entries = try JSONDecoder().decode(BlueprintCatalogResponse.self, from: Data(contentsOf: url)).entries
        #expect(entries.count == 17)
        #expect(BlueprintBrowseCategory.allCases.count == 18)
        #expect(BlueprintBrowseCategory.available(in: entries) == BlueprintBrowseCategory.allCases)
        for entry in entries {
            let categories = try #require(entry.discovery?.categories)
            #expect(categories.allSatisfy { BlueprintBrowseCategory(rawValue: $0) != nil })
            #expect(entry.definition.supportsCurrentSchema)
            for category in entry.browseCategories {
                #expect(!category.title.isEmpty)
                #expect(!category.symbol.isEmpty)
                #expect(entry.matches(query: category.title))
                #expect(category.catalogAspectRatio > 0)
            }
        }
        #expect(entries.contains { $0.matches(query: "airbnb") })
        #expect(entries.contains { $0.matches(query: "game night") })
        #expect(BlueprintBrowseCategory.available(in: []).isEmpty)
        let wedding = try #require(entries.first { $0.catalogKey == "wedding" })
        #expect(BlueprintBrowseCategory.available(in: [wedding]) == [.weddings])
    }
}

private final class ExploreCategoryFixtureBundle: NSObject {}
