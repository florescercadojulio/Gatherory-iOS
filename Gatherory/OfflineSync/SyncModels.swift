import Foundation
import SwiftData

/// A stable backend-facing name for a synchronized resource.
///
/// This is intentionally open-ended rather than an enum so adding a resource
/// doesn't require migrating every locally queued mutation.
nonisolated struct SyncEntityType: RawRepresentable, Codable, Hashable, Sendable {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    static let workspace = Self(rawValue: "workspace")
    static let event = Self(rawValue: "event")
    static let idea = Self(rawValue: "idea")
    static let ideaResponse = Self(rawValue: "idea_response")
    static let participant = Self(rawValue: "participant")
    static let eventParticipation = Self(rawValue: "event_participation")
    static let attendance = Self(rawValue: "attendance")
    static let expense = Self(rawValue: "expense")
    static let registryItem = Self(rawValue: "registry_item")
    static let note = Self(rawValue: "note")
    static let moment = Self(rawValue: "moment")
    static let todo = Self(rawValue: "todo")

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        rawValue = try container.decode(String.self)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

nonisolated enum SyncMutationOperation: String, Codable, Sendable {
    case create
    case update
    case delete
}

nonisolated enum SyncMutationState: String, Codable, Sendable {
    case pending
    case sending
    case requiresAttention
}

/// One durable action that the server has not acknowledged yet.
///
/// The workspace persistence boundary inserts this model using the same
/// `ModelContext` in which it changes the corresponding archive.
@Model
final class PendingMutation {
    @Attribute(.unique) var id: UUID
    var scopeID: UUID
    var entityTypeValue: String
    var entityID: UUID
    var operationValue: String
    var payload: Data
    var baseVersion: Int?
    var createdAt: Date
    var attemptCount: Int
    var nextAttemptAt: Date?
    var stateValue: String
    var leaseExpiresAt: Date?
    var lastFailureCode: String?
    var ownerUserID: String?

    init(
        id: UUID = UUID(),
        scopeID: UUID,
        entityType: SyncEntityType,
        entityID: UUID,
        operation: SyncMutationOperation,
        payload: Data,
        baseVersion: Int? = nil,
        createdAt: Date = .now,
        ownerUserID: String? = nil
    ) {
        self.id = id
        self.scopeID = scopeID
        self.entityTypeValue = entityType.rawValue
        self.entityID = entityID
        self.operationValue = operation.rawValue
        self.payload = payload
        self.baseVersion = baseVersion
        self.createdAt = createdAt
        self.attemptCount = 0
        self.stateValue = SyncMutationState.pending.rawValue
        self.ownerUserID = ownerUserID
    }

    var entityType: SyncEntityType {
        get { SyncEntityType(rawValue: entityTypeValue) }
        set { entityTypeValue = newValue.rawValue }
    }

    var operation: SyncMutationOperation {
        get { SyncMutationOperation(rawValue: operationValue) ?? .update }
        set { operationValue = newValue.rawValue }
    }

    var state: SyncMutationState {
        get { SyncMutationState(rawValue: stateValue) ?? .pending }
        set { stateValue = newValue.rawValue }
    }
}

/// The server cursor for one independently synchronized workspace.
@Model
final class SyncCheckpoint {
    /// Scoped by both the account and workspace. Collaborators can share the
    /// same remote scope while keeping independent local cursors.
    var scopeID: UUID
    var cursor: String?
    var lastSuccessfulSyncAt: Date?
    var ownerUserID: String?

    init(
        scopeID: UUID,
        cursor: String? = nil,
        lastSuccessfulSyncAt: Date? = nil,
        ownerUserID: String? = nil
    ) {
        self.scopeID = scopeID
        self.cursor = cursor
        self.lastSuccessfulSyncAt = lastSuccessfulSyncAt
        self.ownerUserID = ownerUserID
    }
}

/// A bounded receipt used to make application of incoming envelopes idempotent.
@Model
final class AppliedSyncEnvelope {
    /// The same server change may be applied once for each local account.
    var id: UUID
    var scopeID: UUID
    var appliedAt: Date
    var ownerUserID: String?

    init(id: UUID, scopeID: UUID, appliedAt: Date = .now, ownerUserID: String? = nil) {
        self.id = id
        self.scopeID = scopeID
        self.appliedAt = appliedAt
        self.ownerUserID = ownerUserID
    }
}

nonisolated enum MediaTransferState: String, Codable, Sendable {
    case pending
    case uploading
    case requiresAttention
}

/// File-backed media is tracked independently from small JSON mutations so a
/// future background `URLSession` can upload it while the app is suspended.
@Model
final class PendingMediaTransfer {
    @Attribute(.unique) var id: UUID
    var scopeID: UUID
    var entityID: UUID
    var localFilePath: String
    var contentType: String
    var stateValue: String
    var attemptCount: Int
    var nextAttemptAt: Date?
    var remoteAssetID: String?
    var createdAt: Date
    var ownerUserID: String?

    init(
        id: UUID = UUID(),
        scopeID: UUID,
        entityID: UUID,
        localFileURL: URL,
        contentType: String,
        createdAt: Date = .now,
        ownerUserID: String? = nil
    ) {
        self.id = id
        self.scopeID = scopeID
        self.entityID = entityID
        self.localFilePath = localFileURL.path
        self.contentType = contentType
        self.stateValue = MediaTransferState.pending.rawValue
        self.attemptCount = 0
        self.createdAt = createdAt
        self.ownerUserID = ownerUserID
    }

    var state: MediaTransferState {
        get { MediaTransferState(rawValue: stateValue) ?? .pending }
        set { stateValue = newValue.rawValue }
    }
}

nonisolated struct PendingMediaTransferSnapshot: Sendable {
    let id: UUID
    let scopeID: UUID
    let entityID: UUID
    let localFileURL: URL
    let contentType: String
    let attemptCount: Int
}

nonisolated struct SyncMutationDraft: Sendable {
    let id: UUID
    let scopeID: UUID
    let entityType: SyncEntityType
    let entityID: UUID
    let operation: SyncMutationOperation
    let payload: Data
    let baseVersion: Int?
    let createdAt: Date

    init(
        id: UUID = UUID(),
        scopeID: UUID,
        entityType: SyncEntityType,
        entityID: UUID,
        operation: SyncMutationOperation,
        payload: Data,
        baseVersion: Int? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.scopeID = scopeID
        self.entityType = entityType
        self.entityID = entityID
        self.operation = operation
        self.payload = payload
        self.baseVersion = baseVersion
        self.createdAt = createdAt
    }

    init<Payload: Encodable & Sendable>(
        id: UUID = UUID(),
        scopeID: UUID,
        entityType: SyncEntityType,
        entityID: UUID,
        operation: SyncMutationOperation,
        payload: Payload,
        baseVersion: Int? = nil,
        createdAt: Date = .now,
        encoder: JSONEncoder = JSONEncoder()
    ) throws {
        self.init(
            id: id,
            scopeID: scopeID,
            entityType: entityType,
            entityID: entityID,
            operation: operation,
            payload: try encoder.encode(payload),
            baseVersion: baseVersion,
            createdAt: createdAt
        )
    }
}

nonisolated struct PendingMutationSnapshot: Codable, Hashable, Sendable {
    let id: UUID
    let scopeID: UUID
    let payloadSchemaVersion: Int
    let entityType: SyncEntityType
    let entityID: UUID
    let operation: SyncMutationOperation
    let payload: Data
    let baseVersion: Int?
    let createdAt: Date
    let attemptCount: Int

    init(_ mutation: PendingMutation) {
        id = mutation.id
        scopeID = mutation.scopeID
        payloadSchemaVersion = SyncPayloadContract.currentVersion
        entityType = mutation.entityType
        entityID = mutation.entityID
        operation = mutation.operation
        payload = mutation.payload
        baseVersion = mutation.baseVersion
        createdAt = mutation.createdAt
        attemptCount = mutation.attemptCount
    }
}

/// Version of the entity payload inside the replication envelope. This is
/// independent from the server's optimistic-concurrency version.
nonisolated enum SyncPayloadContract {
    static let currentVersion = 1
}

/// Registers a mutation without saving the context. The persistence boundary
/// owns the save so its model update and outbox entry are atomic.
enum SyncOutbox {
    @discardableResult
    static func enqueue(_ draft: SyncMutationDraft, in context: ModelContext) -> PendingMutation {
        enqueue(draft, ownerUserID: nil, in: context)
    }

    @discardableResult
    static func enqueue(
        _ draft: SyncMutationDraft,
        ownerUserID: String?,
        in context: ModelContext
    ) -> PendingMutation {
        let mutation = PendingMutation(
            id: draft.id,
            scopeID: draft.scopeID,
            entityType: draft.entityType,
            entityID: draft.entityID,
            operation: draft.operation,
            payload: draft.payload,
            baseVersion: draft.baseVersion,
            createdAt: draft.createdAt,
            ownerUserID: ownerUserID
        )
        context.insert(mutation)
        return mutation
    }
}

enum OfflineSyncSchema {
    static let schema = Schema([
        WorkspaceRecord.self,
        LocalGuestWorkspaceImportReceipt.self,
        RemoteEntityVersionRecord.self,
        PendingMutation.self,
        SyncCheckpoint.self,
        AppliedSyncEnvelope.self,
        PendingMediaTransfer.self
    ], version: .init(1, 0, 0))
}
