import Foundation
import SwiftData

/// Stages incoming records in the caller's context. The controller owns the
/// checkpoint, transaction boundary, observation suppression, and live library.
@MainActor
struct WorkspaceRemoteMerger {
    enum PageResult {
        case checkpointOnly
        case merged(archive: WorkspaceArchiveV1?, shouldDeleteWorkspace: Bool)
    }

    private let context: ModelContext
    private let codec: WorkspaceArchiveCodec
    private let ownerUserID: String?

    init(context: ModelContext, codec: WorkspaceArchiveCodec, ownerUserID: String?) {
        self.context = context
        self.codec = codec
        self.ownerUserID = ownerUserID
    }

    func stageBootstrap(
        _ snapshots: [RemoteWorkspaceSnapshot],
        entities: [RemoteEntitySnapshot],
        pendingScopes: Set<UUID>,
        existingWorkspaceCount: Int
    ) throws -> [PlanningWorkspace] {
        var remoteWorkspaces: [PlanningWorkspace] = []
        let entitiesByScope = Dictionary(grouping: entities, by: \.scopeID)

        for snapshot in snapshots where !pendingScopes.contains(snapshot.scopeID) {
            guard snapshot.effectivePayloadSchemaVersion == SyncPayloadContract.currentVersion else {
                throw WorkspacePersistenceError.unsupportedSyncPayloadVersion(
                    snapshot.effectivePayloadSchemaVersion
                )
            }
            var archive = try codec.decode(WorkspaceArchiveV1.self, from: snapshot.payload)
            // The workspace snapshot can carry the authorized canonical todo
            // projection (including direct child events). Supplemental todo
            // entities below provide the entity versions used for later CAS.
            try RemoteEntityVersionRecord.remove(
                scopeID: snapshot.scopeID, ownerUserID: ownerUserID, in: context
            )
            for entity in entitiesByScope[snapshot.scopeID] ?? [] {
                guard entity.effectivePayloadSchemaVersion == SyncPayloadContract.currentVersion else {
                    throw WorkspacePersistenceError.unsupportedSyncPayloadVersion(
                        entity.effectivePayloadSchemaVersion
                    )
                }
                try archive.applyEntity(
                    type: entity.entityType,
                    id: entity.entityID,
                    operation: .update,
                    payload: entity.payload,
                    codec: codec
                )
                if entity.entityType == .todo {
                    try RemoteEntityVersionRecord.upsert(
                        in: context, scopeID: entity.scopeID, entityType: .todo,
                        entityID: entity.entityID, serverVersion: entity.serverVersion,
                        ownerUserID: ownerUserID
                    )
                }
            }
            archive.enforceScopedIsolation()
            let record = try context.fetch(FetchDescriptor<WorkspaceRecord>())
                .first(where: {
                    $0.id == snapshot.scopeID && $0.ownerUserID == ownerUserID
                })

            if let record, let cached = try? codec.decode(WorkspaceArchiveV1.self, from: record.payload) {
                archive.preserveDownloadedMedia(from: cached)
            }
            let payload = try codec.encode(archive)

            if let record {
                record.payload = payload
                record.payloadSchemaVersion = WorkspaceArchiveV1.schemaVersion
                record.serverVersion = snapshot.serverVersion
                record.updatedAt = snapshot.updatedAt
            } else {
                context.insert(
                    WorkspaceRecord(
                        id: snapshot.scopeID,
                        payload: payload,
                        sortOrder: existingWorkspaceCount + remoteWorkspaces.count,
                        updatedAt: snapshot.updatedAt,
                        ownerUserID: ownerUserID,
                        serverVersion: snapshot.serverVersion
                    )
                )
            }
            remoteWorkspaces.append(archive.makeWorkspace())
        }

        return remoteWorkspaces
    }

    func stagePage(
        _ page: SyncPullPage,
        scopeID: UUID,
        existingWorkspaceCount: Int
    ) throws -> PageResult {
        // Empty and duplicate pulls do not decode or re-encode cached archives.
        if page.changes.isEmpty {
            return .checkpointOnly
        }
        let appliedIDs = Set(
            try context.fetch(FetchDescriptor<AppliedSyncEnvelope>())
                .filter { $0.ownerUserID == ownerUserID }
                .map(\.id)
        )
        // Even a previously applied projection can prove that an old rejected
        // update was only the nil-to-empty location restore bug. Re-merge that
        // projection after removing the echo, retaining all genuine pending edits.
        var repairedEnvelopeIDs = Set<UUID>()
        for change in page.changes
        where change.scopeID == scopeID && change.entityID == scopeID
            && change.entityType == .workspace && change.operation != .delete
            && change.effectivePayloadSchemaVersion == SyncPayloadContract.currentVersion {
            if try stageRejectedLocationEchoRepair(change.payload, scopeID: scopeID) {
                repairedEnvelopeIDs.insert(change.id)
            }
        }
        let newChanges = page.changes.filter {
            !appliedIDs.contains($0.id) || repairedEnvelopeIDs.contains($0.id)
        }
        guard !newChanges.isEmpty else {
            return .checkpointOnly
        }
        let record = try context.fetch(FetchDescriptor<WorkspaceRecord>())
            .first(where: {
                $0.id == scopeID && $0.ownerUserID == ownerUserID
            })
        var archive = try record.map {
            try codec.decode(WorkspaceArchiveV1.self, from: $0.payload)
        }
        var workspaceServerVersion = record?.serverVersion ?? 0
        var latestUpdatedAt = record?.updatedAt ?? .distantPast
        var shouldDeleteWorkspace = false

        for change in newChanges {
            guard change.effectivePayloadSchemaVersion == SyncPayloadContract.currentVersion else {
                throw WorkspacePersistenceError.unsupportedSyncPayloadVersion(
                    change.effectivePayloadSchemaVersion
                )
            }
            if change.entityType == .workspace {
                switch change.operation {
                case .delete:
                    archive = nil
                    shouldDeleteWorkspace = true
                case .create, .update:
                    var remoteArchive = try codec.decode(
                        WorkspaceArchiveV1.self,
                        from: change.payload
                    )
                    if let archive {
                        if remoteArchive.isScopedEvent == true {
                            remoteArchive.preserveDownloadedMedia(from: archive)
                        } else {
                            remoteArchive.preserveCollaborativeEntities(from: archive)
                        }
                    }
                    archive = remoteArchive
                    if var currentArchive = archive {
                        try overlayPendingTodoMutations(
                            scopeID: scopeID,
                            on: &currentArchive
                        )
                        archive = currentArchive
                    }
                    workspaceServerVersion = change.serverVersion
                    shouldDeleteWorkspace = false
                }
            } else if var currentArchive = archive {
                try currentArchive.applyEntity(
                    type: change.entityType,
                    id: change.entityID,
                    operation: change.operation,
                    payload: change.payload,
                    codec: codec
                )
                archive = currentArchive
                if change.entityType == .todo {
                    try RemoteEntityVersionRecord.upsert(
                        in: context, scopeID: change.scopeID, entityType: .todo,
                        entityID: change.entityID, serverVersion: change.serverVersion,
                        ownerUserID: ownerUserID
                    )
                    try overlayPendingTodoMutations(
                        entityID: change.entityID,
                        scopeID: scopeID,
                        on: &currentArchive
                    )
                    archive = currentArchive
                }
            }
            latestUpdatedAt = max(latestUpdatedAt, change.occurredAt)

            if !appliedIDs.contains(change.id) {
                context.insert(
                    AppliedSyncEnvelope(
                        id: change.id,
                        scopeID: scopeID,
                        ownerUserID: ownerUserID
                    )
                )
            }
        }

        if archive?.isScopedEvent == true, var authoritativeArchive = archive {
            authoritativeArchive.enforceScopedIsolation()
            try discardWorkspaceMutations(scopeID: scopeID)
            let pendingEntityMutations = try context.fetch(FetchDescriptor<PendingMutation>())
                .filter {
                    $0.ownerUserID == ownerUserID
                        && $0.scopeID == scopeID
                        && $0.entityType != .workspace
                }
                .sorted { $0.createdAt < $1.createdAt }
            for mutation in pendingEntityMutations {
                if mutation.entityType == .eventParticipation { continue }
                if mutation.entityType == .participant {
                    guard mutation.operation != .delete,
                          let pendingMember = try? codec.decode(WorkspaceMember.self, from: mutation.payload)
                    else { continue }
                    let authoritativeMember = authoritativeArchive.members.first { $0.id == mutation.entityID }
                    var overlayMember = pendingMember
                    if let authoritativeMember {
                        guard authoritativeMember.userID == ownerUserID,
                              pendingMember.userID == ownerUserID else { continue }
                    }
                    if let authoritativeMember {
                        // The snapshot owns identity links, role, permission,
                        // attendance, and invitation state. Only the signed-in
                        // user's profile edits can overlay it while pending.
                        overlayMember.userID = authoritativeMember.userID
                        overlayMember.participantRole = authoritativeMember.participantRole
                        overlayMember.attendance = authoritativeMember.attendance
                        overlayMember.planningPermission = authoritativeMember.planningPermission
                        overlayMember.invitationStatus = authoritativeMember.invitationStatus
                    }
                    let payload = try codec.encode(overlayMember)
                    try authoritativeArchive.applyEntity(
                        type: mutation.entityType,
                        id: mutation.entityID,
                        operation: mutation.operation,
                        payload: payload,
                        codec: codec
                    )
                    continue
                }
                if mutation.entityType == .event, mutation.entityID != authoritativeArchive.mainEventID {
                    continue
                }
                try authoritativeArchive.applyEntity(
                    type: mutation.entityType,
                    id: mutation.entityID,
                    operation: mutation.operation,
                    payload: mutation.payload,
                    codec: codec
                )
            }
            authoritativeArchive.enforceScopedIsolation()
            archive = authoritativeArchive
        }

        if shouldDeleteWorkspace {
            if let record { context.delete(record) }
            try RemoteEntityVersionRecord.remove(scopeID: scopeID, ownerUserID: ownerUserID, in: context)
        } else if let archive {
            let payload = try codec.encode(archive)
            if let record {
                record.payload = payload
                record.payloadSchemaVersion = WorkspaceArchiveV1.schemaVersion
                record.serverVersion = workspaceServerVersion
                record.updatedAt = latestUpdatedAt
            } else {
                context.insert(
                    WorkspaceRecord(
                        id: scopeID,
                        payload: payload,
                        sortOrder: existingWorkspaceCount,
                        updatedAt: latestUpdatedAt,
                        ownerUserID: ownerUserID,
                        serverVersion: workspaceServerVersion
                    )
                )
            }
        }

        return .merged(archive: archive, shouldDeleteWorkspace: shouldDeleteWorkspace)
    }

    /// Requires a fresh authorized server projection, not the locally overlaid
    /// archive. Stages only the exact restore artifact; the caller commits it
    /// with the archive, envelope receipt, and cursor in the usual transaction.
    private func stageRejectedLocationEchoRepair(_ payload: Data, scopeID: UUID) throws -> Bool {
        guard let ownerUserID else { return false }
        let candidates = try context.fetch(FetchDescriptor<PendingMutation>()).filter {
            !$0.isDeleted && $0.ownerUserID == ownerUserID && $0.scopeID == scopeID
                && $0.entityID == scopeID && $0.entityType == .event
                && $0.operation == .update && $0.state == .requiresAttention
                && $0.lastFailureCode == "EVENT_SCOPE_FORBIDDEN"
        }
        guard !candidates.isEmpty,
              let archive = try? codec.decode(WorkspaceArchiveV1.self, from: payload),
              archive.isScopedEvent == true, archive.mainEventID == scopeID,
              archive.mainEventLocation == nil,
              let canonical = try archive.syncEntities(using: codec)[.init(type: .event, id: scopeID)],
              let expected = try JSONSerialization.jsonObject(with: canonical) as? [String: Any],
              let emptyLocation = try JSONSerialization.jsonObject(with: codec.encode(EventLocation(address: ""))) as? NSDictionary
        else { return false }
        var repaired = false
        for mutation in candidates {
            guard var proposed = try? JSONSerialization.jsonObject(with: mutation.payload) as? [String: Any],
                  let location = proposed["eventLocation"] as? NSDictionary,
                  location.isEqual(emptyLocation) else { continue }
            proposed.removeValue(forKey: "eventLocation")
            // Compare raw JSON so unknown fields and genuine changes are never
            // silently discarded by decoding into today's model.
            guard NSDictionary(dictionary: proposed).isEqual(NSDictionary(dictionary: expected)) else { continue }
            context.delete(mutation)
            repaired = true
        }
        return repaired
    }

    /// Keep the local optimistic value visible while a todo mutation is still
    /// queued. Its original baseVersion remains unchanged so a concurrent
    /// server edit is surfaced as a CAS conflict instead of silently rebasing.
    private func overlayPendingTodoMutations(
        entityID: UUID,
        scopeID: UUID,
        on archive: inout WorkspaceArchiveV1
    ) throws {
        let mutations = try context.fetch(FetchDescriptor<PendingMutation>())
            .filter {
                $0.ownerUserID == ownerUserID
                    && $0.scopeID == scopeID
                    && $0.entityType == .todo
                    && $0.entityID == entityID
            }
            .sorted { $0.createdAt < $1.createdAt }
        for mutation in mutations {
            try archive.applyEntity(
                type: .todo,
                id: entityID,
                operation: mutation.operation,
                payload: mutation.payload,
                codec: codec
            )
        }
    }

    private func overlayPendingTodoMutations(
        scopeID: UUID,
        on archive: inout WorkspaceArchiveV1
    ) throws {
        let mutations = try context.fetch(FetchDescriptor<PendingMutation>())
            .filter {
                $0.ownerUserID == ownerUserID
                    && $0.scopeID == scopeID
                    && $0.entityType == .todo
            }
            .sorted { $0.createdAt < $1.createdAt }
        for mutation in mutations {
            try archive.applyEntity(
                type: .todo,
                id: mutation.entityID,
                operation: mutation.operation,
                payload: mutation.payload,
                codec: codec
            )
        }
    }

    private func discardWorkspaceMutations(scopeID: UUID) throws {
        for mutation in try context.fetch(FetchDescriptor<PendingMutation>())
        where mutation.ownerUserID == ownerUserID
            && mutation.scopeID == scopeID
            && mutation.entityType == .workspace {
            context.delete(mutation)
        }
    }
}
