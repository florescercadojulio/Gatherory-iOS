import Foundation
import Testing
@testable import Gatherory

struct BlueprintLibraryProjectionTests {
    @Test("Exact recovery payloads deduplicate after normalizing selection sets")
    func exactRecoveryPayload() throws {
        let entry = try catalogEntry()
        var draft = makeDraft(entry: entry)
        draft.selectedChildren = ["ceremony", "reception"]
        draft.selectedIdeas = ["flowers", "music"]
        draft.copyEntry = entry

        var equivalent = draft
        equivalent.selectedChildren = ["reception", "ceremony"]
        equivalent.selectedIdeas = ["music", "flowers"]

        #expect(BlueprintLibraryProjection.isExactRecoveryDuplicate(equivalent, of: draft))
        #expect(!BlueprintLibraryProjection.hasSetupProgress(draft))
    }

    @Test("Changed recovery progress, share source, or catalog revision remains visible")
    func changedRecoveryPayloadRemainsVisible() throws {
        let entry = try catalogEntry()
        let source = makeDraft(entry: entry)

        var progressChanged = source
        progressChanged.eventName = "Different event"
        #expect(!BlueprintLibraryProjection.isExactRecoveryDuplicate(progressChanged, of: source))

        var shareChanged = source
        shareChanged.shareToken = "a-different-share-token"
        #expect(!BlueprintLibraryProjection.isExactRecoveryDuplicate(shareChanged, of: source))

        var revisionChanged = source
        revisionChanged.entry = try catalogEntry(revision: entry.revision + 1)
        #expect(!BlueprintLibraryProjection.isExactRecoveryDuplicate(revisionChanged, of: source))

        var datesChanged = source
        datesChanged.confirmedDates["ceremony"] = Date(timeIntervalSince1970: 1_900_000_000)
        #expect(!BlueprintLibraryProjection.isExactRecoveryDuplicate(datesChanged, of: source))
    }

    @Test("Deduplication compares full catalog and copied definitions, not only their hashes")
    func fullDefinitionsAreCompared() throws {
        let entry = try catalogEntry()
        let source = makeDraft(entry: entry)

        var changedEntryDefinition = source
        changedEntryDefinition.entry = try catalogEntry(name: "Changed definition", contentHash: entry.contentHash)
        #expect(!BlueprintLibraryProjection.isExactRecoveryDuplicate(changedEntryDefinition, of: source))

        var sourceWithCopy = source
        sourceWithCopy.copyEntry = entry
        var changedCopyDefinition = sourceWithCopy
        changedCopyDefinition.copyEntry = try catalogEntry(name: "Changed copy definition", contentHash: entry.contentHash)
        #expect(!BlueprintLibraryProjection.isExactRecoveryDuplicate(changedCopyDefinition, of: sourceWithCopy))
    }

    @Test("Exact receipt source is removed from recovery rows")
    func exactReceiptSourceIsHidden() throws {
        let draft = makeDraft(entry: try catalogEntry())
        let rows = BlueprintLibraryProjection.visibleRecoveryDrafts(
            drafts: [draft], installations: [try installation(for: draft)], ownerID: "owner"
        )
        #expect(rows.isEmpty)
    }

    @Test("Recovery rows remain visible when receipt source has a different share token or revision")
    func differentSourceIdentityRemainsVisible() throws {
        let entry = try catalogEntry()
        let draft = makeDraft(entry: entry)
        var otherShare = draft
        otherShare.shareToken = "another-share"
        let revisionEntry = try catalogEntry(revision: entry.revision + 1)
        var otherRevision = draft
        otherRevision.entry = revisionEntry

        let rows = BlueprintLibraryProjection.visibleRecoveryDrafts(
            drafts: [draft], installations: [try installation(for: otherShare), try installation(for: otherRevision)],
            ownerID: "owner"
        )
        #expect(rows.map(\.requestID) == [draft.requestID])
    }

    @Test("Foreign-owner and corrupt receipt sources do not hide recovery rows")
    func invalidReceiptSourcesRemainVisible() throws {
        let draft = makeDraft(entry: try catalogEntry())
        var foreignSource = draft
        foreignSource.ownerUserID = "another-owner"
        let foreignReceipt = try installation(for: foreignSource)
        let corruptReceipt = try installation(for: draft, sourceData: Data("not a draft".utf8))

        let rows = BlueprintLibraryProjection.visibleRecoveryDrafts(
            drafts: [draft], installations: [foreignReceipt, corruptReceipt], ownerID: "owner"
        )
        #expect(rows.map(\.requestID) == [draft.requestID])
    }

    @Test("Continue setup is contextual only after setup has actual date progress")
    func setupProgressPresentation() throws {
        var draft = makeDraft(entry: try catalogEntry())
        #expect(!BlueprintLibraryProjection.hasSetupProgress(draft))
        draft.mainDateConfirmed = true
        #expect(BlueprintLibraryProjection.hasSetupProgress(draft))
        draft.mainDateConfirmed = false
        draft.confirmedDates["ceremony"] = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(BlueprintLibraryProjection.hasSetupProgress(draft))
    }

    private func makeDraft(entry: BlueprintCatalogEntry) -> BlueprintSetupDraft {
        BlueprintSetupDraft(
            ownerUserID: "owner",
            entry: entry,
            requestID: UUID(uuidString: "E02F1A1A-6F43-46D6-8734-150D70E5A31D")!,
            eventName: "Saved event",
            startsAt: Date(timeIntervalSince1970: 1_800_000_000),
            timeZoneIdentifier: "America/Detroit",
            selectedChildren: ["ceremony", "reception"],
            selectedIdeas: ["flowers", "music"],
            confirmedDates: [:]
        )
    }

    private func installation(for draft: BlueprintSetupDraft, sourceData: Data? = nil) throws -> BlueprintUsedTemplate {
        let encodedSource: Data
        if let sourceData { encodedSource = sourceData }
        else { encodedSource = try JSONEncoder().encode(draft) }
        return BlueprintUsedTemplate(
            installationID: UUID(), scopeID: UUID(), catalogKey: draft.entry.catalogKey,
            revision: draft.entry.revision, templateName: "Library source", eventName: draft.eventName,
            installedAt: "2026-01-01T00:00:00Z",
            sourceDraftData: encodedSource
        )
    }

    private func catalogEntry(name: String? = nil, revision: Int? = nil, contentHash: String? = nil) throws -> BlueprintCatalogEntry {
        let url = try #require(Bundle(for: BlueprintLibraryProjectionFixtureBundle.self)
            .url(forResource: "wedding-catalog.v1", withExtension: "json"))
        let original = try #require(JSONDecoder().decode(BlueprintCatalogResponse.self, from: Data(contentsOf: url)).entries.first)
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
        object["revision"] = revision ?? original.revision
        object["contentHash"] = contentHash ?? original.contentHash
        if let name {
            var definition = try #require(object["definition"] as? [String: Any])
            var blueprint = try #require(definition["blueprint"] as? [String: Any])
            blueprint["name"] = name
            definition["blueprint"] = blueprint
            object["definition"] = definition
        }
        return try JSONDecoder().decode(BlueprintCatalogEntry.self, from: JSONSerialization.data(withJSONObject: object))
    }
}

private final class BlueprintLibraryProjectionFixtureBundle: NSObject {}
