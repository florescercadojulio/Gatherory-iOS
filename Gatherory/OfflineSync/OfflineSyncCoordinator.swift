import Foundation

/// Coordinates the durable local outbox with Gatherory's authenticated API.
actor OfflineSyncCoordinator {
    private let store: any SyncOutboxStore
    private let transport: any SyncTransport
    private let remoteApplier: any RemoteChangeApplying
    private let retryPolicy: SyncRetryPolicy
    private let batchSize: Int
    private let ownerUserID: String?

    init(
        store: any SyncOutboxStore,
        transport: any SyncTransport,
        remoteApplier: any RemoteChangeApplying,
        retryPolicy: SyncRetryPolicy = .init(),
        batchSize: Int = 50,
        ownerUserID: String? = nil
    ) {
        self.store = store
        self.transport = transport
        self.remoteApplier = remoteApplier
        self.retryPolicy = retryPolicy
        self.batchSize = batchSize
        self.ownerUserID = ownerUserID
    }

    func synchronize(
        scopeID: UUID,
        trigger: SyncTrigger = .manual,
        at date: Date = .now
    ) async throws -> SyncRunSummary {
        _ = trigger // Reserved for metrics and policy decisions when activated.
        var summary = SyncRunSummary()

        while true {
            let claimed = try await store.claimReadyMutations(
                scopeID: scopeID,
                ownerUserID: ownerUserID,
                limit: batchSize,
                at: date,
                leaseDuration: 60
            )
            guard !claimed.isEmpty else { break }
            summary.pushed += claimed.count

            do {
                let response = try await transport.push(claimed)
                let claimedIDs = Set(claimed.map(\.id))
                let batchResults = response.results.filter {
                    claimedIDs.contains($0.mutationID)
                }
                let acknowledgedResults = batchResults.filter { result in
                    switch result.disposition {
                    case .applied, .duplicate:
                        true
                    case .conflict, .rejected:
                        false
                    }
                }
                let acknowledgedIDs = Set(acknowledgedResults.map(\.mutationID))
                let attentionResults = batchResults.filter {
                    $0.disposition == .conflict || $0.disposition == .rejected
                }
                let attentionIDs = Set(attentionResults.map(\.mutationID))
                let unansweredIDs = claimedIDs.subtracting(acknowledgedIDs).subtracting(attentionIDs)

                try await store.acknowledge(acknowledgedResults)
                summary.acknowledged += acknowledgedIDs.count

                if !attentionIDs.isEmpty {
                    let code = attentionResults.first?.failureCode ?? "server_requires_attention"
                    try await store.requireAttention(attentionIDs, failureCode: code)
                    summary.requiresAttention += attentionIDs.count
                    summary.attentionFailureCode = code
                }

                if !unansweredIDs.isEmpty {
                    try await store.retry(
                        unansweredIDs,
                        failureCode: "missing_server_result",
                        at: date,
                        policy: retryPolicy
                    )
                }

                // Preserve the local version for conflict resolution. Pulling
                // the server snapshot now would make the user's pending edit
                // disappear while its outbox entry still requires attention.
                if !attentionIDs.isEmpty {
                    summary.completedAt = .now
                    return summary
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
