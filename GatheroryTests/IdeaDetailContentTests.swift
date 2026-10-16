import Foundation
import Testing
@testable import Gatherory

@MainActor
struct IdeaDetailContentTests {
    @Test("Template ideas feed the shared idea screen without truncating authored content")
    func fullPreviewContent() {
        let notes = String(repeating: "Keep the complete suggestion. ", count: 100)
        let idea = BlueprintCatalogIdea(key: "flowers", title: "Seasonal flowers", category: "flowers",
                                        notes: notes, target: .child(key: "ceremony"), configuration: [:])
        let content = IdeaDetailContent(preview: idea)
        #expect(content.title == idea.title)
        #expect(content.note == notes)
        #expect(content.category == .flowers)
        #expect(idea.key == "flowers")
        #expect(idea.notes == notes)
    }

    @Test("An idea with no notes does not gain placeholder content")
    func missingNotes() {
        let idea = BlueprintCatalogIdea(key: "venue", title: "Venue", category: "venue",
                                        notes: nil, target: .main, configuration: [:])
        let content = IdeaDetailContent(preview: idea)
        #expect(content.note.isEmpty)
        #expect(content.category == .venue)
    }

    @Test("A future category retains its authored text with the existing Other presentation")
    func futureCategory() {
        let idea = BlueprintCatalogIdea(key: "future", title: "A future idea", category: "future_category",
                                        notes: "The author's guidance", target: .main, configuration: [:])
        let content = IdeaDetailContent(preview: idea)
        #expect(content.category == .other)
        #expect(content.title == idea.title)
        #expect(content.note == idea.notes)
    }

    @Test("All workspace categories retain the exact configuration used by their existing cards", arguments: IdeaCategory.allCases)
    func workspaceCardContent(category: IdeaCategory) {
        let idea = PlanningIdea(title: "Authored title", note: "Keep these details", category: category,
                                submittedBy: "Planner", estimatedCost: 42)
        let original = idea
        let content = IdeaDetailContent(idea: idea, currencyCode: "CAD")
        #expect(content.title == idea.title)
        #expect(content.note == idea.note)
        #expect(content.category == category)
        #expect(content.configuration == idea.configuration)
        #expect(content.currencyCode == "CAD")
        #expect(content.musicTracks == idea.musicTracks)
        #expect(IdeaCategoryDetailContent(idea: content, liveIdea: idea).showsLiveControls)
        #expect(idea == original)
    }

    @Test("Every template category uses the shared card renderer without activating live controls", arguments: IdeaCategory.allCases)
    func previewCardsAreReadOnly(category: IdeaCategory) {
        let idea = BlueprintCatalogIdea(key: "example", title: "Authored title", category: category.rawValue,
                                        notes: "Full authored notes", target: .main,
                                        configuration: ["version": .integer(1)])
        let content = IdeaDetailContent(preview: idea)
        #expect(content.configuration == nil)
        #expect(content.currencyCode == nil)
        #expect(content.musicTracks.isEmpty)
        #expect(!IdeaCategoryDetailContent(idea: content).showsLiveControls)
        #expect(idea.configuration == ["version": .integer(1)])
    }

    @Test("Supported rich card data remains readable without a live idea binding")
    func configuredReadOnlyCards() {
        let content = IdeaDetailContent(title: "Garden party", note: "Use seasonal colors", category: .venue,
                                        configuration: .venue(VenueIdeaConfiguration(setting: .outdoor, capacity: 45, area: "Garden")))
        let cards = IdeaCategoryDetailContent(idea: content)
        #expect(cards.idea.configuration == content.configuration)
        #expect(!cards.showsLiveControls)
    }
}
