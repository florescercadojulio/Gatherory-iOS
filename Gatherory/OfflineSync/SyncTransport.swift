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
    let entityType: SyncEntityType
    let entityID: UUID
    let operation: SyncMutationOperation
    let payload: Data
    let serverVersion: Int
    let occurredAt: Date
}

nonisolated struct SyncPullPage: Codable, Sendable {
    let changes: [RemoteChangeEnvelope]
    let nextCursor: String?
    let hasMore: Bool
}

protocol SyncTransport: Sendable {
    func push(_ mutations: [PendingMutationSnapshot]) async throws -> SyncPushResponse
    func pull(scopeID: UUID, after cursor: String?) async throws -> SyncPullPage
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
    var pulled = 0
    var completedAt: Date?
}
