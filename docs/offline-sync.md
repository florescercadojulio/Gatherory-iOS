# Offline synchronization foundation

Gatherory's offline layer follows a local-first outbox/inbox design. This
folder describes the code in `Gatherory/OfflineSync`; the feature is scaffolded
but intentionally not connected to the running application yet.

## Invariants

1. The local database is the UI's source of truth.
2. A domain edit and its `PendingMutation` are inserted into the same
   `ModelContext` and saved once.
3. Mutation IDs are stable idempotency keys and survive retries and launches.
4. Delivery is at least once. The server must safely accept duplicates.
5. Applying a remote change page and advancing its cursor is one local
   transaction.
6. Deletes remain as tombstones until the server acknowledges them.
7. Large media uses file-backed background uploads, separate from JSON changes.

## Current pieces

- `PendingMutation`: durable client outbox entry.
- `SyncCheckpoint`: cursor per workspace.
- `AppliedSyncEnvelope`: inbox receipt for deduplicating remote changes.
- `PendingMediaTransfer`: future file upload state.
- `SwiftDataSyncStore`: leases batches and handles acknowledgement, retry, and
  attention states.
- `SyncTransport`: protocol for the future Gatherory API client.
- `RemoteChangeApplying`: transaction boundary for pulled server changes.
- `OfflineSyncCoordinator`: dormant push/pull orchestration.

## Deliberately not connected

- No `ModelContainer` is installed in `GatheroryApp`.
- Existing `WeddingWorkspace` and `WorkspaceLibrary` behavior is unchanged.
- No network transport is implemented.
- No background task is registered.
- No UI displays synchronization state.

## Activation sequence

1. Convert the centralized domain records to SwiftData models.
2. Put domain writes behind repositories.
3. In each repository write, insert the domain change and call
   `SyncOutbox.enqueue(_:in:)` before one `ModelContext.save()`.
4. Implement the PostgreSQL mutation inbox and cursor-based changes endpoint.
5. Implement `SyncTransport` and `RemoteChangeApplying`.
6. Install a model container and construct `OfflineSyncCoordinator`.
7. Trigger foreground sync first; add background refresh and media transfers
   after foreground behavior is reliable.
