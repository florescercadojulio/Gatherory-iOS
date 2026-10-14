import Foundation
import SwiftData
import Testing
@testable import Gatherory

@MainActor
struct WorkspaceOutboxWriterTests {
    private let codec = WorkspaceArchiveCodec()
    private let timestamp = Date(timeIntervalSinceReferenceDate: 900_000_000)

    @Test("Outbox and archive changes stay staged until their caller saves together")
    func stagesWithoutCommitting() throws {
        let context = try makeContext()
        let scopeID = UUID()
        let record = WorkspaceRecord(id: scopeID, payload: Data([1]), sortOrder: 0, ownerUserID: "owner")
        context.insert(record)
        let pending = insertMutation(in: context, scopeID: scopeID, entityID: scopeID)
        try context.save()
        let original = PendingMutationSnapshot(pending)
        let childID = UUID()

        record.payload = Data([2])
        let writer = makeWriter(context)
        writer.coalesceMutation(scopeID: scopeID, entityType: .workspace, entityID: scopeID,
            payload: Data([2]), operation: .update, baseVersion: 9, pendingMutations: [pending])
        writer.coalesceMutation(scopeID: scopeID, entityType: .idea, entityID: childID,
            payload: Data([3]), operation: .create, baseVersion: nil, pendingMutations: [pending])

        #expect(context.hasChanges)
        #expect(pending.payload == Data([2]))
        #expect(try mutations(in: context).count == 2)
        let beforeSave = ModelContext(context.container)
        #expect(try beforeSave.fetch(FetchDescriptor<WorkspaceRecord>()).first?.payload == Data([1]))
        #expect(try mutations(in: beforeSave).map(PendingMutationSnapshot.init) == [original])

        try context.save()
        let afterSave = ModelContext(context.container)
        #expect(try afterSave.fetch(FetchDescriptor<WorkspaceRecord>()).first?.payload == Data([2]))
        let committed = try mutations(in: afterSave)
        #expect(committed.count == 2)
        #expect(committed.first { $0.id == original.id }?.payload == Data([2]))
        #expect(committed.first { $0.entityID == childID }?.operation == .create)
    }

    @Test("The caller can roll back staged insertions, updates, and create cancellations together")
    func callerRollbackRestoresTransaction() throws {
        let context = try makeContext()
        let scopeID = UUID()
        let record = WorkspaceRecord(id: scopeID, payload: Data([1]), sortOrder: 0, ownerUserID: "owner")
        context.insert(record)
        let updated = insertMutation(in: context, scopeID: scopeID, entityID: scopeID)
        let deletedScopeID = UUID()
        let cancelled = insertMutation(in: context, scopeID: deletedScopeID,
            entityID: deletedScopeID, operation: .create)
        try context.save()
        let originals = Set([updated, cancelled].map(PendingMutationSnapshot.init))
        let writer = makeWriter(context)

        record.payload = Data([2])
        writer.coalesceMutation(scopeID: scopeID, entityType: .workspace, entityID: scopeID,
            payload: Data([2]), operation: .update, baseVersion: 9, pendingMutations: [updated, cancelled])
        writer.coalesceDeletion(scopeID: deletedScopeID, baseVersion: 4, pendingMutations: [updated, cancelled])
        writer.coalesceMutation(scopeID: scopeID, entityType: .idea, entityID: UUID(),
            payload: Data([3]), operation: .create, baseVersion: nil, pendingMutations: [])
        #expect(context.hasChanges)
        #expect(cancelled.isDeleted)
        #expect(Set(try mutations(in: ModelContext(context.container)).map(PendingMutationSnapshot.init)) == originals)

        context.rollback()

        #expect(!context.hasChanges)
        #expect(record.payload == Data([1]))
        #expect(Set(try mutations(in: context).map(PendingMutationSnapshot.init)) == originals)
        #expect(Set(try mutations(in: ModelContext(context.container)).map(PendingMutationSnapshot.init)) == originals)
        #expect(!cancelled.isDeleted)
    }

    @Test("Only the newest matching pending mutation changes, preserving its identity and create")
    func latestPendingSelectionAndRetryReset() throws {
        let context = try makeContext()
        let scopeID = UUID()
        let entityID = UUID()
        let older = insertMutation(in: context, scopeID: scopeID, entityType: .idea, entityID: entityID)
        let latest = insertMutation(in: context, scopeID: scopeID, entityType: .idea,
            entityID: entityID, operation: .create, offset: 1)
        let sending = insertMutation(in: context, scopeID: scopeID, entityType: .idea,
            entityID: entityID, state: .sending, offset: 2)
        let attention = insertMutation(in: context, scopeID: scopeID, entityType: .idea,
            entityID: entityID, state: .requiresAttention, offset: 3)
        let otherScope = insertMutation(in: context, scopeID: UUID(), entityType: .idea,
            entityID: entityID, offset: 4)
        let otherType = insertMutation(in: context, scopeID: scopeID, entityType: .event,
            entityID: entityID, offset: 5)
        let otherEntity = insertMutation(in: context, scopeID: scopeID, entityType: .idea,
            entityID: UUID(), offset: 6)
        let untouched = [older, sending, attention, otherScope, otherType, otherEntity]
        let originals = untouched.map(PendingMutationSnapshot.init)
        let originalID = latest.id
        let originalDate = latest.createdAt
        // Coalescing resets retry fields, but does not rewrite a lease field.
        latest.leaseExpiresAt = timestamp.addingTimeInterval(300)
        let lease = latest.leaseExpiresAt
        try context.save()

        makeWriter(context).coalesceMutation(scopeID: scopeID, entityType: .idea, entityID: entityID,
            payload: Data([9]), operation: .update, baseVersion: nil,
            pendingMutations: [latest] + untouched)

        #expect(latest.id == originalID)
        #expect(latest.createdAt == originalDate)
        #expect(latest.operation == .create)
        #expect(latest.payload == Data([9]))
        #expect(latest.baseVersion == nil)
        expectRetryReset(latest)
        #expect(latest.leaseExpiresAt == lease)
        #expect(untouched.map(PendingMutationSnapshot.init) == originals)
        for mutation in untouched { expectRetryUnchanged(mutation) }
        #expect(sending.state == .sending)
        #expect(sending.leaseExpiresAt == timestamp.addingTimeInterval(300))
        #expect(attention.state == .requiresAttention)
        #expect(try mutations(in: context).count == 7)
    }

    @Test("A non-create pending row adopts the requested operation and version")
    func nonCreateAdoptsOperation() throws {
        let context = try makeContext()
        let scopeID = UUID()
        let pending = insertMutation(in: context, scopeID: scopeID, entityID: scopeID, operation: .delete)
        let originalID = pending.id

        makeWriter(context).coalesceMutation(scopeID: scopeID, entityType: .workspace, entityID: scopeID,
            payload: Data([8]), operation: .update, baseVersion: 17, pendingMutations: [pending])

        #expect(pending.id == originalID)
        #expect(pending.operation == .update)
        #expect(pending.baseVersion == 17)
        #expect(pending.payload == Data([8]))
        expectRetryReset(pending)
    }

    @Test("Leased and attention mutations retain their envelopes while a fresh pending edit is inserted",
          arguments: [SyncMutationState.sending, .requiresAttention])
    func nonPendingEditGetsFreshIdentity(state: SyncMutationState) throws {
        let context = try makeContext()
        let scopeID = UUID()
        let pending = insertMutation(in: context, scopeID: scopeID, entityID: scopeID,
            operation: .create, state: state)
        try context.save()
        let original = PendingMutationSnapshot(pending)
        let lease = pending.leaseExpiresAt

        makeWriter(context).coalesceMutation(scopeID: scopeID, entityType: .workspace, entityID: scopeID,
            payload: Data([9]), operation: .update, baseVersion: 7, pendingMutations: [pending])

        let rows = try mutations(in: context)
        let fresh = try #require(rows.first { $0.id != original.id })
        #expect(rows.count == 2)
        #expect(PendingMutationSnapshot(pending) == original)
        #expect(pending.state == state)
        #expect(pending.leaseExpiresAt == lease)
        expectRetryUnchanged(pending)
        #expect(fresh.scopeID == scopeID)
        #expect(fresh.entityID == scopeID)
        #expect(fresh.entityType == .workspace)
        #expect(fresh.operation == .update)
        #expect(fresh.payload == Data([9]))
        #expect(fresh.baseVersion == 7)
        #expect(fresh.ownerUserID == "owner")
        expectRetryReset(fresh)
    }

    @Test("The supplied account-filtered candidates and owner control account isolation")
    func respectsCallerAccountScope() throws {
        let context = try makeContext()
        let scopeID = UUID()
        let other = insertMutation(in: context, scopeID: scopeID, entityID: scopeID, ownerUserID: "other")
        try context.save()
        let original = PendingMutationSnapshot(other)

        // The controller excludes the other account before handing candidates to the writer.
        for owner: String? in ["owner", nil] {
            let candidates = try mutations(in: context).filter { $0.ownerUserID == owner }
            makeWriter(context, ownerUserID: owner).coalesceMutation(
                scopeID: scopeID, entityType: .workspace, entityID: scopeID,
                payload: Data([9]), operation: .update, baseVersion: nil, pendingMutations: candidates)
        }

        let rows = try mutations(in: context)
        #expect(rows.count == 3)
        #expect(rows.filter { $0.ownerUserID == "owner" }.count == 1)
        #expect(rows.filter { $0.ownerUserID == nil }.count == 1)
        #expect(PendingMutationSnapshot(other) == original)
        expectRetryUnchanged(other)
    }

    @Test("Workspace and child deletes cancel only the newest pending create",
          arguments: [true, false])
    func deletionCancelsLatestCreate(isWorkspace: Bool) throws {
        let context = try makeContext()
        let archive = makeArchive()
        let entityID = isWorkspace ? archive.mainEventID : archive.ideas[0].id
        let entityType: SyncEntityType = isWorkspace ? .workspace : .idea
        let older = insertMutation(in: context, scopeID: archive.mainEventID,
            entityType: entityType, entityID: entityID)
        let latest = insertMutation(in: context, scopeID: archive.mainEventID,
            entityType: entityType, entityID: entityID, operation: .create, offset: 1)
        try context.save()
        let originals = Set([older, latest].map(PendingMutationSnapshot.init))

        try delete(using: makeWriter(context), archive: archive, isWorkspace: isWorkspace,
            pendingMutations: [latest, older])

        #expect(latest.isDeleted)
        #expect(!older.isDeleted)
        #expect(older.operation == .update)
        expectRetryUnchanged(older)
        #expect(Set(try mutations(in: ModelContext(context.container)).map(PendingMutationSnapshot.init)) == originals)
        try context.save()
        #expect(try mutations(in: ModelContext(context.container)).map(\.id) == [older.id])
    }

    @Test("Workspace and child tombstones retain the newest pending identity and reset retries",
          arguments: [true, false])
    func deletionCoalescesLatestPending(isWorkspace: Bool) throws {
        let context = try makeContext()
        let archive = makeArchive()
        let entityID = isWorkspace ? archive.mainEventID : archive.ideas[0].id
        let entityType: SyncEntityType = isWorkspace ? .workspace : .idea
        let older = insertMutation(in: context, scopeID: archive.mainEventID,
            entityType: entityType, entityID: entityID, operation: .create)
        let latest = insertMutation(in: context, scopeID: archive.mainEventID,
            entityType: entityType, entityID: entityID, offset: 1)
        let originalID = latest.id
        let originalDate = latest.createdAt

        try delete(using: makeWriter(context), archive: archive, isWorkspace: isWorkspace,
            pendingMutations: [latest, older])

        #expect(latest.id == originalID)
        #expect(latest.createdAt == originalDate)
        #expect(latest.operation == .delete)
        #expect(latest.payload.isEmpty)
        #expect(latest.baseVersion == (isWorkspace ? 19 : nil))
        expectRetryReset(latest)
        #expect(!older.isDeleted)
        #expect(older.operation == .create)
        expectRetryUnchanged(older)
        #expect(try mutations(in: context).count == 2)
    }

    @Test("Workspace and child deletes enqueue fresh tombstones when no pending candidate exists",
          arguments: [true, false])
    func deletionInsertsTombstone(isWorkspace: Bool) throws {
        // Include no candidate, a leased create, and an attention create. None
        // may be cancelled as though it were an unsent pending create.
        for state: SyncMutationState? in [nil, .sending, .requiresAttention] {
            let context = try makeContext()
            let archive = makeArchive()
            let entityID = isWorkspace ? archive.mainEventID : archive.ideas[0].id
            let entityType: SyncEntityType = isWorkspace ? .workspace : .idea
            let existing = state.map {
                insertMutation(in: context, scopeID: archive.mainEventID, entityType: entityType,
                    entityID: entityID, operation: .create, state: $0)
            }
            let candidates = existing.map { [$0] } ?? []
            try context.save()
            let originals = candidates.map(PendingMutationSnapshot.init)

            try delete(using: makeWriter(context), archive: archive, isWorkspace: isWorkspace,
                pendingMutations: candidates)

            let rows = try mutations(in: context)
            let tombstone = try #require(rows.first { $0.id != existing?.id })
            #expect(rows.count == candidates.count + 1)
            #expect(tombstone.scopeID == archive.mainEventID)
            #expect(tombstone.entityType == entityType)
            #expect(tombstone.entityID == entityID)
            #expect(tombstone.operation == .delete)
            #expect(tombstone.payload.isEmpty)
            #expect(tombstone.baseVersion == (isWorkspace ? 19 : nil))
            #expect(tombstone.ownerUserID == "owner")
            expectRetryReset(tombstone)
            #expect(candidates.map(PendingMutationSnapshot.init) == originals)
            if let existing {
                #expect(existing.state == state)
                #expect(!existing.isDeleted)
                expectRetryUnchanged(existing)
            }
            #expect(try mutations(in: ModelContext(context.container)).map(PendingMutationSnapshot.init) == originals)
        }
    }

    @Test("Entity diffs skip identical payloads and stage creates and updates without child base versions")
    func entityDiffs() throws {
        let context = try makeContext()
        let writer = makeWriter(context)
        let previous = makeArchive()
        try writer.coalesceEntityMutations(scopeID: previous.mainEventID,
            previousArchive: previous, archive: previous, pendingMutations: [])
        #expect(!context.hasChanges)
        #expect(try mutations(in: context).isEmpty)

        var archive = previous
        archive.ideas[0].title = "Edited idea"
        let added = PlanningIdea(eventID: archive.mainEventID, title: "Added idea", note: "",
            category: .music, submittedBy: "Host", submittedAt: timestamp)
        archive.ideas.append(added)
        let pending = insertMutation(in: context, scopeID: archive.mainEventID, entityType: .idea,
            entityID: archive.ideas[0].id)
        let originalID = pending.id
        try writer.coalesceEntityMutations(scopeID: archive.mainEventID,
            previousArchive: previous, archive: archive, pendingMutations: [pending])

        let rows = try mutations(in: context)
        #expect(rows.count == 2)
        #expect(pending.id == originalID)
        #expect(pending.operation == .update)
        #expect(pending.baseVersion == nil)
        expectRetryReset(pending)
        let fresh = try #require(rows.first { $0.entityID == added.id })
        #expect(fresh.operation == .create)
        #expect(fresh.baseVersion == nil)
        #expect(fresh.ownerUserID == "owner")
        #expect(try codec.decode(PlanningIdea.self, from: pending.payload).title == "Edited idea")
        #expect(try codec.decode(PlanningIdea.self, from: fresh.payload) == added)
        #expect(previous.ideas[0].title == "Original idea")
        #expect(archive.ideas[0].imageData == Data([1, 2]))
        #expect(try codec.decode(PlanningIdea.self, from: pending.payload).imageData == nil)
    }

    @Test("An initial archive queues each child as a create with the supplied owner")
    func initialArchiveCreatesChildren() throws {
        let context = try makeContext()
        let archive = makeArchive()
        let expected = try archive.syncEntities(using: codec)

        try makeWriter(context).coalesceEntityMutations(scopeID: archive.mainEventID,
            previousArchive: nil, archive: archive, pendingMutations: [])

        let rows = try mutations(in: context)
        #expect(!rows.isEmpty)
        #expect(rows.count == expected.count)
        for row in rows {
            #expect(row.payload == expected[.init(type: row.entityType, id: row.entityID)])
            #expect(row.scopeID == archive.mainEventID)
            #expect(row.operation == .create)
            #expect(row.baseVersion == nil)
            #expect(row.ownerUserID == "owner")
            expectRetryReset(row)
        }
        #expect(try mutations(in: ModelContext(context.container)).isEmpty)
    }

    private func makeContext() throws -> ModelContext {
        let configuration = ModelConfiguration(schema: OfflineSyncSchema.schema,
            isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: OfflineSyncSchema.schema, configurations: [configuration])
        let context = ModelContext(container)
        context.autosaveEnabled = false
        return context
    }

    private func makeWriter(_ context: ModelContext, ownerUserID: String? = "owner") -> WorkspaceOutboxWriter {
        WorkspaceOutboxWriter(context: context, codec: codec, ownerUserID: ownerUserID)
    }

    private func mutations(in context: ModelContext) throws -> [PendingMutation] {
        try context.fetch(FetchDescriptor<PendingMutation>())
    }

    private func insertMutation(
        in context: ModelContext, scopeID: UUID, entityType: SyncEntityType = .workspace,
        entityID: UUID, operation: SyncMutationOperation = .update,
        state: SyncMutationState = .pending, offset: TimeInterval = 0, ownerUserID: String? = "owner"
    ) -> PendingMutation {
        let mutation = PendingMutation(scopeID: scopeID, entityType: entityType, entityID: entityID,
            operation: operation, payload: Data([1]), baseVersion: 6,
            createdAt: timestamp.addingTimeInterval(offset), ownerUserID: ownerUserID)
        mutation.state = state
        mutation.attemptCount = 3
        mutation.nextAttemptAt = timestamp.addingTimeInterval(60)
        mutation.lastFailureCode = "RETRY_TEST"
        if state == .sending { mutation.leaseExpiresAt = timestamp.addingTimeInterval(300) }
        context.insert(mutation)
        return mutation
    }

    private func expectRetryReset(_ mutation: PendingMutation) {
        #expect(mutation.state == .pending)
        #expect(mutation.attemptCount == 0)
        #expect(mutation.nextAttemptAt == nil)
        #expect(mutation.lastFailureCode == nil)
    }

    private func expectRetryUnchanged(_ mutation: PendingMutation) {
        #expect(mutation.attemptCount == 3)
        #expect(mutation.nextAttemptAt == timestamp.addingTimeInterval(60))
        #expect(mutation.lastFailureCode == "RETRY_TEST")
    }

    private func makeArchive() -> WorkspaceArchiveV1 {
        let workspace = PlanningWorkspace.newWorkspace(title: "Outbox fixture", startsAt: timestamp,
            eventLocation: nil, imageData: nil)
        var archive = WorkspaceArchiveV1(workspace: workspace)
        archive.ideas = [PlanningIdea(eventID: archive.mainEventID, title: "Original idea", note: "",
            category: .music, submittedBy: "Host", submittedAt: timestamp, imageData: Data([1, 2]))]
        return archive
    }

    private func delete(
        using writer: WorkspaceOutboxWriter, archive: WorkspaceArchiveV1,
        isWorkspace: Bool, pendingMutations: [PendingMutation]
    ) throws {
        if isWorkspace {
            writer.coalesceDeletion(scopeID: archive.mainEventID, baseVersion: 19,
                pendingMutations: pendingMutations)
        } else {
            var removed = archive
            removed.ideas = []
            try writer.coalesceEntityMutations(scopeID: archive.mainEventID,
                previousArchive: archive, archive: removed, pendingMutations: pendingMutations)
        }
    }
}
