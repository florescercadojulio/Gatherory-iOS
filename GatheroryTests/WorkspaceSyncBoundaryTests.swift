import Foundation
import SwiftData
import Testing
@testable import Gatherory

/// Tests the controller's commit/publication boundary, not just helper outputs.
@MainActor
struct WorkspaceSyncBoundaryTests {
    @Test("A local encoding failure rolls back staged records and outbox edits before notification")
    func failedLocalSaveRollsBackBothWrites() throws {
        let persistence = try WorkspacePersistenceController(isStoredInMemoryOnly: true)
        let library = persistence.restoreLibrary(seedData: false, ownerUserID: "owner")
        let first = workspace("First")
        let second = workspace("Second")
        library.add(first)
        library.add(second)
        try persistence.saveChanges(in: library)
        let before = ModelContext(persistence.container)
        let payloads = Dictionary(uniqueKeysWithValues:
            try before.fetch(FetchDescriptor<WorkspaceRecord>()).map { ($0.id, $0.payload) })
        let mutations = Set(try before.fetch(FetchDescriptor<PendingMutation>()).map(PendingMutationSnapshot.init))
        var notifications = 0
        persistence.onPendingMutations = { notifications += 1 }

        // The valid prefix is staged before the second archive fails encoding.
        let orderedFirst = try #require(library.workspaces.first)
        let orderedSecond = try #require(library.workspaces.last)
        orderedFirst.title = "Valid edit before failure"
        let validDate = orderedSecond.mainEventStartsAt
        orderedSecond.mainEventStartsAt = Date(timeIntervalSinceReferenceDate: .infinity)
        #expect(throws: EncodingError.self) {
            try persistence.saveChanges(in: library)
        }
        #expect(persistence.lastError != nil)
        #expect(persistence.hasUnsavedLocalChanges)
        #expect(notifications == 0)
        let reader = ModelContext(persistence.container)
        #expect(Dictionary(uniqueKeysWithValues:
            try reader.fetch(FetchDescriptor<WorkspaceRecord>()).map { ($0.id, $0.payload) }) == payloads)
        #expect(Set(try reader.fetch(FetchDescriptor<PendingMutation>()).map(PendingMutationSnapshot.init)) == mutations)

        orderedSecond.mainEventStartsAt = validDate
        try persistence.saveChanges(in: library)
        #expect(persistence.lastError == nil)
        #expect(!persistence.hasUnsavedLocalChanges)
        #expect(notifications == 1)
        let saved = try ModelContext(persistence.container).fetch(FetchDescriptor<WorkspaceRecord>())
        let edited = try #require(saved.first { $0.id == orderedFirst.mainEventID })
        #expect(try WorkspaceArchiveCodec().decode(WorkspaceArchiveV1.self, from: edited.payload).title == orderedFirst.title)
    }

    @Test("A failed bootstrap batch does not commit its valid prefix or publish a partial graph")
    func failedBootstrapDoesNotPublishOrCommit() throws {
        let persistence = try WorkspacePersistenceController(isStoredInMemoryOnly: true)
        let library = persistence.restoreLibrary(seedData: false, ownerUserID: "owner")
        let first = workspace("Valid prefix")
        let second = workspace("Unsupported suffix")
        var unsupported = try snapshot(second)
        unsupported.payloadSchemaVersion = SyncPayloadContract.currentVersion + 1

        #expect(throws: WorkspacePersistenceError.self) {
            try persistence.applyBootstrap([snapshot(first), unsupported], to: library)
        }

        #expect(library.workspaces.isEmpty)
        let reader = ModelContext(persistence.container)
        #expect(try reader.fetch(FetchDescriptor<WorkspaceRecord>()).isEmpty)
        #expect(try reader.fetch(FetchDescriptor<PendingMutation>()).isEmpty)
        #expect(try reader.fetch(FetchDescriptor<SyncCheckpoint>()).isEmpty)
        // The pre-existing throwing remote path does not roll back its context.
        // This checks the durable boundary without changing that error policy.
    }

    @Test("A failed pull page commits neither its receipt prefix nor its next cursor")
    func failedPageDoesNotCommitReceiptsOrCursor() throws {
        let persistence = try WorkspacePersistenceController(isStoredInMemoryOnly: true)
        let library = persistence.restoreLibrary(seedData: false, ownerUserID: "owner")
        let source = workspace("Original")
        try persistence.applyBootstrap([snapshot(source)], to: library)
        try persistence.applyRemotePage(
            SyncPullPage(changes: [], nextCursor: "before", hasMore: false),
            scopeID: source.mainEventID, to: library
        )
        let original = try #require(library.workspaces.first)
        source.title = "Not committed"
        let valid = try change(source, operation: .update)
        var invalid = try change(source, operation: .update)
        invalid.payloadSchemaVersion = SyncPayloadContract.currentVersion + 1

        #expect(throws: WorkspacePersistenceError.self) {
            try persistence.applyRemotePage(
                SyncPullPage(changes: [valid, invalid], nextCursor: "after", hasMore: false),
                scopeID: source.mainEventID, to: library
            )
        }

        #expect(library.workspaces.first === original)
        #expect(original.title == "Original")
        let reader = ModelContext(persistence.container)
        let record = try #require(reader.fetch(FetchDescriptor<WorkspaceRecord>()).first)
        #expect(try WorkspaceArchiveCodec().decode(WorkspaceArchiveV1.self, from: record.payload).title == "Original")
        #expect(try reader.fetch(FetchDescriptor<AppliedSyncEnvelope>()).isEmpty)
        let checkpoint = try #require(reader.fetch(FetchDescriptor<SyncCheckpoint>()).first)
        #expect(checkpoint.cursor == "before")
        #expect(try reader.fetch(FetchDescriptor<PendingMutation>()).isEmpty)
    }

    @Test("Writers and mergers use the current account after switching, including remote deletion")
    func accountSwitchScopesBothHelpers() throws {
        let persistence = try WorkspacePersistenceController(isStoredInMemoryOnly: true)
        let library = persistence.restoreLibrary(seedData: false, ownerUserID: "first")
        let shared = workspace("Shared scope")
        let initial = try snapshot(shared)
        try persistence.applyBootstrap([initial], to: library)
        let first = try #require(library.workspaces.first)
        first.title = "First account offline edit"
        try persistence.saveChanges(in: library)
        let firstMutations = try ModelContext(persistence.container)
            .fetch(FetchDescriptor<PendingMutation>()).map(PendingMutationSnapshot.init)

        persistence.activate(userID: "second", in: library)
        try persistence.applyBootstrap([initial], to: library)
        let second = try #require(library.workspaces.first)
        second.title = "Second account offline edit"
        try persistence.saveChanges(in: library)
        let queued = try ModelContext(persistence.container)
            .fetch(FetchDescriptor<PendingMutation>())
        let beforeDelete = queued.map(PendingMutationSnapshot.init)
        #expect(Set(queued.filter { $0.ownerUserID == "first" }.map(PendingMutationSnapshot.init)) == Set(firstMutations))
        #expect(queued.contains { $0.ownerUserID == "second" })

        // Exercise the persistence boundary directly; the sync coordinator's
        // pending-work policy remains separate and unchanged.
        let deletion = try change(shared, operation: .delete)
        try persistence.applyRemotePage(
            SyncPullPage(changes: [deletion], nextCursor: "deleted", hasMore: false),
            scopeID: shared.mainEventID, to: library
        )
        #expect(library.workspaces.isEmpty)
        let reader = ModelContext(persistence.container)
        let records = try reader.fetch(FetchDescriptor<WorkspaceRecord>())
        #expect(records.count == 1)
        #expect(records.first?.ownerUserID == "first")
        #expect(Set(try reader.fetch(FetchDescriptor<PendingMutation>()).map(PendingMutationSnapshot.init)) == Set(beforeDelete))
        let receipt = try #require(reader.fetch(FetchDescriptor<AppliedSyncEnvelope>()).first)
        #expect(receipt.id == deletion.id)
        #expect(receipt.ownerUserID == "second")
        let checkpoint = try #require(reader.fetch(FetchDescriptor<SyncCheckpoint>()).first)
        #expect(checkpoint.ownerUserID == "second")
        #expect(checkpoint.cursor == "deleted")

        persistence.activate(userID: "first", in: library)
        #expect(library.workspaces.first?.title == "First account offline edit")
        #expect(try persistence.currentCursor(for: shared.mainEventID) == nil)
    }

    private func workspace(_ title: String) -> PlanningWorkspace {
        PlanningWorkspace.newWorkspace(title: title,
            startsAt: Date(timeIntervalSinceReferenceDate: 900_000_000),
            eventLocation: nil, imageData: nil)
    }

    private func snapshot(_ workspace: PlanningWorkspace) throws -> RemoteWorkspaceSnapshot {
        RemoteWorkspaceSnapshot(scopeID: workspace.mainEventID,
            payload: try WorkspaceArchiveCodec().encode(WorkspaceArchiveV1(workspace: workspace)),
            serverVersion: 1, updatedAt: workspace.mainEventStartsAt)
    }

    private func change(_ workspace: PlanningWorkspace, operation: SyncMutationOperation) throws -> RemoteChangeEnvelope {
        RemoteChangeEnvelope(id: UUID(), scopeID: workspace.mainEventID,
            entityType: .workspace, entityID: workspace.mainEventID, operation: operation,
            payload: operation == .delete ? Data() : try WorkspaceArchiveCodec().encode(WorkspaceArchiveV1(workspace: workspace)),
            serverVersion: 2, occurredAt: workspace.mainEventStartsAt)
    }
}
