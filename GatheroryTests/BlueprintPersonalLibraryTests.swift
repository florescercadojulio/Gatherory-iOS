import Foundation
import Testing
@testable import Gatherory

struct BlueprintPersonalLibraryTests {
    @Test("Older personal records decode without the optional sharing metadata")
    func optionalSharingMetadataDecodes() throws {
        let url = try #require(Bundle(for: PersonalBlueprintFixtureBundle.self).url(forResource: "wedding-catalog.v1", withExtension: "json"))
        let entry = try #require(JSONDecoder().decode(BlueprintCatalogResponse.self, from: Data(contentsOf: url)).entries.first)
        let encodedEntry = try JSONEncoder().encode(entry)
        let catalogEntry = try #require(JSONSerialization.jsonObject(with: encodedEntry) as? [String: Any])
        let legacy: [String: Any] = [
            "id": UUID().uuidString,
            "draftVersion": 1,
            "publishedRevision": 1,
            "listedRevision": NSNull(),
            "catalogEntry": catalogEntry
        ]
        let legacyRecord = try JSONDecoder().decode(
            BlueprintPersonalRecord.self,
            from: JSONSerialization.data(withJSONObject: legacy)
        )
        #expect(legacyRecord.creatorName == nil)
        #expect(legacyRecord.activeShareLinkCount == nil)

        var current = legacy
        current["creatorName"] = "Garden Hosts"
        current["activeShareLinkCount"] = 2
        let currentRecord = try JSONDecoder().decode(
            BlueprintPersonalRecord.self,
            from: JSONSerialization.data(withJSONObject: current)
        )
        #expect(currentRecord.creatorName == "Garden Hosts")
        #expect(currentRecord.activeShareLinkCount == 2)
    }

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

struct BlueprintPublicProfileTests {
    @Test("Creator names are trimmed and limited by Unicode scalar count")
    func creatorNameValidation() {
        #expect(BlueprintCreatorNameValidation.normalized("  Rae 🌿  ") == "Rae 🌿")
        #expect(BlueprintCreatorNameValidation.normalized(" \n ") == nil)
        #expect(BlueprintCreatorNameValidation.normalized(String(repeating: "🌿", count: 80)) != nil)
        #expect(BlueprintCreatorNameValidation.normalized(String(repeating: "🌿", count: 81)) == nil)
    }

    @Test("Sharing status never calls unknown server state private")
    func sharingStatusRequiresKnownCount() {
        #expect(BlueprintSharingStatus.badges(activeShareLinkCount: 0, listedRevision: nil) == [.privateBlueprint])
        #expect(BlueprintSharingStatus.badges(activeShareLinkCount: 3, listedRevision: nil) == [.linkActive])
        #expect(BlueprintSharingStatus.badges(activeShareLinkCount: 0, listedRevision: 4) == [.inSearch])
        #expect(BlueprintSharingStatus.badges(activeShareLinkCount: 3, listedRevision: 4) == [.linkActive, .inSearch])
        #expect(BlueprintSharingStatus.badges(activeShareLinkCount: nil, listedRevision: nil).isEmpty)
        #expect(BlueprintSharingStatus.badges(activeShareLinkCount: -1, listedRevision: nil).isEmpty)
    }

    @Test("Publish acknowledgements accept only the same or next published revision")
    func publishAcknowledgementRevisionRules() throws {
        let url = try #require(Bundle(for: PersonalBlueprintFixtureBundle.self).url(forResource: "wedding-catalog.v1", withExtension: "json"))
        let baseEntry = try #require(JSONDecoder().decode(BlueprintCatalogResponse.self, from: Data(contentsOf: url)).entries.first)
        let recordID = UUID()

        func acknowledgement(_ revision: Int, name: String = "Garden Hosts", id: UUID = recordID,
                             catalogKey: String = baseEntry.catalogKey, draftVersion: Int = 3,
                             listedRevision: Int? = nil) -> BlueprintPersonalRecord {
            let entry = BlueprintCatalogEntry(catalogKey: catalogKey, revision: revision,
                contentHash: baseEntry.contentHash, definition: baseEntry.definition,
                discovery: baseEntry.discovery, description: baseEntry.description, creator: baseEntry.creator)
            return BlueprintPersonalRecord(id: id, draftVersion: draftVersion,
                publishedRevision: revision, listedRevision: listedRevision ?? revision,
                creatorName: name, activeShareLinkCount: 0, catalogEntry: entry)
        }

        func valid(_ record: BlueprintPersonalRecord, previous: Int?) -> Bool {
            BlueprintPersonalPublishAcknowledgement.isValid(record, expectedID: recordID,
                expectedCatalogKey: baseEntry.catalogKey, expectedDraftVersion: 3,
                previousPublishedRevision: previous, expectedCreatorName: "Garden Hosts")
        }

        #expect(valid(acknowledgement(1), previous: nil))
        #expect(valid(acknowledgement(2), previous: 2))
        #expect(valid(acknowledgement(3), previous: 2))
        #expect(!valid(acknowledgement(4), previous: 2))
        #expect(!valid(acknowledgement(1), previous: 2))
        #expect(!valid(acknowledgement(2, name: "Different Name"), previous: 1))
        #expect(!valid(acknowledgement(2, id: UUID()), previous: 1))
        #expect(!valid(acknowledgement(2, catalogKey: "different-key"), previous: 1))
        #expect(!valid(acknowledgement(2, draftVersion: 4), previous: 1))
        #expect(!valid(acknowledgement(2, listedRevision: 1), previous: 1))
    }
}
