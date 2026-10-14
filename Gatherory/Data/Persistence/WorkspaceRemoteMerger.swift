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
            }
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
        let newChanges = page.changes.filter { !appliedIDs.contains($0.id) }
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
                        remoteArchive.preserveCollaborativeEntities(from: archive)
                    }
                    archive = remoteArchive
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
            }
            latestUpdatedAt = max(latestUpdatedAt, change.occurredAt)

            context.insert(
                AppliedSyncEnvelope(
                    id: change.id,
                    scopeID: scopeID,
                    ownerUserID: ownerUserID
                )
            )
        }

        if shouldDeleteWorkspace {
            if let record { context.delete(record) }
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
}
