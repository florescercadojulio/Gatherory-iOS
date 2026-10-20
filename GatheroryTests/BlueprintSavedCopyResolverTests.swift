import Foundation
import CryptoKit
import Testing
@testable import Gatherory

@MainActor
struct BlueprintSavedCopyResolverTests {
    @Test("Saved-copy snapshots preserve main and child to-dos with their stable targets")
    func snapshotPreservesTodos() throws {
        let source = try weddingEntry()
        let decoder = JSONDecoder()
        let encoder = JSONEncoder()
        var root = try #require(JSONSerialization.jsonObject(with: encoder.encode(source)) as? [String: Any])
        var definition = try #require(root["definition"] as? [String: Any])
        var modules = try #require(definition["modules"] as? [[String: Any]])
        modules.append([
            "key": "starter_todos", "type": "todos", "version": 1, "required": false,
            "config": ["todos": [
                ["key": "confirm-venue", "title": "Confirm venue", "target": ["kind": "main"]],
                ["key": "book-transport", "title": "Book transport", "websiteURL": "https://example.com",
                 "target": ["kind": "child", "key": "ceremony"]]
            ]]
        ])
        definition["modules"] = modules
        root["definition"] = definition
        let entry = try decoder.decode(BlueprintCatalogEntry.self, from: JSONSerialization.data(withJSONObject: root))

        let snapshot = try BlueprintDraftContent.snapshot(of: entry)
        #expect(snapshot.todos.map(\.key) == ["confirm-venue", "book-transport"])
        #expect(snapshot.todos[0].target == .main)
        #expect(snapshot.todos[1].target == .child(key: "ceremony"))
        #expect(snapshot.todos[1].websiteURL == "https://example.com")

        let decodedCopy = try decoder.decode(BlueprintCatalogEntry.self, from: encoder.encode(entry))
        #expect(try BlueprintDraftContent.snapshot(of: decodedCopy).todos == snapshot.todos)
    }

    @Test("Copies the original snapshot and attaches a differently keyed private catalog entry")
    func copiesOriginalSnapshotAndAttachesPrivateEntry() async throws {
        let context = try makeContext()
        defer { try? FileManager.default.removeItem(at: context.directory) }
        var draft = context.draft
        var overlay = BlueprintCustomization()
        try overlay.upsert(.init(key: "ceremony", title: "Our custom ceremony", purpose: "part_of_event",
                                 category: "ceremony", scheduleProposal: nil))
        draft.customizations = overlay
        try context.store.save(draft)
        let privateEntry = try weddingEntry(catalogKey: "personal_\(UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased())")
        let record = BlueprintPersonalRecord(id: UUID(), draftVersion: 1, publishedRevision: privateEntry.revision,
                                             listedRevision: nil, catalogEntry: privateEntry)
        let transport = SavedCopyFakeTransport { requestID, content in
            let persisted = try context.store.load(ownerUserID: "account-a", catalogKey: "wedding", shareToken: context.draft.shareToken)
            let expectedContent = try BlueprintDraftContent.snapshot(of: context.draft.entry)
            #expect(persisted?.copyRequestID == requestID)
            #expect(content == expectedContent)
            return record
        }

        let resolved = try await resolve(draft, context: context, transport: transport)

        #expect(transport.calls.count == 1)
        #expect(resolved.entry.catalogKey == context.draft.entry.catalogKey)
        #expect(resolved.shareToken == context.draft.shareToken)
        #expect(resolved.copyEntry?.catalogKey == privateEntry.catalogKey)
        #expect(resolved.installationEntry.catalogKey == privateEntry.catalogKey)
        #expect(resolved.installationShareToken == nil)
        let savedCopy = try context.store.load(ownerUserID: "account-a", catalogKey: "wedding", shareToken: context.draft.shareToken)
        #expect(savedCopy?.copyEntry?.catalogKey == privateEntry.catalogKey)
        #expect(resolved.customizations == overlay)

        let cached = try await resolve(draft, context: context, transport: transport)
        #expect(cached.copyEntry?.catalogKey == privateEntry.catalogKey)
        #expect(transport.calls.count == 1)
    }

    @Test("Persists and reuses one copy request ID after a lost network response")
    func retryUsesStableCopyRequestID() async throws {
        let context = try makeContext()
        defer { try? FileManager.default.removeItem(at: context.directory) }
        let transport = SavedCopyFakeTransport { _, _ in throw SavedCopyTestError.networkLost }

        do {
            _ = try await resolve(context.draft, context: context, transport: transport)
            Issue.record("Expected the first copy request to fail")
        } catch SavedCopyTestError.networkLost {
        } catch {
            throw error
        }
        let savedAfterFailure = try #require(try context.store.load(ownerUserID: "account-a", catalogKey: "wedding", shareToken: context.draft.shareToken))
        let stableID = try #require(savedAfterFailure.copyRequestID)
        transport.handler = { _, _ in try self.copyRecord() }

        let result = try await resolve(savedAfterFailure, context: context, transport: transport)

        #expect(transport.calls.count == 2)
        #expect(transport.calls[0].requestID == stableID)
        #expect(transport.calls[1].requestID == stableID)
        #expect(result.copyRequestID == stableID)
    }

    @Test("Rejects a wrong owner or pending installation before network access or disk writes")
    func rejectsOwnerAndPendingInstallation() async throws {
        let context = try makeContext()
        defer { try? FileManager.default.removeItem(at: context.directory) }
        let original = try draftBytes(in: context.directory)
        let transport = SavedCopyFakeTransport { _, _ in
            Issue.record("Transport must not be called")
            throw SavedCopyTestError.networkLost
        }

        await #expect(throws: (any Error).self) {
            try await BlueprintSavedCopyResolver.resolve(
                draft: context.draft, ownerID: "account-b", store: context.store, transport: transport,
                currentOwnerID: { "account-b" }, hasPendingInstallation: { false }
            )
        }
        await #expect(throws: (any Error).self) {
            try await BlueprintSavedCopyResolver.resolve(
                draft: context.draft, ownerID: "account-a", store: context.store, transport: transport,
                currentOwnerID: { "account-a" }, hasPendingInstallation: { true }
            )
        }

        #expect(transport.calls.isEmpty)
        let after = try draftBytes(in: context.directory)
        #expect(after == original)
        #expect(context.draft.copyRequestID == nil)
    }

    @Test("Rejects a callback after the current account changes")
    func lateCallbackAfterAccountSwitchIsRejected() async throws {
        let context = try makeContext()
        defer { try? FileManager.default.removeItem(at: context.directory) }
        var activeOwner: String? = "account-a"
        let transport = SavedCopyFakeTransport(suspends: true)
        let task = Task {
            try await BlueprintSavedCopyResolver.resolve(
                draft: context.draft, ownerID: "account-a", store: context.store, transport: transport,
                currentOwnerID: { activeOwner }, hasPendingInstallation: { false }
            )
        }
        await transport.waitUntilCalled()
        let before = try #require(try context.store.load(ownerUserID: "account-a", catalogKey: "wedding", shareToken: context.draft.shareToken))
        #expect(before.copyRequestID != nil)
        activeOwner = "account-b"
        transport.complete(with: try copyRecord())

        do {
            _ = try await task.value
            Issue.record("Expected the account switch to reject the callback")
        } catch {
        }
        let saved = try context.store.load(ownerUserID: "account-a", catalogKey: "wedding", shareToken: context.draft.shareToken)
        #expect(saved?.copyEntry == nil)
    }

    @Test("Rejects a late callback after the saved draft has been replaced with another request")
    func lateCallbackAfterDraftReplacementIsRejected() async throws {
        let context = try makeContext()
        defer { try? FileManager.default.removeItem(at: context.directory) }
        let transport = SavedCopyFakeTransport(suspends: true)
        let task = Task { try await resolve(context.draft, context: context, transport: transport) }
        await transport.waitUntilCalled()
        var replacement = context.draft
        replacement.requestID = UUID()
        replacement.eventName = "Replacement draft"
        try context.store.save(replacement)
        transport.complete(with: try copyRecord())

        do {
            _ = try await task.value
            Issue.record("Expected the replaced draft to reject the callback")
        } catch {
        }
        let saved = try #require(try context.store.load(ownerUserID: "account-a", catalogKey: "wedding", shareToken: context.draft.shareToken))
        #expect(saved.requestID == replacement.requestID)
        #expect(saved.eventName == "Replacement draft")
        #expect(saved.copyEntry == nil)
    }

    @Test("Attaches the copy to the latest same-request draft while preserving edits and dates")
    func preservesEditsMadeDuringNetworkWait() async throws {
        let context = try makeContext()
        defer { try? FileManager.default.removeItem(at: context.directory) }
        let transport = SavedCopyFakeTransport(suspends: true)
        let task = Task { try await resolve(context.draft, context: context, transport: transport) }
        await transport.waitUntilCalled()
        var edited = try #require(try context.store.load(ownerUserID: "account-a", catalogKey: "wedding", shareToken: context.draft.shareToken))
        let laterDate = Date(timeIntervalSince1970: 1_900_000_000.75)
        edited.eventName = "Edited while copying"
        edited.startsAt = laterDate
        edited.timeZoneIdentifier = "UTC"
        edited.selectedChildren = ["reception"]
        edited.selectedIdeas = ["venue"]
        edited.confirmedDates = ["reception": laterDate]
        edited.previewDecisions = ["venue": .love]
        var overlay = BlueprintCustomization()
        try overlay.upsert(.init(key: "ceremony", title: "Edited overlay", purpose: "part_of_event",
                                 category: "ceremony", scheduleProposal: nil))
        let sourceIdea = try #require(try BlueprintDraftContent.snapshot(of: edited.entry).ideas.first)
        try overlay.upsert(.init(key: sourceIdea.key, title: sourceIdea.title, category: sourceIdea.category,
                                 notes: "Keep these personal notes", target: sourceIdea.target,
                                 configuration: sourceIdea.configuration))
        edited.customizations = overlay
        try context.store.save(edited)
        transport.complete(with: try copyRecord())

        let resolved = try await task.value

        #expect(resolved.eventName == "Edited while copying")
        #expect(resolved.startsAt == laterDate)
        #expect(resolved.timeZoneIdentifier == "UTC")
        #expect(resolved.selectedChildren == ["reception"])
        #expect(resolved.selectedIdeas == ["venue"])
        #expect(resolved.confirmedDates == ["reception": laterDate])
        #expect(resolved.previewDecisions == ["venue": .love])
        #expect(resolved.customizations == overlay)
        #expect(resolved.customizations?.ideas.first?.notes == "Keep these personal notes")
        #expect(resolved.copyEntry != nil)
    }

    @Test("Does not attach the returned copy if an installation becomes pending during the request")
    func pendingInstallationAfterAwaitRejectsCopy() async throws {
        let context = try makeContext()
        defer { try? FileManager.default.removeItem(at: context.directory) }
        var pending = false
        let transport = SavedCopyFakeTransport(suspends: true)
        let task = Task {
            try await BlueprintSavedCopyResolver.resolve(
                draft: context.draft, ownerID: "account-a", store: context.store, transport: transport,
                currentOwnerID: { "account-a" }, hasPendingInstallation: { pending }
            )
        }
        await transport.waitUntilCalled()
        pending = true
        transport.complete(with: try copyRecord())

        do {
            _ = try await task.value
            Issue.record("Expected the pending installation to reject the callback")
        } catch {
        }
        let saved = try #require(try context.store.load(ownerUserID: "account-a", catalogKey: "wedding", shareToken: context.draft.shareToken))
        #expect(saved.copyEntry == nil)
        #expect(saved.copyRequestID != nil)
    }

    @Test("Legacy drafts decode without the optional saved-copy fields")
    func legacyDraftDecodes() throws {
        let context = try makeContext()
        defer { try? FileManager.default.removeItem(at: context.directory) }
        let draft = context.draft
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        var object = try #require(JSONSerialization.jsonObject(with: encoder.encode(draft)) as? [String: Any])
        object.removeValue(forKey: "copyRequestID")
        object.removeValue(forKey: "copyEntry")
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let decoded = try decoder.decode(BlueprintSetupDraft.self, from: JSONSerialization.data(withJSONObject: object))

        #expect(decoded.copyRequestID == nil)
        #expect(decoded.copyEntry == nil)
        #expect(decoded.installationEntry.catalogKey == decoded.entry.catalogKey)
        #expect(decoded.installationShareToken == decoded.shareToken)
    }

    private func resolve(
        _ draft: BlueprintSetupDraft,
        context: Context,
        transport: SavedCopyFakeTransport
    ) async throws -> BlueprintSetupDraft {
        try await BlueprintSavedCopyResolver.resolve(
            draft: draft, ownerID: "account-a", store: context.store, transport: transport,
            currentOwnerID: { "account-a" }, hasPendingInstallation: { false }
        )
    }

    private func makeContext() throws -> Context {
        let directory = FileManager.default.temporaryDirectory.appending(path: "BlueprintSavedCopyResolverTests-\(UUID().uuidString)")
        let store = BlueprintSetupDraftStore(directoryURL: directory)
        let draft = BlueprintSetupDraft(
            ownerUserID: "account-a", entry: try weddingEntry(), requestID: UUID(), eventName: "Wedding",
            startsAt: Date(timeIntervalSince1970: 1_800_000_000.25), timeZoneIdentifier: "America/Detroit",
            selectedChildren: ["ceremony"], selectedIdeas: ["flowers"],
            confirmedDates: ["ceremony": Date(timeIntervalSince1970: 1_800_000_000.5)],
            shareToken: String(repeating: "a", count: 64)
        )
        try store.save(draft)
        return Context(directory: directory, store: store, draft: draft)
    }

    private func weddingEntry(catalogKey: String = "wedding") throws -> BlueprintCatalogEntry {
        let url = try #require(Bundle(for: SavedCopyFixtureBundle.self)
            .url(forResource: "wedding-catalog.v1", withExtension: "json"))
        let response = try JSONDecoder().decode(BlueprintCatalogResponse.self, from: Data(contentsOf: url))
        let source = try #require(response.entries.first { $0.catalogKey == "wedding" })
        guard catalogKey != "wedding" else { return source }
        let identity = ExperienceBlueprintIdentity(id: catalogKey, revision: source.definition.blueprint.revision,
                                                   name: source.definition.blueprint.name)
        let definition = ExperienceBlueprintDocument(
            schema: source.definition.schema, kind: source.definition.kind,
            schemaVersion: source.definition.schemaVersion, blueprint: identity,
            experienceDefaults: source.definition.experienceDefaults, roles: source.definition.roles,
            modules: source.definition.modules, presentation: source.definition.presentation
        )
        let digest = SHA256.hash(data: Data("\(source.contentHash):\(catalogKey)".utf8))
            .map { String(format: "%02x", $0) }.joined()
        return BlueprintCatalogEntry(catalogKey: catalogKey, revision: source.revision,
                                     contentHash: digest, definition: definition,
                                     discovery: source.discovery, description: source.description)
    }

    private func copyRecord() throws -> BlueprintPersonalRecord {
        let entry = try weddingEntry(catalogKey: "private_\(UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased())")
        return BlueprintPersonalRecord(id: UUID(), draftVersion: 1, publishedRevision: entry.revision, listedRevision: nil,
                                       catalogEntry: entry)
    }

    private func draftBytes(in directory: URL) throws -> Data {
        let files = try #require(FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil))
        let file = try #require(files.allObjects.compactMap { $0 as? URL }.first { $0.lastPathComponent == "draft.json" })
        return try Data(contentsOf: file)
    }
}

private struct Context {
    let directory: URL
    let store: BlueprintSetupDraftStore
    let draft: BlueprintSetupDraft
}

@MainActor
private final class SavedCopyFakeTransport: BlueprintSavedCopyTransport {
    struct Call {
        let requestID: UUID
        let content: BlueprintDraftContent
    }

    var calls: [Call] = []
    var handler: @MainActor (UUID, BlueprintDraftContent) async throws -> BlueprintPersonalRecord
    private var continuation: CheckedContinuation<BlueprintPersonalRecord, any Error>?

    init(suspends: Bool = false,
         handler: @escaping @MainActor (UUID, BlueprintDraftContent) async throws -> BlueprintPersonalRecord = { _, _ in
             throw SavedCopyTestError.networkLost
         }) {
        self.handler = handler
        self.suspends = suspends
    }

    private let suspends: Bool

    func copyBlueprintSnapshot(requestID: UUID, content: BlueprintDraftContent) async throws -> BlueprintPersonalRecord {
        calls.append(Call(requestID: requestID, content: content))
        if suspends {
            return try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
            }
        }
        return try await handler(requestID, content)
    }

    func waitUntilCalled() async {
        for _ in 0..<100 where calls.isEmpty { await Task.yield() }
    }

    func complete(with record: BlueprintPersonalRecord) {
        continuation?.resume(returning: record)
        continuation = nil
    }
}

private enum SavedCopyTestError: Error {
    case networkLost
}

private final class SavedCopyFixtureBundle: NSObject {}
