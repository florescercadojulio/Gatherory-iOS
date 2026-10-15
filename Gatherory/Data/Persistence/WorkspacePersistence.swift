import Foundation
import Observation
import SwiftData

@Model
final class WorkspaceRecord {
    /// A remote workspace can legitimately be cached for more than one signed-in
    /// account on the same device, so identity is `(ownerUserID, id)`.
    var id: UUID
    @Attribute(.externalStorage) var payload: Data
    var payloadSchemaVersion: Int
    var sortOrder: Int
    var createdAt: Date
    var updatedAt: Date
    var ownerUserID: String?
    var serverVersion: Int = 0

    init(
        id: UUID,
        payload: Data,
        payloadSchemaVersion: Int = WorkspaceArchiveV1.schemaVersion,
        sortOrder: Int,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        ownerUserID: String? = nil,
        serverVersion: Int = 0
    ) {
        self.id = id
        self.payload = payload
        self.payloadSchemaVersion = payloadSchemaVersion
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.ownerUserID = ownerUserID
        self.serverVersion = serverVersion
    }
}

/// Owns the one local write path for the workspace graph and its sync outbox.
/// Feature views continue to edit observable domain objects; observation below
/// turns those edits into a debounced, atomic SwiftData transaction.
@MainActor
@Observable
final class WorkspacePersistenceController {
    @ObservationIgnored let container: ModelContainer
    private(set) var lastError: Error?

    @ObservationIgnored private let context: ModelContext
    @ObservationIgnored private let codec: WorkspaceArchiveCodec
    @ObservationIgnored private weak var observedLibrary: WorkspaceLibrary?
    @ObservationIgnored private var pendingSaveTask: Task<Void, Never>?
    @ObservationIgnored private var isObserving = false
    @ObservationIgnored private var suppressNextObservedChange = false
    @ObservationIgnored private(set) var activeUserID: String?
    @ObservationIgnored var onPendingMutations: (() -> Void)?

    /// Passive refresh must yield to local edits, including a failed disk save.
    var hasUnsavedLocalChanges: Bool {
        pendingSaveTask != nil || lastError != nil
    }

    init(
        isStoredInMemoryOnly: Bool = false,
        storeURL: URL? = nil
    ) throws {
        let configuration: ModelConfiguration
        if let storeURL {
            configuration = ModelConfiguration(
                "Gatherory",
                schema: OfflineSyncSchema.schema,
                url: storeURL,
                cloudKitDatabase: .none
            )
        } else {
            configuration = ModelConfiguration(
                "Gatherory",
                schema: OfflineSyncSchema.schema,
                isStoredInMemoryOnly: isStoredInMemoryOnly,
                cloudKitDatabase: .none
            )
        }
        container = try ModelContainer(
            for: OfflineSyncSchema.schema,
            configurations: [configuration]
        )
        context = ModelContext(container)
        context.autosaveEnabled = false

        codec = WorkspaceArchiveCodec()
    }

    static func bootstrap(
        isStoredInMemoryOnly: Bool = false
    ) -> WorkspacePersistenceController {
        do {
            return try WorkspacePersistenceController(
                isStoredInMemoryOnly: isStoredInMemoryOnly
            )
        } catch {
            guard !isStoredInMemoryOnly else {
                fatalError("Gatherory could not create an ephemeral data store: \(error)")
            }

            do {
                let fallback = try WorkspacePersistenceController(isStoredInMemoryOnly: true)
                fallback.lastError = error
                return fallback
            } catch {
                fatalError("Gatherory could not create a local data store: \(error)")
            }
        }
    }

    /// Restores the durable graph. Development fixtures are written only when
    /// the store is genuinely empty and intentionally do not enter the outbox.
    func restoreLibrary(seedData: Bool, ownerUserID: String? = nil) -> WorkspaceLibrary {
        do {
            let descriptor = FetchDescriptor<WorkspaceRecord>(
                sortBy: [SortDescriptor(\WorkspaceRecord.sortOrder)]
            )
            let records = try context.fetch(descriptor).filter {
                $0.ownerUserID == ownerUserID
            }

            activeUserID = ownerUserID

            if !records.isEmpty {
                let workspaces = try records.map { record -> PlanningWorkspace in
                    guard record.payloadSchemaVersion == WorkspaceArchiveV1.schemaVersion else {
                        throw WorkspacePersistenceError.unsupportedArchiveVersion(
                            record.payloadSchemaVersion
                        )
                    }
                    return try codec.decode(WorkspaceArchiveV1.self, from: record.payload)
                        .makeWorkspace()
                }
                return WorkspaceLibrary(workspaces: workspaces)
            }

            let library = WorkspaceLibrary.bootstrap(seedData: seedData)
            if !library.workspaces.isEmpty {
                try persist(library, enqueuesMutations: false)
            }
            return library
        } catch {
            lastError = error
            return WorkspaceLibrary.bootstrap(seedData: seedData)
        }
    }

    func activate(
        userID: String?,
        in library: WorkspaceLibrary,
        seedData: Bool = false
    ) {
        guard activeUserID != userID else { return }
        pendingSaveTask?.cancel()
        pendingSaveTask = nil
        activeUserID = userID

        let restored = restoreLibrary(seedData: seedData, ownerUserID: userID)
        suppressNextObservedChange = true
        library.replaceAll(with: restored.workspaces)
    }

    func startObserving(_ library: WorkspaceLibrary) {
        guard observedLibrary !== library || !isObserving else { return }
        observedLibrary = library
        isObserving = true
        observeNextChange(in: library)
    }

    func flush(_ library: WorkspaceLibrary? = nil) {
        pendingSaveTask?.cancel()
        pendingSaveTask = nil

        guard let library = library ?? observedLibrary else { return }
        do {
            try flushForAccountTransition(library)
        } catch {
            context.rollback()
            lastError = error
        }
    }

    /// Account teardown must surface disk errors instead of losing unsaved edits.
    func flushForAccountTransition(_ library: WorkspaceLibrary) throws {
        try saveChanges(in: library)
    }

    /// Explicit actions can confirm durable local storage before closing their UI.
    func saveChanges(in library: WorkspaceLibrary) throws {
        pendingSaveTask?.cancel()
        pendingSaveTask = nil
        do {
            try persist(library, enqueuesMutations: true)
            lastError = nil
        } catch {
            context.rollback()
            lastError = error
            throw error
        }
    }

    /// Explicit sign-out retries pending work, but never discards conflicts.
    /// Call only after joining the active sync task (no live leases).
    func prepareFinalSyncRetry() throws {
        for mutation in try context.fetch(FetchDescriptor<PendingMutation>())
        where mutation.ownerUserID == activeUserID && mutation.state != .requiresAttention {
            mutation.state = .pending
            mutation.nextAttemptAt = nil
            mutation.leaseExpiresAt = nil
        }
        try mediaBookkeeper.stageFinalRetry()
        try context.save()
    }

    /// Removes every account-scoped local artifact after the backend confirms
    /// permanent account deletion. No outbox tombstones are produced because
    /// the deleted identity can no longer authenticate to deliver them.
    func purgeAllLocalData(from library: WorkspaceLibrary) throws {
        pendingSaveTask?.cancel()
        pendingSaveTask = nil

        let userID = activeUserID
        try mediaBookkeeper.stageRemoval()

        for record in try context.fetch(FetchDescriptor<WorkspaceRecord>())
        where record.ownerUserID == userID {
            context.delete(record)
        }
        for mutation in try context.fetch(FetchDescriptor<PendingMutation>())
        where mutation.ownerUserID == userID {
            context.delete(mutation)
        }
        for checkpoint in try context.fetch(FetchDescriptor<SyncCheckpoint>())
        where checkpoint.ownerUserID == userID {
            context.delete(checkpoint)
        }
        for receipt in try context.fetch(FetchDescriptor<AppliedSyncEnvelope>())
        where receipt.ownerUserID == userID {
            context.delete(receipt)
        }

        try context.save()
        library.removeAll()
    }

    private func observeNextChange(in library: WorkspaceLibrary) {
        let persistence = self
        withObservationTracking {
            // Constructing archives intentionally reads every persisted field,
            // including value-type children, so any domain edit invalidates the
            // observation without feature code needing explicit save calls.
            _ = library.workspaces.map(WorkspaceArchiveV1.init(workspace:))
        } onChange: {
            Task { @MainActor in
                persistence.handleObservedChange()
            }
        }
    }

    private func handleObservedChange() {
        guard let library = observedLibrary else { return }
        observeNextChange(in: library)
        if suppressNextObservedChange {
            suppressNextObservedChange = false
            return
        }
        scheduleSave(of: library)
    }

    private func scheduleSave(of library: WorkspaceLibrary) {
        pendingSaveTask?.cancel()
        pendingSaveTask = Task { @MainActor [weak self, weak library] in
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled, let self, let library else { return }
            self.flush(library)
        }
    }

    private func persist(
        _ library: WorkspaceLibrary,
        enqueuesMutations: Bool
    ) throws {
        let archives = library.workspaces.map(WorkspaceArchiveV1.init(workspace:))
        let existingRecords = try context.fetch(FetchDescriptor<WorkspaceRecord>())
            .filter { $0.ownerUserID == activeUserID }
        let recordsByID = Dictionary(uniqueKeysWithValues: existingRecords.map { ($0.id, $0) })
        let pendingMutations = enqueuesMutations
            ? try context.fetch(FetchDescriptor<PendingMutation>())
                .filter { $0.ownerUserID == activeUserID }
            : []
        let persistedIDs = Set(archives.map(\.mainEventID))
        let outbox = WorkspaceOutboxWriter(context: context, codec: codec, ownerUserID: activeUserID)

        for record in existingRecords where !persistedIDs.contains(record.id) {
            let wasScopedEvent = (try? codec.decode(WorkspaceArchiveV1.self, from: record.payload).isScopedEvent) == true
            context.delete(record)
            guard enqueuesMutations else { continue }
            if wasScopedEvent {
                try discardPendingMutations(scopeID: record.id)
                continue
            }
            outbox.coalesceDeletion(
                scopeID: record.id,
                baseVersion: record.serverVersion,
                pendingMutations: pendingMutations
            )
        }

        for (sortOrder, archive) in archives.enumerated() {
            if enqueuesMutations, archive.isScopedEvent == true {
                // Scoped workspaces never have a workspace-level mutation.
                // Keep this cleanup within the save transaction, not in the
                // read-only pending-scope query used by UI state.
                try discardWorkspaceMutations(scopeID: archive.mainEventID)
            }
            let payload = try codec.encode(archive)
            let syncPayload = try archive.syncPayload(using: codec)
            let existingRecord = recordsByID[archive.mainEventID]
            let previousArchive = try existingRecord.map {
                try codec.decode(WorkspaceArchiveV1.self, from: $0.payload)
            }
            let payloadChanged = existingRecord?.payload != payload
            let syncPayloadChanged = try previousArchive.map {
                try $0.syncPayload(using: codec) != syncPayload
            } ?? true
            let orderChanged = existingRecord?.sortOrder != sortOrder

            guard existingRecord == nil || payloadChanged || orderChanged else { continue }

            if let existingRecord {
                existingRecord.payload = payload
                existingRecord.payloadSchemaVersion = WorkspaceArchiveV1.schemaVersion
                existingRecord.sortOrder = sortOrder
                existingRecord.updatedAt = .now
            } else {
                context.insert(
                    WorkspaceRecord(
                        id: archive.mainEventID,
                        payload: payload,
                        sortOrder: sortOrder,
                        ownerUserID: activeUserID
                    )
                )
            }

            guard enqueuesMutations else { continue }
            if archive.isScopedEvent != true && (syncPayloadChanged || existingRecord == nil) {
                outbox.coalesceMutation(
                    scopeID: archive.mainEventID,
                    entityType: .workspace,
                    entityID: archive.mainEventID,
                    payload: syncPayload,
                    operation: existingRecord == nil ? .create : .update,
                    // Workspace snapshots are the compatibility/materialized view.
                    // Independently versioned child records are the collaboration boundary.
                    baseVersion: nil,
                    pendingMutations: pendingMutations
                )
            }
            try outbox.coalesceEntityMutations(
                scopeID: archive.mainEventID,
                previousArchive: previousArchive,
                archive: archive,
                pendingMutations: pendingMutations
            )
        }

        if context.hasChanges {
            try context.save()
            if enqueuesMutations {
                onPendingMutations?()
            }
        }
    }

    func pendingScopeIDs() throws -> Set<UUID> {
        return Set(try context.fetch(FetchDescriptor<PendingMutation>())
            .filter { $0.ownerUserID == activeUserID }
            .map(\.scopeID))
    }

    /// A rejection is durable state, not a connectivity problem. Surface its
    /// safe server code after relaunches so it cannot be cleared merely because
    /// there are no ready mutations left to claim.
    func pendingSyncAttentionFailureCode() throws -> String? {
        try context.fetch(FetchDescriptor<PendingMutation>())
            .filter {
                $0.ownerUserID == activeUserID
                    && $0.state == .requiresAttention
            }
            .sorted { $0.createdAt < $1.createdAt }
            .first?
            .lastFailureCode
    }

    /// Repairs a workspace scope that the server cannot materialize.
    ///
    /// This covers both legacy malformed workspace mutations and a server
    /// reset that removed a previously acknowledged scope. In the latter case
    /// only child mutations may remain locally and the server responds with
    /// `SYNC_SCOPE_NOT_FOUND`. Reusing rejected identifiers would replay their
    /// durable receipts, so replace the whole scope with a fresh workspace-first
    /// batch derived from the current local workspace.
    @discardableResult
    func repairWorkspaceScopeMismatches(from library: WorkspaceLibrary) throws -> Int {
        let mutations = try context.fetch(FetchDescriptor<PendingMutation>())
            .filter { $0.ownerUserID == activeUserID }
        let workspacesByID = Dictionary(
            uniqueKeysWithValues: library.workspaces.map { ($0.mainEventID, $0) }
        )
        var repairedScopes = Set<UUID>()

        var repairs: [(corruptScopeID: UUID, workspace: PlanningWorkspace)] = []

        for mutation in mutations
        where mutation.entityType == .workspace && mutation.operation != .delete {
            let archive = try codec.decode(WorkspaceArchiveV1.self, from: mutation.payload)
            let intendedScopeID = archive.mainEventID
            guard mutation.scopeID != intendedScopeID || mutation.entityID != intendedScopeID,
                  let workspace = workspacesByID[intendedScopeID]
            else { continue }
            repairs.append((mutation.scopeID, workspace))
        }

        // A valid local workspace can lose its server scope after a database
        // reset or interrupted migration. Re-bootstrap it from the local graph
        // rather than leaving child mutations permanently blocked.
        for mutation in mutations
        where mutation.state == .requiresAttention
            && mutation.lastFailureCode == "SYNC_SCOPE_NOT_FOUND"
            && mutation.operation != .delete
            && mutation.entityType != .workspace {
            guard let workspace = workspacesByID[mutation.scopeID] else { continue }
            repairs.append((mutation.scopeID, workspace))
        }

        for repair in repairs {
            let corruptScopeID = repair.corruptScopeID
            guard repairedScopes.insert(corruptScopeID).inserted else { continue }
            let workspace = repair.workspace
            let intendedScopeID = workspace.mainEventID
            let affected = mutations.filter { $0.scopeID == corruptScopeID }
            for affectedMutation in affected {
                context.delete(affectedMutation)
            }

            try mediaBookkeeper.stageRemoval(scopeID: corruptScopeID)

            for checkpoint in try context.fetch(FetchDescriptor<SyncCheckpoint>())
            where checkpoint.ownerUserID == activeUserID && checkpoint.scopeID == corruptScopeID {
                context.delete(checkpoint)
            }

            let repairedArchive = WorkspaceArchiveV1(workspace: workspace)
            SyncOutbox.enqueue(
                SyncMutationDraft(
                    scopeID: intendedScopeID,
                    entityType: .workspace,
                    entityID: intendedScopeID,
                    operation: .create,
                    payload: try repairedArchive.syncPayload(using: codec),
                    baseVersion: nil
                ),
                ownerUserID: activeUserID,
                in: context
            )
            for (key, payload) in try repairedArchive.syncEntities(using: codec) {
                SyncOutbox.enqueue(
                    SyncMutationDraft(
                        scopeID: intendedScopeID,
                        entityType: key.type,
                        entityID: key.id,
                        operation: .create,
                        payload: payload,
                        baseVersion: nil
                    ),
                    ownerUserID: activeUserID,
                    in: context
                )
            }
        }

        if context.hasChanges {
            try context.save()
            onPendingMutations?()
        }
        return repairedScopes.count
    }

    // Build for each operation so account switches never leave a stale owner.
    private var mediaBookkeeper: WorkspaceMediaBookkeeper {
        WorkspaceMediaBookkeeper(context: context, codec: codec, ownerUserID: activeUserID)
    }

    func prepareMediaTransfers(from library: WorkspaceLibrary) throws {
        try mediaBookkeeper.stagePreparation(from: library)
        if context.hasChanges { try context.save() }
    }

    /// Upgrades image-bearing mutations produced by builds that predate the
    /// R2 outbox. This runs before the first push so a legacy base64 payload
    /// cannot fail with HTTP 413 and block the media worker behind it.
    func sanitizePendingMediaMutations() throws {
        try mediaBookkeeper.stageSanitization()
        if context.hasChanges { try context.save() }
    }

    func pendingMediaTransfers(scopeID: UUID? = nil) throws -> [PendingMediaTransferSnapshot] {
        try mediaBookkeeper.pendingMediaTransfers(scopeID: scopeID)
    }

    func hasPendingMediaTransfers() throws -> Bool {
        try mediaBookkeeper.hasPendingMediaTransfers()
    }

    func pendingMediaScopeIDs() throws -> Set<UUID> {
        try mediaBookkeeper.pendingMediaScopeIDs()
    }

    func markMediaTransferUploading(_ id: UUID) throws {
        guard try mediaBookkeeper.stageUploading(id) else { return }
        try context.save()
    }

    func completeMediaTransfer(_ id: UUID) throws {
        guard try mediaBookkeeper.stageCompletion(id) else { return }
        try context.save()
    }

    func failMediaTransfer(_ id: UUID) throws {
        guard try mediaBookkeeper.stageFailure(id) else { return }
        try context.save()
    }

    func currentCursor(for scopeID: UUID) throws -> String? {
        try context.fetch(FetchDescriptor<SyncCheckpoint>())
            .first(where: {
                $0.scopeID == scopeID && $0.ownerUserID == activeUserID
            })?
            .cursor
    }

    func applyBootstrap(
        _ snapshots: [RemoteWorkspaceSnapshot],
        entities: [RemoteEntitySnapshot] = [],
        to library: WorkspaceLibrary
    ) throws {
        let pendingScopes = try pendingScopeIDs().union(pendingMediaScopeIDs())
        let authoritativeScopeIDs = Set(snapshots.map(\.scopeID))
        // An empty bootstrap can mean that the request was omitted, failed
        // before decoding, or was made during an account transition. Only a
        // successful root snapshot is authoritative enough to reconcile stale
        // scoped projections from this account's local cache.
        let hasAuthoritativeRoot = try snapshots.contains { snapshot in
            guard !pendingScopes.contains(snapshot.scopeID) else { return false }
            guard snapshot.effectivePayloadSchemaVersion == SyncPayloadContract.currentVersion else {
                throw WorkspacePersistenceError.unsupportedSyncPayloadVersion(
                    snapshot.effectivePayloadSchemaVersion
                )
            }
            let archive = try codec.decode(WorkspaceArchiveV1.self, from: snapshot.payload)
            return archive.isScopedEvent != true
        }

        for workspace in library.workspaces where workspace.isScopedEvent {
            try discardWorkspaceMutations(scopeID: workspace.mainEventID)
        }
        let merger = WorkspaceRemoteMerger(context: context, codec: codec, ownerUserID: activeUserID)
        let remoteWorkspaces = try merger.stageBootstrap(
            snapshots,
            entities: entities,
            pendingScopes: pendingScopes,
            existingWorkspaceCount: library.workspaces.count
        )

        let staleScopedWorkspaceIDs = hasAuthoritativeRoot
            ? try removeStaleScopedWorkspaces(
                authoritativeScopeIDs: authoritativeScopeIDs,
                pendingScopeIDs: pendingScopes
            )
            : []

        if context.hasChanges { try context.save() }
        suppressNextObservedChange = true
        for workspaceID in staleScopedWorkspaceIDs {
            library.remove(workspaceID: workspaceID)
        }
        remoteWorkspaces.forEach(library.upsert)
    }

    func applyRemotePage(
        _ page: SyncPullPage,
        scopeID: UUID,
        to library: WorkspaceLibrary
    ) throws {
        if library.workspaces.first(where: { $0.mainEventID == scopeID })?.isScopedEvent == true {
            // Capture edits made while the request was in flight into the same
            // archive/outbox transaction before applying the authoritative page.
            try saveChanges(in: library)
        }
        let merger = WorkspaceRemoteMerger(context: context, codec: codec, ownerUserID: activeUserID)
        let cachedScopedArchive = try context.fetch(FetchDescriptor<WorkspaceRecord>())
            .first(where: { $0.id == scopeID && $0.ownerUserID == activeUserID })
            .flatMap { try? codec.decode(WorkspaceArchiveV1.self, from: $0.payload) }
        let result: WorkspaceRemoteMerger.PageResult
        do {
            result = try merger.stagePage(
                page,
                scopeID: scopeID,
                existingWorkspaceCount: library.workspaces.count
            )

            // Commit staged records, repairs, and receipts with the cursor,
            // before publishing. A failed merge must not leak a staged repair
            // into an unrelated later local save.
            if case let .merged(_, shouldDeleteWorkspace) = result,
               shouldDeleteWorkspace, cachedScopedArchive?.isScopedEvent == true {
                try discardPendingMutations(scopeID: scopeID)
                try mediaBookkeeper.stageRemoval(scopeID: scopeID)
            }
            try saveRemoteCheckpoint(page.nextCursor, scopeID: scopeID)
        } catch {
            context.rollback()
            throw error
        }

        switch result {
        case .checkpointOnly:
            // Empty/duplicate pages must not replace the graph or suppress edits.
            return
        case let .merged(archive, shouldDeleteWorkspace):
            suppressNextObservedChange = true
            if shouldDeleteWorkspace {
                library.remove(workspaceID: scopeID)
            } else if let archive {
                library.upsert(archive.makeWorkspace())
            }
        }
    }

    private func saveRemoteCheckpoint(_ cursor: String?, scopeID: UUID) throws {
        let checkpoint = try context.fetch(FetchDescriptor<SyncCheckpoint>())
            .first(where: {
                $0.scopeID == scopeID && $0.ownerUserID == activeUserID
            })
        if let checkpoint {
            checkpoint.cursor = cursor
            checkpoint.lastSuccessfulSyncAt = .now
        } else {
            context.insert(
                SyncCheckpoint(
                    scopeID: scopeID,
                    cursor: cursor,
                    lastSuccessfulSyncAt: .now,
                    ownerUserID: activeUserID
                )
            )
        }
        try context.save()
    }

    private func discardPendingMutations(scopeID: UUID) throws {
        for mutation in try context.fetch(FetchDescriptor<PendingMutation>())
        where mutation.ownerUserID == activeUserID && mutation.scopeID == scopeID {
            context.delete(mutation)
        }
    }

    private func discardWorkspaceMutations(scopeID: UUID) throws {
        for mutation in try context.fetch(FetchDescriptor<PendingMutation>())
        where mutation.ownerUserID == activeUserID
            && mutation.scopeID == scopeID
            && mutation.entityType == .workspace {
            context.delete(mutation)
        }
    }

    /// Reconciles local scoped projections after an authoritative root
    /// bootstrap. A root snapshot is the server's complete answer for a
    /// planner, so independently cached child projections that are absent
    /// from that answer are stale. Pending structured or media work protects
    /// a scope from removal so account switches and offline edits remain
    /// recoverable.
    private func removeStaleScopedWorkspaces(
        authoritativeScopeIDs: Set<UUID>,
        pendingScopeIDs: Set<UUID>
    ) throws -> [UUID] {
        let records = try context.fetch(FetchDescriptor<WorkspaceRecord>())
            .filter {
                $0.ownerUserID == activeUserID
                    && !authoritativeScopeIDs.contains($0.id)
                    && !pendingScopeIDs.contains($0.id)
            }

        var removedIDs: [UUID] = []
        for record in records {
            guard (try? codec.decode(WorkspaceArchiveV1.self, from: record.payload).isScopedEvent) == true
            else { continue }

            context.delete(record)
            try mediaBookkeeper.stageRemoval(scopeID: record.id)
            for receipt in try context.fetch(FetchDescriptor<AppliedSyncEnvelope>())
            where receipt.ownerUserID == activeUserID && receipt.scopeID == record.id {
                context.delete(receipt)
            }
            for checkpoint in try context.fetch(FetchDescriptor<SyncCheckpoint>())
            where checkpoint.ownerUserID == activeUserID && checkpoint.scopeID == record.id {
                context.delete(checkpoint)
            }
            removedIDs.append(record.id)
        }

        return removedIDs
    }

    /// A scoped write rejection is authoritative evidence that this account no
    /// longer has access. Clear only a locally identified scoped projection;
    /// bootstrap omission alone never discards offline work.
    @discardableResult
    func clearScopedWorkspaceAfterWriteForbidden(
        scopeID: UUID,
        from library: WorkspaceLibrary
    ) throws -> Bool {
        guard let record = try context.fetch(FetchDescriptor<WorkspaceRecord>())
            .first(where: { $0.id == scopeID && $0.ownerUserID == activeUserID }),
              (try? codec.decode(WorkspaceArchiveV1.self, from: record.payload).isScopedEvent) == true
        else { return false }

        context.delete(record)
        try discardPendingMutations(scopeID: scopeID)
        try mediaBookkeeper.stageRemoval(scopeID: scopeID)
        for receipt in try context.fetch(FetchDescriptor<AppliedSyncEnvelope>())
        where receipt.ownerUserID == activeUserID && receipt.scopeID == scopeID {
            context.delete(receipt)
        }
        for checkpoint in try context.fetch(FetchDescriptor<SyncCheckpoint>())
        where checkpoint.ownerUserID == activeUserID && checkpoint.scopeID == scopeID {
            context.delete(checkpoint)
        }
        try context.save()
        suppressNextObservedChange = true
        library.remove(workspaceID: scopeID)
        return true
    }

}

enum WorkspacePersistenceError: Error {
    case unsupportedArchiveVersion(Int)
    case unsupportedSyncPayloadVersion(Int)
}
