import Foundation
import Testing
@testable import Gatherory

@MainActor
struct BlueprintPreviewWorkingCopyTests {
    @Test("Explicit Use creates and persists the default local working plan")
    func createsWorkingCopyOnUse() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = BlueprintSetupDraftStore(directoryURL: directory)
        let entry = try weddingEntry()

        let prepared = try BlueprintPreviewWorkingCopy.prepare(
            ownerID: "account-a",
            entry: entry,
            shareToken: nil,
            defaultEventName: "Our celebration",
            store: store,
            hasPendingInstallation: false
        )
        let loaded = try #require(try store.load(ownerUserID: "account-a", catalogKey: entry.catalogKey))

        #expect(prepared.ownerUserID == "account-a")
        #expect(prepared.entry.catalogKey == entry.catalogKey)
        #expect(prepared.entry.revision == entry.revision)
        #expect(prepared.entry.contentHash == entry.contentHash)
        #expect(prepared.eventName == "Our celebration")
        #expect(prepared.requestID == loaded.requestID)
        #expect(prepared.selectedChildren == loaded.selectedChildren)
        let content = try #require(BlueprintPreviewContent(entry: entry))
        #expect(prepared.selectedChildren == Set(content.children.map(\.key)))
        #expect(prepared.selectedIdeas == Set(content.ideas.map(\.key)))
        #expect(try store.all(ownerUserID: "account-a").count == 1)
    }

    @Test("New Use drafts retain every authored child without fabricated preview responses")
    func newUseDraftRetainsAllChildrenWithoutChildIdeas() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = BlueprintSetupDraftStore(directoryURL: directory)
        let entry = try weddingEntry()
        let content = try #require(BlueprintPreviewContent(entry: entry))
        let childIdeaKeys = Set(content.ideas.compactMap { idea -> String? in
            guard case .child(let key) = idea.target else { return nil }
            return key
        })
        let authoredChildKeys = Set(content.children.map(\.key))
        #expect(!authoredChildKeys.isEmpty)
        #expect(childIdeaKeys.isEmpty)

        let prepared = try BlueprintPreviewWorkingCopy.prepare(
            ownerID: "account-a", entry: entry, shareToken: nil,
            defaultEventName: "Our celebration", store: store, hasPendingInstallation: false
        )
        let allIdeaKeys = Set(content.ideas.map(\.key))
        #expect(prepared.selectedChildren == authoredChildKeys)
        #expect(prepared.selectedIdeas == allIdeaKeys)
        #expect(prepared.previewDecisions == nil)
        #expect(prepared.confirmedDates.isEmpty)
        #expect(prepared.entry.viewerState == nil)

        var resumed = BlueprintPreviewSession(
            ownerID: "account-a", entry: entry, shareToken: nil,
            savedDraft: prepared, defaultEventName: "Must not replace saved plan"
        )
        let changedDate = Date(timeIntervalSince1970: prepared.startsAt.timeIntervalSince1970 + 86_400)
        try resumed.editMainEvent(.init(
            name: prepared.eventName,
            startsAt: changedDate,
            timeZoneIdentifier: prepared.timeZoneIdentifier
        ))
        try resumed.save(to: store, hasPendingInstallation: false)

        let saved = try #require(try store.load(ownerUserID: "account-a", catalogKey: entry.catalogKey))
        #expect(saved.selectedChildren == authoredChildKeys)
        #expect(saved.selectedIdeas == allIdeaKeys)
        #expect(saved.confirmedDates.isEmpty)
        #expect(saved.mainDateConfirmed == false)
        #expect(saved.previewDecisions == nil)
        #expect(saved.entry.viewerState == nil)
    }

    @Test("Existing setup resumes unchanged and keeps its pinned older publication")
    func resumesExistingDraftUnchanged() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = BlueprintSetupDraftStore(directoryURL: directory)
        let entry = try weddingEntry()
        let existing = BlueprintSetupDraft(
            ownerUserID: "account-a",
            entry: entry,
            requestID: UUID(),
            eventName: "A carefully named plan",
            startsAt: Date(timeIntervalSince1970: 1_800_000_000),
            timeZoneIdentifier: "America/Detroit",
            selectedChildren: ["ceremony"],
            selectedIdeas: ["flowers"],
            confirmedDates: ["ceremony": Date(timeIntervalSince1970: 1_800_100_000)],
            shareToken: nil
        )
        try store.save(existing)
        let newerEntry = BlueprintCatalogEntry(
            catalogKey: entry.catalogKey,
            revision: entry.revision + 1,
            contentHash: String(repeating: "c", count: 64),
            definition: entry.definition,
            discovery: entry.discovery,
            description: entry.description,
            creator: entry.creator
        )

        let resumed = try BlueprintPreviewWorkingCopy.prepare(
            ownerID: "account-a",
            entry: newerEntry,
            shareToken: nil,
            defaultEventName: "A new default",
            store: store,
            hasPendingInstallation: false
        )

        #expect(resumed.requestID == existing.requestID)
        #expect(resumed.entry.revision == existing.entry.revision)
        #expect(resumed.entry.contentHash == existing.entry.contentHash)
        #expect(resumed.eventName == existing.eventName)
        #expect(resumed.selectedChildren == existing.selectedChildren)
        #expect(resumed.selectedIdeas == existing.selectedIdeas)
        #expect(resumed.confirmedDates == existing.confirmedDates)
    }

    @Test("Public and shared-link working plans have separate identities")
    func publicAndSharedPlansAreDistinct() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = BlueprintSetupDraftStore(directoryURL: directory)
        let entry = try weddingEntry()
        let token = String(repeating: "a1", count: 32)

        let publicPlan = try BlueprintPreviewWorkingCopy.prepare(
            ownerID: "account-a", entry: entry, shareToken: nil,
            defaultEventName: "Public plan", store: store, hasPendingInstallation: false
        )
        let sharedPlan = try BlueprintPreviewWorkingCopy.prepare(
            ownerID: "account-a", entry: entry, shareToken: token,
            defaultEventName: "Shared plan", store: store, hasPendingInstallation: false
        )

        #expect(publicPlan.requestID != sharedPlan.requestID)
        #expect(publicPlan.shareToken == nil)
        #expect(sharedPlan.shareToken == token)
        #expect(try store.load(ownerUserID: "account-a", catalogKey: entry.catalogKey)?.requestID == publicPlan.requestID)
        #expect(try store.load(ownerUserID: "account-a", catalogKey: entry.catalogKey, shareToken: token)?.requestID == sharedPlan.requestID)
        #expect(try store.all(ownerUserID: "account-a").count == 2)
    }

    @Test("The same shared source gets an independent working plan for each owner")
    func workingCopiesAreOwnerIsolated() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = BlueprintSetupDraftStore(directoryURL: directory)
        let entry = try weddingEntry()
        let token = String(repeating: "b2", count: 32)

        let accountA = try BlueprintPreviewWorkingCopy.prepare(
            ownerID: "account-a", entry: entry, shareToken: token,
            defaultEventName: "A's plan", store: store, hasPendingInstallation: false
        )
        let accountB = try BlueprintPreviewWorkingCopy.prepare(
            ownerID: "account-b", entry: entry, shareToken: token,
            defaultEventName: "B's plan", store: store, hasPendingInstallation: false
        )
        let reloadedA = try #require(try store.load(ownerUserID: "account-a", shareToken: token))
        let reloadedB = try #require(try store.load(ownerUserID: "account-b", shareToken: token))

        #expect(reloadedA.ownerUserID == "account-a")
        #expect(reloadedA.requestID == accountA.requestID)
        #expect(reloadedA.eventName == "A's plan")
        #expect(reloadedB.ownerUserID == "account-b")
        #expect(reloadedB.requestID == accountB.requestID)
        #expect(reloadedB.requestID != reloadedA.requestID)
        #expect(reloadedB.eventName == "B's plan")
        #expect(try store.all(ownerUserID: "account-a").count == 1)
        #expect(try store.all(ownerUserID: "account-b").count == 1)
    }

    @Test("A pending installation blocks Use before reading or writing a plan")
    func pendingInstallationBlocksUseBeforeWrite() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = BlueprintSetupDraftStore(directoryURL: directory)
        let entry = try weddingEntry()

        #expect(throws: BlueprintPreviewWorkingCopy.PrepareError.installationPending) {
            try BlueprintPreviewWorkingCopy.prepare(
                ownerID: "account-a", entry: entry, shareToken: nil,
                defaultEventName: "Unused", store: store, hasPendingInstallation: true
            )
        }
        #expect(!FileManager.default.fileExists(atPath: directory.path))
    }

    @Test("A pending installation rejects Use without changing an existing draft")
    func pendingInstallationPreservesExistingDraft() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = BlueprintSetupDraftStore(directoryURL: directory)
        let entry = try weddingEntry()
        let token = String(repeating: "c3", count: 32)
        let original = BlueprintSetupDraft(
            ownerUserID: "account-a",
            entry: entry,
            requestID: UUID(),
            eventName: "Saved before pending work",
            startsAt: Date(timeIntervalSince1970: 1_800_000_000),
            timeZoneIdentifier: "America/Detroit",
            selectedChildren: ["ceremony"],
            selectedIdeas: ["flowers"],
            confirmedDates: ["ceremony": Date(timeIntervalSince1970: 1_800_100_000)],
            shareToken: token
        )
        try store.save(original)
        let before = try directorySnapshot(directory)

        #expect(throws: BlueprintPreviewWorkingCopy.PrepareError.installationPending) {
            try BlueprintPreviewWorkingCopy.prepare(
                ownerID: "account-a", entry: entry, shareToken: token,
                defaultEventName: "Must not replace saved plan", store: store,
                hasPendingInstallation: true
            )
        }

        let after = try directorySnapshot(directory)
        let unchanged = try #require(try store.load(ownerUserID: "account-a", shareToken: token))
        #expect(after == before)
        #expect(unchanged.requestID == original.requestID)
        #expect(unchanged.entry.revision == original.entry.revision)
        #expect(unchanged.entry.contentHash == original.entry.contentHash)
        #expect(unchanged.eventName == original.eventName)
        #expect(unchanged.startsAt == original.startsAt)
        #expect(unchanged.timeZoneIdentifier == original.timeZoneIdentifier)
        #expect(unchanged.selectedChildren == original.selectedChildren)
        #expect(unchanged.selectedIdeas == original.selectedIdeas)
        #expect(unchanged.confirmedDates == original.confirmedDates)
    }

    @Test("An empty owner cannot create a working plan")
    func emptyOwnerCannotUse() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = BlueprintSetupDraftStore(directoryURL: directory)
        let entry = try weddingEntry()

        #expect(throws: BlueprintPreviewWorkingCopy.PrepareError.emptyOwner) {
            try BlueprintPreviewWorkingCopy.prepare(
                ownerID: "", entry: entry, shareToken: nil,
                defaultEventName: "Unused", store: store, hasPendingInstallation: false
            )
        }
        #expect(!FileManager.default.fileExists(atPath: directory.path))
    }

    private func weddingEntry() throws -> BlueprintCatalogEntry {
        let url = try #require(Bundle(for: PreviewWorkingCopyFixtureBundle.self)
            .url(forResource: "wedding-catalog.v1", withExtension: "json"))
        return try #require(JSONDecoder().decode(BlueprintCatalogResponse.self, from: Data(contentsOf: url)).entries.first)
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "PreviewWorkingCopy-\(UUID().uuidString)")
    }

    private func directorySnapshot(_ directory: URL) throws -> [String: Data] {
        let urls = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        return try urls.reduce(into: [:]) { snapshot, url in
            let isDirectory = try url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true
            if isDirectory {
                let nested = try directorySnapshot(url)
                for (path, data) in nested {
                    snapshot[url.lastPathComponent + "/" + path] = data
                }
            } else {
                snapshot[url.lastPathComponent] = try Data(contentsOf: url)
            }
        }
    }
}

private final class PreviewWorkingCopyFixtureBundle: NSObject {}
