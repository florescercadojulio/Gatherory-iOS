import Foundation

nonisolated enum SyncPushDisposition: String, Codable, Sendable {
    case applied
    case duplicate
    case conflict
    case rejected
}

nonisolated struct SyncPushResult: Codable, Sendable {
    let mutationID: UUID
    let disposition: SyncPushDisposition
    let serverVersion: Int?
    let failureCode: String?
}

nonisolated struct SyncPushResponse: Codable, Sendable {
    let results: [SyncPushResult]
}

nonisolated struct RemoteChangeEnvelope: Codable, Sendable {
    let id: UUID
    let scopeID: UUID
    /// Optional while older deployments roll forward. Missing means v1.
    var payloadSchemaVersion: Int? = nil
    let entityType: SyncEntityType
    let entityID: UUID
    let operation: SyncMutationOperation
    let payload: Data
    let serverVersion: Int
    let occurredAt: Date

    var effectivePayloadSchemaVersion: Int {
        payloadSchemaVersion ?? 1
    }
}

nonisolated struct SyncPullPage: Codable, Sendable {
    let changes: [RemoteChangeEnvelope]
    let nextCursor: String?
    let hasMore: Bool
}

nonisolated struct RemoteWorkspaceSnapshot: Codable, Sendable {
    let scopeID: UUID
    /// Optional while older deployments roll forward. Missing means v1.
    var payloadSchemaVersion: Int? = nil
    let payload: Data
    let serverVersion: Int
    let updatedAt: Date

    var effectivePayloadSchemaVersion: Int {
        payloadSchemaVersion ?? 1
    }
}

nonisolated struct RemoteEntitySnapshot: Codable, Sendable {
    let scopeID: UUID
    /// Optional while older deployments roll forward. Missing means v1.
    var payloadSchemaVersion: Int? = nil
    let entityType: SyncEntityType
    let entityID: UUID
    let payload: Data
    let serverVersion: Int
    let updatedAt: Date

    var effectivePayloadSchemaVersion: Int {
        payloadSchemaVersion ?? 1
    }
}

nonisolated struct SyncAccountState: Codable, Sendable {
    let hasCompletedOnboarding: Bool
}

nonisolated struct SyncBootstrapResponse: Codable, Sendable {
    /// Optional while older development deployments roll forward. A response
    /// without this field can still infer completion from existing snapshots.
    let account: SyncAccountState?
    let snapshots: [RemoteWorkspaceSnapshot]
    /// Optional while older deployments roll forward.
    var entities: [RemoteEntitySnapshot]? = nil

    var entitySnapshots: [RemoteEntitySnapshot] {
        entities ?? []
    }
}

protocol SyncTransport: Sendable {
    func push(_ mutations: [PendingMutationSnapshot]) async throws -> SyncPushResponse
    func pull(scopeID: UUID, after cursor: String?) async throws -> SyncPullPage
}

protocol WorkspaceSnapshotTransport: SyncTransport {
    func bootstrap() async throws -> SyncBootstrapResponse
}

/// Applying the page and advancing its cursor must be one local transaction.
/// A concrete implementation arrives when Gatherory's domain objects move to
/// SwiftData; keeping this contract separate prevents accidental partial pulls.
protocol RemoteChangeApplying: Sendable {
    func currentCursor(for scopeID: UUID) async throws -> String?
    func apply(_ page: SyncPullPage, to scopeID: UUID) async throws
}

nonisolated enum SyncTrigger: String, Sendable {
    case mutationCreated
    case appBecameActive
    case backgroundRefresh
    case pushHint
    case manual
}

nonisolated struct SyncRunSummary: Sendable {
    var pushed = 0
    var acknowledged = 0
    var requiresAttention = 0
    /// The first durable server rejection from this run. Keeping this on the
    /// summary lets the presentation layer distinguish a rejected mutation
    /// from a transient transport failure without exposing mutation payloads.
    var attentionFailureCode: String?
    var pulled = 0
    var completedAt: Date?
}
