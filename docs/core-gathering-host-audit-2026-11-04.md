# Core gathering host and collaborator audit — November 4, 2026

## Scope

This audit covers the native host/collaborator planning lifecycle: create and
edit a root event, add a direct subevent, collect individual and team idea
decisions, approve an ordinary idea, schedule an event idea, manage budgets and
expenses, and coordinate tasks and notes under role permissions. Explore and
Blueprints are excluded.

The new `CoreGatheringSimulationTests` suite exercises that sequence through
`PlanningWorkspace` domain APIs. Existing focused tests remain the main evidence
for individual validation and recovery cases; this simulation checks that the
cross-feature handoffs retain event, idea, budget, and author identity.

## Existing focused suites

These Swift Testing suites are present and relevant:

- `IdeaApprovalTests` — explicit non-event approval, stale requests, parent
  changes, permissions, and expense creation.
- `TeamDecisionTests` — independent viewer responses, undo, eligible roster,
  and child-event scope.
- `EventIdeaSchedulingTests` — proposal validation, schedule confirmation,
  retries, changed inputs, and contributor restrictions.
- `EventManagementAccessTests` — exact event destinations, guest/view-only and
  pending boundaries, and account identity.
- `WorkspaceBudgetRulesTests` and `WorkspaceBudgetFacadeParityTests` — Decimal
  allocations, cap changes, funding, transfers, and expense coordination.
- `EventTodoTests` — task validation, event scoping, assignments, and role access.
- `EventNoteTests` — event/author targeting, validation, persistence, and role
  access.

## Source review findings and limits

- The root event edit path checks `canManageMainEvent` before writing the root
  fields (`Gatherory/App/PlanningWorkspace.swift:1631-1654`). Root and child
  scheduling decisions are separate: ordinary approval is an explicit,
  snapshot-checked operation (`PlanningWorkspace.swift:1260-1318`), while event
  proposals require management authority and a confirmed schedule
  (`PlanningWorkspace.swift:1366-1421`).
- Team responses are counted only for active, non-guest, non-view-only
  participants (`PlanningWorkspace.swift:1340-1357`). The simulation checks an
  individual response from each of two planners and the team summary.
- Budget-cap, child-allocation, and initial-funding methods are manager-gated
  (`PlanningWorkspace.swift:577-649`). Expense and budget validation also have
  dedicated facade and rule tests.
- Task writes explicitly gate active event planners and reject guests
  (`PlanningWorkspace.swift:1927-1951`). Notes validate text and target the
  selected viewer/event (`PlanningWorkspace.swift:2011-2022`); `EventNoteTests`
  includes guest, read-only, signed-out, and finished-event cases.
- `addTimelineItem` and `updateTimelineItem` enforce direct-child structure and
  budget normalization, but the methods themselves do not check the current
  viewer's role (`PlanningWorkspace.swift:1533-1570`). Their current safety
  depends on authorized callers. The relevant native UI path should be walked
  with a guest and view-only account to verify those controls are unreachable;
  direct mutation should also be considered if these methods become exposed to
  an untrusted caller.
- There is no dedicated UI test suite for adding/editing tasks or composing
  notes. Their model rules are covered, but keyboard behavior, event-context
  routing, and visible permission affordances still need a native UI run.

## Recommended native UI coverage

Run the existing suites that cover the visible parts of this flow:

- `ManageEventEditingUITests` and `EventManagementUITests` for root/subevent
  creation, editing entry points, event context, and guest access.
- `IdeasApprovalUITests` and `IdeaSchedulingUITests` for individual decisions,
  approval confirmation, scheduling, and contributor restrictions.
- `ManageBudgetNavigationUITests`, `TeamBudgetAuditUITests`, and
  `BudgetConflictRecoveryUITests` for budget navigation, collaborator review,
  and conflict recovery.
- Add or run native UI coverage for task creation/completion and note creation
  in both root and child contexts, including guest and view-only denial.

## Coordinating agent execution update

The parent corrected the simulation's Swift argument labels and a mistaken test
assumption about ordinary contributor edits. The connected domain scenario now
passes within 800 core native tests. The task UI scenario also passes after
updating its filled-title field locator (104.476 s), including main/child
isolation and native back navigation. Fresh default-Overview guest/read-only UI
probes pass. The broad UI acceptance run still has unresolved methods; see the
[canonical execution report](core-gathering-release-check-2026-11-04.md) for
actual per-method results and the production hold.

## Original delegated verification status

No Xcode build or test run was performed for this audit, as requested by the
coordinating agent. The added simulation test is source-reviewed only and must
be compiled and run in the serialized native test pass. The local Intent CLI is
not available from this native checkout (`pnpm intent list` reports
`Command "intent" not found`); no replacement dependency was downloaded.

## UI coordination coverage addendum

`CoreGatheringCoordinationUITests.testTasksCreateEditCompleteAndReopenInExactMainAndChildEvents`
adds native coverage for task creation, editing, completion, reopening, and
root/child event isolation through the Manage dashboard and To-dos screen. It
uses the ordinary development seed, an ephemeral store, and the requested
Overview Home layout. It has not been run locally; the coordinating agent owns
the serialized UI test pass.

I inspected `EventAnnouncementsView` and `EventAnnouncementController` before
considering a note composer flow. The seeded authenticated path loads and sends
through `HTTPEventAnnouncementTransport`, so the UI test deliberately skips
that flow to avoid server activity. The local planning-note composer is gated
to a device-local guest planning profile, which the ordinary authenticated
fixture does not provide.
