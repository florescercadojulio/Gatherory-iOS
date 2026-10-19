import Foundation
import Testing
@testable import Gatherory

@MainActor
struct BlueprintLibraryModelTests {
    private enum Offline: Error { case unavailable }

    @Test("Cached history appears immediately, stays account scoped, and survives offline refresh")
    func cacheAndOfflineRefresh() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = BlueprintLibraryCache(directoryURL: directory)
        let accountA = "account-a"
        let accountB = "account-b"
        let rowA = row(eventName: "A's event")
        let rowB = row(eventName: "B's event")
        try cache.save([rowA], ownerID: accountA)
        try cache.save([rowB], ownerID: accountB)

        let model = BlueprintLibraryModel(ownerID: accountA, cache: cache)
        #expect(model.installations == [rowA])
        await model.load { throw Offline.unavailable }
        #expect(model.installations == [rowA])
        #expect(model.refreshFailed)
        #expect(!model.loading)

        let otherAccount = BlueprintLibraryModel(ownerID: accountB, cache: cache)
        #expect(otherAccount.installations == [rowB])
        #expect(try cache.load(ownerID: accountA) == [rowA])
    }

    @Test("A local import recorded after model creation appears on an offline reload")
    func rereadsRecordedCacheBeforeRefresh() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = BlueprintLibraryCache(directoryURL: directory)
        let model = BlueprintLibraryModel(ownerID: "account", cache: cache)
        #expect(model.installations.isEmpty)

        let imported = row(eventName: "Imported locally")
        try cache.record(imported, ownerID: "account")
        await model.load { throw Offline.unavailable }

        #expect(model.installations == [imported])
        #expect(model.refreshFailed)
        #expect(!model.cacheFailed)
    }

    @Test("A failed cache reread preserves visible rows and reports the cache error")
    func failedCacheRereadPreservesMemory() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = BlueprintLibraryCache(directoryURL: directory)
        let saved = row(eventName: "Still visible")
        try cache.save([saved], ownerID: "account")
        let model = BlueprintLibraryModel(ownerID: "account", cache: cache)
        let cacheFile = try #require(
            FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).first
        )
        try Data("corrupt".utf8).write(to: cacheFile, options: .atomic)

        await model.load { throw Offline.unavailable }
        #expect(model.installations == [saved])
        #expect(model.cacheFailed)
        #expect(model.refreshFailed)
    }

    @Test("Recording an import merges stable installation IDs and caps recent history")
    func recordImport() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = BlueprintLibraryCache(directoryURL: directory)
        let original = row(eventName: "Original")
        let priorRows = [original] + (1..<200).map { _ in row() }
        try cache.save(priorRows, ownerID: "account")

        let updated = row(eventName: "Imported again", installationID: original.installationID)
        try cache.record(updated, ownerID: "account")
        let merged = try cache.load(ownerID: "account")
        #expect(merged.count == 200)
        #expect(merged.first == updated)
        #expect(merged.filter { $0.installationID == original.installationID }.count == 1)

        let newImport = row(eventName: "New import")
        try cache.record(newImport, ownerID: "account")
        let capped = try cache.load(ownerID: "account")
        #expect(capped.count == 200)
        #expect(capped.first == newImport)
        #expect(!capped.contains(where: { $0.installationID == priorRows.last?.installationID }))
    }

    @Test("Refresh preserves server order and removes exact duplicate installation IDs")
    func responseOrderAndDuplicateHandling() async {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = BlueprintLibraryModel(ownerID: "account", cache: BlueprintLibraryCache(directoryURL: directory))
        let newest = row(eventName: "Second", installationID: UUID())
        let first = row(eventName: "First", installationID: UUID(), catalogKey: "cottage")
        await model.load { BlueprintLibraryResponse(installations: [newest, first, newest]) }
        #expect(model.installations == [newest, first])
        #expect(!model.refreshFailed)
    }

    @Test("Malformed response cannot replace previously cached history")
    func invalidResponsePreservesCache() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = BlueprintLibraryCache(directoryURL: directory)
        let saved = row(eventName: "Saved")
        try cache.save([saved], ownerID: "account")
        let model = BlueprintLibraryModel(ownerID: "account", cache: cache)
        let conflictingDuplicate = row(eventName: "Different", installationID: saved.installationID)
        await model.load { BlueprintLibraryResponse(installations: [saved, conflictingDuplicate]) }
        #expect(model.installations == [saved])
        #expect(model.refreshFailed)
        #expect(try cache.load(ownerID: "account") == [saved])
    }

    @Test("An older in-flight response cannot overwrite the latest response")
    func reorderedResponses() async {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = BlueprintLibraryModel(ownerID: "account", cache: BlueprintLibraryCache(directoryURL: directory))
        let earlier = ResponseLatch()
        let later = ResponseLatch()
        let earlyTask = Task { await model.load { await earlier.fetch() } }
        await earlier.waitUntilStarted()
        let lateTask = Task { await model.load { await later.fetch() } }
        await later.waitUntilStarted()

        let latestRow = row(eventName: "Latest")
        later.resolve(BlueprintLibraryResponse(installations: [latestRow]))
        await lateTask.value
        earlier.resolve(BlueprintLibraryResponse(installations: [row(eventName: "Stale")]))
        await earlyTask.value

        #expect(model.installations == [latestRow])
        #expect(!model.loading)
        #expect(!model.refreshFailed)
    }

    @Test("A canceled refresh does not prevent a later load")
    func canceledLoadCanRetry() async {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = BlueprintLibraryModel(ownerID: "account", cache: BlueprintLibraryCache(directoryURL: directory))
        let latch = ResponseLatch()
        let canceledTask = Task { await model.load { await latch.fetch() } }
        await latch.waitUntilStarted()
        canceledTask.cancel()
        latch.resolve(BlueprintLibraryResponse(installations: [row(eventName: "Canceled result")]))
        await canceledTask.value
        #expect(model.installations.isEmpty)
        #expect(!model.loading)

        let recovered = row(eventName: "Recovered")
        await model.load { BlueprintLibraryResponse(installations: [recovered]) }
        #expect(model.installations == [recovered])
        #expect(!model.refreshFailed)
        #expect(!model.loading)
    }

    @Test("Invalidation clears account data and ignores an in-flight completion")
    func invalidation() async {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = BlueprintLibraryModel(ownerID: "account", cache: BlueprintLibraryCache(directoryURL: directory))
        let latch = ResponseLatch()
        let task = Task { await model.load { await latch.fetch() } }
        await latch.waitUntilStarted()
        model.invalidate()
        latch.resolve(BlueprintLibraryResponse(installations: [row(eventName: "Old account")]))
        await task.value
        #expect(model.installations.isEmpty)
        #expect(!model.loading)
    }

    @Test("Cache envelope owner is checked independently of its file path")
    func strictOwnerEnvelope() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = BlueprintLibraryCache(directoryURL: directory)
        try cache.save([row()], ownerID: "account-a")
        let file = try #require(FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).first)
        var object = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        object["ownerID"] = "account-b"
        try JSONSerialization.data(withJSONObject: object).write(to: file, options: .atomic)

        do {
            _ = try cache.load(ownerID: "account-a")
            Issue.record("A cache envelope for a different account must be rejected")
        } catch let error as BlueprintLibraryCache.StoreError {
            #expect(error == .ownerMismatch)
        } catch {
            Issue.record("Unexpected cache error: \(error)")
        }
    }

    @Test("Wire identifiers and Unicode name bounds are validated precisely")
    func validationBounds() {
        let valid = row()
        #expect(BlueprintLibraryCache.validated([valid]) == [valid])
        #expect(BlueprintLibraryCache.validated([row(revision: 0)]) == nil)
        #expect(BlueprintLibraryCache.validated([row(installedAt: "yesterday")]) == nil)
        #expect(BlueprintLibraryCache.validated([row(catalogKey: String(repeating: "a", count: 100))]) != nil)
        #expect(BlueprintLibraryCache.validated([row(catalogKey: String(repeating: "a", count: 101))]) == nil)
        #expect(BlueprintLibraryCache.validated([row(catalogKey: "Wedding-template")]) == nil)
        #expect(BlueprintLibraryCache.validated([row(catalogKey: "a_b9")]) != nil)
        #expect(BlueprintLibraryCache.validated([row(templateName: String(repeating: "x", count: 160))]) != nil)
        #expect(BlueprintLibraryCache.validated([row(templateName: String(repeating: "x", count: 161))]) == nil)
        #expect(BlueprintLibraryCache.validated([row(eventName: String(repeating: "e\u{301}", count: 60))]) != nil)
        #expect(BlueprintLibraryCache.validated([row(eventName: String(repeating: "e\u{301}", count: 61))]) == nil)
        #expect(BlueprintLibraryCache.validated(Array(repeating: valid, count: 201)) == nil)
        #expect(valid.installedDate != nil)
        #expect(row(installedAt: "2026-10-15T12:30:45Z").installedDate != nil)
        #expect(row(installedAt: "2026-10-15T12:30:45.123+00:00").installedDate != nil)
        #expect(row(installedAt: "2026-10-15T12:30:45.1234+00:00").installedDate == nil)
    }

    @Test("Deleting a library entry survives refresh/relaunch without deleting receipts or another account's entry")
    func deleteLibraryEntryOnly() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let suite = "BlueprintVisibility-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let visibility = BlueprintLibraryVisibilityStore(defaults: defaults)
        let cache = BlueprintLibraryCache(directoryURL: directory)
        let installed = row()
        let other = row(catalogKey: "cottage")
        try cache.save([installed, other], ownerID: "a")
        try cache.save([installed], ownerID: "b")
        let model = BlueprintLibraryModel(ownerID: "a", cache: cache, visibility: visibility)
        await model.load {
            model.removeFromLibrary(installed)
            return BlueprintLibraryResponse(installations: [installed, other])
        }
        #expect(model.installations == [other])
        #expect(try cache.load(ownerID: "a") == [installed, other])
        let relaunched = BlueprintLibraryModel(ownerID: "a", cache: cache, visibility: visibility)
        #expect(relaunched.installations == [other])
        await relaunched.load { throw Offline.unavailable }
        #expect(relaunched.installations == [other])
        let secondAccount = BlueprintLibraryModel(ownerID: "b", cache: cache, visibility: visibility)
        #expect(secondAccount.installations == [installed])
        model.invalidate()
        model.removeFromLibrary(other)
        #expect(!visibility.hiddenIDs(ownerID: "a").contains(other.id))
    }

    @Test("Installed previews cannot install again without explicit Create Workspace")
    func installedActionPolicy() {
        #expect(BlueprintLibraryActionPolicy.blocksInlineInstall(isInstalled: true, explicitCreateWorkspace: false))
        #expect(!BlueprintLibraryActionPolicy.blocksInlineInstall(isInstalled: true, explicitCreateWorkspace: true))
        #expect(!BlueprintLibraryActionPolicy.blocksInlineInstall(isInstalled: false, explicitCreateWorkspace: false))
    }

    @Test("Server refresh retains the local offline source without changing receipt identity")
    func keepsOfflineSource() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = BlueprintLibraryCache(directoryURL: directory)
        let receipt = row()
        var local = receipt
        local.sourceDraftData = Data("local source".utf8)
        try cache.save([local], ownerID: "a")
        let model = BlueprintLibraryModel(ownerID: "a", cache: cache)
        await model.load { BlueprintLibraryResponse(installations: [receipt]) }
        #expect(model.installations == [local])
        #expect(try cache.load(ownerID: "a") == [local])
    }

    @Test("Workspace copies with different dates remain one blueprint across refresh and offline relaunch")
    func repeatedCopiesDoNotCreateBlueprints() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = BlueprintLibraryCache(directoryURL: directory)
        let original = row(eventName: "Original date", installedAt: "2026-10-15T12:00:00Z")
        let copy = row(eventName: "New workspace date", installedAt: "2026-10-19T12:00:00Z")
        let revision = row(revision: 3)
        try cache.save([original], ownerID: "a")
        let model = BlueprintLibraryModel(ownerID: "a", cache: cache)
        await model.load { BlueprintLibraryResponse(installations: [copy, revision, original]) }
        #expect(model.installations == [revision, original])
        #expect(try cache.load(ownerID: "a") == [copy, revision, original])
        let relaunched = BlueprintLibraryModel(ownerID: "a", cache: cache)
        await relaunched.load { throw Offline.unavailable }
        #expect(relaunched.installations == [revision, original])
        #expect(relaunched.installations.last?.id == original.id)
        #expect(relaunched.installations.last?.eventName == "Original date")
    }

    private func row(
        eventName: String = "Gathering",
        installationID: UUID = UUID(),
        catalogKey: String = "wedding",
        templateName: String = "Wedding",
        revision: Int = 2,
        installedAt: String = "2026-10-15T12:30:45.123Z"
    ) -> BlueprintUsedTemplate {
        BlueprintUsedTemplate(
            installationID: installationID,
            scopeID: UUID(),
            catalogKey: catalogKey,
            revision: revision,
            templateName: templateName,
            eventName: eventName,
            installedAt: installedAt
        )
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("BlueprintLibraryTests-\(UUID().uuidString)", isDirectory: true)
    }
}

@MainActor
private final class ResponseLatch {
    private var continuation: CheckedContinuation<BlueprintLibraryResponse, Never>?
    private var startedContinuation: CheckedContinuation<Void, Never>?

    func fetch() async -> BlueprintLibraryResponse {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            startedContinuation?.resume()
            startedContinuation = nil
        }
    }

    func waitUntilStarted() async {
        guard continuation == nil else { return }
        await withCheckedContinuation { startedContinuation = $0 }
    }

    func resolve(_ response: BlueprintLibraryResponse) {
        continuation?.resume(returning: response)
        continuation = nil
    }
}
