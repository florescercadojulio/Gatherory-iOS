# Offline and PostgreSQL synchronization

Gatherory uses a local-first outbox/inbox design. SwiftData remains the UI's
source of truth, while the authenticated web API replicates independently
versioned planning records to PostgreSQL. A complete workspace snapshot remains
as a compatibility and web-companion materialized view. Losing connectivity
does not block editing: changes remain in the durable outbox and retry when the
app becomes active or another local edit is made.

## Invariants

1. The local database is the UI's source of truth.
2. A workspace edit and its `PendingMutation` are saved in one `ModelContext`
   transaction.
3. Mutation IDs are stable idempotency keys and survive retries and launches.
4. Delivery is at least once. PostgreSQL mutation receipts make duplicates
   safe.
5. Applying a remote change page and advancing its cursor is one local
   transaction.
6. Deletes are durable tombstones until the server acknowledges them.
7. Every local row and remote snapshot is scoped to the canonical Better Auth
   user ID.
8. A server-version conflict preserves the local edit for later resolution;
   it does not overwrite the visible workspace with the server snapshot.
9. Large media will use file-backed S3 uploads, separate from JSON sync.
10. A foreground run drains every ready outbox batch before pulling remote
    changes; the server's 50-mutation request limit cannot strand later rows.
11. Local workspace records, cursors, receipts, and leases are account scoped.
    The same shared workspace may be cached independently for two accounts on
    one device.

## Runtime flow

- `WorkspacePersistenceController` restores only the signed-in account's
  records, observes workspace edits, and writes a coalesced mutation.
- `WorkspaceCloudSyncController` bootstraps the account from the server and
  schedules foreground synchronization.
- `PostgresSyncTransport` sends the Keychain-backed Better Auth bearer token
  to `/api/sync/bootstrap`, `/api/sync/push`, and `/api/sync/pull`.
- `SwiftDataSyncStore` leases only the active account's outbox entries and
  records acknowledgement, retry, or attention state.
- `OfflineSyncCoordinator` drains ready mutations in server-sized batches,
  then applies cursor-based server changes.
- The web app stores the current compatibility snapshot, independently
  versioned child records, idempotency receipts, and an ordered change log in
  PostgreSQL.
- Pull-to-refresh is the explicit collaboration control. Opening/foregrounding
  the app and saving a local edit also synchronize automatically.

Events, ideas, participants, expenses, registry items, notes, and moments each
have an independent synchronization identity. This lets collaborators change
unrelated records without replacing one another's work. Same-record edits use
last-writer-wins for now; version fields preserve the path to a later review UI
without requiring sockets or real-time presence. Accepted native mutations are
transactionally projected into the canonical PostgreSQL workspace, event,
idea, participant, expense, registry, note, and moment tables. The compatibility
snapshot remains available while the web companion transitions to those
normalized records.

## Local development

Debug defaults to production-like account behavior and
`https://dev.gatherory.com`. Start `gatherory-web-app` with `pnpm dev`, expose
port 3003 through the named Cloudflare tunnel for that hostname, then run the
iOS app. The Simulator and physical devices use the same Better Auth origin,
so the normal scheme does not need launch arguments.

For a one-off endpoint test, `-AuthenticationBaseURL` remains available as a
temporary scheme override:

```text
-AuthenticationBaseURL
https://temporary-development-origin.example
```

If the stable development hostname changes, update `AUTH_BASE_URL` in
`Config/Debug.xcconfig`, update the web app's `BETTER_AUTH_URL`, and rebuild the
iOS app. Production changes belong in `Config/Release.xcconfig` and the
production authentication provider configuration.

The local PostgreSQL database must have the generated Drizzle migrations
applied with `pnpm db:migrate`.

Release verification and the physical-device persistence checklist live in
[`app-store-release.md`](app-store-release.md).

## Still to connect before full collaboration release

- Move cover and gallery bytes out of the JSON archive and use the existing
  `PendingMediaTransfer` records with presigned S3 uploads.
- Add background refresh and background media uploads after foreground and
  pull-to-refresh behavior has been exercised on device.
- Add conflict-resolution UI for mutations marked `requiresAttention`.
- Exercise organization membership and event-scoped participant authorization
  with two real production accounts before advertising collaboration broadly.
- Keep workspace-wide sync membership limited to explicit planning roles;
  never infer it from a guest or child-event invitation.
- Expose a small sync-status surface for retryable and attention states.
