# Core gathering: budget navigation follow-up (2026-11-04)

## Scope

This follow-up covers native Manage entry, scoped budget navigation, workspace budget allocations, and the read-only collaborator boundary. Explore and Blueprints are out of scope. No production account or network data was used. Fresh results are from Debug app 1.0 (6), iPhone 18 Pro, iOS 27.0, in [`/tmp/gatherory-core-acceptance-roles-budget-20261104.xcresult`](/tmp/gatherory-core-acceptance-roles-budget-20261104.xcresult). This agent did not run Xcode or a simulator.

## Current UI coverage

`ManageBudgetNavigationUITests` covers main and child event Manage entry from Overview, budget scope toggling while preserving the managed event scope, a single back step from Budget to the same management dashboard, and returning from management to Home. `TeamBudgetAuditUITests` covers host access to workspace allocation editing, cancel/reopen draft preservation, return to Manage, and read-only collaborator visibility with allocation editing disabled. These checks assert user-visible navigation and role outcomes; retain them unchanged.

The four methods failed in the earlier `/tmp/gatherory-core-ui-recovery-20261104.xcresult` run:

- `ManageBudgetNavigationUITests.testBackFromWorkspaceOverviewReturnsDirectlyToManage`
- `ManageBudgetNavigationUITests.testBudgetBackReturnsToTheSameEventDashboardFromOverviewManagement`
- `TeamBudgetAuditUITests.testHostCanOpenWorkspaceBudgetAndAllocationEditorThenReturnToManage`
- `TeamBudgetAuditUITests.testReadOnlyCollaboratorCanViewBudgetButCannotOpenAllocationEditing`

All stopped at the first wait for `event.management.dashboard`, before budget navigation, allocation editing, or read-only allocation assertions. The exported accessibility hierarchy for the Team Budget test showed Manage was pushed and rendered “Event Unavailable.” This observation did not reproduce in the fresh run; its earlier cause remains unconfirmed. Team Budget explicitly launches with `-home.layout overview`, so the old trace alone did not establish an Overview-layout mismatch or a product defect.

## Source checks

- [EventManagementView.swift](../Gatherory/Features/Manage/EventManagementView.swift) lines 18–30 checks the selected event, active member, visibility, and non-archived child relationship before opening management.
- The account-scoped overload at lines 33–53 additionally requires `hasAuthenticatedViewer(accountID:)` and a matching or unbound viewer member identity.
- `EventManagementView.isCurrentScope` at lines 102–113 re-evaluates the account/local-guest identity and principal generation after navigation. Its unavailable view and dismissal behavior are at lines 148–167.
- [HomeView.swift](../Gatherory/Features/Home/HomeView.swift) lines 676–679 pushes the route after its general access check; the destination then applies its principal-scoped check. This describes the two checks but does not establish why the earlier run showed “Event Unavailable.”
- [WorkspaceLibrary.swift](../Gatherory/App/WorkspaceLibrary.swift) lines 121–145 seeds the development account ID on the host member (or Alex for the read-only collaborator fixture). [AuthenticationSession.swift](../Gatherory/App/AuthenticationSession.swift) lines 230–253 initializes the development planner as current user when authentication skipping is enabled. Source was unchanged for this follow-up; the successful fresh run does not establish the earlier rejection's cause.

## Fresh verification

Both budget/navigation UI test suites attach a final screenshot and accessibility hierarchy with `.deleteOnSuccess` before terminating the app. Assertions and fixture arguments were not weakened or changed. The parent ran these exact methods successfully in [`/tmp/gatherory-core-acceptance-roles-budget-20261104.log`](/tmp/gatherory-core-acceptance-roles-budget-20261104.log):

- `ManageBudgetNavigationUITests.testBackFromWorkspaceOverviewReturnsDirectlyToManage` — passed, 29.527 s.
- `ManageBudgetNavigationUITests.testBudgetBackReturnsToTheSameEventDashboardFromOverviewManagement` — passed, 105.002 s.
- `TeamBudgetAuditUITests.testHostCanOpenWorkspaceBudgetAndAllocationEditorThenReturnToManage` — passed, 29.706 s.
- `TeamBudgetAuditUITests.testReadOnlyCollaboratorCanViewBudgetButCannotOpenAllocationEditing` — passed, 15.907 s.

The containing selection ran 8 tests total and had 1 failure in a separate `MainInvitationEditingUITests` method. The four budget/navigation methods above all passed. `EventManagementUITests/testMainAndChildUpdatesUseTheManagedEvent` was not part of this fresh selection.

Acceptance limit: the earlier route-scope failure did not reproduce in the fresh build. No product or fixture change was needed to make these four checks pass, and the cause of the earlier result remains unknown.
