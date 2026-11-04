# Core gathering guest and view-only permission follow-up — 2026-11-04

## Prior UI evidence

The three role failures came from `/tmp/gatherory-core-ui-recovery-20261104.xcresult`, produced by `xcodebuild test-without-building`. The actual failed assertions were:

- `EventManagementUITests.testInvitationGuestDoesNotSeeEventManagementEntryPoints`: found three buttons with IDs beginning `home.manage.` on the Cards Home screen.
- `MainInvitationEditingUITests.testGuestRoleCannotEditOrShareMainInvitation`: found `invitation.edit.title` after opening the main invitation.
- `MainInvitationEditingUITests.testViewOnlyCollaboratorCannotEditOrShareMainInvitation`: found the same title edit button.

The newer `CoreGatheringRoleUITests` launched with a forced Overview preference and passed both role cases. This narrows the discrepancy to setup or identity resolution across the other launch/layout path; it does not by itself prove a permission leak or explain the Cards result.

## Source review

The role fixture changes Alex in the `Alex & Jordan` sample to either guest/view-only or collaborator/view-only. The matching account ID is assigned to Alex in `WorkspaceLibrary.sample`. The fixture selector matches the unique `Alex & Jordan` workspace title; Maya's separate sample workspace is titled `Maya & Theo’s Wedding`.

Current app source has guards at the relevant presentation points:

- `EventManagementAccess.canOpen` requires `workspace.showsPlanningInterface`, an active exact-event member, and a visible event context ([EventManagementView.swift](/Users/nexus/Documents/gatherory/ios-apps/gatherory/Gatherory/Features/Manage/EventManagementView.swift:17)). Guests do not have the planning interface; active view-only collaborators can still open a read-only management dashboard.
- Main invitation edit controls require `canManageMainEvent`, a non-guest active participant, and planning permission other than view-only ([EventInvitationScreen.swift](/Users/nexus/Documents/gatherory/ios-apps/gatherory/Gatherory/Features/Events/EventInvitationScreen.swift:436)). Invitation sharing is separately gated by `canManageInvitations` ([HomeView.swift](/Users/nexus/Documents/gatherory/ios-apps/gatherory/Gatherory/Features/Home/HomeView.swift:453)).

No app permission code was changed. Existing role assertions were retained.

## Regression-test changes

`MainInvitationEditingUITests` now pins guest and view-only cases to the Cards preference so they cannot inherit a simulator preference left by an earlier test. The role launch path also uses production onboarding mode consistently with the fresh role probes. A new `testGuestAndViewOnlyStayReadOnlyAfterSwitchingHomeLayout` explicitly starts each fixture in Overview, uses the Account → Home Layout control to switch to Cards, then checks guest management visibility, invitation editing/sharing controls, and read-only title/date taps. The view-only case continues to allow its read-only management dashboard entry point.

`EventManagementUITests.testInvitationGuestDoesNotSeeEventManagementEntryPoints` now starts directly in Cards, making its layout explicit. The Account → Cards transition is covered separately by the new Main Invitation Editing method for both guest and view-only roles.

## Fresh follow-up and validation status

The parent ran the deterministic direct Cards role paths on a fresh build. `EventManagementUITests.testInvitationGuestDoesNotSeeEventManagementEntryPoints` passed (17 s), `MainInvitationEditingUITests.testGuestRoleCannotEditOrShareMainInvitation` passed (16 s), and `MainInvitationEditingUITests.testViewOnlyCollaboratorCannotEditOrShareMainInvitation` passed (15 s). These runs resolve the previous direct-path assertions for the current executable without changing app permission code.

The first run of the new Account layout-transition test failed inside `HomeLayoutUITestSupport` immediately after attempting to select Overview. The test had launched with `-home.layout overview`; XCTest launch arguments populate the UserDefaults argument domain, which takes precedence over the value saved from Account. That flag made layout changes impossible, so the failure was a test harness error before the role checks ran. The method now sets `pinsHomeLayout: false`, chooses Overview and then Cards through the UI, and captures a screenshot plus accessibility tree on teardown. The corrected transition method passed in `gatherory-core-acceptance-final-ui-20261104.xcresult` (75.875 s), including both guest and view-only fixtures through Account → Overview → Cards. Diagnostic teardown also skips an already terminated app.

The initial three UI failures showed controls on screen, but their exact fixture/layout cause in that earlier test-without-building run was not established by source review alone. Fresh direct Cards passes show the current deterministic launch path is correct; they do not prove the earlier simulator state or older executable had the same fixture state.

No `xcodebuild` was run by this lane; the parent serializes simulator builds and test execution. Runnable methods:

- `EventManagementUITests.testInvitationGuestDoesNotSeeEventManagementEntryPoints`
- `MainInvitationEditingUITests.testGuestRoleCannotEditOrShareMainInvitation`
- `MainInvitationEditingUITests.testViewOnlyCollaboratorCannotEditOrShareMainInvitation`
- `MainInvitationEditingUITests.testGuestAndViewOnlyStayReadOnlyAfterSwitchingHomeLayout`

The earlier Overview role passes remain valid for that route. The current direct Cards guest/view-only checks also passed. The corrected Account → Overview → Cards transition regression also passed. All three prior direct-path failures now have passing follow-ups, and no app permission change was needed.
