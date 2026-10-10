import Foundation
import SwiftData

nonisolated struct SyncRetryPolicy: Sendable {
    var initialDelay: TimeInterval = 5
    var maximumDelay: TimeInterval = 60 * 30

    func nextAttemptDate(after attemptCount: Int, from date: Date) -> Date {
        let exponent = max(0, min(attemptCount - 1, 16))
        let delay = min(maximumDelay, initialDelay * pow(2, Double(exponent)))
        return date.addingTimeInterval(delay)
    }
}

protocol SyncOutboxStore: Sendable {
    func claimReadyMutations(
        scopeID: UUID,
        limit: Int,
        at date: Date,
        leaseDuration: TimeInterval
    ) async throws -> [PendingMutationSnapshot]

    func acknowledge(_ mutationIDs: Set<UUID>) async throws
    func retry(
        _ mutationIDs: Set<UUID>,
        failureCode: String,
        at date: Date,
        policy: SyncRetryPolicy
    ) async throws
    func requireAttention(_ mutationIDs: Set<UUID>, failureCode: String) async throws
}

@ModelActor
actor SwiftDataSyncStore: SyncOutboxStore {
    func claimReadyMutations(
        scopeID: UUID,
        limit: Int = 50,
        at date: Date = .now,
        leaseDuration: TimeInterval = 60
    ) throws -> [PendingMutationSnapshot] {
        var descriptor = FetchDescriptor<PendingMutation>(
            sortBy: [SortDescriptor(\.createdAt)]
        )
        descriptor.fetchLimit = max(limit * 4, limit)

        let candidates = try modelContext.fetch(descriptor)
        let ready = candidates
            .filter { mutation in
                guard mutation.scopeID == scopeID else { return false }

                switch mutation.state {
                case .pending:
                    return mutation.nextAttemptAt.map { $0 <= date } ?? true
                case .sending:
                    return mutation.leaseExpiresAt.map { $0 <= date } ?? true
                case .requiresAttention:
                    return false
                }
            }
            .prefix(limit)

        let leaseExpiration = date.addingTimeInterval(leaseDuration)
        ready.forEach { mutation in
            mutation.state = .sending
            mutation.leaseExpiresAt = leaseExpiration
        }
        try modelContext.save()

        return ready.map(PendingMutationSnapshot.init)
    }

    func acknowledge(_ mutationIDs: Set<UUID>) throws {
        guard !mutationIDs.isEmpty else { return }
        for mutation in try modelContext.fetch(FetchDescriptor<PendingMutation>())
        where mutationIDs.contains(mutation.id) {
            modelContext.delete(mutation)
        }
        try modelContext.save()
    }

    func retry(
        _ mutationIDs: Set<UUID>,
        failureCode: String,
        at date: Date = .now,
        policy: SyncRetryPolicy = .init()
    ) throws {
        guard !mutationIDs.isEmpty else { return }
        for mutation in try modelContext.fetch(FetchDescriptor<PendingMutation>())
        where mutationIDs.contains(mutation.id) {
            mutation.attemptCount += 1
            mutation.state = .pending
            mutation.leaseExpiresAt = nil
            mutation.lastFailureCode = failureCode
            mutation.nextAttemptAt = policy.nextAttemptDate(
                after: mutation.attemptCount,
                from: date
            )
        }
        try modelContext.save()
    }

    func requireAttention(_ mutationIDs: Set<UUID>, failureCode: String) throws {
        guard !mutationIDs.isEmpty else { return }
        for mutation in try modelContext.fetch(FetchDescriptor<PendingMutation>())
        where mutationIDs.contains(mutation.id) {
            mutation.state = .requiresAttention
            mutation.leaseExpiresAt = nil
            mutation.lastFailureCode = failureCode
        }
        try modelContext.save()
    }
}
