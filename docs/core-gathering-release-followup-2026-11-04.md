# Core gathering release follow-up — November 4, 2026

## Result

All **11 previously unresolved UI acceptance methods now have passing current-source follow-ups**. Across the finalized selections, **13 distinct UI methods passed** (the original 11, the read-only scheduling check, and a new Account layout-transition permission check). This does not claim the entire app UI suite passed.

The final native selection passed **68 tests in seven suites, zero failures**: 67 focused model/service tests plus one real dev-server acceptance test. The 67 overlap the earlier 800-test core run; do not add them to 800. The **real dev-server acceptance test passed** using two independently authenticated accounts, two independent SwiftData stores and the normal native sync transport. Its previous interrupted test records were recovered, and fresh test content was removed through normal authorized sync.

No new product defect was demonstrated by these follow-up UI failures. The earlier account-scoped interrupted-upload recovery fix remains included and its regressions pass. Changes in this follow-up are regression-test setup, selectors, diagnostics and bounded dev-test cleanup. No app permission guard was loosened.

Three Luna agents handled permissions, budget navigation, and media/recovery. The parent built and executed the native tests and used Device Hub for manual host Overview → invitation cancellation and Overview → Manage → Budget checks.

## Native UI evidence

Debug **1.0 (6)**, native base `cabef2a2` plus the existing pending working tree, iPhone 18 Pro / iOS 27.0. Builds used Xcode 27.1. No production build was uploaded, installed on a physical phone or deployed.

| Check | Passing evidence |
| --- | --- |
| Guest Cards Home offers no management | roles-budget selection, 17.223 s |
| Guest invitation has no edit/share; plain information stays viewable | roles-budget, 16.661 s |
| View-only invitation has no edit/share; plain information stays viewable | roles-budget, 15.653 s |
| Main/child Manage → Budget → one Back returns to the exact event dashboard; repeated entry and scope switching | roles-budget, 105.002 s |
| Aggregate budget → one Back returns directly to Manage | roles-budget, 29.527 s |
| Host allocation editor cancel/reopen preserves saved allocation | roles-budget, 29.706 s |
| Read-only collaborator sees budget but cannot edit allocations | roles-budget, 15.907 s |
| Schedule cancel/save, exactly one linked Home event, canonical date/place, native Back and edge swipe, Light/Dark | final-ui, 178.807 s |
| Read-only collaborator cannot schedule an idea | followup-r2, 17.101 s |
| Shared-album preview → photo viewer → album → same invitation | followup-r2, 29.366 s |
| Cancellation confirmation can be dismissed; confirmed cancellation retains invitation, disables edits and RSVP, Light/Dark | final-ui, 61.376 s |
| Guest and view-only permissions survive Account → Overview → Cards | final-ui, 75.875 s |
| Unsaved event title survives Photos open/cancel/reopen and return to the editor, Light/Dark | final-ui, 107.695 s |

Finalized result bundles and matching `.log` files under `/tmp`:

- `gatherory-core-acceptance-roles-budget-20261104.xcresult`: 7 passed, 1 initial layout-test setup failure later superseded by final-ui.
- `gatherory-core-acceptance-followup-r2-20261104.xcresult`: 2 passed, 4 initial test-harness failures later superseded by final-ui.
- `gatherory-core-acceptance-final-ui-20261104.xcresult`: **4 passed, zero failures**; the final four rows requiring corrected harness behavior.
- `gatherory-core-acceptance-final-native-20261104.xcresult`: **67 model tests passed**, 1 initial dev acceptance cleanup failure later superseded by the live rerun.
- `gatherory-core-live-dev-sync-r4-20261104.xcresult`: **1 real dev acceptance test passed**, zero failures (8.743 s test execution), including recovery of the earlier interrupted test.
- `gatherory-core-acceptance-native-green-20261104.xcresult`: **68 tests in seven suites passed**, zero failures (9.910 s test execution). The final live run additionally verifies that the remote contributor projection has no test-created event participation rows.

An earlier secondary-simulator media selection completed its assertions (67 model tests passed, two offline Account UI checks passed, five UI checks failed), then Xcode stalled while finalizing diagnostics. The parent stopped that owned process. Its unfinished result bundle is not counted as finalized acceptance; its plain log is `gatherory-core-acceptance-media-recovery-20261104.log`.

## What the follow-up corrected

- Invitation tests now locate the current `invitation.actions` element through its stable identifier rather than relying on the old toolbar label or a specific XCUI query classification. Album acceptance does not require an unrelated conditional editing menu to remain present.
- Tests switching Home layouts no longer pin `home.layout` in the UserDefaults argument domain. That launch override takes precedence over the preference the Account UI saves. Direct Cards tests remain pinned; the layout-transition test changes both preferences through the UI.
- Home scheduling assertions recognize the current `home.overview.event.<UUID>` identifiers and use the default Overview layout. The linked-event count, cancel behavior and duplicate protection assertions remain intact.
- Photos tests dismiss the title keyboard with the editor's existing Done control before scrolling to Change Image. The Dark failure showed the image control beneath the keyboard; it had not attempted to present Photos. The final run presented and cancelled Photos twice in each appearance while preserving the unsaved draft.
- Cancelled invitations may omit their entire conditional action menu when nothing is permitted. Tests require the invitation to remain and edits/RSVP to be disabled; any retained action menu must omit Edit and Cancel Event.
- Diagnostic teardown skips an app that has already terminated. Tests no longer fail while taking a screenshot after all user-visible assertions passed. Teardown registration retains failure evidence when the app is running.

The earlier guest/edit and Event Unavailable failures did not reproduce in the fresh deterministic direct-path tests. Their exact original runtime/fixture cause remains unproven. There is no evidence here of a deployed privilege escalation; the current permissions and navigation assertions pass without app authorization changes.

## Real dev-server simulation and cleanup

Normal sign-in verified distinct `appreview@gatherory.test` and `coordinator@gatherory.test` sessions and active manager/contributor membership in the shared dev fixture. Bearers stayed in a temporary mode-0600 file and were never printed. The file and its empty private directory were removed after acceptance; no bearer was checked into the repository. The test is hard-coded to `https://dev.gatherory.com`.

The contributor's local Maybe response was saved before synchronization. The host received it through the real endpoint, scheduled the proposal, and the contributor pulled the chosen idea plus exactly one linked event. A second reconnect did not duplicate that event. Independent preference state survived scheduling.

The initial live test failed its strict outbox allowlist during cleanup: it had discarded participation IDs after reopening/removing the linked event, while those exact rows still needed tombstones. Cleanup now retains only event IDs linked to the test's idea and their exact participation IDs across phases, consulting the account-scoped cached archive before normalization removes those identities. Schedule setup derives and validates new participation rows after persistence. The safety guard continues to reject every other pending entity.

An interrupted-run recovery explicitly names the original idea and linked-event receipt. It verifies the exact generated title, submitting host and any surviving event-to-idea relation before cleanup; it does not sweep unrelated content. The successful native run confirmed removal of the earlier proposal and cleaned its own new proposal, linked event, event participation rows and active contributor response. The final repeated run also verified the earlier proposal remained absent. A standalone script's Cloudflare 1010 denial was not bypassed or used for mutations; verification and cleanup used the application's ordinary native transport. No firewall, access scope or production configuration changed.

## Remaining release acceptance limits

- This is Debug simulator and dev-backend acceptance, not a signed Release/TestFlight candidate or physical-device UI run. A connected physical phone was inspected only for device metadata (iOS 27.2); it was not installed or modified. Minimum iOS 26 is not installed in the simulator inventory.
- Offline disk reopen/account isolation, retry identity and interrupted-upload recovery pass locally. The two-client dev test proves native vote/schedule/reconnect behavior; it does not prove two physical phones under airplane-mode transitions.
- Real R2 photo upload/download, Photos-library image selection/save permissions, live invitation delivery/join/RSVP and APNs delivery/tap remain exact-candidate/device/service checks. Picker cancellation and seeded album navigation are verified separately above.
- Xcode records a non-fatal SwiftUI warning, “Invalid frame dimension (negative or non-finite),” without a source location in the finalized UI bundle. All assertions passed; the warning remains recorded, not claimed fixed.
- Localization verification passes for 1,882 English/Spanish strings, with the existing dynamic-key extraction advisory. `git diff --check` passes.

Explore, advertising, Blueprints and blueprint onboarding remain excluded. No production deployment, TestFlight upload, database reset, real invitation or message was performed.
