# Core gathering recovery audit — 2026-11-04

Scope: native core event planning, offline sync and recovery, media transfer and albums, event invitations/deletion, and account isolation. Explore and Blueprint discovery/install flows are excluded. This is a source and test review; no server requests, production data changes, database resets, or fixture seeding were performed.

## Findings

### P1 — Interrupted media uploads could remain stuck as `uploading` — fixed locally

`WorkspaceMediaBookkeeper.pendingMediaTransfers` excludes rows in `.uploading` state ([WorkspaceMediaBookkeeper.swift](/Users/nexus/Documents/gatherory/ios-apps/gatherory/Gatherory/Data/Persistence/WorkspaceMediaBookkeeper.swift:108)). The normal preparation pass only resets `.requiresAttention` rows and leaves `.uploading` unchanged ([WorkspaceMediaBookkeeper.swift](/Users/nexus/Documents/gatherory/ios-apps/gatherory/Gatherory/Data/Persistence/WorkspaceMediaBookkeeper.swift:18)). The sync controller runs preparation before enumerating uploads ([WorkspaceCloudSyncController.swift](/Users/nexus/Documents/gatherory/ios-apps/gatherory/Gatherory/OfflineSync/WorkspaceCloudSyncController.swift:425)) and the media uploader queries eligible transfers, so a process exit after marking upload-in-progress can strand the durable row and local file indefinitely.

Added focused regressions in [CoreGatheringRecoveryTests.swift](/Users/nexus/Documents/gatherory/ios-apps/gatherory/GatheroryTests/CoreGatheringRecoveryTests.swift:1): one simulates an interrupted upload and expects the next preparation pass to make the same transfer eligible; the other verifies account A's restored transfer keeps its ID and attempt count while account B's `.uploading` row is unchanged. The parent ran the core native unit suite after adding account-scoped recovery; both regressions passed as part of 800 passing core unit tests. The recovery should reset only the restored account's stale upload state, preserving an actually running upload while its coordinator is active.

### UI invitation-permission fixture failure is not evidence of account role promotion

The focused UI run logged failures in `EventManagementUITests.testInvitationGuestDoesNotSeeEventManagementEntryPoints` (three `home.manage.*` buttons found), `MainInvitationEditingUITests.testGuestRoleCannotEditOrShareMainInvitation`, and `MainInvitationEditingUITests.testViewOnlyCollaboratorCannotEditOrShareMainInvitation`. Source tracing found no role promotion in session prep: `PlanningWorkspace.configureViewer` only updates viewer identity and generation ([PlanningWorkspace.swift](/Users/nexus/Documents/gatherory/ios-apps/gatherory/Gatherory/App/PlanningWorkspace.swift:360)); `WorkspaceLibrary.configureViewer` forwards that identity to each workspace ([WorkspaceLibrary.swift](/Users/nexus/Documents/gatherory/ios-apps/gatherory/Gatherory/App/WorkspaceLibrary.swift:88)); `LiveSessionPreparationServices.finishPlanningActivation` does the same ([SessionPreparationCoordinator.swift](/Users/nexus/Documents/gatherory/ios-apps/gatherory/Gatherory/App/SessionPreparationCoordinator.swift:124)). In development, the fixture assigns the planner account ID to the chosen sample member ([WorkspaceLibrary.swift](/Users/nexus/Documents/gatherory/ios-apps/gatherory/Gatherory/App/WorkspaceLibrary.swift:134)), while the guest fixture gives Alex the guest role and view-only permission ([PlanningWorkspace.swift](/Users/nexus/Documents/gatherory/ios-apps/gatherory/Gatherory/App/PlanningWorkspace.swift:2521)). The workspace derives event participation role from the member during construction ([PlanningWorkspace.swift](/Users/nexus/Documents/gatherory/ios-apps/gatherory/Gatherory/App/PlanningWorkspace.swift:190)). `-SkipAuthentication` uses the development planner account, and the UI launch passes `-UseEphemeralDataStore`, so the expected fixture should resolve to a guest Alex in an isolated store.

The UI failure therefore points to fixture activation or the graph actually opened by the test; logs do not expose the runtime member role, so the root cause remains unconfirmed. Source review found no matching path that changes a guest/view-only participant into a host during account configuration. Treat this as a failing UI acceptance check until runtime fixture state is inspected; it is not evidence of a production account permission leak.

Added [CoreGatheringRoleUITests.swift](/Users/nexus/Documents/gatherory/ios-apps/gatherory/GatheroryUITests/CoreGatheringRoleUITests.swift:1) as a runtime probe for the guest and read-only fixture paths. It pins Home to Overview at launch, uses a fresh ephemeral store, verifies Home and invitation controls, and captures a screenshot plus accessibility tree on failure. This probe has not been run; the parent owns sequential UI execution.

## Coordinating agent execution update

The parent reproduced the upload failure before applying an account-restoration
reconciliation in `WorkspaceMediaBookkeeper`/`WorkspacePersistenceController`.
Both new recovery tests passed within the 800-test core native run and in the
fresh follow-up. The normal preparation/query path still excludes active
uploads; only restoration resets abandoned markers. See the
[canonical execution report](core-gathering-release-check-2026-11-04.md) for
current results, UI failures/limits and release verdict. The earlier static
review below is historical review evidence, not the final execution status.

## Existing coverage reviewed

- Outbox draining, account-scoped leasing, transient/rejected work, and cancellation: [OfflineSyncTests.swift](/Users/nexus/Documents/gatherory/ios-apps/gatherory/GatheroryTests/OfflineSyncTests.swift:640), including the batch drain and rejection/recovery cases at lines 678–806.
- Offline account restoration across a cold relaunch with durable mutation IDs: [OfflineAccountRestorationTests.swift](/Users/nexus/Documents/gatherory/ios-apps/gatherory/GatheroryTests/OfflineAccountRestorationTests.swift:97).
- Workspace reopen and durable delete tombstone: [OfflineSyncTests.swift](/Users/nexus/Documents/gatherory/ios-apps/gatherory/GatheroryTests/OfflineSyncTests.swift:979).
- Media content typing, deduplication, failure backoff, account isolation, and transfer metadata persistence: [WorkspaceMediaBookkeepingTests.swift](/Users/nexus/Documents/gatherory/ios-apps/gatherory/GatheroryTests/WorkspaceMediaBookkeepingTests.swift:8).
- Media scope/owner filtering, due-time behavior, staged writes, and cleanup recovery boundaries: [WorkspaceMediaStagingTests.swift](/Users/nexus/Documents/gatherory/ios-apps/gatherory/GatheroryTests/WorkspaceMediaStagingTests.swift:8).
- Root/child event tombstones, missing-scope recovery, transient failures, and other-account isolation: [RemoteWorkspaceDeletionTests.swift](/Users/nexus/Documents/gatherory/ios-apps/gatherory/GatheroryTests/RemoteWorkspaceDeletionTests.swift:8).
- Album deletion authorization by uploader, event, and permission, including queued account-scoped tombstones: [SharedAlbumDeletionTests.swift](/Users/nexus/Documents/gatherory/ios-apps/gatherory/GatheroryTests/SharedAlbumDeletionTests.swift:8).
- Main-event delete vs child archive rules, lifecycle permissions, stale confirmation rejection, and local restore: [EventRemovalTests.swift](/Users/nexus/Documents/gatherory/ios-apps/gatherory/GatheroryTests/EventRemovalTests.swift:8).
- Invitation/RSVP event identity and sync encoding: [EventInvitationTests.swift](/Users/nexus/Documents/gatherory/ios-apps/gatherory/GatheroryTests/EventInvitationTests.swift:6); note/task event scope and permissions: [ManageNoteTests.swift](/Users/nexus/Documents/gatherory/ios-apps/gatherory/GatheroryTests/ManageNoteTests.swift:7), [ManageNoteHistoryTests.swift](/Users/nexus/Documents/gatherory/ios-apps/gatherory/GatheroryTests/ManageNoteHistoryTests.swift:7), and [EventTodoTests.swift](/Users/nexus/Documents/gatherory/ios-apps/gatherory/GatheroryTests/EventTodoTests.swift:395).
- Account deletion artifact/credential failures and retry while retaining another active account's edits: [AccountDeletionLocalCleanupTests.swift](/Users/nexus/Documents/gatherory/ios-apps/gatherory/GatheroryTests/AccountDeletionLocalCleanupTests.swift:10).

## Focused native verification selection

Run these suites after the media recovery policy is fixed; the parent agent owns execution and will report actual results:

- `GatheroryTests/CoreGatheringRecoveryTests`
- `GatheroryTests/WorkspaceMediaBookkeepingTests`
- `GatheroryTests/WorkspaceMediaStagingTests`
- `GatheroryTests/OfflineSyncTests`
- `GatheroryTests/OfflineAccountRestorationTests`
- `GatheroryTests/RemoteWorkspaceDeletionTests`
- `GatheroryTests/SharedAlbumDeletionTests`
- `GatheroryTests/EventRemovalTests`
- `GatheroryTests/EventInvitationTests`
- `GatheroryTests/ManageNoteTests`, `GatheroryTests/ManageNoteHistoryTests`, and `GatheroryTests/EventTodoTests`
- `GatheroryTests/AccountDeletionLocalCleanupTests`

Useful UI acceptance selections include `GatheroryUITests/OfflineConnectionUITests`, `GatheroryUITests/SharedAlbumUITests`, and `GatheroryUITests/EventManagementUITests`. They cover offline saved-library access, album navigation/selection, and event management navigation. Source review did not find a dedicated native UI test that performs core event deletion and then verifies the Home result; model and persistence deletion behavior is covered by `EventRemovalTests` and `OfflineSyncTests`. That remains a UI acceptance boundary if the release criteria require proof of the destructive confirmation flow.

## Execution status and limits

I did not run `xcodebuild` or a simulator suite in this audit. The parent reports 800 core native unit tests passed, including both added media recovery regressions. The focused UI run still has the invitation fixture failures noted above; other run results are owned by the parent. Server-side authorization and actual remote R2/Postgres behavior remain outside this local audit.
