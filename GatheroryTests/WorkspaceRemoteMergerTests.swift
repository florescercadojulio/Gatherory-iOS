import Foundation
import SwiftData
import Testing
@testable import Gatherory

@MainActor
struct WorkspaceRemoteMergerTests {
    private let codec = WorkspaceArchiveCodec()
    private let date = Date(timeIntervalSinceReferenceDate: 900_000_000)

    @Test("Bootstrap stages ordered, account-scoped records and preserves matching downloaded media")
    func bootstrapStaging() throws {
        let context = try makeContext()
        let cached = makeArchive()
        let originalPayload = try codec.encode(cached)
        let record = makeRecord(cached, payload: originalPayload, owner: "owner")
        let other = makeRecord(cached, payload: originalPayload, owner: "other")
        context.insert(other)
        context.insert(record)
        try context.save()

        let pendingID = UUID()
        let newArchive = makeArchive()
        let lastArchive = makeArchive()
        var remote = try codec.decode(WorkspaceArchiveV1.self, from: cached.syncPayload(using: codec))
        var idea = remote.ideas[0]
        idea.title = "First remote title"
        var latestIdea = idea
        latestIdea.title = "Last remote title"
        // Bootstrap must not restore a locally cached entity removed remotely.
        remote.ideas = []
        remote.ideaResponses = []
        let entitySnapshots = try [idea, latestIdea].map {
            RemoteEntitySnapshot(scopeID: cached.mainEventID, entityType: .idea,
                entityID: $0.id, payload: try codec.encode($0), serverVersion: 99,
                updatedAt: date.addingTimeInterval(500))
        }
        let merger = WorkspaceRemoteMerger(context: context, codec: codec, ownerUserID: "owner")
        let workspaces = try merger.stageBootstrap([
            RemoteWorkspaceSnapshot(scopeID: pendingID, payloadSchemaVersion: 999,
                payload: Data(), serverVersion: 1, updatedAt: date),
            try snapshot(remote), try snapshot(newArchive), try snapshot(lastArchive)
        ], entities: entitySnapshots, pendingScopes: [pendingID], existingWorkspaceCount: 4)

        #expect(workspaces.map(\.mainEventID) == [cached.mainEventID, newArchive.mainEventID, lastArchive.mainEventID])
        #expect(workspaces[0].mainEventImageData == cached.mainEventImageData)
        #expect(workspaces[0].ideas.map(\.title) == ["Last remote title"])
        #expect(workspaces[0].ideas[0].imageData == cached.ideas[0].imageData)
        #expect(workspaces[0].ideaResponses.isEmpty)
        #expect(record.sortOrder == 2)
        #expect(record.createdAt == date.addingTimeInterval(-100))
        #expect(record.updatedAt == date)
        #expect(record.serverVersion == 7)
        #expect(record.payloadSchemaVersion == WorkspaceArchiveV1.schemaVersion)
        #expect(other.payload == originalPayload)
        #expect(other.serverVersion == 3)
        let records = try context.fetch(FetchDescriptor<WorkspaceRecord>())
        #expect(records.first { $0.id == newArchive.mainEventID }?.sortOrder == 5)
        #expect(records.first { $0.id == lastArchive.mainEventID }?.sortOrder == 6)
        #expect(records.filter { $0.ownerUserID == "owner" }.count == 3)
        #expect(context.hasChanges)
        let durable = try ModelContext(context.container).fetch(FetchDescriptor<WorkspaceRecord>())
        #expect(durable.count == 2)
        #expect(durable.allSatisfy { $0.payload == originalPayload })
        try expectNoSyncSideEffects(in: context)
        #expect(try context.fetch(FetchDescriptor<AppliedSyncEnvelope>()).isEmpty)
    }

    @Test("Bootstrap never imports another account's cached media", arguments: ["owner", nil] as [String?])
    func bootstrapMediaAccountIsolation(owner: String?) throws {
        let context = try makeContext()
        let cached = makeArchive()
        let payload = try codec.encode(cached)
        let other = makeRecord(cached, payload: payload, owner: "other")
        context.insert(other)
        try context.save()
        let remote = try codec.decode(WorkspaceArchiveV1.self, from: cached.syncPayload(using: codec))

        let result = try WorkspaceRemoteMerger(context: context, codec: codec, ownerUserID: owner)
            .stageBootstrap([try snapshot(remote)], entities: [], pendingScopes: [], existingWorkspaceCount: 0)

        #expect(result[0].mainEventImageData == nil)
        #expect(result[0].ideas[0].imageData == nil)
        let records = try context.fetch(FetchDescriptor<WorkspaceRecord>())
        #expect(records.count == 2)
        #expect(records.first { $0.ownerUserID == owner }?.sortOrder == 0)
        #expect(other.payload == payload)
        #expect(try ModelContext(context.container).fetch(FetchDescriptor<WorkspaceRecord>()).count == 1)
    }

    @Test("Page staging preserves collaborative entities and leaves commit and rollback to its caller")
    func pageStaging() throws {
        let context = try makeContext()
        let local = makeArchive()
        let payload = try codec.encode(local)
        let record = makeRecord(local, payload: payload, owner: "owner")
        context.insert(record)
        try context.save()
        let remoteWorkspace = local.makeWorkspace()
        remoteWorkspace.title = "Remote metadata"
        var remote = WorkspaceArchiveV1(workspace: remoteWorkspace)
        remote.mainEventImageData = nil
        remote.ideas = []
        remote.ideaResponses = nil
        var idea = local.ideas[0]
        idea.title = "Remote entity"
        idea.imageData = nil
        let entity = RemoteChangeEnvelope(id: UUID(), scopeID: local.mainEventID,
            entityType: .idea, entityID: idea.id, operation: .update,
            payload: try codec.encode(idea), serverVersion: 99, occurredAt: date.addingTimeInterval(50))
        let workspaceChange = try change(remote, version: 8, occurredAt: date.addingTimeInterval(-50))
        let page = SyncPullPage(changes: [entity, workspaceChange], nextCursor: "next", hasMore: true)

        let result = try WorkspaceRemoteMerger(context: context, codec: codec, ownerUserID: "owner")
            .stagePage(page, scopeID: local.mainEventID, existingWorkspaceCount: 10)
        guard case let .merged(archive, shouldDelete) = result else {
            Issue.record("Expected a merged page")
            return
        }
        let merged = try #require(archive)
        #expect(!shouldDelete)
        #expect(merged.title == "Remote metadata")
        #expect(merged.mainEventImageData == local.mainEventImageData)
        #expect(merged.ideas[0].title == "Remote entity")
        #expect(merged.ideas[0].imageData == local.ideas[0].imageData)
        #expect(merged.ideaResponses == local.ideaResponses)
        #expect(record.payload == (try codec.encode(merged)))
        #expect(record.serverVersion == 8)
        #expect(record.updatedAt == date.addingTimeInterval(50))
        #expect(record.createdAt == date.addingTimeInterval(-100))
        #expect(record.sortOrder == 2)
        #expect(context.hasChanges)
        let receipts = try context.fetch(FetchDescriptor<AppliedSyncEnvelope>())
        #expect(Set(receipts.map(\.id)) == [entity.id, workspaceChange.id])
        #expect(receipts.allSatisfy { $0.ownerUserID == "owner" && $0.scopeID == local.mainEventID })
        let durable = ModelContext(context.container)
        #expect(try durable.fetch(FetchDescriptor<WorkspaceRecord>()).first?.payload == payload)
        #expect(try durable.fetch(FetchDescriptor<AppliedSyncEnvelope>()).isEmpty)
        try expectNoSyncSideEffects(in: context)

        // Only an explicit caller rollback discards the staged graph and receipts.
        context.rollback()
        #expect(record.payload == payload)
        #expect(try context.fetch(FetchDescriptor<AppliedSyncEnvelope>()).isEmpty)
        #expect(!context.hasChanges)
    }

    @Test("Receipt deduplication and workspace writes are isolated by account", arguments: ["owner", nil] as [String?])
    func receiptAccountIsolation(owner: String?) throws {
        let context = try makeContext()
        let archive = makeArchive()
        let payload = try codec.encode(archive)
        let other = makeRecord(archive, payload: payload, owner: "other")
        let envelope = try change(archive)
        context.insert(other)
        context.insert(AppliedSyncEnvelope(id: envelope.id, scopeID: archive.mainEventID, ownerUserID: "other"))
        try context.save()
        let merger = WorkspaceRemoteMerger(context: context, codec: codec, ownerUserID: owner)
        let page = SyncPullPage(changes: [envelope], nextCursor: "next", hasMore: false)

        guard case .merged = try merger.stagePage(page, scopeID: archive.mainEventID, existingWorkspaceCount: 6) else {
            Issue.record("Another account's receipt must not suppress this page")
            return
        }
        // Staged receipts also suppress a retry before the caller saves.
        guard case .checkpointOnly = try merger.stagePage(page, scopeID: archive.mainEventID, existingWorkspaceCount: 6) else {
            Issue.record("Expected the staged receipt to suppress the duplicate")
            return
        }
        #expect(try context.fetch(FetchDescriptor<AppliedSyncEnvelope>()).count == 2)
        let records = try context.fetch(FetchDescriptor<WorkspaceRecord>())
        #expect(records.count == 2)
        #expect(records.first { $0.ownerUserID == owner }?.sortOrder == 6)
        #expect(records.first { $0.ownerUserID == owner }?.serverVersion == 7)
        #expect(other.payload == payload)
        #expect(other.serverVersion == 3)
        #expect(try ModelContext(context.container).fetch(FetchDescriptor<AppliedSyncEnvelope>()).count == 1)
        try expectNoSyncSideEffects(in: context)

        try context.save()
        let durable = ModelContext(context.container)
        #expect(try durable.fetch(FetchDescriptor<WorkspaceRecord>()).count == 2)
        #expect(try durable.fetch(FetchDescriptor<AppliedSyncEnvelope>()).count == 2)
    }

    @Test("Empty and fully duplicated pages do not decode archives or touch checkpoints")
    func checkpointOnlyPages() throws {
        let context = try makeContext()
        let archive = makeArchive()
        let invalidPayload = Data("invalid cached archive".utf8)
        let record = makeRecord(archive, payload: invalidPayload, owner: "owner")
        let envelope = RemoteChangeEnvelope(id: UUID(), scopeID: archive.mainEventID,
            payloadSchemaVersion: 999, entityType: .workspace, entityID: archive.mainEventID,
            operation: .update, payload: Data(), serverVersion: 99, occurredAt: date)
        let checkpoint = SyncCheckpoint(scopeID: archive.mainEventID, cursor: "original",
            lastSuccessfulSyncAt: date, ownerUserID: "owner")
        context.insert(record)
        context.insert(checkpoint)
        context.insert(AppliedSyncEnvelope(id: envelope.id, scopeID: archive.mainEventID, ownerUserID: "owner"))
        try context.save()
        let merger = WorkspaceRemoteMerger(context: context, codec: codec, ownerUserID: "owner")

        for changes in [[], [envelope]] {
            let result = try merger.stagePage(.init(changes: changes, nextCursor: "next", hasMore: false),
                scopeID: archive.mainEventID, existingWorkspaceCount: 1)
            guard case .checkpointOnly = result else {
                Issue.record("Expected checkpoint-only result")
                return
            }
        }
        #expect(record.payload == invalidPayload)
        #expect(checkpoint.cursor == "original")
        #expect(checkpoint.lastSuccessfulSyncAt == date)
        #expect(!context.hasChanges)
    }

    @Test("Delete then recreate drops old entities; recreate then delete removes only the current account", arguments: [true, false])
    func deletionRecreation(deleteFirst: Bool) throws {
        let context = try makeContext()
        let local = makeArchive()
        let payload = try codec.encode(local)
        let record = makeRecord(local, payload: payload, owner: "owner")
        let other = makeRecord(local, payload: payload, owner: "other")
        context.insert(record)
        context.insert(other)
        try context.save()
        var remote = local
        remote.ideas = []
        remote.ideaResponses = []
        let deletion = RemoteChangeEnvelope(id: UUID(), scopeID: local.mainEventID,
            entityType: .workspace, entityID: local.mainEventID, operation: .delete,
            payload: Data(), serverVersion: 100, occurredAt: date.addingTimeInterval(100))
        let creation = try change(remote, operation: .create, version: 9)
        let changes = deleteFirst ? [deletion, creation] : [creation, deletion]
        let result = try WorkspaceRemoteMerger(context: context, codec: codec, ownerUserID: "owner")
            .stagePage(.init(changes: changes, nextCursor: "next", hasMore: false),
                scopeID: local.mainEventID, existingWorkspaceCount: 20)

        guard case let .merged(archive, shouldDelete) = result else {
            Issue.record("Expected merged deletion/recreation")
            return
        }
        #expect(shouldDelete == !deleteFirst)
        if deleteFirst {
            let recreated = try #require(archive)
            #expect(recreated.ideas.isEmpty)
            #expect(recreated.ideaResponses == [])
            #expect(record.serverVersion == 9)
            #expect(record.updatedAt == date.addingTimeInterval(100))
            #expect(record.sortOrder == 2)
            #expect(record.createdAt == date.addingTimeInterval(-100))
        } else {
            #expect(archive == nil)
            #expect(context.deletedModelsArray.contains { $0 === record })
        }
        #expect(other.payload == payload)
        #expect(!context.deletedModelsArray.contains { $0 === other })
        #expect(try context.fetch(FetchDescriptor<AppliedSyncEnvelope>()).count == 2)
        #expect(try ModelContext(context.container).fetch(FetchDescriptor<WorkspaceRecord>()).count == 2)
        try expectNoSyncSideEffects(in: context)
        try context.save()
        let durable = try ModelContext(context.container).fetch(FetchDescriptor<WorkspaceRecord>())
        #expect(durable.count == (deleteFirst ? 2 : 1))
        #expect(durable.contains { $0.ownerUserID == "other" && $0.payload == payload })
    }

    @Test("Entity-only pages without a workspace still stage receipts")
    func missingWorkspace() throws {
        let context = try makeContext()
        let scopeID = UUID()
        let envelope = RemoteChangeEnvelope(id: UUID(), scopeID: scopeID,
            entityType: .idea, entityID: UUID(), operation: .update,
            payload: Data(), serverVersion: 12, occurredAt: date)
        let result = try WorkspaceRemoteMerger(context: context, codec: codec, ownerUserID: "owner")
            .stagePage(.init(changes: [envelope], nextCursor: "next", hasMore: false),
                scopeID: scopeID, existingWorkspaceCount: 0)
        guard case let .merged(archive, shouldDelete) = result else {
            Issue.record("An unmaterialized entity still requires a receipt")
            return
        }
        #expect(archive == nil)
        #expect(!shouldDelete)
        #expect(try context.fetch(FetchDescriptor<WorkspaceRecord>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<AppliedSyncEnvelope>()).map(\.id) == [envelope.id])
        #expect(try ModelContext(context.container).fetch(FetchDescriptor<AppliedSyncEnvelope>()).isEmpty)
        try expectNoSyncSideEffects(in: context)
    }

    @Test("Unsupported bootstrap snapshots and entities leave previous staging and caller edits intact", arguments: [true, false])
    func unsupportedBootstrapPayload(snapshotIsUnsupported: Bool) throws {
        let context = try makeContext()
        let first = makeArchive()
        let second = makeArchive()
        let checkpoint = SyncCheckpoint(scopeID: first.mainEventID, cursor: "saved", ownerUserID: "owner")
        context.insert(checkpoint)
        try context.save()
        checkpoint.cursor = "caller edit"
        let unsupported = RemoteWorkspaceSnapshot(scopeID: second.mainEventID,
            payloadSchemaVersion: snapshotIsUnsupported ? 999 : nil,
            payload: snapshotIsUnsupported ? Data() : try codec.encode(second),
            serverVersion: 1, updatedAt: date)
        let entity = RemoteEntitySnapshot(scopeID: second.mainEventID, payloadSchemaVersion: 999,
            entityType: .idea, entityID: UUID(), payload: Data(), serverVersion: 1, updatedAt: date)

        do {
            _ = try WorkspaceRemoteMerger(context: context, codec: codec, ownerUserID: "owner")
                .stageBootstrap([try snapshot(first), unsupported], entities: [entity],
                    pendingScopes: [], existingWorkspaceCount: 0)
            Issue.record("Expected unsupported payload version")
        } catch WorkspacePersistenceError.unsupportedSyncPayloadVersion(let version) {
            #expect(version == 999)
        }
        #expect(try context.fetch(FetchDescriptor<WorkspaceRecord>()).map(\.id) == [first.mainEventID])
        #expect(checkpoint.cursor == "caller edit")
        #expect(context.hasChanges)
        let durable = ModelContext(context.container)
        #expect(try durable.fetch(FetchDescriptor<WorkspaceRecord>()).isEmpty)
        #expect(try durable.fetch(FetchDescriptor<SyncCheckpoint>()).first?.cursor == "saved")
    }

    @Test("A failing page leaves earlier receipts staged without committing or rolling back caller edits", arguments: [true, false])
    func failingPage(unsupportedVersion: Bool) throws {
        let context = try makeContext()
        let archive = makeArchive()
        let payload = try codec.encode(archive)
        let record = makeRecord(archive, payload: payload, owner: "owner")
        context.insert(record)
        try context.save()
        record.sortOrder = 42
        let valid = try change(archive)
        let invalid = RemoteChangeEnvelope(id: UUID(), scopeID: archive.mainEventID,
            payloadSchemaVersion: unsupportedVersion ? 999 : nil,
            entityType: .workspace, entityID: archive.mainEventID, operation: .update,
            payload: Data(), serverVersion: 8, occurredAt: date)
        do {
            _ = try WorkspaceRemoteMerger(context: context, codec: codec, ownerUserID: "owner")
                .stagePage(.init(changes: [valid, invalid], nextCursor: "next", hasMore: false),
                    scopeID: archive.mainEventID, existingWorkspaceCount: 1)
            Issue.record("Expected invalid page to throw")
        } catch WorkspacePersistenceError.unsupportedSyncPayloadVersion(let version) {
            #expect(unsupportedVersion)
            #expect(version == 999)
        } catch is DecodingError {
            #expect(!unsupportedVersion)
        }
        #expect(record.sortOrder == 42)
        #expect(record.payload == payload)
        #expect(record.serverVersion == 3)
        #expect(try context.fetch(FetchDescriptor<AppliedSyncEnvelope>()).map(\.id) == [valid.id])
        #expect(context.hasChanges)
        let durable = ModelContext(context.container)
        #expect(try durable.fetch(FetchDescriptor<WorkspaceRecord>()).first?.sortOrder == 2)
        #expect(try durable.fetch(FetchDescriptor<AppliedSyncEnvelope>()).isEmpty)
        try expectNoSyncSideEffects(in: context)
    }

    private func makeContext() throws -> ModelContext {
        let configuration = ModelConfiguration(schema: OfflineSyncSchema.schema,
            isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: OfflineSyncSchema.schema, configurations: [configuration])
        let context = ModelContext(container)
        context.autosaveEnabled = false
        return context
    }

    private func makeArchive() -> WorkspaceArchiveV1 {
        let workspace = PlanningWorkspace.newWorkspace(title: "Remote merger fixture", startsAt: date,
            eventLocation: nil, imageData: Data([1, 2, 3]))
        workspace.mainEventMediaAssetID = UUID()
        var archive = WorkspaceArchiveV1(workspace: workspace)
        let idea = PlanningIdea(eventID: archive.mainEventID, title: "Cached idea", note: "",
            category: .music, submittedBy: "Host", submittedAt: date,
            imageData: Data([4, 5, 6]), mediaAssetID: UUID())
        archive.ideas = [idea]
        archive.ideaResponses = [IdeaResponse(ideaID: idea.id, userID: "teammate", choice: .love)]
        return archive
    }

    private func makeRecord(_ archive: WorkspaceArchiveV1, payload: Data, owner: String?) -> WorkspaceRecord {
        WorkspaceRecord(id: archive.mainEventID, payload: payload, sortOrder: 2,
            createdAt: date.addingTimeInterval(-100), updatedAt: date,
            ownerUserID: owner, serverVersion: 3)
    }

    private func snapshot(_ archive: WorkspaceArchiveV1) throws -> RemoteWorkspaceSnapshot {
        RemoteWorkspaceSnapshot(scopeID: archive.mainEventID, payload: try codec.encode(archive),
            serverVersion: 7, updatedAt: date)
    }

    private func change(_ archive: WorkspaceArchiveV1, operation: SyncMutationOperation = .update,
                        version: Int = 7, occurredAt: Date? = nil) throws -> RemoteChangeEnvelope {
        RemoteChangeEnvelope(id: UUID(), scopeID: archive.mainEventID,
            entityType: .workspace, entityID: archive.mainEventID, operation: operation,
            payload: try codec.encode(archive), serverVersion: version, occurredAt: occurredAt ?? date)
    }

    private func expectNoSyncSideEffects(in context: ModelContext) throws {
        #expect(try context.fetch(FetchDescriptor<SyncCheckpoint>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<PendingMutation>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<PendingMediaTransfer>()).isEmpty)
    }
}
