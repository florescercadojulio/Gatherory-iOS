# V1 core gathering release check — November 4, 2026

## Current verdict

**Superseded by the [completed follow-up](core-gathering-release-followup-2026-11-04.md).** All 11 UI acceptance methods left unresolved by this initial audit now have passing current-source follow-ups. Thirteen distinct native UI checks and 67 focused model tests passed across the finalized follow-up selections; real two-account dev sync also passed separately. The earlier 800 core tests and server checks remain prior evidence, with overlapping focused tests not added to those totals.

The detailed initial failures below are retained as history. They are not the current UI acceptance status. Exact signed-candidate/device/service limits remain in the follow-up report; no production upload or deployment is authorized by these results. Explore, ads, Blueprints and blueprint onboarding remain excluded.

## Simulated gathering

The connected domain scenario starts a Friendsgiving main event, adds and edits
a Dinner child, collects separate host/collaborator preferences, explicitly
approves a meal and commits its cost to the exact child, schedules a Board Games
event proposal into a canonical child event, allocates money, and coordinates
scoped tasks and notes. It then switches to view-only and guest identities and
asserts planning writes are denied. Individual input stays distinct from team
approval, and ordinary idea approval does not manufacture a schedule entry.

`CoreGatheringSimulationTests.coreGatheringLifecycle` passed. This uses real
native domain methods with simulated identities, not three live signed-in users.
Server role and database checks provide separate coverage; cloud networking is
not inferred from local model success.

## Confirmed defect fixed during this check

A process interruption after saving a media transfer as `.uploading` left that
transfer permanently excluded from pending uploads. The baseline regression
failed before the fix. `WorkspaceMediaBookkeeper.stageInterruptedUploadRecovery`
now resets only the restoring account's abandoned upload markers, invoked by
`WorkspacePersistenceController.restoreLibrary` before its worker starts.
Transfer identity, file, attempt count and other-account rows are preserved.
Ordinary preparation still excludes currently active uploads.

Both `CoreGatheringRecoveryTests` cases passed: retry after restoring a fresh
account graph, and A/B account isolation with preserved attempt counts. This is
source work requiring a new candidate build, not a remotely applied fix.

## Executed native model/service tests

**800 tests in 108 suites passed**, zero failures, in
`/tmp/gatherory-core-gathering-units-20261104.xcresult` (23.392 s test execution).
The explicit core suite allowlist is
`/tmp/gatherory-core-unit-suites-20261104.json`. It excludes Explore/Blueprint,
ad, curated-tour and experience-contract suites. Coverage includes:

- Event creation/editing, dates/time zones, root/child context and lifecycle.
- Scoped people, invitations, guest RSVP/leave, identity and role checks.
- Idea preferences, team responses, approval, scheduling and retry identity.
- Decimal money, allocation/expense boundaries, competing budget intents,
  paid history and conflict recovery.
- Tasks/assignment/completion, notes/announcements and exact-event isolation.
- Persistence, durable outboxes, offline restore/reconnect, account switching,
  root/child deletion propagation and media staging/cleanup.
- Calendar drafts, CSV exports, notification routing and photo preparation.

The first new simulation attempt had missing Swift argument labels; these were
corrected before execution. The next baseline exposed the media bug and an
incorrect test assumption that a contributing planner could not edit ordinary
root details. The test now follows existing contributor permissions; no product
permission was broadened to make it pass.

## Initial native UI pass

The two initial lanes executed **24 unique UI methods: 12 passed and 12 failed**.
Several existing methods run both standard appearances internally; no oversized
layout matrix was added. These counts are an initial diagnostic result, not a
claim that all core UI passed. Some entry tests stop before reaching their full
named flow. Exact results:

| UI method | Initial result | Duration |
| --- | --- | --- |
| `CoreGatheringCoordinationUITests.testTasksCreateEditCompleteAndReopenInExactMainAndChildEvents` | failed | 37.805 s |
| `EventManagementUITests.testMainAndChildUpdatesUseTheManagedEvent` | passed | 46.484 s |
| `IdeaSchedulingUITests.testEventIdeaScheduleCancellationAndConfirmationInBothAppearances` | failed | 60.338 s |
| `IdeaSchedulingUITests.testReadOnlyCollaboratorCannotScheduleEventIdea` | passed | 18.039 s |
| `IdeasApprovalUITests.testEventIdeaLongPressRetainsScheduleFlow` | passed | 39.919 s |
| `IdeasApprovalUITests.testPersonalLoveAppearsInLikedAndApprovalRequiresConfirmation` | passed | 85.330 s |
| `InvitationScheduleCardUITests.testHostScheduleCardKeepsDateEditorSeparateFromCalendarExportInBothAppearances` | passed | 87.153 s |
| `MainInvitationEditingUITests.testHostCanSaveAndCancelMainInvitationTitleAndLocationInBothAppearances` | passed | 101.001 s |
| `ReleaseCoreFlowsUITests.testAddEditDecideAndUndoManualIdea` | passed | 93.509 s |
| `ReleaseCoreFlowsUITests.testCreateEventFromScratchOpensHomeAndInvitationShowsTitleAndToday` | passed | 35.687 s |
| `BudgetConflictRecoveryUITests.testCancelKeepsConflictAndUsingSharedBudgetPreservesTitle` | passed | 37.658 s |
| `EventManagementUITests.testInvitationGuestDoesNotSeeEventManagementEntryPoints` | failed | 19.795 s |
| `GatheroryUITests.testCancellationKeepsInvitationButClosesEditing` | failed | 39.631 s |
| `GatheroryUITests.testDuplicateFromEventsLongPressCreatesIndependentEventInLightAndDark` | passed | 48.696 s |
| `MainInvitationEditingUITests.testGuestRoleCannotEditOrShareMainInvitation` | failed | 11.290 s |
| `MainInvitationEditingUITests.testViewOnlyCollaboratorCannotEditOrShareMainInvitation` | failed | 12.037 s |
| `ManageBudgetNavigationUITests.testBackFromWorkspaceOverviewReturnsDirectlyToManage` | failed | 27.729 s |
| `ManageBudgetNavigationUITests.testBudgetBackReturnsToTheSameEventDashboardFromOverviewManagement` | failed | 29.322 s |
| `OfflineConnectionUITests.testOfflineAccountStatusKeepsSavedLibraryVisibleInLightAndDark` | passed | 30.675 s |
| `OfflineConnectionUITests.testOnlineAccountStatusDoesNotOfferRetryInLightAndDark` | passed | 29.400 s |
| `PhotoAttachmentPickerUITests.testMainEventPhotoPickerOpensCancelsAndReopensWithoutDiscardingDraft` | failed | 24.091 s |
| `SharedAlbumUITests.testPreviewPhotoOpensViewerAndCloseReturnsThroughAlbumToEvent` | failed | 14.633 s |
| `TeamBudgetAuditUITests.testHostCanOpenWorkspaceBudgetAndAllocationEditorThenReturnToManage` | failed | 16.872 s |
| `TeamBudgetAuditUITests.testReadOnlyCollaboratorCanViewBudgetButCannotOpenAllocationEditing` | failed | 15.166 s |

Artifacts: `/tmp/gatherory-core-ui-host-20261104.xcresult` and
`/tmp/gatherory-core-ui-recovery-20261104.xcresult`.

### Open UI acceptance checks

- Guest/read-only checks unexpectedly find editable invitation controls; the
  guest management check finds three Home management controls. Native and
  server permission suites pass. Source inspection finds no role promotion in
  `configureViewer`; actual fixture/runtime perspective needs verification.
  Do not classify this as a confirmed deployed privilege escalation or waive it
  on the strength of model tests.
- Budget navigation tests fail waiting for the management dashboard. Budget
  conflict recovery passes, so the failure must be localized to that entry/back
  route before declaring ordinary budget navigation accepted.
- Photo-picker and album checks fail at event-detail entry/toolbar expectations;
  they do not establish that the system picker or album viewer itself failed.
- Schedule confirmation exposes View Event, but the old Home-card count query
  finds zero linked Reception cards. Domain scheduling and its idempotence pass;
  distinguish virtualized/date-group presentation from a missing canonical event.
- Cancellation UI fails before its action menu; cancellation model tests pass.
- The new task UI test initially loses the filled title field's placeholder.
  Its locator now uses the current value; a fresh follow-up is recorded below.

## Fresh native follow-up

`/tmp/gatherory-core-gathering-followup-20261104.xcresult` passed **3 native
model tests and 3 UI methods**, zero failures. The model cases overlap the
800-test run and are not extra unique tests.

| Fresh check | Result |
| --- | --- |
| Full main/child task create, edit, complete, reopen and separation | Passed, 104.476 s |
| Guest identity through default Overview and invitation, with no editing/sharing/management | Passed, 13.021 s |
| View-only collaborator through default Overview and invitation, with no editing/sharing | Passed, 13.081 s |

The task test's initial failure was an obsolete placeholder locator after the
field contained text. It now resolves the existing title value. The new role
probes launch directly into the default Overview path and avoid Account/layout
switching. These results establish that path's fixture behavior; they do not
silently waive the failed older Cards/layout and guest checks. Read-only
collaborators retain view access to management; they do not receive writes.
The earlier UI role failures are not evidence of a demonstrated deployed
privilege escalation, and their alternate navigation/fixture cause remains
unresolved.

After the task rerun, **11 of the original 24 UI acceptance methods remain
unresolved**. The 12 initially passing methods plus the repaired task and two
new default-role checks are positive evidence for 15 unique UI methods. No
claim that the whole UI suite passed is made. Runtime verification is complete
for this audit pass; production approval remains on hold pending the listed
checks and exact-candidate device/service acceptance.

## Server evidence

The actual server checkout is `/Users/nexus/Documents/gatherory/gatherory-web-app`,
base `93902bb1b8b98a19a96c6a66eccde1349df6f84c` with pending changes.
The first agent audit used an old worktree; its results were superseded by runs
in the owning checkout. **112 tests across 18 non-DB files passed**. Notes/tasks
and authorization were also rerun as a focused 22-test subset; do not add that
subset to the total as if it were independent coverage.

A new UUID-named local PostgreSQL database was created from `template0`, migrated
using current source and used for **13 passing DB tests across six files**.
Those checks include invitations, lifecycle, device/browser guest capabilities,
guest claim feed and native budget sync. The database was dropped and absence
verified. Existing local/remote databases were not migrated or reset.
One intermediate DB invocation used the already dropped test DB; it was retried
successfully on a freshly recreated disposable DB. This was harness ordering,
not an assertion failure. No real invitations/messages were sent.

The opt-in invitation HTTP and device-guest HTTP suites were not run. No claim
of current production schema, service, R2, APNs, provider sign-in or real
multi-device synchronization is made. See the agent's detailed
[server evidence](../../../gatherory-web-app/docs/release/core-gathering-guest-audit-2026-11-04.md).

## Remaining candidate acceptance

Resolve the UI checks above, then exercise the exact signed candidate on real
accounts/devices against its intended backend: invitation join/RSVP, updates,
photo upload and interrupted recovery, offline edit → terminate/relaunch →
reconnect, and cross-account isolation. Calendar save/cancel, notification
delivery/tap and provider sign-in remain external-service/device acceptance.
The installed simulator runtime is iOS 27; the target minimum is iOS 26, which
was not exercised here. A signed Release archive/upgrade and production schema
compatibility are separate gates; this audit authorizes no upload or deployment.

Native base: `cabef2a2` plus the extensive pending workspace changes. Exact
commits and a candidate build number must be recorded when preparing a release.
