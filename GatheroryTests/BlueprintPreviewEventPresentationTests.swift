import Foundation
import Testing
@testable import Gatherory

@MainActor
struct BlueprintPreviewEventPresentationTests {
    @Test("Root preview artwork uses the selected browse category's symbol and palette")
    func rootArtworkMatchesBrowseCategory() throws {
        let entry = try fixture()
        let content = try #require(BlueprintPreviewContent(entry: entry))
        let event = try #require(content.event(for: .main))

        for browseCategory in BlueprintBrowseCategory.allCases {
            let artwork = BlueprintPreviewEventArtwork.resolve(
                id: .main,
                rawCategory: event.category,
                browseCategory: browseCategory
            )
            #expect(artwork.category == browseCategory.artworkCategory)
            #expect(artwork.symbol == browseCategory.symbol)
            #expect(artwork.colors == browseCategory.artworkCategory.artworkColors)
            #expect(artwork.accent == browseCategory.artworkCategory.artworkAccent)
        }
    }

    @Test("Child artwork resolves canonical and snake case categories without falling back")
    func childArtworkCategoryMapping() {
        let cases: [(String, TimelineCategory)] = [
            ("venue_visit", .venue),
            ("food_tasting", .foodTasting),
            ("photography", .photography),
            ("honeymoon", .honeymoon),
            ("attire_fitting", .attireFitting),
            ("wedding_shower", .weddingShower),
            ("bachelor_bachelorette", .bachelorBachelorette),
            ("rehearsal", .rehearsal),
            ("ceremony", .ceremony),
            ("reception", .reception)
        ]

        for (rawCategory, expected) in cases {
            let artwork = BlueprintPreviewEventArtwork.resolve(
                id: .child("source-key"), rawCategory: rawCategory, browseCategory: .weddings
            )
            #expect(artwork.category == expected)
            #expect(artwork.symbol == expected.symbol)
        }

        let genericEvent = BlueprintPreviewEventArtwork.resolve(
            id: .child("source-key"), rawCategory: "event", browseCategory: .birthdays
        )
        #expect(genericEvent.category == BlueprintBrowseCategory.birthdays.artworkCategory)
        #expect(genericEvent.symbol == BlueprintBrowseCategory.birthdays.symbol)

        let unknown = BlueprintPreviewEventArtwork.resolve(
            id: .child("source-key"), rawCategory: "future_category", browseCategory: .weddings
        )
        #expect(unknown.category == .other)
    }

    @Test("Preview rail follows source event IDs and only shows authored schedule proposals")
    func railItemsPreserveAuthoredScopeAndScheduling() throws {
        let content = try #require(BlueprintPreviewContent(entry: fixture()))
        let items = BlueprintPreviewEventRailItem.items(from: content)

        #expect(items.map(\.id) == content.eventIDs)
        #expect(items.first?.id == .main)
        #expect(items.first?.title == content.title)
        #expect(items.first?.annotation == nil)
        #expect(items.dropFirst().allSatisfy { $0.annotation != nil })
        #expect(items.dropFirst().allSatisfy { item in
            guard case .child(let key) = item.id else { return false }
            return content.children.contains { $0.key == key && $0.title == item.title }
        })
    }

    private func fixture() throws -> BlueprintCatalogEntry {
        let url = try #require(Bundle(for: BlueprintPreviewEventPresentationFixture.self)
            .url(forResource: "wedding-catalog.v1", withExtension: "json"))
        let root = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let response = try JSONDecoder().decode(
            BlueprintCatalogResponse.self,
            from: JSONSerialization.data(withJSONObject: root)
        )
        return try #require(response.entries.first)
    }
}

private final class BlueprintPreviewEventPresentationFixture: NSObject {}
