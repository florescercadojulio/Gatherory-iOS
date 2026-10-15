import Foundation
import Testing
@testable import Gatherory

@MainActor
struct BlueprintCatalogContractTests {
    @Test("The server Wedding schedule fixture decodes without confirming dates")
    func weddingScheduleSuggestions() throws {
        let bundle = Bundle(for: BlueprintFixtureBundle.self)
        let url = try #require(bundle.url(forResource: "wedding-schedule.v1", withExtension: "json"))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let response = try decoder.decode(BlueprintScheduleResponse.self, from: Data(contentsOf: url))
        #expect(response.catalogKey == "wedding")
        #expect(response.mainEvent.timeZone == "America/Detroit")
        #expect(response.suggestions.count == 4)
        let ceremony = try #require(response.suggestions.first { $0.key == "ceremony" })
        #expect(ceremony.localDateTime == "2027-06-15T15:00:00")
        #expect(ceremony.candidates.first == ISO8601DateFormatter().date(from: "2027-06-15T19:00:00Z"))
        var draft = BlueprintScheduleDraft()
        let token = draft.beginRefresh()
        draft.apply(response.suggestions, token: token)
        #expect(draft.confirmedDates.isEmpty)
        #expect(draft.confirmSuggestion(key: "ceremony", candidateIndex: 0, token: token) == true)
        #expect(draft.confirmedDates["ceremony"] == ceremony.candidates.first)
    }

    @Test("The real Wedding catalog and preview decode through the native wire models")
    func weddingCatalogAndPreview() throws {
        let bundle = Bundle(for: BlueprintFixtureBundle.self)
        let catalogURL = try #require(bundle.url(forResource: "wedding-catalog.v1", withExtension: "json"))
        let previewURL = try #require(bundle.url(forResource: "wedding-preview.v1", withExtension: "json"))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let catalog = try decoder.decode(BlueprintCatalogResponse.self, from: Data(contentsOf: catalogURL))
        let entry = try #require(catalog.entries.first)
        #expect(entry.catalogKey == "wedding")
        #expect(entry.discovery?.categories == ["weddings"])
        #expect(entry.discovery?.tags.contains("ceremony") == true)
        #expect(entry.definition.supportsCurrentSchema)
        let treeModule = try #require(entry.definition.modules.first { $0.type == "experience_tree" })
        let tree = try #require(treeModule.decodeConfiguration(BlueprintExperienceTreeConfig.self))
        #expect(tree.children.count == 4)
        let ideaModule = try #require(entry.definition.modules.first { $0.type == "ideas" })
        let ideas = try #require(ideaModule.decodeConfiguration(BlueprintIdeasConfig.self))
        #expect(ideas.ideas.count == 5)
        let preview = try decoder.decode(BlueprintPreviewResponse.self, from: Data(contentsOf: previewURL))
        #expect(preview.contentHash == entry.contentHash)
        #expect(preview.plan.main.name == "Riley and Jordan")
        #expect(preview.plan.children.count == 2)
        #expect(preview.plan.ideas.count == 3)
        #expect(preview.plan.instructions.count == 2)
        #expect(preview.plan.instructions.map(\.audience) == [.planningOnly, .eventParticipants])
        let venue = try #require(preview.plan.children.first { $0.sourceKey == "venue_visit" })
        #expect(venue.startsAt == ISO8601DateFormatter().date(from: "2027-06-14T20:00:00Z"))
    }
}

private final class BlueprintFixtureBundle: NSObject {}
