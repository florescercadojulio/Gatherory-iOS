# Workspace boundaries

Archive/budget, outbox/remote-merge, and media-bookkeeping extractions: October 14, 2026.
These are structural changes, not a new
persistence format, synchronization policy, or state-management framework.

## Observable state remains in PlanningWorkspace

`Gatherory/App/PlanningWorkspace.swift` remains the feature-facing observable
model. Its properties, public commands, and synchronous mutation behavior are
unchanged. Screens continue calling methods such as `transferBudget`,
`allocateInitialBudget`, and `updateWorkspaceBudgetCap`.

`Gatherory/Models/WorkspaceBudgetRules.swift` contains stateless calculations
and validation for currency normalization, initial allocations, cap changes,
free-pool balances, initial funding, transfers, and editor budget opt-in/out.
It returns values for the workspace to apply; it does not retain a second copy
of state, reference a view, perform I/O, or save anything.

The workspace still resolves event identities and account availability, rejects
same-account transfers, and applies changes to the existing observable fields.
Cross-domain actions such as approving an event idea still coordinate the idea,
scheduled event, participation, and expense through their existing methods.
An event editor still cannot invent an allocation by changing its budget field.

## Archive representation is separate from storage orchestration

The persistence directory now separates these responsibilities:

| File | Responsibility |
| --- | --- |
| `WorkspaceArchiveV1.swift` | The existing version-1 Codable representation and conversion to/from the observable workspace, including legacy optional-field defaults. |
| `WorkspaceArchiveV1+Sync.swift` | Metadata-only sync projections, independently synchronized entity payloads, and existing remote-entity/media merge rules. |
| `WorkspaceArchiveCodec.swift` | The concrete JSON encoder/decoder configuration shared by archives and embedded entity payloads. |
| `WorkspaceOutboxWriter.swift` | Stages ordinary workspace/entity outbox coalescing and deletion in the caller's context; never saves. |
| `WorkspaceRemoteMerger.swift` | Stages bootstrap snapshots and pull-page records/receipts, preserving existing entity and media merge rules; never saves or mutates the live library. |
| `WorkspaceMediaBookkeeper.swift` | File-backed transfer preparation, queries, state changes, legacy payload sanitization, and account/scope cleanup; stages database changes without saving. |
| `WorkspacePersistence.swift` | SwiftData record definition and the controller that owns observation, account scoping, local-record writes, save/rollback boundaries, remote checkpoints/publication, and scope repair orchestration. |

The codec retains sorted JSON keys, Foundation's default reference-date encoding,
and default Data/base64 encoding. The outer HTTP sync envelopes have their own
ISO-8601 transport encoding; these two formats must not be conflated.

Local archives retain image bytes and idea responses. Workspace sync projections
strip image bytes and omit idea responses; responses are emitted as independent
entities. Existing media asset IDs and matching local cached image bytes retain
their previous merge behavior. No archive version or SwiftData schema changed.

## Transaction and lifecycle ownership did not move

The extracted helpers do not create a ModelContext, save records, schedule tasks,
or send network requests. The outbox writer, remote merger, and media bookkeeper borrow the
controller's existing context and codec. Each is constructed for the current
operation with the current account ID; neither retains an account across
activation. The persistence controller still:

- Observes persisted fields through archive construction and debounces ordinary
  edits for 450 ms; explicit action/account-transition flushes remain available.
- Saves workspace records and their coalesced outbox entries together, then
  notifies sync after the save succeeds. Existing rollback/error handling stays
  at the same boundary.
- Preserves stable mutation IDs and pending/leased/attention distinctions.
- Applies remote records, processed-envelope receipts, and the cursor in the
  same save before publishing the remote graph to the library.
- Suppresses outgoing echoes from remote graph updates while continuing to
  observe subsequent local edits.
- Preserves account filters, account-switch cancellation, pending work, deletion,
  and media-file ordering.

`WorkspaceCloudSyncController`, `OfflineSyncCoordinator`, and the transports have
not been refactored in this step. There is no new actor hop or asynchronous gap
inside a workspace command or persistence write.

### Staging is not a transaction boundary

The outbox writer receives the same account-filtered pending-mutation snapshot
used before extraction. It updates only the newest pending entry, preserves
unsent create identities, and leaves leased/attention entries intact. The
controller stages local records alongside these mutations, saves once, and then
notifies sync. Its local save failure still rolls back and sets `lastError`.

The remote merger returns bootstrap workspaces or a page result. Empty/duplicate
pages return `checkpointOnly`; the controller advances the cursor without
replacing the graph or suppressing the next local edit. Other pages stage records
and receipts, then the controller saves them with the cursor before publishing.
Bootstrap still skips pending scopes and saves once before publishing its batch.

Remote errors retain their existing policy: the throwing remote methods do not
introduce a rollback. A failed batch does not publish or save its prefix, but
staged context changes may remain. This extraction does not change recovery
policy or claim to add rollback semantics to remote application.

### Media files and database rows retain their existing ordering

The media bookkeeper borrows the same context and codec and is created with the
current account for each operation. It prepares files/transfer rows, sanitizes
legacy image-bearing mutations, queries ready transfers, stages upload/failure/
completion transitions, and removes account/scope media. The controller retains
all original saves: guarded saves after preparation/sanitization, saves after
found-ID transitions, and the shared lifecycle saves for final retry, account
purge, and scope repair. Unknown or other-account transfer IDs do not trigger a
save. No new notifications or rollback handling were added.

File writes remain atomic and happen before row insertion/update; removals remain
best-effort and happen before row deletion/save. These are not a cross-filesystem
transaction: a later failure or SwiftData rollback does not undo earlier file
effects. Tests preserve this existing behavior rather than introducing a new
recovery policy. Transfer IDs, paths, content sniffing, retry delays, attention
states, and ready-query filtering are unchanged. Upload/download orchestration
and archive media-merge rules remain in their existing owners.

## Regression coverage

- `WorkspaceBudgetRulesTests`: isolated rules and feature-facing budget behavior.
- `WorkspaceArchiveCodecTests`: encoding compatibility, legacy decoding,
  metadata-only projections, independent response payloads, and media merges.
- `WorkspaceExtractionRegressionTests`: public budget commands still trigger
  debounced saves; fresh database contexts see archives and outbox entries before
  sync notification; rejected commands leave bytes/envelopes unchanged; remote
  pages update receipts/cursors without echoes or breaking later observation.
- `WorkspaceOutboxWriterTests`: stage-only writes, rollback, stable coalescing,
  retry state, and workspace/child tombstones.
- `WorkspaceRemoteMergerTests`: stage-only remote writes, receipt/account
  filtering, ordered changes, and unsupported payloads.
- `WorkspaceSyncBoundaryTests`: failed local saves roll back records/outbox
  edits without notification; failed remote batches do not partially commit or
  publish; account switching scopes both helpers, receipts, and checkpoints.
- `WorkspaceMediaBookkeepingTests`: controller-level file reuse/pruning, format
  detection, durable state changes, account isolation, backoff, and sanitization.
- `WorkspaceMediaStagingTests`: no premature database saves, file-operation
  ordering on failure/rollback, scoped cleanup, queries, and final-retry states.
- Existing domain, account-isolation, offline-sync, transport, and UI tests remain
  the integration safety net. See [verification commands](testing-verification.md).

### Verification results

The archive/codec and budget-rule stage below is historical. The subsequent
outbox/remote-merge stage runs native tests only; UI tests are explicitly skipped
at the user's request. See the latest record in [iOS verification](testing-verification.md).

On October 14, 2026, using Xcode 27.0 and the iPhone 18 Pro/iOS 27.0 simulator:

- Pre-extraction baseline (`09eaf9f`): all 219 native unit tests passed.
- Extracted implementation: all 241 native unit tests passed, including 22 new
  archive, budget, and integration regression tests.
- Functional UI suite: seven tests passed. `testDecidePrimerPracticeAndLayout`
  failed at line 271: an upward swipe left the previous "Not for you" response
  instead of showing "Undecided". A targeted rerun reproduced the failure.
- The identical UI assertion also failed in a clean temporary checkout of
  `09eaf9f`, with no extraction changes. This is an existing gesture/UI-test
  issue, not evidence of a regression introduced by this extraction. No UI
  assertions were weakened or skipped to hide it. Its cause remains a separate
  follow-up; the overall functional UI suite is not green.
- The launch-performance benchmark was intentionally excluded. No live backend,
  provider, database migration, or physical-device checks were performed.

Source comparison also confirmed that the archive representation moved unchanged;
sync helper changes were limited to codec substitution and module visibility;
controller changes were limited to replacing its JSON encoder/decoder with the
codec. Existing save/rollback, account filters, and coalescing code did not change.

### Outbox/remote-merge verification results

- Baseline after archive/budget extraction: all 241 native unit tests passed.
- After outbox/remote-merge extraction: all **265 native unit tests passed**
  (306 executions including parameterized cases), with zero failures or skips
  in the selected unit target. This adds 11 outbox, nine remote-merger, and four
  controller-boundary tests.
- UI tests were not run, as requested. No claim about the historical UI issue
  above is changed by this native-only result.
- Source comparison confirmed coalescing and bootstrap/page staging logic is
  unchanged apart from visibility and owner/count parameter substitutions.
  Observation, local save/rollback, checkpoint saving, scope repair, and media
  methods remain unchanged. No schema or transport contract changed.

### Media-bookkeeping verification results

- Pre-extraction baseline: all 265 native unit tests passed.
- After extraction: all **276 native unit tests passed** (321 executions including
  parameterized cases), with zero failures or skips in the native target.
- Eleven new tests cover media staging and controller behavior, including
  filesystem effects before failed writes/rollback, MIME/extension compatibility,
  stable transfer IDs, scoped cleanup, retries, account isolation, and legacy
  mutation sanitization. UI tests were not run, as requested.
- Source comparison confirmed all moved preparation, sanitization, query,
  transition, and file-format methods match the originals after owner/name and
  save-return substitutions. The controller retains the original save guards and
  lifecycle ordering. No transport or schema changes were made.

## Stopping point

Archive/codec, budget rules, ordinary outbox coalescing, remote-merge staging,
and media bookkeeping have been extracted. Session-state ownership, access
policies, idea reconciliation, observation scheduling, transaction orchestration,
and scope repair remain in their existing owners. Scope repair deliberately
keeps its distinct fresh-ID rebuild and save boundary rather than going through
ordinary coalescing. Sync coordination, transport, and lease/retry scheduling
remain unchanged.
Do not infer that the rest of the proposed refactor is implemented. Future
extractions should keep the current public facade and transaction boundaries
until separate changes are deliberately designed and tested.
