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
        ownerUserID: String?,
        limit: Int,
        at date: Date,
        leaseDuration: TimeInterval
    ) async throws -> [PendingMutationSnapshot]

    func acknowledge(_ results: [SyncPushResult]) async throws
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
        ownerUserID: String?,
        limit: Int = 50,
        at date: Date = .now,
        leaseDuration: TimeInterval = 60
    ) throws -> [PendingMutationSnapshot] {
        let descriptor = FetchDescriptor<PendingMutation>(
            predicate: #Predicate { mutation in
                mutation.scopeID == scopeID
            },
            sortBy: [SortDescriptor(\.createdAt)]
        )

        let candidates = try modelContext.fetch(descriptor)
        let hasBudgetConflict = candidates.contains {
            $0.ownerUserID == ownerUserID
                && $0.entityType == .budgetTransfer
                && $0.state == .requiresAttention
        }
        let deferredBudgetMutationID = candidates
            .filter { mutation in
                guard mutation.ownerUserID == ownerUserID,
                      mutation.entityType == .budgetTransfer else { return false }
                switch mutation.state {
                case .pending:
                    return mutation.nextAttemptAt.map { $0 > date } ?? false
                case .sending:
                    return mutation.leaseExpiresAt.map { $0 > date } ?? false
                case .requiresAttention:
                    return false
                }
            }
            .min(by: { $0.createdAt < $1.createdAt })?.id
        let ownedCandidates = candidates
            .filter { mutation in
                guard mutation.ownerUserID == ownerUserID else { return false }
                if mutation.entityType == .budgetTransfer && hasBudgetConflict { return false }
                if mutation.entityType == .budgetTransfer,
                   let deferredBudgetMutationID,
                   mutation.id != deferredBudgetMutationID {
                    return false
                }

                switch mutation.state {
                case .pending:
                    return mutation.nextAttemptAt.map { $0 <= date } ?? true
                case .sending:
                    return mutation.leaseExpiresAt.map { $0 <= date } ?? true
                case .requiresAttention:
                    return false
                }
            }
        // Keep all ready phases in one batch, but do not cross a phase whose
        // earlier work is awaiting retry, an active lease, or user review.
        let blockedPhase = candidates
            .filter { mutation in
                guard mutation.ownerUserID == ownerUserID else { return false }
                switch mutation.state {
                case .requiresAttention:
                    return true
                case .pending:
                    return mutation.nextAttemptAt.map { $0 > date } ?? false
                case .sending:
                    return mutation.leaseExpiresAt.map { $0 > date } ?? false
                }
            }
            .map(syncDependencyPriority)
            .min()
        let orderedCandidates = ownedCandidates
            .filter { mutation in
                guard let blockedPhase else { return true }
                return syncDependencyPriority(mutation) < blockedPhase
            }
            .sorted { left, right in
                let leftPriority = syncDependencyPriority(left)
                let rightPriority = syncDependencyPriority(right)
                if leftPriority != rightPriority {
                    return leftPriority < rightPriority
                }
                return left.createdAt < right.createdAt
            }
        var hasSelectedBudgetCommand = false
        let ready = orderedCandidates.filter { mutation in
            guard mutation.entityType == .budgetTransfer else { return true }
            guard !hasSelectedBudgetCommand else { return false }
            hasSelectedBudgetCommand = true
            return true
        }.prefix(limit)

        let leaseExpiration = date.addingTimeInterval(leaseDuration)
        ready.forEach { mutation in
            mutation.state = .sending
            mutation.leaseExpiresAt = leaseExpiration
        }
        try modelContext.save()

        return ready.map(PendingMutationSnapshot.init)
    }

    func acknowledge(_ results: [SyncPushResult]) throws {
        guard !results.isEmpty else { return }
        let resultsByID = Dictionary(uniqueKeysWithValues: results.map { ($0.mutationID, $0) })
        for mutation in try modelContext.fetch(FetchDescriptor<PendingMutation>())
        where resultsByID[mutation.id] != nil {
            let result = resultsByID[mutation.id]
            let scopeID = mutation.scopeID
            if mutation.entityType == .workspace,
               let serverVersion = result?.serverVersion,
               let record = try modelContext.fetch(
                   FetchDescriptor<WorkspaceRecord>(
                       predicate: #Predicate { $0.id == scopeID }
                   )
               ).first(where: { $0.ownerUserID == mutation.ownerUserID }) {
                record.serverVersion = max(record.serverVersion, serverVersion)
            }
            if mutation.entityType == .budgetTransfer,
               let workspaceServerVersion = result?.workspaceServerVersion,
               let record = try modelContext.fetch(
                   FetchDescriptor<WorkspaceRecord>(
                       predicate: #Predicate { $0.id == scopeID }
                   )
               ).first(where: { $0.ownerUserID == mutation.ownerUserID }) {
                record.serverVersion = max(record.serverVersion, workspaceServerVersion)
            }
            if mutation.entityType == .budgetTransfer,
               let serverVersion = result?.serverVersion {
                try RemoteEntityVersionRecord.upsert(
                    in: modelContext, scopeID: mutation.scopeID,
                    entityType: .budgetTransfer, entityID: mutation.scopeID,
                    serverVersion: serverVersion, ownerUserID: mutation.ownerUserID
                )
                for followUp in try modelContext.fetch(FetchDescriptor<PendingMutation>())
                where followUp.id != mutation.id
                    && followUp.scopeID == mutation.scopeID
                    && followUp.entityType == .budgetTransfer
                    && followUp.ownerUserID == mutation.ownerUserID
                    && followUp.state == .pending {
                    if var payload = try? JSONDecoder().decode(
                        ReplaceBudgetMutationPayload.self, from: followUp.payload
                    ) {
                        payload.expectedBudgetVersion = serverVersion
                        followUp.payload = try JSONEncoder().encode(payload)
                        followUp.baseVersion = serverVersion
                    }
                }
            }
            if mutation.entityType == .todo, let serverVersion = result?.serverVersion {
                try RemoteEntityVersionRecord.upsert(
                    in: modelContext,
                    scopeID: mutation.scopeID,
                    entityType: .todo,
                    entityID: mutation.entityID,
                    serverVersion: serverVersion,
                    ownerUserID: mutation.ownerUserID
                )
                for followUp in try modelContext.fetch(FetchDescriptor<PendingMutation>())
                where followUp.id != mutation.id
                    && followUp.scopeID == mutation.scopeID
                    && followUp.entityType == .todo
                    && followUp.entityID == mutation.entityID
                    && followUp.ownerUserID == mutation.ownerUserID
                    && followUp.state == .pending
                    && followUp.operation != .create {
                    followUp.baseVersion = serverVersion
                }
            }
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
        let mutations = try modelContext.fetch(FetchDescriptor<PendingMutation>())
        let conflictedBudgetScopes = mutations.filter {
            mutationIDs.contains($0.id) && $0.entityType == .budgetTransfer
        }.map { ($0.scopeID, $0.ownerUserID) }
        for mutation in mutations
        where mutationIDs.contains(mutation.id) {
            mutation.state = .requiresAttention
            mutation.leaseExpiresAt = nil
            mutation.lastFailureCode = failureCode
        }
        for (scopeID, ownerUserID) in conflictedBudgetScopes {
            for followUp in mutations where followUp.scopeID == scopeID
                && followUp.ownerUserID == ownerUserID
                && followUp.entityType == .budgetTransfer
                && followUp.state == .pending {
                followUp.state = .requiresAttention
                followUp.leaseExpiresAt = nil
                followUp.lastFailureCode = "budget_conflict_review_required"
            }
        }
        try modelContext.save()
    }
}

/// Canonical records have foreign-key dependencies. This ordering makes a
/// freshly repaired/offline workspace deterministic even though its local
/// entity map is a dictionary.
///
/// Keep this outside the model actor: it is pure value logic and must remain
/// usable while the actor sorts a collection.
private nonisolated func syncDependencyPriority(_ mutation: PendingMutation) -> Int {
    syncDependencyPriority(for: mutation.entityType.rawValue, operation: mutation.operation)
}

private nonisolated func syncDependencyPriority(
    for rawValue: String,
    operation: SyncMutationOperation
) -> Int {
    if rawValue == "workspace", operation == .delete { return 9 }
    if rawValue == "budget_transfer" { return 7 }
    if rawValue == "event", operation == .delete { return 6 }
    if operation == .delete { return 5 }
    // SyncEntityType is deliberately open-ended, so future entity names sort
    // after the records whose dependencies we know today.
    return switch rawValue {
    case "workspace":
        0
    case "participant":
        1
    case "event":
        2
    case "event_participation":
        3
    case "idea", "registry_item", "expense", "note", "moment", "attendance", "todo":
        4
    default:
        5
    }
}
