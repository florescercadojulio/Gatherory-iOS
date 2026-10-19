import Foundation
import Testing
@testable import Gatherory

struct BlueprintPersonalLibraryTests {
    @Test("Owned publication saves include edited content but never installation dates")
    @MainActor func editsArePortableAndCopiesIndependent() throws {
        let url = try #require(Bundle(for: PersonalBlueprintFixtureBundle.self).url(forResource: "wedding-catalog.v1", withExtension: "json"))
        let entry = try #require(JSONDecoder().decode(BlueprintCatalogResponse.self, from: Data(contentsOf: url)).entries.first)
        let record = BlueprintPersonalRecord(id: UUID(), draftVersion: 1, publishedRevision: 1, listedRevision: 1, catalogEntry: entry)
        let original = record.draftContent
        #expect(!original.children.isEmpty)
        #expect(!original.ideas.isEmpty)
        var session = BlueprintPreviewSession(ownerID: "a", entry: entry, shareToken: nil, savedDraft: nil,
            defaultEventName: entry.definition.blueprint.name)
        let idea = try #require(original.ideas.first)
        try session.editIdea(.init(key: idea.key, title: "Our changed idea", category: idea.category,
                                  notes: idea.notes, target: idea.target, configuration: idea.configuration))
        let values = session.mainEventValues
        try session.editMainEvent(.init(name: values.name, startsAt: values.startsAt.addingTimeInterval(86_400),
                                       timeZoneIdentifier: values.timeZoneIdentifier), confirmsDate: true)
        let edited = try record.editedContent(from: session)
        #expect(edited.ideas.first(where: { $0.key == idea.key })?.title == "Our changed idea")
        #expect(record.draftContent == original)
        let encoded = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(edited)) as? [String: Any])
        #expect(encoded["startsAt"] == nil && encoded["confirmedDates"] == nil)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = BlueprintPersonalLibraryStore(directoryURL: directory)
        try cache.upsert(record, ownerID: "a")
        #expect(try cache.load(ownerID: "a").first?.draftContent == original)
        #expect(try cache.load(ownerID: "b").isEmpty)
        try cache.remove(id: record.id, ownerID: "a")
        #expect(try cache.load(ownerID: "a").isEmpty)
        #expect(original.ideas.first?.title == idea.title)
    }
    @Test("Personal blueprint cache is account scoped")
    func accountScopedCache() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = BlueprintPersonalLibraryStore(directoryURL: directory)
        #expect(try store.load(ownerID: "account-a").isEmpty)
        try store.save([], ownerID: "account-a")
        #expect(try store.load(ownerID: "account-b").isEmpty)
    }

    @Test("Personal draft content encodes the portable web field names")
    func contentWireKeys() throws {
        let content = BlueprintDraftContent(name: "Dinner", description: "A plan", experienceType: "dinner",
            children: [], ideas: [], instructions: [])
        let object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(content)) as? [String: Any])
        #expect(Set(object.keys) == Set(["name", "description", "experienceType", "children", "ideas", "instructions"]))
    }
}

private final class PersonalBlueprintFixtureBundle: NSObject {}
