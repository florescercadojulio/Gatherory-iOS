import Foundation

/// A dormant orchestration layer for future backend synchronization.
///
/// Nothing constructs this actor yet, so adding it has no runtime behavior.
actor OfflineSyncCoordinator {
    private let store: any SyncOutboxStore
    private let transport: any SyncTransport
    private let remoteApplier: any RemoteChangeApplying
    private let retryPolicy: SyncRetryPolicy
    private let batchSize: Int

    init(
        store: any SyncOutboxStore,
        transport: any SyncTransport,
        remoteApplier: any RemoteChangeApplying,
        retryPolicy: SyncRetryPolicy = .init(),
        batchSize: Int = 50
    ) {
        self.store = store
        self.transport = transport
        self.remoteApplier = remoteApplier
        self.retryPolicy = retryPolicy
        self.batchSize = batchSize
    }

    func synchronize(
        scopeID: UUID,
        trigger: SyncTrigger = .manual,
        at date: Date = .now
    ) async throws -> SyncRunSummary {
        _ = trigger // Reserved for metrics and policy decisions when activated.
        var summary = SyncRunSummary()

        let claimed = try await store.claimReadyMutations(
            scopeID: scopeID,
            limit: batchSize,
            at: date,
            leaseDuration: 60
        )
        summary.pushed = claimed.count

        if !claimed.isEmpty {
            do {
                let response = try await transport.push(claimed)
                let claimedIDs = Set(claimed.map(\.id))
                let acknowledgedIDs = Set(
                    response.results.compactMap { result in
                        switch result.disposition {
                        case .applied, .duplicate:
                            result.mutationID
                        case .conflict, .rejected:
                            nil
                        }
                    }
                )
                let attentionResults = response.results.filter {
                    $0.disposition == .conflict || $0.disposition == .rejected
                }
                let attentionIDs = Set(attentionResults.map(\.mutationID))
                let unansweredIDs = claimedIDs.subtracting(acknowledgedIDs).subtracting(attentionIDs)

                try await store.acknowledge(acknowledgedIDs)
                summary.acknowledged = acknowledgedIDs.count

                if !attentionIDs.isEmpty {
                    let code = attentionResults.first?.failureCode ?? "server_requires_attention"
                    try await store.requireAttention(attentionIDs, failureCode: code)
                    summary.requiresAttention = attentionIDs.count
                }

                if !unansweredIDs.isEmpty {
                    try await store.retry(
                        unansweredIDs,
                        failureCode: "missing_server_result",
                        at: date,
                        policy: retryPolicy
                    )
                }
            } catch {
                try await store.retry(
                    Set(claimed.map(\.id)),
                    failureCode: "transport_failure",
                    at: date,
                    policy: retryPolicy
                )
                throw error
            }
        }

        var cursor = try await remoteApplier.currentCursor(for: scopeID)
        repeat {
            let page = try await transport.pull(scopeID: scopeID, after: cursor)
            try await remoteApplier.apply(page, to: scopeID)
            summary.pulled += page.changes.count
            cursor = page.nextCursor
            if !page.hasMore { break }
        } while true

        summary.completedAt = .now
        return summary
    }
}
