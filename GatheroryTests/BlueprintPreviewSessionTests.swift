import Foundation
import Testing
@testable import Gatherory

@MainActor
struct BlueprintPreviewSessionTests {
    @Test("Removing a public main cover persists an explicit null customization")
    func removalPersistsAsExplicitNull() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = BlueprintSetupDraftStore(directoryURL: directory)
        var entry = try weddingEntry()
        var discovery = try #require(entry.discovery)
        discovery.coverImageURL = "https://cdn.gatherory.com/explore/covers/wedding/\(String(repeating: "d", count: 64))/card.jpg"
        entry.discovery = discovery

        var session = makeSession(entry)
        #expect(session.content?.publicCoverImageURL == discovery.coverImageURL)
        session.editCoverAssetID(nil)
        #expect(session.customizations.overridesCover)
        #expect(session.content?.publicCoverImageURL == nil)
        try session.save(to: store, hasPendingInstallation: false)

        let saved = try #require(try store.load(ownerUserID: "account-a", catalogKey: entry.catalogKey))
        let customization = try #require(saved.customizations)
        #expect(customization.overridesCover)
        #expect(customization.coverAssetId == nil)
        let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(customization)) as? [String: Any]
        #expect(encoded?["coverAssetId"] is NSNull)
    }

    @Test("Fresh exact-revision discovery metadata refreshes pinned preview drafts")
    func refreshesCachedDiscoveryMetadataWithoutRestoringRemovedIdeaCover() throws {
        let freshEntry = try weddingEntry()
        var cachedEntry = freshEntry
        var cachedDiscovery = try #require(cachedEntry.discovery)
        cachedDiscovery.coverImages = nil
        cachedEntry.discovery = cachedDiscovery
        let sourceIdeas = try #require(freshEntry.definition.modules.first { $0.type == "ideas" }?
            .decodeConfiguration(BlueprintIdeasConfig.self)?.ideas)
        let assignments = try #require(freshEntry.discovery?.coverImages?.ideas)
        let removedKey = try #require(assignments.keys.sorted().first)
        var removedIdea = try #require(sourceIdeas.first { $0.key == removedKey })
        removedIdea.coverAssetId = nil
        removedIdea.coverAssetIdWasProvided = true
        var overlay = BlueprintCustomization()
        try overlay.upsert(removedIdea)

        var draft = BlueprintSetupDraft(ownerUserID: "account-a", entry: cachedEntry, requestID: UUID(),
                                        eventName: "My pinned event", startsAt: .now,
                                        timeZoneIdentifier: "UTC", selectedChildren: [], selectedIdeas: [],
                                        confirmedDates: [:])
        draft.customizations = overlay
        draft.previewDecisions = [removedKey: .maybe]

        var session = BlueprintPreviewSession(ownerID: "account-a", entry: freshEntry, shareToken: nil,
                                              savedDraft: draft, defaultEventName: "Default")
        let content = try #require(session.content)
        let remainingMappedKeys = Set(assignments.keys).subtracting([removedKey])
        #expect(session.entry.revision == cachedEntry.revision)
        #expect(session.entry.contentHash == cachedEntry.contentHash)
        #expect(session.entry.definition.blueprint.name == cachedEntry.definition.blueprint.name)
        #expect(content.publicIdeaCoverImageURLs[removedKey] == nil)
        #expect(remainingMappedKeys.contains { content.publicIdeaCoverImageURLs[$0] != nil })
        #expect(session.responses[removedKey] == .maybe)
        #expect(session.customizations.ideas.first { $0.key == removedKey }?.coverAssetIdWasProvided == true)

        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = BlueprintSetupDraftStore(directoryURL: directory)
        try store.save(draft)
        try session.save(to: store, hasPendingInstallation: false)
        let savedEntry = try #require(try store.load(ownerUserID: "account-a", catalogKey: cachedEntry.catalogKey)?.entry)
        #expect(savedEntry.discovery?.coverImages?.ideas == assignments)
        #expect(savedEntry.definition.blueprint.name == cachedEntry.definition.blueprint.name)
        #expect(savedEntry.revision == cachedEntry.revision)
        #expect(savedEntry.contentHash == cachedEntry.contentHash)

        // Installed/source drafts use the same metadata refresh while retaining
        // their pinned definition and customization state.
        let remainingMappedKey = try #require(remainingMappedKeys.sorted().first)
        let sourceSession = BlueprintPreviewSession(ownerID: "account-a", entry: freshEntry, shareToken: nil,
                                                    savedDraft: nil, defaultEventName: "Default",
                                                    sourceDraft: draft)
        #expect(sourceSession.content?.publicIdeaCoverImageURLs[removedKey] == nil)
        #expect(sourceSession.content?.publicIdeaCoverImageURLs[remainingMappedKey] != nil)
        #expect(sourceSession.entry.contentHash == cachedEntry.contentHash)
    }

    @Test("Discovery metadata from another revision or content hash cannot refresh a pinned draft")
    func keepsPinnedMetadataOnCatalogMismatch() throws {
        var cachedEntry = try weddingEntry()
        var cachedDiscovery = try #require(cachedEntry.discovery)
        cachedDiscovery.coverImages = nil
        cachedEntry.discovery = cachedDiscovery
        let draft = BlueprintSetupDraft(ownerUserID: "account-a", entry: cachedEntry, requestID: UUID(),
                                        eventName: "Pinned", startsAt: .now, timeZoneIdentifier: "UTC",
                                        selectedChildren: [], selectedIdeas: [], confirmedDates: [:])

        let differentRevision = BlueprintCatalogEntry(catalogKey: cachedEntry.catalogKey,
                                                      revision: cachedEntry.revision + 1,
                                                      contentHash: cachedEntry.contentHash,
                                                      definition: cachedEntry.definition,
                                                      discovery: try weddingEntry().discovery,
                                                      description: cachedEntry.description, creator: cachedEntry.creator)
        let revisionMismatch = BlueprintPreviewSession(ownerID: "account-a", entry: differentRevision,
                                                       shareToken: nil, savedDraft: draft, defaultEventName: "Default")
        #expect(revisionMismatch.entry.revision == cachedEntry.revision)
        #expect(revisionMismatch.content?.publicIdeaCoverImageURLs.isEmpty == true)

        let fresh = try weddingEntry()
        let hashMismatchEntry = BlueprintCatalogEntry(catalogKey: cachedEntry.catalogKey,
                                                      revision: cachedEntry.revision,
                                                      contentHash: String(repeating: "a", count: 64),
                                                      definition: fresh.definition, discovery: fresh.discovery,
                                                      description: fresh.description, creator: fresh.creator)
        let hashMismatch = BlueprintPreviewSession(ownerID: "account-a", entry: hashMismatchEntry,
                                                   shareToken: nil, savedDraft: draft, defaultEventName: "Default")
        #expect(hashMismatch.entry.contentHash == cachedEntry.contentHash)
        #expect(hashMismatch.content?.publicIdeaCoverImageURLs.isEmpty == true)
    }

    @Test("Preview swipes and discard never create a draft or change the catalog")
    func stagedChoicesStayInMemory() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = BlueprintSetupDraftStore(directoryURL: directory)
        let entry = try weddingEntry()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let original = try encoder.encode(entry)
        var session = makeSession(entry)
        session.decide(.pass, key: "venue")
        session.decide(.maybe, key: "flowers")
        session.decide(.love, key: "unknown")
        #expect(session.responses == ["venue": .pass, "flowers": .maybe])
        #expect(BlueprintIdeaResponsePresentation.summary(session.responses["venue"]).pass == 1)
        #expect(BlueprintIdeaResponsePresentation.summary(session.responses["flowers"]).maybe == 1)
        #expect(session.isDirty)
        #expect(try store.all(ownerUserID: "account-a").isEmpty)
        #expect(!FileManager.default.fileExists(atPath: directory.path))
        #expect(session.entry.contentHash == entry.contentHash)
        #expect(try encoder.encode(session.entry) == original)
        session.discardChanges()
        #expect(!session.isDirty)
        #expect(session.responses.isEmpty)
        #expect(BlueprintIdeaResponsePresentation.summary(session.responses["venue"]).unanswered == 1)
    }

    @Test("Only explicit Save Draft persists choices and selects all content for a new plan")
    func explicitSaveAndResume() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = BlueprintSetupDraftStore(directoryURL: directory)
        let entry = try weddingEntry()
        var session = makeSession(entry)
        session.decide(.pass, key: "venue")
        session.decide(.maybe, key: "flowers")
        session.decide(.love, key: "food")
        try session.save(to: store, hasPendingInstallation: false)
        let saved = try #require(try store.load(ownerUserID: "account-a", catalogKey: entry.catalogKey))
        let content = try #require(BlueprintPreviewContent(entry: entry))
        #expect(saved.selectedIdeas == Set(content.ideas.map(\.key)))
        #expect(saved.selectedChildren == Set(content.children.map(\.key)))
        #expect(saved.confirmedDates.isEmpty)
        #expect(saved.previewDecisions == session.responses)
        #expect(!session.isDirty)
        let resumed = makeSession(entry, draft: saved)
        #expect(resumed.responses == session.responses)
        #expect(BlueprintIdeaResponsePresentation.summary(resumed.responses["food"]).love == 1)
        #expect(!resumed.isDirty)
        #expect(resumed.draft?.requestID == saved.requestID)
    }

    @Test("Saving preview choices preserves custom content, confirmed dates, exclusions, identity and link")
    func savesWithoutReplacingSetup() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = BlueprintSetupDraftStore(directoryURL: directory)
        let entry = try weddingEntry()
        let token = String(repeating: "a", count: 64)
        let date = Date(timeIntervalSince1970: 1_800_000_000.125)
        var draft = BlueprintSetupDraft(
            ownerUserID: "account-a", entry: entry, requestID: UUID(),
            eventName: "Our private celebration", startsAt: date,
            timeZoneIdentifier: "America/Detroit", selectedChildren: ["ceremony"],
            selectedIdeas: ["venue"], confirmedDates: ["ceremony": date], shareToken: token
        )
        draft.customizations = BlueprintCustomization(ideas: [
            .init(key: "custom_snacks", title: "Late snacks", category: "food", notes: "Our list", target: .child(key: "ceremony"), configuration: ["version": .integer(1)])
        ])
        try store.save(draft)
        var session = makeSession(entry, draft: draft, token: token)
        #expect(session.content?.title == draft.eventName)
        #expect(session.content?.ideas(for: "ceremony").contains { $0.key == "custom_snacks" } == true)
        session.decide(.pass, key: "venue")
        session.decide(.maybe, key: "flowers")
        session.decide(.love, key: "custom_snacks")
        try session.save(to: store, hasPendingInstallation: false)
        let saved = try #require(try store.load(ownerUserID: "account-a", shareToken: token))
        #expect(saved.requestID == draft.requestID)
        #expect(saved.entry.contentHash == entry.contentHash)
        #expect(saved.eventName == draft.eventName)
        #expect(saved.startsAt == date)
        #expect(saved.confirmedDates == draft.confirmedDates)
        #expect(saved.selectedChildren == draft.selectedChildren)
        #expect(saved.selectedIdeas == ["venue"])
        #expect(saved.customizations == draft.customizations)
        #expect(saved.shareToken == token)
        let resumed = makeSession(entry, draft: saved, token: token)
        let resumedContent = try #require(resumed.content)
        let home = resumedContent.homeContent(responses: resumed.responses)
        #expect(home.eventIDs == [.main, .child("ceremony")])
        #expect(home.ideas(for: "ceremony").map(\.key) == ["custom_snacks"])
        #expect(resumed.draft?.confirmedDates == draft.confirmedDates)
        #expect(resumed.content?.children.count == 4)
        #expect(try store.all(ownerUserID: "account-b").isEmpty)
    }

    @Test("Pending recovery and concurrent draft replacement prevent preview overwrite")
    func blocksUnsafeSave() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = BlueprintSetupDraftStore(directoryURL: directory)
        let entry = try weddingEntry()
        var first = makeSession(entry)
        first.decide(.pass, key: "venue")
        #expect(throws: BlueprintPreviewSession.SaveError.self) {
            try first.save(to: store, hasPendingInstallation: true)
        }
        #expect(try store.all(ownerUserID: "account-a").isEmpty)
        var other = makeSession(entry)
        other.decide(.love, key: "venue")
        try other.save(to: store, hasPendingInstallation: false)
        let request = try #require(other.draft?.requestID)
        #expect(throws: BlueprintPreviewSession.SaveError.self) {
            try first.save(to: store, hasPendingInstallation: false)
        }
        #expect(try store.load(ownerUserID: "account-a", catalogKey: entry.catalogKey)?.requestID == request)
        #expect(try store.load(ownerUserID: "account-a", catalogKey: entry.catalogKey)?.selectedIdeas.contains("venue") == true)
    }

    @Test("A mismatched account draft cannot become another account's preview session")
    func rejectsCrossAccountSeed() throws {
        let entry = try weddingEntry()
        let source = BlueprintSetupDraft(ownerUserID: "account-b", entry: entry, requestID: UUID(), eventName: "B private", startsAt: .now,
                                         timeZoneIdentifier: "UTC", selectedChildren: [], selectedIdeas: [], confirmedDates: [:], previewDecisions: ["venue": .pass])
        let session = makeSession(entry, draft: source)
        #expect(session.draft == nil)
        #expect(session.responses.isEmpty)
        #expect(session.content?.title == entry.definition.blueprint.name)
    }

    private func makeSession(_ entry: BlueprintCatalogEntry, draft: BlueprintSetupDraft? = nil, token: String? = nil) -> BlueprintPreviewSession {
        BlueprintPreviewSession(ownerID: "account-a", entry: entry, shareToken: token, savedDraft: draft, defaultEventName: "My celebration")
    }

    private func weddingEntry() throws -> BlueprintCatalogEntry {
        let url = try #require(Bundle(for: PreviewSessionFixtureBundle.self).url(forResource: "wedding-catalog.v1", withExtension: "json"))
        return try #require(JSONDecoder().decode(BlueprintCatalogResponse.self, from: Data(contentsOf: url)).entries.first)
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "PreviewSession-\(UUID().uuidString)")
    }
}

private final class PreviewSessionFixtureBundle: NSObject {}
