# iOS verification

## Core gathering follow-up — November 4, 2026

All 11 UI methods left unresolved in the initial core audit now have passing follow-ups. Thirteen distinct UI methods passed across the finalized selections, including permissions through Account layout changes, exact-event budget/back behavior, cancellation, native Photos picker recovery, shared album viewer/back, and idea scheduling/native swipe. The final native selection passed 68 tests: 67 focused model tests (overlap with the earlier 800) plus one real two-account native dev sync acceptance, including bounded cleanup of interrupted-run records. See the [completed follow-up](core-gathering-release-followup-2026-11-04.md) for result bundles, intermediate harness failures, warning and device/service limits. No production deployment or upload occurred.


## V1 core gathering simulation — November 4, 2026

Three Luna agents covered host/collaborator planning, guest/server access and
offline/media recovery. Explore, Blueprints and advertising were excluded.
The parent ran **800 native tests in 108 suites, all passing**, and two initial
UI lanes containing **24 methods: 12 passed, 12 failed**. A fresh follow-up
passed the repaired task scenario and two default-Overview guest/read-only UI
checks, plus three overlapping model checks. Eleven older UI acceptance
methods still need classification/retesting; this is **not a production go**.

A confirmed interrupted-upload defect was fixed: account restoration now
requeues that account's abandoned `.uploading` transfers while preserving file,
transfer ID, retry count and other-account state. Both regressions pass.
Server checks in the actual owning checkout passed **112 non-DB tests** and
**13 isolated PostgreSQL tests**. The disposable DB was migrated only for tests,
then dropped; current production compatibility and live HTTP/device flows
were not asserted. The additional focused 22-test server rerun overlaps the
112 tests and is not additive coverage.

See the [full scope, scenario, per-method results, artifacts and release hold](core-gathering-release-check-2026-11-04.md).
No deployment, upload, real guest messaging or production data change occurred.

## AdMob native asset bounds — November 4, 2026

The reported validator error was reproduced by focused UIKit tests before the
fix: a 180-point native view measured 381 points tall but accepted a host height
of 380.75, leaving its CTA 0.25 points outside. A shorter/zero-height host also
retained overflowing asset frames. The old 0.5-point tolerance was insufficient.
Baseline: `/tmp/gatherory-native-ad-bounds-before-20261104.xcresult`
(two failing regression cases, one passing normal-layout case).

`RegisteredNativeAdView` now uses exact containment, a one-point internal inset,
and actual UIKit coordinates after SDK layout. It detaches the creative before
moving assets, clears invalid transient frames, requests a fitting height and
registers only a contained layout. Repeated updates of the same immutable
creative avoid resetting the registered media/content. No validator switch,
production IDs, consent policy, SDK version or click handling was changed.

Final scoped run: `/tmp/gatherory-native-ad-bounds-scoped-20261104.xcresult` —
**18 unit tests in four suites and one native UI test passed**, zero failures,
on iPhone Duo / iOS 27.1, default appearance and portrait app window.
The suites are `NativeAdAssetBoundsTests` (5), `ExploreAdPlacementTests`,
`ExploreAdConfigurationTests` and `ExploreAdSessionLifecycleTests`.
New bounds cases cover fractional/short/zero heights, collapsed widths,
recovery, multiline/optional assets, narrow columns, RTL and fractional bounds
origins. A first RTL check caught outward coordinate rounding; the internal
inset resolved it without relaxing the containment rule.

`NativeAdValidationUITests.testGoogleSampleAssetBoundsWhileScrolling`
passed in **28.574 seconds**, loading Google's real sample native inventory,
scrolling around the creative and checking a Debug-only diagnostic for both
`registered=true` and `assetsContained=true` before and after scrolling.
The SDK validator remains enabled. Captures were inspected; the validator shows
**No implementation issues found**. Evidence:
`/tmp/gatherory-native-ad-bounds-scoped-attachments-20261104`.
The sample app ID was a command-line build override; checked-in configuration
was preserved. No ad/CTA/AdChoices clicks or live creative requests were used.

**Separate acceptance limit:** an exploratory longer scroll-away/return test
repeatedly lost the original `explore-ad-6` slot. Its cause is unconfirmed;
slot inventory/lazy remount retention is not certified by this fix. The broader
return runs (`...bounds-verified...`, `...bounds-final...`, and
`...bounds-final-r2...` result bundles) failed that return assertion, although
the initial creative's registered/contained checks passed and no bounds warning
was observed. The retained UI test is scoped to the reported asset bounds error;
it does not claim long-distance remount acceptance. Investigate slot retention
separately before treating the older scroll-stability results as current proof.

English/Spanish coverage passed for **1,882 strings**, with the existing
nonliteral-key extraction advisory at `AppCopy.swift:326`.
`git diff --check` passed. No physical-device, Light/Dark matrix, oversized-text,
expanded Duo, signed Release archive, new TestFlight build or production rollout
was performed. SDK sample behavior does not establish approval for every
creative/provider/device configuration. No server, database or ad-account state
was changed.

## Branded primer refinement — November 4, 2026

Following visual feedback, Explore and Decide now use the original welcome's
Gatherory mark instead of oversized SF Symbol heroes. The header uses the
existing 108-point asset and system large-title style, with 24-point internal
spacing and 40 points before the feature group. Leading row alignment and short
copy are retained. Native full-screen covers replace the large-detent sheets,
removing the rounded inset surface and grabber. Continue remains a centered,
content-sized native capsule. The original welcome screen and tour content were
not redesigned. Existing adaptive colors remain; no custom appearance switch,
new palette, decorative cards or animation was introduced.

The Apple design skill informed the layout/typography review; rationale and
actual layout values are recorded in `movie-night-onboarding.md`.

`/tmp/gatherory-brand-primers-20261104.xcresult` passed **4 unit tests and two
native UI tests** on Duo / iOS 27.1, default appearance and portrait app window:
`ContextualPrimerPolicyTests`,
`testDecidePrimerSimpleLayoutAndDismissal` (**18.212 s**) and
`testOriginalWelcomePrecedesTourAndSearchWaitsForExplore` (**23.220 s**).
Assertions cover brand header presence, edge-to-edge presentation rather than a
sheet, content-sized/reachable Continue, brief instruction rows, no practice
controls or decision writes, account-scoped first-tab timing and dismissal.
Both captured layouts were inspected; all three feature rows and the action
fit clearly in the tested compact window. Captures:
`/tmp/gatherory-brand-primers-attachments-20261104`.

The tour handoff also passed in
`/tmp/gatherory-brand-primers-tour-20261104.xcresult`:
`testWorkspaceGuidePointersFollowDecideAndIdeasTabs` (**54.309 s**).
This exercises Search during guided discovery, native tab hit testing, the
full-screen Decide primer, its dismissal, a real Love It response and the
resumed Ideas guidance. Total for this refinement: **4 unit tests and 3 native
UI tests passed**, zero failures.

Localization coverage passed for **1,882 English/Spanish strings** with the
existing dynamic-key advisory; `git diff --check` passed. No Light/Dark matrix,
large-text matrix, expanded Duo posture, physical-device or Release archive
acceptance is claimed. No account, database, server or deployment changes.

## Welcome-style contextual primers — November 4, 2026

Explore and Decide now share a native welcome-style layout: centered blue hero,
large title, short leading icon/text rows, and one content-sized capsule Continue
button. Decide's interactive practice deck, sample idea, feedback, choice buttons
and date lesson were removed. Its three rows explain left/Pass, up/Maybe and
right/Love It. Explore retains its three discovery features with shorter copy.
The original welcome and Movie Night tour are unchanged; primers still appear
on their own first active tab and remember dismissal per account.

Final run: `/tmp/gatherory-simple-primers-r2-20261104.xcresult`, **12 unit tests
and two native UI tests passed**, zero failures, on iPhone Duo / iOS 27.1 in its
default appearance and portrait app window. This supersedes the first passing
run's longer Explore descriptions.

- `ContextualPrimerPolicyTests` (4): first-tab timing, completion, persisted
  dismissal, account isolation and replay reset.
- `DecisionSwipeMappingTests` (8): real swipe thresholds/direction precedence,
  queue handling and existing response/undo presentation behavior.
- `testDecidePrimerSimpleLayoutAndDismissal` (**17.421 s**): three instruction
  rows, no practice UI/text, reachable 44-point Continue, final row clear of the
  action, no recorded decision on dismissal, and no repeated primer on revisit.
- `testOriginalWelcomePrecedesTourAndSearchWaitsForExplore` (**24.640 s**):
  original Welcome and Skip, Search deferred until Explore, feature rows,
  reachable Continue, last row clear of footer, and remembered dismissal.

Exported captures were reviewed for both primers. The shorter Explore copy fits
above the footer in this compact window. Content can scroll when needed; the
footer uses an opaque adaptive background. Attachments are in
`/tmp/gatherory-simple-primers-r2-attachments-20261104`.
Localization coverage passed for **1,882 English/Spanish strings**, with the
existing nonliteral-key extraction advisory at `AppCopy.swift:326`.
`git diff --check` passed. No dedicated Light/Dark, oversized-text, expanded Duo,
physical-device or signed Release acceptance was performed. No deployment,
account, server or database changes were made.

## Developer-only full onboarding replay — November 3, 2026

Two Luna agents implemented the Account action and focused regression coverage.
Development Debug builds expose **Account → Developer → Redo onboarding**, using
the existing launch onboarding rather than a second copy of its UI. The request
is in memory and bound to the current prepared, authenticated non-guest account.
Only that account's tutorial/discovery/primer keys are cleared; authentication,
existing workspaces and normal account onboarding state remain intact. Recovery,
imports, invitations and shared-blueprint routing keep priority. The normal Redo
tour action is unchanged.

UI, request subscription and replay state are compiled out of Release. Configured
staging/production are also ineligible. The developer gate reads configured
`APP_ENVIRONMENT` independently of `SIMULATE_PRODUCTION_FLOW`, allowing the
ordinary development Debug build to exercise production-like sign-in and still
use the control. The shared scheme archives with Release configuration.

Final verification: **30 unit tests across two suites and one native UI method
passed**, zero failures/skips, in
`/tmp/gatherory-developer-redo-onboarding-r4-20261103.xcresult`, using the clean
Simulator build directory `/tmp/gatherory-developer-onboarding-dd-20261103`.
Unit coverage checks configured environment gating, Release/staging/production
rejection, nil/empty/stale accounts, guest/signed-out/unprepared sessions, blocked
recovery/import/invitation/shared-blueprint requests, safe terminal destinations,
notification scoping and the existing authentication chain.

On Duo / iOS 27.1 in the default appearance,
`testDeveloperRedoOnboardingRepeatsWelcomeAndSkipWithoutChangingAccountOrWorkspaces`
passes in **35.119 seconds**. It starts with an existing signed-in seeded library,
uses the adaptive Account control and lazy settings List, repeats full welcome →
Movie Night choice → Skip twice, and compares the same event card IDs after each
cycle without logging in again.

The first attempts used stale generated modules and an invalid cached simulator
test signature; a clean derived-data directory with ad-hoc Simulator signing
resolved those build artifacts. The first clean UI attempt also assumed an
existing cached account would initially show onboarding; the test now enters
through its real library fast path before pressing the developer action. Those
attempts are superseded by R4 and are not green acceptance evidence.

Localization verifies 1,879 English/Spanish strings with the existing dynamic-key
advisory; `git diff --check` passes. No Light/Dark matrix, full planning matrix,
signed Release archive or live-account provider test was performed for this
developer control. No database reset, package/version change, deployment or upload.

## Explore primer in the welcome style — November 3, 2026

Two Luna agents handled the native layout and focused regression additions.
The Explore/Search primer now uses a centered accent search hero, large centered
heading, supporting introduction and welcome-style icon/feature rows. The existing
Search/filter/add education and first-visit policy remain. Its native bottom
action has a solid adaptive background, and compact windows scroll to reveal all
features. No extra collaboration copy or UI package was added.

`/tmp/gatherory-explore-welcome-style-20261103.xcresult` passes **four contextual
primer unit tests and two native UI methods**, zero failures or skips, on Duo /
iOS 27.1 in the default appearance. The welcome/first-Explore case passed in
**24.769 seconds** and the tour's Explore/Decide pointer and real Love It case in
**61.165 seconds**. Stable feature-row identifiers verify actual content, while
the native CTA is checked for a visible, hittable touch target of at least 44 points.

Visual inspection caught text showing behind the fixed action. The final footer
follow-up passes the strengthened first-Explore case in **27.623 seconds**, zero
failures/skips, in
`/tmp/gatherory-explore-welcome-style-footer-r2-20261103.xcresult`. It also scrolls
the final feature fully above the action and verifies the action remains hittable,
dismissal returns to Search, and revisiting Explore does not repeat the primer.
Both initial and scrolled captures in
`/tmp/gatherory-explore-welcome-style-footer-r2-attachments-20261103/` were inspected.
The earlier tour check precedes only that footer background adjustment.

No Light/Dark, complete device-size or full-planning matrix was rerun for this
visual change. Localization passes for 1,879 English/Spanish strings with the
existing dynamic-key advisory; `git diff --check` passes. No production deployment,
upload or package installation.

## Original welcome and contextual tab primers — November 3, 2026

Restored the original Welcome to Gatherory content before Movie Night's
Start tour / Skip choice. `OnboardingWelcomePrimer` shares the existing mark,
invitation/planning features, collaboration copy and native layout with classic
onboarding. The classic creation screen remains intact. Decide and Search are
no longer consumed before the choice: each presents on its first active tab
visit, including during the tour. Its native sheet takes priority, and dismissing
it returns to the same guide. Starting/replaying the lesson resets only its
account's tab-primer dismissals; dismissing a primer persists that account's
completion across later visits.

**Nine unit tests in two suites and four native UI methods passed across the
targeted runs**, on Duo / iOS 27.1:

| Check | Passing result |
| --- | --- |
| Contextual primer persistence/eligibility and onboarding flow | 9 unit tests |
| Original welcome → tour choice → Skip; Search only after first Explore visit, without repeating | 18.278 s |
| First Explore/Decide primers during the lesson; real control hit testing, guide resumption, Love It and Ideas | 69.566 s |
| Complete guided planning, approval, scheduling, Finish/Keep, reopen and keyboard Search | 179.068 s |
| Original classic welcome/create/skip flow | 12.635 s |

The unit tests, welcome/Skip case and first-tab/pointer case pass in
`/tmp/gatherory-welcome-contextual-primers-20261103.xcresult`. That bundle is not
wholly green: the full-tour helper still expected Search to have been consumed
before discovery. It now explicitly dismisses the first-visit Search sheet for
both discovery entry paths. The full flow passes in
`/tmp/gatherory-welcome-contextual-primers-full-r2-20261103.xcresult`, and the
default-appearance classic check passes in
`/tmp/gatherory-welcome-contextual-primers-classic-r3-20261103.xcresult`.
Application behavior is unchanged between these follow-up runs; only UI test
helpers and the classic test's appearance override changed.

Accepted UI evidence uses the default appearance; no Light/Dark or full device
matrix was rerun. Earlier account-replay evidence below describes its prior
source; the account sheet itself was not rerun in this pass. Localization passes
for 1,879 English/Spanish strings with the existing dynamic-key advisory;
`git diff --check` passes. No database reset, packages, deployment or upload.

## Standard primers before the tour — November 3, 2026

**Historical, superseded:** the restored-welcome follow-up above replaces this
ordering. Decide and Search now present on their first active tab visits; the
original general welcome content precedes the optional tour.

Movie Night onboarding now reuses the existing Decide primer, then Search primer,
before showing Start tour / Skip. Each Continue persists account-scoped education
state. Interrupted onboarding resumes the next unseen primer; starting the tour
preserves those values so they do not repeat after completion or Skip. Account's
Redo tour explicitly replays both primers before its choice. Classic onboarding
and contextual fallback for unseen education remain available. No workspace,
discovery phase or real decision is created by viewing the primers.

**Ten unit tests in two suites and five native UI methods passed across the
targeted runs** on Duo / iOS 27.1:

| Check | Passing result |
| --- | --- |
| Contextual primer policy and onboarding flow | 10 unit tests |
| Primers precede choice; Skip creates no event and Search does not repeat | 26.591 s |
| Relaunch between primers resumes Search | 18.531 s |
| Full tour: Love It, approval, scheduling, Finish/Keep, reopen and keyboard Search | 192.521 s |
| Classic override retains the original onboarding | 11.459 s |
| Account replay repeats education, resumes unfinished content, and creates a fresh lesson after completion | 123.622 s |

The ten unit tests and first four UI methods passed in
`/tmp/gatherory-primers-before-tour-20261103.xcresult`. That bundle is **not wholly
green**: its replay case used an outdated navigation-bar-only Account selector.
The intermediate R2 replay then exposed a test assumption that offscreen native
List rows already exist. The helper now supports the real adaptive toolbar and
scrolls the lazy List before requiring Redo tour to exist. The final replay
passes with zero failures or skips in
`/tmp/gatherory-primers-before-tour-replay-r3-20261103.xcresult`, superseding those
two harness failures. Application source is unchanged between these runs.

The new first-run/recovery, full-planning and final replay checks use the current
default appearance; no Light/Dark or complete device matrix was rerun. Localization
passes for 1,879 English/Spanish strings with the existing dynamic-key advisory;
`git diff --check` passes. No database, package, deployment or upload changes.

## Instructions-only tour with pill buttons — November 3, 2026

Discovery and workspace guides now show their instruction and footer without
the smiling face, title or minus button. The obsolete minimize/resume state and
mascot entry point were removed. Previous, Skip tour and Next/Finish use separate
native bordered capsule buttons; disabled actions retain native muted styling.
The rounded gradient, arrows, real-action gates and Keep/Remove confirmation remain.

**Three unit tests and two native UI methods passed**, zero failures or skips,
in `/tmp/gatherory-tour-instructions-pill-20261103.xcresult`, on Duo / iOS 27.1
using the default appearance. `testTourLayoutAndPlanningFlowOnCurrentDevice`
passed in **158.686 seconds**, covering discovery, Previous/Next, real Love It,
approval, scheduling, Finish/Keep, reopening without restarting, and keyboard
Search. `testWorkspaceGuidePointersFollowDecideAndIdeasTabs` passed in **44.355
seconds**. Updated assertions verify instruction visibility, absence of the old
heading/minimize/resume controls, full-size on-screen tappable buttons, centered
Skip tour and stable underlying event/navigation frames across tabs.

Discovery and workspace captures in
`/tmp/gatherory-tour-instructions-pill-attachments-20261103/` were inspected for
instruction-only content, visible capsule boundaries, muted disabled states,
the gradient and clear pointing arrows. No Light/Dark or full device matrix was
rerun. Localization passes for 1,879 English/Spanish strings with the existing
dynamic-key advisory; `git diff --check` passes. No production deployment or upload.

## Rounded gradient tour backdrop — November 3, 2026

The shared discovery/workspace guide now has continuous 32-point corners, a
soft outer blur and a cyan/lilac/pink/peach gradient wash. The strong adaptive
background remains beneath the colors; primary text and blue pointers stay
sharp. Reduce Transparency retains an opaque rounded background with the same
color wash. No layout space, border or shadow was added.

**Three focused unit tests and one native UI method passed**, zero failures or
skips, in `/tmp/gatherory-tour-gradient-20261103.xcresult`. Tests cover rounded
corner protection at the heading/footer insets, the outside-only linear feather,
and invalid/transient geometry. The Duo / iOS 27.1 default-appearance
`testWorkspaceGuidePointersFollowDecideAndIdeasTabs` passed in **46.197 seconds**,
including discovery, native navigation, Love It and Ideas guidance. Exported
captures in `/tmp/gatherory-tour-gradient-attachments-20261103/` were visually
checked for rounded edges, visible gradient, readable text and unobscured arrows.

No Light/Dark or full device-size matrix was rerun. This is Debug Simulator
evidence; no new Release archive, package installation, deployment or upload.
Localization verification passes for 1,879 English/Spanish strings with the
existing dynamic-key advisory; `git diff --check` passes.

## Tour overlay contrast — November 3, 2026

Discovery and workspace guides now use thick native material with a 94% adaptive
system-background wash. The fully opaque mask plateau protects the entire guide
rectangle, including the header and footer; feathering is confined to the extra
44-point area outside it. The heading and active Skip tour text use primary
foreground contrast. Workspace arrows draw above the backdrop, keeping the blue
pointer visible near the soft edge. The existing opaque Reduce Transparency
fallback remains. No border, shadow or layout-reserving card was added.

Final result: **two unit tests and one native UI method passed**, zero failures
or skips, in `/tmp/gatherory-tour-contrast-final-20261103.xcresult`. The unit tests
check full mask protection across short/tall content and its horizontal extent,
with translucent outer edges and finite ordered stops for transient geometry.
The default-appearance Duo / iOS 27.1 UI case
`testWorkspaceGuidePointersFollowDecideAndIdeasTabs` passed in **46.431 seconds**,
including discovery, native control hit testing, actual Love It input and
subsequent Ideas guidance. Captures over busy artwork were visually inspected.
The earlier passing `/tmp/gatherory-tour-contrast-20261103.xcresult` precedes only
the final arrow layering adjustment.

No Light/Dark matrix or complete phone-size/full-planning matrix was rerun for
this visual change. The following full-journey results describe their earlier
source snapshots. This pass is Debug Simulator evidence, not a new signed Release
archive. Localization remains 1,879
English/Spanish strings, with the existing dynamic-key advisory; `git diff --check`
passes. No package, shared-data, deployment or upload changes were involved.

## Movie Night tour on iPhone Duo — November 3, 2026

The preceding navigation-compatibility full guided planning journey and keyboard Search handoff passed on
iPhone Duo / iOS 27.1 in portrait. Its app window is **466 × 678 points** and
uses the native vertical toolbar, not a tab bar. The run completed in **154.995
seconds**, with one UI method and zero failures, in
`/tmp/gatherory-tour-device-duo-r14-20261103.xcresult`. It covered the real
Explore-to-Movie-Night entry, approval and scheduling, completion, and native
Search with the keyboard open.

The production native-control measurement now uses public UIKit APIs and a
bounded NSObject accessibility walk matching the exact localized label, public
identifier, and button trait. It falls back to public getters for objects that do
not declare the accessibility protocol. A hidden virtual backing control is
accepted only when it has a real finite visible frame and `window.hitTest`
confirms hit-testing. Lookup is limited to the current target and at most 12
attempts, starting after 20 ms and retrying missing frames every 150 ms. Each
walk is bounded by depth 40, 2,048 work units and validated container counts of
1–128; stale work is cancelled. The Ideas filter target is `ideas.filter`. Pointer visibility uses
the visible viewport union including the side filter, while the dialog remains
in the content lane. The discovery probe is a 1-point background inside the
visible guide. Temporary measurement logs were removed.

The UI helpers use adaptive native navigation, workspace exit, a hittable Back
control or edge swipe, and native Search Close. The screenshot evidence is from
the actual app window. A separate repeated-entry case passed on two fresh
launches in **43.684 seconds** in
`/tmp/gatherory-tour-device-duo-r13-20261103.xcresult`. R13's full case later
failed on a hidden Back selector and is superseded by R14; it is not a green
full-suite result. R13 also recorded 24 unit tests across four suites passing.

The current-source standard iPhone 18 Pro / iOS 27.0 regression also passes:
**24 unit tests in four suites and two native UI methods**, zero failures/skips,
in `/tmp/gatherory-tour-duo-standard-regression-20261103.xcresult`.
`testAdaptiveExplorePointerSurvivesRepeatedEntry` passes in 46.710 seconds and
`testWorkspaceGuidePointersFollowDecideAndIdeasTabs` in 46.012 seconds. These
verify the original tab-bar path, repeated entry, real Love It and the Ideas
filter after the adaptive-toolbar change. Earlier three-phone full-journey
evidence below predates this source; the current Pro check is focused coverage.
The default appearance was used throughout; no Light/Dark matrix, UI package,
Release archive, deployment or upload was involved.

Duo captures from the passing full journey are in
`/tmp/gatherory-tour-device-duo-r14-attachments-20261103/`, including the actual
side-filter arrow, both scheduled activities and keyboard Search. The standard
regression keeps the previously running development simulator; the Duo is
restored to its original shutdown state after the run. Localization verification
passes for 1,879 English/Spanish strings with the existing dynamic-key advisory;
`git diff --check` passes.

Intermediate attempts exposed assumptions about tab-bar-only selectors, public
getter protocol conformance, hidden backing views, startup timing and exclusion
of side controls from the pointer viewport. Those failed bundles are not green
acceptance evidence. The final full Duo result supersedes their failures. Test
helpers now find the real native toolbar controls and use a real Back action or
edge swipe, preserving the return-state assertion. No tap, alignment, workflow,
or keyboard acceptance assertion was removed.

Public `simctl` exposes two integrated display streams (1398 × 2034 and 2007 ×
2853 pixels), but no documented fold, posture, or input-routing API was available
for this run. Evidence is limited to the current app window. No expanded-window,
folded-posture, or physical-hardware behavior is claimed.

## Movie Night tour across iPhone sizes — November 3, 2026

> Historical results: this three-device run predates the latest source. See the
> current-source [Duo verification](#movie-night-tour-on-iphone-duo--november-3-2026).

At that source snapshot, the default-appearance regression completed the real tour on three
representative iPhone viewports. No app layout or device-specific offsets were
changed for this pass. Existing appearance-loop tests remain available, but were
not selected; the owner's request to skip Light/Dark mode testing is preserved.

| Simulator (iOS 27.0, portrait) | Viewport in points | Result | UI duration |
| --- | --- | --- | --- |
| iPhone SE (3rd generation), `Gatherory Tour Compact SE` | 375 × 667 | Passed | 157.189 seconds |
| iPhone 17 | 402 × 874 | Passed | 164.050 seconds |
| iPhone 18 Pro Max | 440 × 956 | Passed | 162.249 seconds |

`MovieNightOnboardingUITests.testTourLayoutAndPlanningFlowOnCurrentDevice` reuses
the complete real planning journey with no appearance launch overrides. Assertions
cover initial Explore pointing, bundled Movie Night-only selection, on-screen
guide text, 44-point footer controls (one-point rounding tolerance), nonoverlapping
footer buttons, enabled controls remaining hittable, and measured Decide/Ideas/
Home frames matching the actual native tabs within three points. Hide/Resume and
Previous/Next preserve underlying content/navigation frames and saved actions.
The case performs Love It → Liked → long-press Approve → Schedule, enters/dismisses
native sheets and detail navigation, verifies both activities on Home, completes
with Keep and reopens the event without restarting the guide.

It then returns to normal Explore, dismisses the Search primer, types `wedding`,
verifies the software keyboard and reachable native Close/Cancel, submits,
checks enabled fixture results, scrolls while retaining the query and dismisses
Search. Results and content are deterministic local fixtures; this is not a live
server/network acceptance run.

Artifacts:

- Compact: `/tmp/gatherory-tour-device-se-r2-20261103.xcresult`.
- Regular and Pro Max, run sequentially:
  `/tmp/gatherory-tour-device-regular-promax-20261103.xcresult`.
  The log reports both destination executions passed. Xcode's summary counts one
  unique method for that two-destination bundle. Across both artifacts this is
  **three passing device executions of one regression**, with no failures/skips.
- Inspected captures: `/tmp/gatherory-tour-device-se-r2-attachments-20261103/`
  and `/tmp/gatherory-tour-device-regular-promax-attachments-20261103/`.
  Recorded PNG resolutions are respectively 750×1334, 1206×2622 and 1320×2868.
- The initial compact attempt asserted the complete accessibility container bounds
  and failed because the decorative feathered blur intentionally overscans the
  display. Inspection confirmed the visible guide fit. The corrected assertion
  checks actual text and interactive controls, leaving the blur unchanged. That
  initial bundle is superseded by the passing compact rerun.
- English/Spanish verification remains **1,879 strings**, with the existing
  dynamic-key advisory. `git diff --check` passes. Only test code and docs changed.

These are simulator results for the tour and its search handoff at normal text
size in portrait. They do not prove every app screen, physical hardware, minimum
supported iOS 26, iPad layouts, landscape or accessibility text sizes. Those
acceptance boundaries remain open. No packages, backend changes, shared-account
data, release build, deployment or upload were involved. Test simulators are shut
down afterward; the preexisting running development simulator was retained.

## Planning tour tab pointers — November 3, 2026

Three Luna agents split native tab measurement, target routing/policy tests and a
focused native UI regression. The guide now points to Decide for the initial
input step, Ideas after Love It or when returning to approval/scheduling, and Home
after scheduling. On the appropriate tab, existing arrows point to the filter or
exact idea/decision card. Copy names the same next action. Earlier instruction
recaps remain unpointed. Native tab arrows have no partial outline behind the
tab bar; card/filter outlines remain. The soft backdrop and initial Explore
spotlight are preserved.

Native target measurement uses localized labels and public UIKit properties,
prioritizing visibly hosted bars with a fallback for adaptive backing containers.
It validates the actual target frame rather than relying on the container's own
bounds. Only the currently needed native target is scanned, outside layout with
cancellation guards. Accessibility-container counts are bounded before iteration,
including handling the NSNotFound sentinel. The guide remains inside the content
safe area; pointer visibility includes the measured tab bounds beyond that area.
Native arrows ignore hits and are hidden from accessibility. The isolated Debug
readout reports the rendered local target projected back into window coordinates.

Final artifact: `/tmp/gatherory-tour-pointers-final-20261103.xcresult`.
**20 unit tests in four suites plus one native UI case passed**, zero failures or
skips. The UI case `testWorkspaceGuidePointersFollowDecideAndIdeasTabs` passed in
**41.951 seconds**, using the simulator's current default appearance with no
appearance launch overrides. It traverses initial Explore and bundled selection,
checks actual Decide/Ideas target frames against native tabs, taps both, records
Love It on Popcorn bar and verifies the next filter/card focus. Unit tests cover
step/tab/filter routing, missing IDs, completed and earlier recap states, localized
tab labels, invalid container counts, pointer placement and same-window/stale
measurement boundaries. English/Spanish verification passes for **1,879 strings**;
only the existing dynamic-key extraction advisory remains. `git diff --check` passes.

The first compilation's missing explicit return was fixed. Intermediate attempts
caught rejected adaptive backing containers and an unbounded native accessibility
count that stalled workspace entry; that run was cancelled, and the final bounded,
single-target implementation passes. These attempts are superseded by the final
artifact. The preceding R5 passing run predates the final tab-outline cleanup.

At the owner's request, **Light/Dark appearance testing was not run for this
addition**; earlier appearance evidence below covers its earlier source snapshots.
Home-after-schedule targeting has unit coverage but no new full journey UI run.
This pass builds Debug for Simulator; signed Release, minimum-iOS and physical
device acceptance remain separate. No deployment, upload or shared data changed.

## Feathered guide backdrop and Explore spotlight — November 3, 2026

Both discovery and workspace guides use a feathered live native-material backdrop
instead of a bordered, shadowed card. Text, mascot and buttons stay sharp. Reduce
Transparency retains an opaque system-background fallback. No content or control
frames are moved. The first Tap Explore step dims the rest of the app, cutting out
the actual measured native tab and guide; its outline and arrow remain blue.
The overlay ignores hits and is hidden from accessibility. Overlapping cutouts
are unioned; the outer mask extends beyond the viewport to prevent bright screen
edges when feathering. The spotlight disappears after the native tab is selected.
The normal guided Explore feed and Movie Night-only selection rules are unchanged.

Validation on iPhone 18 Pro / iOS 27.0 Simulator:

- `/tmp/gatherory-tour-spotlight-20261103.xcresult`: **11 unit tests in two
  suites and two native UI cases passed**, zero failures/skips. Unit coverage
  includes target/guide cutouts, overlap, unavailable/offscreen geometry and
  existing placement boundaries. Native Light/Dark tests pass regular-feed locks,
  native search restoration (99.703 seconds) and the complete real planning tour
  through approval, scheduling, Finish and Keep (248.911 seconds).
- After the visual-only outer mask edge adjustment,
  `/tmp/gatherory-tour-spotlight-final-20261103.xcresult`: **the same 11 unit
  tests plus a new focused native UI case passed**, zero failures/skips. The new
  Light/Dark case (30.549 seconds) proves Explore is hittable through the
  spotlight, Previous returns to the same native tab frame, the guide controls
  remain tappable and Skip removes the guide without obstructing navigation.
  These bundles establish **three distinct passing UI cases**.
- Simulator captures were inspected in Light/Dark for the feathered guide and
  actual Explore-tab highlight. English/Spanish coverage remains **1,876
  strings**; the existing dynamic-key advisory in `AppCopy.swift` remains.
  `git diff --check` passes.

This slice builds in Debug for Simulator. It does not claim a new signed Release
archive, physical-device, minimum-iOS, or assistive-technology acceptance run.
No packages, server changes, shared data writes, deployment or upload were needed.

## Regular Explore tour and text navigation — November 2, 2026

The guide uses Previous / Skip tour / Next words, changing Next to Finish tour
at completion. Start points at the actual native Explore tab with a blue border
and arrow. Explore reuses the regular header, profile, native search, filter and
masonry feed; cached/online cards remain visible but disabled. Bundled Movie
Night is pinned first, deduplicated, outlined and the only selectable item.
Its local creation works without a catalog response. Feed scrolling remains
available; activation resets to the pinned card. Ads, discovery measurements and
other selection/action paths stay inactive while guided. Normal controls and
search restore after completion/skip. Keep/Remove and classic onboarding remain.

Final evidence on iPhone 18 Pro / iOS 27.0 Simulator:

- Full run: `/tmp/gatherory-tour-clarity-final-20261102.xcresult`.
  **1,269 unit tests passed**, one opt-in live-sync test skipped (1,270
  registered in 180 suites), plus **seven native UI cases passed**. One UI case
  failed because it queried the obsolete “Search blueprints” placeholder rather
  than the current “Search blueprints and ideas”; this full bundle is not green.
- Corrected search case: `/tmp/gatherory-tour-clarity-search-final-20261102.xcresult`:
  **one passed, zero failed**, 100.278 seconds. The test now locates the native
  search field directly. No app behavior changed for this correction. In Light
  and Dark it proves the actual native Explore tab remains hittable, measured
  tab/card frames match the controls within 3 points, text navigation is visible,
  other feed items/controls are disabled, and only Movie Night opens the lesson.
  After Skip → Keep, native search accepts `wedding`, returns enabled fixture
  cards and preserves the query during scrolling. This supersedes that one
  failure; **all eight distinct targeted UI cases have passing evidence**.
- Other passing UI cases cover the complete real planning journey in Light/Dark
  (247.209 seconds), replay/resume/fresh copy (95.412 seconds), intro Skip and
  Search primer (32.342 seconds), classic override (8.091 seconds), Skip → Remove
  (34.429 seconds, Light), discovery Skip without creating a workspace
  (19.911 seconds), and Skip → Keep persistence in Light/Dark (88.528 seconds).
- Generic Simulator **Release build passed for arm64 and x86_64**, signing
  disabled: `/tmp/gatherory-tour-clarity-release-20261102.log`. Existing warnings
  remain for the constant development-fixture branch and skipped App Intents
  metadata extraction. This is not a signed device archive.
- English/Spanish verification passes for **1,876 strings**. The existing
  dynamic-key extraction advisory in `AppCopy.swift` remains. Native and changed
  web-doc `git diff --check` pass.

The native tab target uses public UIKit view/accessibility geometry, with the
scan deferred outside layout. Decorative outlines/pointers are hidden from
accessibility and ignore hits, preserving the real tab/card targets. A Debug-only
isolated-test diagnostic exposes measured coordinates as a value inside the
guide; it does not cover the native control and is absent from Release. This
corrects development attempts that synchronously scanned during layout or placed
an accessible decoration over the tab. Temporary logging has been removed.

Catalog/search results in this test use deterministic fixtures. Live catalog,
authenticated reconnect, physical-device and minimum-supported-iOS acceptance
remain release checks. No shared data, schema, deployment or TestFlight upload
was changed. Earlier results below describe their respective historical slices.

## Tour completion: keep or remove Movie Night — November 2, 2026

Finish tour and in-lesson Skip now open a native Keep event / Remove event alert.
The tutorial is marked completed only after the choice; Keep leaves the complete
practice plan intact and returns Home. Remove validates the current account,
exact stored tour workspace ID, active host/manage permission, lifecycle and
normal deletion authorization, then physically removes that workspace through
the existing local persistence/outbox transaction and returns to Events. It does
not locate events by title. Intro/discovery Skip before selecting Movie Night
has nothing to remove and remains prompt-free.

Final focused result: **25 passed, zero failed/skipped** — 22 unit tests in three
suites plus three native UI cases. Artifact:
`/tmp/gatherory-tour-cleanup-final-20261102.xcresult`.

- Full Light/Dark journey with Finish → Keep: **239.145 seconds**. The native
  prompt appears after the final chevron; keeping retains both activities and
  ideas, finishes the guide, avoids hidden-tab primers and stays finished when
  the workspace is reopened.
- Skip → Remove: **30.788 seconds**, Light. The prompt's destructive choice
  removes the local lesson and returns to the main Events tab with no Movie Night
  entry. This case does not separately exercise destructive selection in Dark;
  the native alert itself is exercised in both appearances by the Keep paths.
- Skip → Keep in Light/Dark: **81.348 seconds**. The event is retained and the
  guide stays dismissed across native tab changes.
- Unit coverage includes pending local-create coalescing, exact renamed lesson
  removal with another workspace retained, normal server ACK at version 7 then
  one account-scoped delete tombstone surviving disk relaunch, preservation of
  another account's data/mutations, failed-save rollback of library order,
  selection, records and outbox, stale/replaced receipts, wrong accounts,
  non-hosts and lost manage permission. Completed receipts remain scoped for
  post-tour primers and fresh replay.
- Generic iOS Simulator **Release build passed for arm64 and x86_64**, signing
  disabled: `/tmp/gatherory-tour-cleanup-release-20261102.log`. Only the existing
  constant development-fixture branch and skipped App Intents metadata warnings
  remain. This is not a signed archive or upload.
- English/Spanish coverage passes for **1,875 strings** and `git diff --check`
  passes. The existing dynamic-key extraction advisory in `AppCopy.swift`
  remains. The earlier rollback test's reversed insertion-order expectation and
  native alert's nested accessibility-button query ambiguity are fixed; the
  passing final bundle supersedes the initial attempt.

The save and delete paths are local and offline-capable; the server ACK test
uses the real local acknowledgement API with synthetic responses, not a live
server deletion. Production reconnect, physical device and minimum-iOS remain
release acceptance checks. No live account data, schema, server, production
rollout, or TestFlight build was changed for this slice.


## Explore-first tour and chevron navigation — November 2, 2026

The intro primer still offers Start tour or Skip. Start now records a durable,
account-scoped entry phase and prompts the real Explore tab; it creates no plan.
Guided Explore shows only the bundled Movie Night card. Selecting it creates or
resumes the ordinary local owned lesson through the existing transaction/outbox.
Previous on Explore returns to the Events prompt. Preselection Skip creates no
lesson and restores normal Explore and its Search primer. Both entry and workspace
coaches have dialog-wide Previous / centered Skip tour / Next controls with 44pt
hit targets. Next waits for actual actions; Previous reviews completed steps as
recaps without reversing votes, approval or scheduling. Old target pointers are
suppressed for recap steps. Classic onboarding/auth routing stay intact.

Current native results on standard iPhone 18 Pro / iOS 27.0, PostHog disabled:

- Full unit portion: **1,259 registered in 177 suites; 1,258 passed and one opt-in
  live sync test skipped**, zero unit failures. Log:
  `/tmp/gatherory-explore-tour-final-r2-20261102.log`; result bundle:
  `/tmp/gatherory-explore-tour-final-r2-20261102.xcresult`. That bundle also holds
  an earlier UI attempt that used the removed Done-button identifier; its UI
  failure is superseded by the final journey below. The entire earlier bundle
  must not be described as passing.
- Final full Light/Dark UI journey: **passed, 234.345 seconds**. Artifact:
  `/tmp/gatherory-explore-tour-journey-final-20261102.xcresult`. It verifies Start
  with no workspace, native Explore, one bundled choice/no live cards or Search
  primer, Previous back to Events and return, actual local copy, unchanged Home
  frames on hide/resume, real Love It, reviewing the earlier instruction without
  losing the response, Next disabled until approval, Liked/detail push-back,
  native approval and Schedule sheets, two Home activities, Finish tour using the
  right chevron, no hidden-tab primer, and persistent completion on reopening.
  It also measures Skip centered between the chevron controls.
- The other **five focused UI cases passed** in
  `/tmp/gatherory-explore-tour-r2-20261102.xcresult`: account replay via Explore
  (**77.049 seconds**), intro Skip/Search primer in Light/Dark, classic override
  (**8.328 seconds**), discovery Skip/no workspace/normal searchable Explore
  (**20.964 seconds**), and guide Skip across Light/Dark (**68.350 seconds**).
  The earlier failed full journey in that bundle is superseded, not an extra
  passing test; there are six distinct passing UI cases across these runs.
- Final unsigned generic iOS Simulator **Release build passed for arm64 and
  x86_64**: `/tmp/gatherory-explore-tour-release-final-20261102.log`. Only the
  existing constant development-fixture branch and skipped App Intents metadata
  warnings remain. This is a local build, not a signed archive or upload.
- The final disabled-control styling check passed the discovery-Skip case again
  (**21.528 seconds**): `/tmp/gatherory-explore-tour-final-skip-20261102.xcresult`.
  Locked Events actions are visibly disabled during entry; the overlaid Skip
  remains interactive and restores the normal searchable surface. This is the
  same UI case repeated after the styling change, not a seventh distinct case.
- Discovery tests cover phase restoration/account isolation, no planning data on
  Start, selection blocked before Explore, bundled local creation/outbox,
  failed-save retry/no orphan state, and wrong-account protection. Navigation
  tests cover earlier-step bounds, real-action gates, recap detection and final
  schedule readiness. Primer and deletion tests cover the discovery phase too.
- Localization coverage passes for **1,870 English/Spanish strings**; only the
  existing nonliteral-key extraction advisory in `AppCopy.swift` remains.
  `git diff --check` passes. Ten automatic journey captures were exported; Events
  prompt, sole Movie Night selection in Light/Dark, and the new footer were
  visually reviewed. No oversized UI scenarios were added.

The initial missing environment binding and switch-return compile errors, stale
previous-instruction expectation, and removed Done-button probe are fixed. Initial
sign-in/account preparation retains its existing network/cache requirements;
tour entry and the lesson use local content afterward. Normal Explore remains
server-backed. Signed-device/minimum-supported-iOS and authenticated production
reconnect remain release acceptance checks. No DB reset, seed, migration, server
start, production deployment or TestFlight upload was performed for this slice.


## Bundled offline tour, replay, and post-tour primers — November 2, 2026

First run now offers Start tour or Skip only. The app loads its shipped Movie
Night blueprint and saves an ordinary account-owned local workspace plus durable
sync outbox, without a remote catalog/installation request. Account → Redo tour
reuses an unfinished valid lesson or creates one fresh copy after completion or
missing/deleted targets; earlier content is preserved. The intro explains that
people can delete the practice event. Contextual Decide and new Search primers
wait for tour completion/skip and their active tab, with per-account dismissals.
The original classic onboarding and authentication/recovery chain are preserved.

Current native verification:

- Full unit suite: **1,250 registered tests in 175 suites; 1,249 passed and one
  opt-in live sync test skipped**, zero failures. The same result bundle also
  contains one passing Account replay UI method; its top-level summary is 1,250
  passed / one skipped. Do not count that repeated UI method twice. Artifact:
  `/tmp/gatherory-bundled-tour-replay-20261102.xcresult`.
- Final focused native UI suite: **5 passed, zero failures**, standard iPhone 18
  Pro / iOS 27.0, PostHog disabled, ephemeral data. Artifact:
  `/tmp/gatherory-bundled-tour-ui-final-20261102.xcresult`.
- Account replay: **34.323 seconds**. Minimized unfinished replay restores the
  guide without duplicating the event; completed replay preserves the earlier
  event and creates one fresh lesson. Decide education is eligible afterward.
- Start/Skip and Search primer in Light and Dark: **32.228 seconds**. No catalog
  preview/Discover/blank-plan choice is offered; Skip creates no lesson. Search
  education appears on Explore and stays dismissed after switching away/back.
- Preserved classic onboarding override: **8.032 seconds**.
- Full Light/Dark lesson: **187.277 seconds**. Real Love It → Liked → detail
  push/back → long-press approval → Schedule creates the second activity. Native
  sheets suppress the guide, hide/resume leaves content frames unchanged, Done
  from Decide returns Home without a hidden-tab primer, and reopening preserves
  completion. Skip in Light/Dark remains dismissed across tabs: **35.047 seconds**.
- Unit coverage includes loading the actual app-bundle resource, stable blueprint
  key-to-ID mapping, canonical host/child participation, real actions surviving
  disk relaunch with identical queued mutation IDs, scheduled-but-unfinished
  replay, missing/deleted targets, account/authority isolation, malformed data,
  failed-save rollback/previous-selection recovery, primer gating and scoped
  account deletion cleanup.
- Unsigned generic iOS Simulator **Release build passed for arm64 and x86_64**.
  Log: `/tmp/gatherory-bundled-tour-release-final-20261102.log`. The new tour's
  actor-initialization warning is resolved. Only the existing Release-constant
  fixture branch and skipped App Intents metadata warnings remain. This is not a
  signed device archive or upload.
- A final MainActor-safe default-store initialization cleanup passed all **22
  focused regressions in four suites** (tour creation/progress, primers, and
  account cleanup), zero failures. Artifact:
  `/tmp/gatherory-bundled-tour-focused-final-20261102.xcresult`.
- English/Spanish localization coverage passes for **1,857 strings**. The existing
  nonliteral-key extraction advisory in `AppCopy.swift` remains. `git diff --check`
  passes. Intro, Search primer and mascot captures were visually reviewed in
  standard Light and Dark; no oversized UI scenarios were added.

The initial compile's complex test expressions and first replay test's ambiguous
Account-button query are fixed and superseded by these passing runs. Tests prove
local creation/recovery without a tour network dependency, not live reconnect
acceptance with the production server. Initial sign-in/account preparation still
uses the established authentication contract. Explore data remains server-backed.
No DB reset, migration, server seed, deployment, TestFlight upload, or production
change was performed for this slice. Signed-device/minimum-iOS and authenticated
reconnect acceptance remain release checks.


## Control-pointing Movie Night mascot overlay — November 2, 2026

The coach now floats above the existing layout through SwiftUI overlay, rather
than reserving a top safe-area inset. A native-drawn mascot delivers one short
instruction. Measured anchors identify the actual current decision card, idea
card, or native filter. Pointer/highlight decoration passes touches through;
the dialog's buttons and minimized mascot remain interactive. Real card swipes,
native filtering, and long-press menus retain their behavior. Hide/resume state
is shared across tabs, and native tab selection advances the introduction.
The classic onboarding screen and authentication chain remain unchanged.

The native filter's separate toolbar hosting hierarchy uses noninteractive
UIKit window-space probes and same-window projection. Bubble safe bounds are
separate from target visibility, so toolbar targets can be highlighted without
putting the dialog over native navigation. The last actual filter survives
push/back; missing preferences cannot turn Liked back into All guidance. The
coach yields to pushed idea details, approval and Schedule sheets. Account,
workspace, host, exact-target, Skip/Done, deleted-target and persistence rules
remain those of the existing Movie Night receipt.

**Final regression:** `/tmp/gatherory-tour-overlay-regressions-20261102.xcresult`
reports **1,237 passed, one skipped, zero failures**. Swift Testing registered
1,235 tests in 173 suites and passed in **27.841 seconds**; one independent-client
live sync test remains opt-in and skipped without its credentials. The xcresult
summary includes three native UI methods:

- Classic fallback and override: **14.822 seconds**.
- Full planning journey in Light and Dark: **212.115 seconds**. It compares Home
  card/native navigation frames before and after hiding/resuming to **1 point**,
  verifies minimization across tabs, checks the measured focus belongs to the
  actual Popcorn decision card and native filter, performs the real swipe, and
  checks detail push/back plus Liked context before long-press approval. Both
  native sheets hide the guide. Schedule creates the second activity; Done and
  reopening preserve completion.
- Skip in Light and Dark: **71.261 seconds**, including actual native-tab
  navigation, immediate dismissal, and no return on subsequent tab changes.

Runs use standard iPhone 18 Pro / iOS 27.0, ephemeral data, PostHog disabled, and
local protocol responses through the real installation coordinator. Six automatic
attachments cover setup, actual card pointing, and completion in both appearances.
The Light/Dark card-pointing captures were visually reviewed. Earlier compile,
host-mount, toolbar-target and stale-filter failures are superseded by the final
bundle. No oversized native UI scenarios were added. The new geometry tests cover
clipping, offscreen/missing targets, narrow safe bounds, exposed regions on large
cards, zero/nonfinite inputs, toolbar targets outside bubble bounds, same-window
projection, and invalidated/dismantled probe callbacks.

**Release:** `/tmp/gatherory-tour-overlay-release-20261102.log` reports
`BUILD SUCCEEDED` for `generic/platform=iOS Simulator`, Release, arm64 and x86_64,
with `CODE_SIGNING_ALLOWED=NO POSTHOG_ENABLED=NO`. Existing warnings remain for a
constant-false fixture branch and skipped App Intents metadata extraction. This
is not a signed device archive or live service-delivery acceptance.

Localization passes for **1,841 English/Spanish strings** with the existing
nonliteral extraction advisory. Tracked and new-file whitespace checks pass.
No package, shared database seed/reset, production deployment, or TestFlight
upload was performed. VoiceOver/Reduce Motion/Transparency settings are respected
by source behavior; a physical-device assistive-technology acceptance run is
still separate. The live catalog and signed-device limits in the [onboarding
architecture](movie-night-onboarding.md) remain open.

## Movie Night onboarding — November 2, 2026

This initial inset-based presentation is superseded by the mascot overlay record
above; the following results document its earlier implementation.

The new first-run experience is selected after the existing authentication chain.
The original `OnboardingView` and `AuthenticationFlow.swift` remain unchanged.
Both onboarding entry destinations use one presentation selector; Start with a
blank plan and `-ClassicOnboarding` select the preserved flow.

Movie Night uses the ordinary Blueprint preview and Use coordinator, including
explicit date confirmation, private-copy receipt, durable import, and workspace
opening. A device-local, account-specific receipt records the exact installed
workspace and guided idea IDs. The coach advances from the current user's real
Love It response, snack approval, and linked scheduled movie activity. Undo
returns to the corresponding instruction. Customized-away or deleted targets
end education without mutating content or claiming completed planning actions.
Account deletion removes only the deleted account's receipt; stale catalog loads
cannot publish a previous account's card or action store.

**Full native regression:** `/tmp/gatherory-movie-night-final-20261102.xcresult`
reports **1,224 passed, one skipped, zero failures**, including two UI methods.
Swift Testing registered 1,223 tests in 171 suites; the opt-in independent-client
live sync test was skipped because live credentials were not supplied. Coverage
includes selector/fallback policy, per-account progress reload, malformed and
legacy receipts, exact-target action progression, Undo, removed targets, cleanup
isolation, existing authentication boundaries, approval, and event scheduling.
The companion log is `/tmp/gatherory-movie-night-final-20261102.log`.

**Final native UI rerun:**
`/tmp/gatherory-movie-night-navigation-20261102.xcresult` passed both methods.
Catalog unavailable → classic create/skip, and the dark classic override passed
in **17.435 seconds**. The full tour passed in Light and Dark in **158.376
seconds**: preview Save changes state, Use confirms both dates and imports,
Decide Love It → Ideas Liked → long-press Approve, then Schedule Watch the movie
creates the second activity. Done persists and reopening does not show the guide.
The Events navigation control remains hittable during coaching. The guide is
mounted within each navigation root, below native toolbars. Four automatic test
attachments cover setup and the saved plan; the final Light/Dark plan attachments
were visually reviewed for toolbar overlap. These runs use iPhone 18 Pro / iOS
27.0, ephemeral data, and local protocol responses through the actual installation
coordinator; they do not create a live server account or exercise a deployed
catalog. No oversized-layout tests were added.

**Release build:** `xcodebuild build -project Gatherory.xcodeproj -scheme
Gatherory -configuration Release -destination 'generic/platform=iOS Simulator'
CODE_SIGNING_ALLOWED=NO POSTHOG_ENABLED=NO` passed for arm64 and x86_64.
Log: `/tmp/gatherory-movie-night-release-20261102.log`. Existing warnings remain
for a constant-false Release fixture branch in GatheroryApp and skipped App
Intents metadata extraction. There are no build errors. This is an unsigned
simulator build, not a signed device archive or service-delivery acceptance.

English/Spanish localization coverage passes for **1,828 strings** with the
existing nonliteral extraction advisory. The bundled Movie Night JSON exactly
matches the server contract example. Source diff/whitespace checks pass.

The web work reports **169 test files passed / 46 skipped**, with **1,012 tests
passed / 74 skipped**, plus passing typecheck and contract checks. Effect remains
4.1.1. A checked-in pnpm patch corrects Drizzle rc.4's removed TaggedErrorClass
references; the bare adapter import and focused regression pass. These counts
are separate from native results and must not be added to older slice totals.

No shared database reset, catalog seed, production deployment, or TestFlight
upload occurred. Live acceptance still requires additive `movie_night` catalog
seeding in the intended environment, authenticated installation, relaunch/offline
recovery, and a signed candidate. See [flow architecture and live acceptance
boundaries](movie-night-onboarding.md).

## Ideas Liked and approval shortcuts — November 2, 2026

Ideas now filters the current viewer's personal Love It responses through Liked,
independently of shared Shortlist and Blueprint Likes. Event scope, blocked
creators and masonry remain intact. Long-press and accessibility actions open
Approve for pending non-event ideas and the existing Schedule sheet for event
ideas. Detail Approve uses the same new native confirmation sheet. Cancel does
not mutate; confirmation uses existing expense/status reconciliation and
preserves the Liked collection and personal response.

**29 focused units in five suites passed**:
`/tmp/gatherory-ideas-approval-units-20261102.xcresult` (`TEST SUCCEEDED`).
Seven new approval/filter cases cover account-bound preferences, exact retries,
stale source/account/permission boundaries, missing/stale parents, draft parent
preservation, expense targeting, and planning-only invitation visibility. Existing
filter, event Schedule, linked-event and budget regressions are included. Permission
loss is tested through normalized event participation, not just cached member
metadata. The original one-argument filter API remains available for existing
filter predicates.

**Two native UI methods passed in Light and Dark**:
`/tmp/gatherory-ideas-approval-ui-final-20261102.xcresult` (`TEST SUCCEEDED`).
Event long-press Schedule → date/location sheet → Cancel passed in **43.327
seconds**. Decide Love It → Ideas Liked → long-press Approve → Cancel/reopen →
Confirm → Approved filter passed in **84.764 seconds**. Both Cancel and approval
retain the personal Liked collection; confirmation retains one idea. The harness
checks actual filtered content rather than relying on a native Menu exposing an
accessibility value. Runs use ephemeral seeds, no screenshots and no server writes.
Earlier compile/harness/fixture-failure bundles are superseded by these artifacts.

Approval of a non-event idea does not approve or schedule its parent. A positive
estimate becomes a committed expense for the exact event. A dated draft can
already appear to authorized planners, and invitation visibility remains a
separate policy. See [behavior and parent-event semantics](ideas-liked-and-approval.md).

English/Spanish coverage passes for **1,807 strings** with the existing nonliteral
extraction advisory. Tracked diffs and new-file whitespace checks pass. No database
migration, production deployment or TestFlight upload occurred. Live cross-device
acceptance and signed-candidate validation were not run for this native UI slice.

## Idea and Decide author photos — November 2, 2026

Replaced the generic submitter icon with the actual linked author's avatar in
both live card footers and Shared by / Proposed By metadata. The shared view
keeps a 26-point footprint and preserves names, accessibility and edit actions.
Only exact account IDs resolve a photo; unknown/legacy authors retain the icon,
and known people without a photo retain initials. No public-profile lookup or
server/schema change was added.

**Seven unit tests and one native UI method passed**. The UI method covers both
Ideas and Decide in Light and Dark using the birthday fixture, taking **59.492
seconds**. Result: `/tmp/gatherory-author-avatars-20261102.xcresult` (`TEST
SUCCEEDED`); matching `.log` records the checks. It takes no screenshots or
votes. Localization coverage passes for 1,800 English/Spanish strings;
`git diff --check` passes. Live remote photo downloads and pixel comparisons
were not part of this fixture run. See [author-photo behavior](idea-author-attribution.md).
No production deployment or TestFlight upload occurred.

## Ads across all Explore channels — November 2, 2026

All, Blueprints and Ideas now allow native ads in browsing and typed search.
The shared lazy masonry renderer inserts separate ad placements after organic
items 6, 18, 30 and so on, counting both card types in All. Organic relevance
order, consent/NPA gates, three-ad inventory bounds and safe below-viewport
admission remain intact. Recent history and private planning remain ad-free.
No query, account or event values were added to SDK request targeting.

The native UI evaluation found that searching Ideas after scrolling could leave
the new result set partway down. Native `ScrollPosition.scrollTo(edge: .top)`
now resets the position for a new query without rebuilding the native scroll/search
hierarchy; page appends retain the browsing position. An intermediate `.id`
rebuild triggered repeated 60-second XCTest animation waits on short searches
and was removed. The corrected short-result search/Cancel flow passed in
**23.980 seconds**, with no animation timeout:
`/tmp/gatherory-ads-native-scroll-cancel-20261102.xcresult`.
An earlier harness run also needed its native menu selector scoped to avoid
matching the Blueprints tab. The final channel tests cover searching after
scrolling and finding the first organic result.

On iPhone 18 Pro / iOS 27.0, the final run passed **24 focused units in six
suites** covering channel eligibility, spacing, consent/configuration guards,
placement stability, inventory suspension, idea paging and mixed projections.
Real Google sample ads became visible on all three channels in browse and typed
search, in **Dark (93.814 seconds)** and **Light (93.093 seconds)**. The existing
Light/Dark no-layout-shift test passed in **23.765 seconds**. The 80-idea paging
regression passed in **29.583 seconds**, retaining one request / 20 initially,
then two requests / 40 after scrolling rather than draining all pages.

Final result: `TEST EXECUTE SUCCEEDED`, **24 units plus four UI methods**:
`/tmp/gatherory-ads-native-scroll-final-20261102.xcresult` (matching `.log`).
Together with the separate passing Cancel method, this is **24 units and five
UI methods** on the final native-scroll implementation. Earlier selector-failure
and interrupted animation-wait bundles are superseded by these final artifacts.
English/Spanish coverage passes for 1,800 strings; `git diff --check` passes.
The existing nonliteral localization extraction advisory remains.

Sample-ad tests use Google's complete sample app/native-unit pair as command-line
build overrides; checked-in Debug and Release configuration remain unchanged.
No live ad or CTA was clicked. Regional UMP choices and live production fill
were not evaluated by this sample-inventory run. No production deployment or
TestFlight upload was performed.

## Explore Ideas lazy paging — November 2, 2026

Ideas now uses AdaptiveLazyMasonry and positive scroll-visibility triggers for
the last four loaded cards. All uses the same visibility condition for idea
pagination. Source page size remains 20; filter/tab returns reuse the loaded
stream. Offscreen creation can no longer start successive page requests.

The new 80-item/four-page fixture and native paging UI method passed in
**30.573 seconds** on iPhone 18 Pro / iOS 27.0. It verifies one request / 20
loaded on entry and after filter/tab changes, the last first-page card remaining
unmounted initially, then two requests / 40 loaded after scrolling. The final
80th card remains unmounted. The focused nine feed/projection units passed.
Result: `/tmp/gatherory-idea-lazy-paging-20261102.xcresult`; matching log:
`/tmp/gatherory-idea-lazy-paging-20261102.log`.

The same run passed Cancel (**23.635 seconds**) and the complete Light/Dark
main/child add-and-Added flow (**98.907 seconds**): `TEST SUCCEEDED`, three
native UI methods and nine focused units. English/Spanish coverage remains
green for 1,800 strings with the existing nonliteral extraction advisory.

The fixture counts native fetch invocations; this is not a live-server latency
measurement. The server still scans the public catalog and ranks candidates
before slicing its response, as documented in the [flow guide](explore-idea-discovery.md).
No backend, dependency, schema or production deployment changed.

## Add completion and Explore Added markers — November 2, 2026

A durable successful add closes the destination sheet, then the idea detail,
returning to the current Explore query/filter. Both All and Ideas cards overlay
Added without changing geometry. Added remains informational; the detail still
permits another intentional Add to Event. Cancel retains the detail and does
not mark the card; failed image/save paths retain their previous recovery.

Account-scoped identity-only receipts persist on this device. Badge projection
requires the matching copy and active readable membership; removed/deleted
destinations and other accounts cannot inherit the mark. Temporary library
loading gaps retain receipts. Delayed sheet completions check account and store
generations, including A→B→A. Account deletion clears only its receipt namespace.

The final run passed **1,202 registered native unit tests in 166 suites**
(1,201 executed; the opt-in live sync test skipped), including six receipt-store
tests. Two native UI methods passed on iPhone 18 Pro / iOS 27.0: Cancel returning
to detail without a mark (**23.528 seconds**), and the complete Light/Dark
main/child add flow (**94.698 seconds**). The latter verifies both sheets close,
the Garden query and Ideas scope remain, the card reads Added, repeat-add is
enabled, and the copied idea is present in the chosen event.

Result: `/tmp/gatherory-added-idea-final-20261102.xcresult`; matching log:
`/tmp/gatherory-added-idea-final-20261102.log` (`TEST SUCCEEDED`). Localization
coverage passes for **1,800 English/Spanish strings**, with the existing
nonliteral extraction advisory. No manual screenshots, large-layout matrix,
backend, schema, shared-account mutations or deployment changed. Cross-device
Added state is outside this local receipt implementation.

## Flat Explore and workspace destination masonry — November 2, 2026

Explore uses one selected-value native menu (All by default), with no Search
title, filter icon or Ideas/More section. All mixes content in one masonry feed.
First-page coordination removes request-arrival ordering differences; a cached
projection appends later pages without shifting existing identities. Idea card
height estimates match their rendered category aspect ratio. Existing Blueprint
ad anchors, source IDs and impression rules remain scoped to Blueprint cards.

Add to Event shows searchable workspace masonry, then pushes image cards for
that workspace's main event and eligible children. Search matches only eligible
content; opening a match restores all eligible choices. Child write access is
retained when the main event is view-only. Exact account/destination checks and
durable add/retry behavior are retained.

The full native unit target passed **1,196 registered tests in 165 suites**,
with the opt-in live sync test skipped (1,195 executed):
`/tmp/gatherory-destination-masonry-final-20261102.xcresult`. This includes nine
new projection cases and five mixed-feed ordering/cache cases. The existing
Light/Dark Blueprint discovery-session method separately passed in **75.664
seconds** in `/tmp/gatherory-flat-explore-picker-20261102.xcresult`.
The final native add journey passed in Light/Dark in **90.831 seconds**:
`/tmp/gatherory-masonry-picker-ui-20261102.xcresult` (`TEST SUCCEEDED`). It
verifies the value menu, absent Ideas/More and Search headings, discovery query,
local child-title search, main/child choices, native Back with retained query,
explicit confirmation, and the resulting copy in the event's Ideas tab. Light
selects the main event; Dark selects Ceremony. An earlier harness tapped the
underlying detail sheet's Done button; the final check scopes Back to the
destination navigation bar. The earlier missing child-screen Add toolbar was
fixed by attaching confirmation directly to that destination screen.
English/Spanish coverage passes for **1,798 strings**, with the existing
nonliteral AppCopy advisory. No shared database, backend or deployment changed.

## Explore toolbar filter — November 2, 2026

All / Blueprints / Ideas moved from a segmented row into a native toolbar Menu
above the Search title. The icon-only filter stays available during typed
search; All remains the initial selection. The same menu retains explicit
Refresh. The native add journey now opens the filter menu and checks the actual
mixed All feed before choosing Ideas, then types a query and completes the
existing destination/add/find-in-Ideas flow. The discovery-session regression
opens the menu before Refresh, preserving its session and return-position checks.

Both native UI methods passed in Light and Dark: discovery-session/menu Refresh
in `/tmp/gatherory-explore-filter-menu-20261102.xcresult`, and the final
default-All/menu selection/search/add journey in
`/tmp/gatherory-explore-filter-final-20261102.xcresult` (`TEST SUCCEEDED`). The
first combined run's add method failed because UIKit reports an empty Menu
accessibility value; its default assertion now checks the visible mixed feed.
English/Spanish coverage passes for 1,793 strings with the existing extraction
advisory; `git diff --check` passes. No backend or deployment changed.

## Explore individual ideas and Add to Event — November 2, 2026

See [the V1 implementation and acceptance record](explore-idea-discovery.md)
for the new All / Blueprints / Ideas surface, native destination sheet,
source-authorized image copying and durable offline add. The complete Light/
Dark typed-search/add-and-find-in-Ideas journey passed in 67.019 seconds, along
with 21 focused native units. The full unit run passed 1,182 registered tests /
163 suites, with the opt-in live sync case skipped (1,181 executed). The
existing Blueprint browsing-session Light/Dark UI regression also passed in
72.244 seconds. The final unsigned Release simulator build also passed.
Relevant result bundles and acceptance limits are recorded in that guide;
no deployment was performed.

## Events tab bar and V1 checkpoint — November 2, 2026

The root tab view uses native `.never` minimization for Events and retains
`.onScrollDown` for Blueprints and Explore. `events.list` identifies the Events
scroll surface without changing its layout. The new
`EventsTabBarUITests.testEventsKeepsAllMainTabsExpandedWhileScrollingInLightAndDark`
passed on iPhone 18 Pro / iOS 27.0 in **39.426 seconds**. It scrolls the Events
list three times, checks that all three tabs stay directly accessible at the
expanded height, switches to Blueprints and back, then checks upward scrolling.
Both appearances use the existing ephemeral date-ordering fixture.

Result: `/tmp/gatherory-events-tab-bar-20261102.xcresult`; log:
`/tmp/gatherory-events-tab-bar-20261102.log` (`TEST SUCCEEDED`). A generic
unsigned Release simulator build also passed; log:
`/tmp/gatherory-v1-release-build-20261102.log` (`BUILD SUCCEEDED`). Remaining
warnings concern an unreachable Release fixture branch and absent App Intents
metadata. The focused UI run compiled the app and both test targets; the full
unit suite was not repeated for this native tab policy change.

No manual screenshots, large-layout matrix, new dependencies, server changes,
shared account mutations, uploads or deployments were performed. Physical-device
gesture acceptance and a signed archive remain unverified in this pass. See
the [V1 checkpoint](v1-release-checkpoint-2026-11-02.md) for prioritized release
gates and the distinction between source checks and live acceptance.

## Home and Events date ordering — November 2, 2026

Home retains the main event at the top and orders child events by current/
upcoming dates, recent past dates, then undated items. Overview keeps date rows
and chronological times within a day; Cards and its rail use the same date
policy. Events applies date ordering to each filtered result. Existing filter
membership, permission checks, selection and persisted record order are retained.
See [Home event layouts](home-event-layouts.md#date-ordering).

`EventDateOrderingTests` covers shuffled library insertion order, recent-first
past results, undated placeholders, multi-day/all-day events ending today,
event-local midnight boundaries, stable identity ties, grouped time ordering,
and unchanged selection/library/timeline. Existing Home projection tests cover
guest scope, archived children and main-event deletion. Their fixed historical
timezone fixture now supplies an explicit reference date.

The final full native unit run passed **1,161 registered tests in 159 suites**
(one opt-in live sync test skipped; 1,160 executed). The native UI method
`EventDateOrderingUITests.testEventsAndHomeStartWithUpcomingDatesInLightAndDark`
also passed in **35.156 seconds** on iPhone 18 Pro / iOS 27.0. It verifies that
Events opens with the nearest upcoming gathering, Home keeps its main card
above correctly ordered date rows, same-day events remain chronological, and
Cards leads with the main event then today's child, in Light and Dark.
Layouts launch independently because command-line preference values override
settings changes; the earlier failed fixture-switch run is not acceptance.

Result: `/tmp/gatherory-date-ordering-verified-20261102.xcresult`; log:
`/tmp/gatherory-date-ordering-verified-20261102.log` (`TEST SUCCEEDED`).
No manual screenshots, large-layout tests, new dependencies, backend edits,
shared data changes or deployment were performed.

## Invitation management shortcut removal — November 2, 2026

The invitation toolbar no longer repeats the Manage action. Management stays
on the preceding Home card's footer; invitation sharing, actions and editing
remain available through their existing controls.

The focused native build and two UI regression methods passed on iPhone 18 Pro /
iOS 27.0. The main-event Light and subevent Dark scenarios verify the missing
invitation Manage button, retained share/actions controls, native Back to Home,
the original Manage footer opening the correct event dashboard, and Back to
Home. The guest scenario verifies management remains unavailable. Result:
`/tmp/gatherory-invitation-manage-removal-20261102.xcresult`; log:
`/tmp/gatherory-invitation-manage-removal-20261102.log`
(`TEST SUCCEEDED`, two methods, zero failures). `git diff --check` passed.
No manual screenshots, new copy, packages, web changes or deployment were needed.

## Team budget implementation and mobile acceptance — November 2, 2026

The [team budget safety implementation](team-budget-safety.md) is verified
locally on the mobile side. Paid records retain their amount/status across idea
edits and withdrawal; budget changes require management authority; unaffordable
Schedule requests fail before mutation. Allocation edits use one versioned
whole-budget command with immutable retry identities and conflict review.

Account now confirms **Use shared budget** with a native alert containing
explicit Cancel and destructive actions. The earlier confirmation dialog was
presented as a popover without a Cancel button. Accessibility inspection
identified that presentation difference; the final UI test exercises the alert
instead of treating the missing action as a timing failure.

The complete native unit target passed **1,154 registered tests in 157 suites**,
with the one opt-in live development sync test skipped (1,153 executed). No
known-issue expectations were recorded in this run. The same build passed all
three native UI methods on Gatherory MCP Dev / iPhone 18 Pro / iOS 27.0:

- Host Light budget navigation, allocation draft cancellation and direct Back:
  **27.271 seconds**.
- View-only collaborator Dark budget visibility with editing disabled:
  **15.178 seconds**.
- Account conflict recovery in Dark, Cancel retaining intent, confirmation
  restoring shared $600/$400 allocations and preserving the local event title:
  **28.693 seconds**.

Result: `/tmp/gatherory-budget-mobile-20261102.xcresult`; log:
`/tmp/gatherory-budget-mobile-20261102.log` (`TEST SUCCEEDED`). Earlier failed
October 30 bundles remain diagnostic evidence, not final acceptance.

Two additional inbound `BudgetNativeWireTests` then passed in a focused run.
They decode numeric major-unit expense/cap values through the archive codec,
bootstrap and pull; exercise native `foodAndDrink`, explicit null allocations,
25,001 integer cents and the exact maximum `999999999999.99`; and reject money
encoded as strings. Result:
`/tmp/gatherory-budget-native-wire-20261102.xcresult`; log:
`/tmp/gatherory-budget-native-wire-20261102.log` (`TEST SUCCEEDED`). These two
tests were added after the full-suite run and are reported separately.

The user's separate web Decimal.js agent was contacted through its existing
Codex chat. That agent owns web/server calculations and projections. The
agreed contract retains Foundation Decimal in iOS, JSON numbers for archive
money, integer cents/explicit nulls for budget commands, and decimal database
values. No JavaScript money dependency was added to iOS. Server/database test
results belong to that agent's acceptance record; this mobile verification
does not claim a deployed end-to-end test.

The coordinated web agent subsequently reported **eight passing isolated
PostgreSQL budget integration tests**, including paid-expense rehoming before
child deletion, replacement with the post-delete allocation vector, numeric
archive/event/pull projections, and native `foodAndDrink`. That work also removes
deleted children from the compatibility timeline and rehomed paid rows from
their former child archive. These are that agent's executed server results,
not tests re-executed by this mobile chat. Its broader web suite was still
running when the initial update arrived. Its final handoff then confirmed
typecheck and contracts passed, **962 web tests passed with 74 skipped**, and all
eight opt-in budget database tests passed. Prettier and `git diff --check` passed;
the disposable PostgreSQL container was stopped and removed. The server handoff
is recorded in web `docs/development/money-arithmetic.md` and
`docs/development/team-budget-sync.md`. No deployment is implied.

English/Spanish localization coverage passed for **1,769 strings** with the
existing nonliteral AppCopy extraction advisory. `git diff --check` passed.
No manual screenshots, large-layout matrix, shared account budget writes,
database reset, dev-server startup, production deployment, TestFlight upload or
Git commit was performed. Physical-device radio-off/relaunch and real two-account
acceptance against the matching server build remain release checks.

## Team budgeting audit — October 30, 2026

Luna agents audited native budget commands, UI permissions and the server sync
protocol. See [the findings and recommended build order](team-budget-audit-2026-10-30.md).
Only synthetic regression tests and documentation were added in this pass;
budget behavior was not changed.

The final focused native run passed **28 tests in four suites with seven known
issue expectations**: `TeamBudgetAuditTests`, `WorkspaceBudgetRulesTests`,
`IdeaBudgetTests` and `ManageBudgetTests`. Result:
`/tmp/gatherory-team-budget-audit-unit-accepted-20261030.xcresult`; log:
`/tmp/gatherory-team-budget-audit-unit-accepted-20261030.log`
(`TEST SUCCEEDED`). Expected failures reproduce contributor cap-write authority,
Paid status loss on note edits, Paid record removal on archival, silent Schedule
funding failure, negative values at a trusted local replacement boundary, and
concurrent allocation overrun. Seven expectations do not mean seven independent
production defects, and this accepted run does not establish budget correctness.

Both screenshot-free native UI scenarios passed on the standard iPhone 18 Pro
simulator: host Light in **27.671 seconds**, and view-only collaborator Dark in
**14.821 seconds**. They verify scoped Budget navigation, root allocation draft
editing/cancellation, unchanged allocation on reopening, direct Back navigation,
and disabled allocation controls for a read-only collaborator. Result:
`/tmp/gatherory-team-budget-audit-final-20261030.xcresult`; log:
`/tmp/gatherory-team-budget-audit-final-20261030.log` (`TEST SUCCEEDED`).
This earlier combined bundle contains six known unit issues; the final unit-only
bundle above adds the Paid archival probe. Earlier failed runs were harness
diagnostics and are not acceptance evidence.

The existing web overview, native contract, ordering and identity unit selection
passed **nine tests in four files**; log:
`/tmp/gatherory-team-budget-web-unit-20261030.log`. No database integration,
committed UI allocation, live server budget mutation, real concurrent server
race or physical-device test was run. The allocation race is a local native
merge simulation; server authorization/atomicity findings are source-backed
and still need isolated integration coverage. No actual account data, server,
migration, production deployment or Git commit was changed.

## Idea toolbar iOS 26 compatibility — October 30, 2026

The unavailable-link branch in `IdeaDetailView`'s toolbar was explicitly empty.
Swift 6 inferred `EmptyView` as toolbar content, whose conformance requires
iOS 27. The toolbar now gates Schedule directly on the absence of any stored
link instead of emitting an empty branch. Inaccessible links still expose
neither View Event nor another Schedule action. Deployment and Swift language
settings are unchanged.

A focused Swift 6 compiler check with an iOS 26 simulator target and
warnings-as-errors reproduced the exact diagnostic for the old builder pattern
and passed for the corrected pattern. Logs:
`/tmp/gatherory-toolbar-ios26-{before,fixed}-20261030.log`. This is a focused
builder-availability check, not a whole-project Swift 6 migration. The normal
native build and all **12 scheduling/link-projection regressions** passed in
`/tmp/gatherory-toolbar-ios26-20261030.xcresult`; log:
`/tmp/gatherory-toolbar-ios26-20261030.log` (`TEST SUCCEEDED`).

## Scheduled idea navigation and live development collaboration — October 30, 2026

The scheduled idea exposes **View Event** through the native navigation stack.
The exact visible linked child supplies the preview content and the canonical
invitation destination; the preview no longer says Proposed. System Back and
interactive pop return to the same idea. Unavailable, duplicate, archived,
foreign-root and unauthorized links have no fallback. The old proposal editor
is hidden after scheduling; canonical event content retains its native editor.
The Schedule sheet displays compact event-scoped team preference counts.

The complete native unit run passed **1,125 registered tests in 155 suites**,
with the one opt-in live test skipped by default (1,124 executed). The new
`ScheduledIdeaEventProjectionTests` covers exact linkage, invalid/ambiguous
links, deleted roots, isolated scopes, invitation projections, and inactive or
missing participation. Result:
`/tmp/gatherory-scheduled-idea-unit-final-20261030.xcresult`; log:
`/tmp/gatherory-scheduled-idea-unit-final-20261030.log` (`TEST SUCCEEDED`).

The opt-in `IdeaSchedulingLiveSyncTests` then passed against the actual
development HTTPS API in **6.319 seconds** with two authenticated accounts and
independent SwiftData stores, using the production native transport and sync
coordinator. It verifies a queued contributor preference reaches the manager,
the manager's Schedule produces one event on the contributor client, the vote
survives scheduling, and repeated reconnect does not duplicate the event.
The final cleanup also passed. Result:
`/tmp/gatherory-live-idea-sync-accepted-20261030.xcresult`; log:
`/tmp/gatherory-live-idea-sync-accepted-20261030.log`
(`TEST EXECUTE SUCCEEDED`). Fresh bootstrap reads for both development accounts
confirmed zero remaining acceptance ideas/events. The temporary sessions were
revoked and credential/staging files removed.

Earlier failed runs remain diagnostic evidence only. Projection fixtures were
corrected for initializer reconciliation, localization now uses distinct named
keys, and the live harness follows ordinary lifecycle, response-retraction and
snapshot/tombstone cleanup instead of assuming generic entities use Todo CAS
records. Initial test-only cleanup leftovers were removed and verified; those
failed bundles are not counted as successful acceptance.

These are two separate clients within a simulator-hosted test, not two physical
devices. The offline interval delays synchronization after saving locally; it
does not disable networking or prove persistence across a process restart.
Actual two-device UI, radio-off/relaunch and signed-release acceptance remain
open. No production deployment, server startup, migration, reset or upload was
performed. See [the flow and opt-in test contract](idea-scheduling.md).

The final screenshot-free native UI run passed both methods:
`testEventIdeaScheduleCancellationAndConfirmationInBothAppearances` in
**176.413 seconds**, and `testReadOnlyCollaboratorCannotScheduleEventIdea` in
**16.143 seconds**. The first covers Light/Dark edited-draft cancellation,
compact team input, View Event, canonical invitation title/date/location,
absence of the stale proposal editor, system Back, interactive swipe-back, and
one linked Home event. Result:
`/tmp/gatherory-scheduled-idea-ui-final-20261030.xcresult`; log:
`/tmp/gatherory-scheduled-idea-ui-final-20261030.log`
(`TEST EXECUTE SUCCEEDED`, zero failures). The final build-for-testing also
passed in `/tmp/gatherory-scheduled-idea-verified-build-20261030.log`.

English/Spanish localization coverage passed for **1,755 strings**, retaining
the existing nonliteral AppCopy extraction advisory; `git diff --check` passed.
No screenshot inspection, super-large layout matrix, production action or Git
commit was performed.

## Event idea Schedule handoff — October 30, 2026

See [event idea scheduling](idea-scheduling.md) for the native flow and scope.
Ideas and Decide detail now offer Schedule for authorized event proposals,
using a native draft sheet and the existing date/time and location editors.
Non-event approvals and guest voting behavior are unchanged.

The final screenshot-free `IdeaSchedulingUITests` run passed both methods on
Gatherory MCP Dev / iPhone 18 Pro / iOS 27.0:

- `testEventIdeaScheduleCancellationAndConfirmationInBothAppearances` passed
  in 138.608 seconds. In Light and Dark, it starts from Reception, opens and
  cancels the nested date editor, changes and saves an all-day draft, removes
  the draft location, then cancels the outer sheet. Reopening restores the
  original timed proposal and location. Confirmation adds exactly one Home
  event; reopening the idea exposes Scheduled instead of another Schedule.
- `testReadOnlyCollaboratorCannotScheduleEventIdea` passed in 16.619 seconds.
  The view-only fixture cannot open Schedule and creates no linked Home event.

Result: `/tmp/gatherory-idea-schedule-ui-final-20261030.xcresult`; log:
`/tmp/gatherory-idea-schedule-ui-final-20261030.log`. The runner completed with
`TEST SUCCEEDED`. These are seeded ephemeral DEBUG fixtures, not live server,
multi-device, push, or signed-release acceptance. No screenshots were inspected.

Earlier attempts are diagnostic evidence only: the initial build exposed test
setup/compiler errors, the next build caught untyped localization format
values, and the first combined functional run passed both UI methods but
failed new unit fixtures that used pre-normalization proposal values. The
fixtures now obtain the canonical stored proposal. Do not count that combined
bundle as an all-green run.

The final complete native unit run passed **1,121 tests in 153 suites** with
`TEST SUCCEEDED`: `/tmp/gatherory-idea-schedule-unit-accepted-20261030.xcresult`,
log `/tmp/gatherory-idea-schedule-unit-accepted-20261030.log`. Nine new scheduling
tests cover content/media preservation, votes remaining separate, host/manage
authority, contributor suggestion rights, revocation protection, stale
source/root/viewer boundaries, same-account reconfiguration versus A→nil→A,
identical retries, invalid schedules, inclusive one-day all-day dates, legacy
configuration defaults, and preservation of independently edited linked events.
The last unit iteration corrected a test that incorrectly assumed the legacy
idea initializer leaves event configuration absent; it actually supplies an
undated default. The accepted run covers both that default and an explicitly
mismatched configuration.

The final unit run includes two model-only guards added after the green UI run:
changed submissions cannot rebuild an existing linked event, and unsupported
event configurations expose no Schedule action. Their targeted regressions and
the full unit suite passed; the native UI run covers the normal configured
proposal path. Existing voting, budget, persistence and permission suites also
remain green. English/Spanish localization coverage passed for **1,746 strings**
with the existing nonliteral AppCopy extraction advisory; `git diff --check`
passed. No production data, schema, deployment, upload or Git commit changed.

See the [October 23 release readiness audit](release-readiness-audit-2026-10-23.md)
for the broader native UI, database/HTTP and production-entrypoint checks after
build 6, the invitation-preview date correction and remaining device acceptance.

Run the native tests before changing permissions, authentication, or sync behavior.
Use Swift Testing for native unit/transport tests and XCTest for UI automation;
the web backend uses Vitest and `@effect/vitest`.

## Repeatable local checks

The supported minimum is iOS/iPadOS 26. Before testing an OS compatibility
change, run `bash scripts/verify-deployment-targets.sh`. It checks effective
Debug/Release settings for the app and both test targets against the device and
simulator SDKs; it does not run UI tests. Keep availability checking enabled
when compiling against newer SDKs.

From the iOS repository, choose an installed simulator with
`xcrun simctl list devices available`. Substitute its ID below:

```sh
xcodebuild test \
  -project Gatherory.xcodeproj \
  -scheme Gatherory \
  -destination 'platform=iOS Simulator,id=<SIMULATOR_ID>' \
  -only-testing:GatheroryTests \
  -parallel-testing-enabled NO \
  -disableAutomaticPackageResolution \
  -collect-test-diagnostics never \
  POSTHOG_ENABLED=NO
```

For the functional UI suite, replace `-only-testing:GatheroryTests` with:

```sh
-only-testing:GatheroryUITests \
-skip-testing:GatheroryUITests/GatheroryUITests/testLaunchPerformance
```

Omit the skip option when intentionally measuring launch performance. The UI
tests use ephemeral, seeded local data and skip authentication; passing them
does **not** prove that production sign-in or deployed endpoints work.

`-collect-test-diagnostics never` avoids lengthy simulator sysdiagnose collection
on a failure. It does not suppress assertions or the `.xcresult` report. Omit it
when investigating a simulator/OS problem that needs those diagnostics.

From `gatherory-web-app`, also run:

```sh
pnpm test
pnpm typecheck
```

The default web test command checks generated contracts before running Vitest.
Database/provider integration suites are opt-in. Do not enable their flags or
load live credentials as part of the ordinary local check.

## What the tests protect

### TestFlight build 6 verification — October 23, 2026

Build 1.0 (6) archives native HEAD `19833ddc` plus the build-number increment.
The device Release archive and Xcode upload passed. The archived production
configuration and distribution app/profile both verify the intended bundle,
team, production APNs entitlement and disabled debugging; flags retain the
production API, opt-in push, consent-gated ads and PostHog without development
seeding/sign-in bypass. The unit/UI/Light-Dark evidence for its new behavior is
recorded immediately below. Localization rechecked at 1,700 English/Spanish
strings, and project/plist syntax and `git diff --check` passed. Xcode returned
the existing two vendor dSYM warnings without rejecting the upload. See the
[release record](app-store-release.md#testflight-build-6--october-23-2026)
for processing/tester status and `/tmp/gatherory-testflight-1.0-6-*` for local
archive, upload and sanitized configuration evidence. This did not rerun live
production/device flows or deploy the backend.

### Main invitation tap editing and sharing — October 23, 2026

See [invitation cards](event-invitation-cards.md#main-event-sharing-and-tap-editing--october-23-2026)
for native title/date/location edit sheets, sharing beside Back, permission
boundaries and final results. `MainInvitationEditingTests` exercises the real
field mutation command, including stale identities/fields and preservation of
current unrelated event data. `MainInvitationEditingUITests` covers host
save/cancel, read-only guests/collaborators, the information tiles and a pinned
child share presentation with native Back. These use synthetic ephemeral
fixtures and normal Light/Dark appearances.

### Beta feedback follow-up — October 23, 2026

New event/Blueprint dates default to today, the date editor automatically keeps
the saved event timezone, and event labels use that same zone. Read-only
collaborator identities render as content instead of disabled controls. See the
[cross-project feedback handoff](../../../gatherory-web-app/docs/release/beta-feedback-2026-10-23.md)
for the final checks, evidence paths and remaining acceptance work. Earlier
timezone-picker descriptions below record superseded implementation passes.
These changes are included in TestFlight build 6.

### TestFlight build 5 verification — October 23, 2026

Version **1.0 (5)** was archived from native HEAD
`9190bc3da97a57bcf7bc8a3794a287edbfa0e70f` plus the current working-tree
changes and build-number increment. Apple's versioning utility advanced the
app and test targets to build 5; the project plist validates. Existing source
and pinned dependencies were preserved.

- The complete non-UI `GatheroryTests` target passed **1,016 tests / 1,150
  executions**, including 53 parameterized tests with 187 parameter executions.
  There were zero failures, skips or runtime warnings on iPhone 18 Pro / iOS 27.0
  simulator. Result: `/tmp/gatherory-testflight-1.0-next-tests-20261023.xcresult`;
  log: `/tmp/gatherory-testflight-1.0-next-tests-20261023.log`.
- Localization passed for **1,695 EN/ES strings**. The existing dynamic-key
  extraction warning remains in `AppCopy.swift`.
  Log: `/tmp/gatherory-testflight-1.0-5-localizations.log`.
- The signed Release device archive passed. Its Info.plist confirms version
  1.0 (5), iOS 26.0 minimum, production origin/environment, ads and FCM enabled,
  ad test mode off, PostHog enabled, and seeding/login bypass/forced onboarding
  disabled. Its bundled Firebase configuration matches the app/project.
- The App Store Connect export re-signed the app for **Guide Systems LLC /
  LW97NHT3JA**. Both the actual distribution app signature and embedded store
  provisioning profile were inspected: `aps-environment=production`,
  `get-task-allow=false`, and application identifier
  `LW97NHT3JA.com.guide-systems.gatherory`. Deep signature verification passed.
  The initial development-signed archive's sandbox entitlement was replaced
  during distribution export; the submitted app was checked separately.

Archive: `~/Library/Developer/Xcode/Archives/2026-10-23/Gatherory 1.0 (5).xcarchive`.
Archive log: `/tmp/gatherory-testflight-1.0-5-archive.log`.
Distribution configuration evidence:
`/tmp/gatherory-testflight-1.0-5-verified-config.json`.
The archive emits only the App Intents metadata-extraction warning because this
app does not depend on AppIntents.framework. Upload succeeded with two
non-blocking missing-vendor-dSYM warnings for GoogleMobileAds and
UserMessagingPlatform. These limit SDK stack symbolication, not upload acceptance.
Upload log: `/tmp/gatherory-testflight-1.0-5-upload.log`.
UI tests and real device push
delivery were not rerun for this release. No backend deployment or database
reset is included. See [release status](app-store-release.md) for upload and
tester-group acceptance, which is separate from the local checks above.
App Store Connect now shows the build's overall status as **Testing** with both
existing groups attached (Friends & Family: 0 invitees; External Friends &
Family: 4 invitees); automatic tester notification was enabled. This does not
establish separate external review approval or real-device push delivery.
See the [App Store Connect build detail](https://appstoreconnect.apple.com/teams/56187352-94ba-429f-82d1-35f22508a99b/apps/6820635528/testflight/ios/26074dbf-5cb8-4c14-86f7-583d1e1cbe50).

### Beta ads, push and telemetry configuration — October 23, 2026

At the release owner's request, Release now enables consent-gated Explore ads
with Gatherory's production unit and opt-in FCM with production APNs. PostHog
remains enabled. Debug retains sample ads and development APNs. No package,
onboarding, permission flow or server behavior changed.

Focused Debug regression run: **28 tests passed, zero failures/skips/runtime
warnings** in `ExploreAdConfigurationTests`, `ExploreAdPlacementTests`,
`ExploreAdSessionLifecycleTests`, `NotificationControllerTests`,
`NotificationNavigationTests`, and `AnalyticsConfigurationTests` on iPhone 18 Pro
/ iOS 27.0 simulator. These cover the ad enable/disable switch, production ID
validation, Debug sample-only inventory, consent separation, stable placement,
inventory lifecycle, notification identity/permission/tap controls, and suppression
of telemetry in tests. No new tests mirroring the configuration constants were
added; existing behavior coverage was rerun.

Result: `/tmp/gatherory-beta-services-debug-20261023.xcresult`;
log: `/tmp/gatherory-beta-services-debug-20261023.log`.
The initial Release test attempt did not run assertions: the ordinary Release
module is built without `-enable-testing`, so `@testable import Gatherory` was
rejected. Regression checks were rerun in the supported Debug test configuration;
this is not a passing Release test-suite result.

Built Release `Info.plist` inspection confirms production origin/environment,
ads on, ad test mode off, FCM on, PostHog on, seeding/authentication bypass off,
and Firebase auto-init off. The bundled Firebase configuration is present,
matches `com.guide-systems.gatherory`, and identifies `gatherory-e4d8b`.

The stock Release simulator build also passed with `CODE_SIGNING_ALLOWED=NO`
and no feature/telemetry overrides:
`/tmp/gatherory-beta-services-release-20261023.log`. This verifies compilation
and bundled configuration, not a signed device archive or live provider delivery.

The initial Firebase inspection found only the development key. A subsequent
browser setup, explicitly confirmed by the release owner, reused the existing
`KL2Y639363` `.p8` in Firebase's production slot. Apple confirms this key supports
Sandbox & Production and the Gatherory App ID has Push Notifications enabled.
Firebase now lists both development and production keys under team `LW97NHT3JA`.
No new key was created or revoked and private key contents were not logged.
Source/provider configuration does not establish distribution provisioning,
FCM delivery or deployed server credentials. The current server attempts one
best-effort send after saving, superseding older manual-dispatch notes. No
notification was sent, database reset or deployment performed as part of this
configuration change. The later build 5 upload is recorded above. The owner
reports the earlier layout warning is resolved.
See [the beta release decision](app-store-release.md#beta-configuration-decision--october-23-2026).

### Unseen-first discovery and browsing sessions — October 23, 2026

Three Luna agents split server ordering/HTTP validation, native history/session
integration, and repeated-visit evaluation. The parent reviewed boundaries,
added native UI coverage, integrated the standard Refresh button and ran Xcode
serially. Pinned open-source references and the policy/evaluation artifact live
in [roadmap 16](../../../gatherory-web-app/docs/roadmaps/blueprint-ranking-roadmap/16-unseen-first-discovery.md).

Native history records only browse cards at least half visible for one second,
separately from analytics consent. It is exact-account, bounded to 200 valid keys
and 30 days, with a 16 KiB request-context limit. Live views do not mutate the
active header snapshot. Foreground pagination, preview return and quick tab
return keep the session. Returning after 30 minutes away or tapping the native
toolbar Refresh button creates another snapshot. Typed queries omit it. A
stale browse cursor renews the context before the feed's existing one-time
restart. Account changes fence late callbacks; deletion clears only its history.

Final verification passed **36/36 distinct native checks (34 unit/two UI), 48
executions, zero failures/skips** on iPhone 18 Pro/iOS 27.0 simulator:
`/tmp/gatherory-unseen-final.xcresult` and `/tmp/gatherory-unseen-final.log`.
The focused run contains no runtime warnings. The four unit suites are
`BlueprintDiscoveryContextStoreTests`, `BlueprintDiscoveryTests`,
`PostgresSyncTransportTests` and `AccountDeletionLocalCleanupTests`.

Coverage includes bounded/expired history, isolated accounts, frozen header
bytes across pages, foreground continuity, short/long away return, clock
rollback, long-key rejection, stale-cursor renewal, typed-search header omission,
account deletion and existing feed cancellation/scope/retry behavior.
`testSeenHistoryWaitsForRefreshAndPreviewAndTabReturnPreserveBrowse` passes in
normal Light/Dark. It checks meaningful live views against the frozen snapshot,
excludes fetched offscreen keys, preserves card position and first-page request
count after preview/tab return, and verifies Refresh starts a new request with
the accumulated view history. `testExploreSwipeReturnRestoresSearchQuery` also
passes. UI uses the fixed local catalog and a Debug-only audit value with isolated
defaults; it does not simulate or claim the server's actual ranking order.

The final simulator Release build passed with exit 0 and no compiler diagnostics
in `/tmp/gatherory-unseen-release.log`. No packages were installed.

Both final Light/Dark screenshots under `/tmp/gatherory-unseen-final-shots` were
inspected. Localization verifies all **1,695 EN/ES strings** in
`/tmp/gatherory-unseen-localization.log`, with the existing dynamic-key extraction
warning. The onboarding and ordinary creation reference hashes are unchanged.

The server passed **85 tests across nine files**: 52 ranking/paging/HTTP/search/
freshness checks and 33 measurement/action/baseline-evaluation regressions.
Logs: `/tmp/gatherory-unseen-server-tests-r2.log` and
`/tmp/gatherory-unseen-measurement-tests.log`. Typecheck, generated contract check
and deterministic artifact check pass. The synthetic five-visit evaluation
reports 47 candidate versus 10 baseline distinct top-ten cards and 0% versus
60% previously viewed top-ten cards on visits 2–5, while unseen inventory remains.
These are repetition-policy fixtures, not online relevance/usefulness estimates.

Earlier failures are retained for diagnosis. The first native attempt failed
compilation on dictionary tuple labels; the next found a missing continuation
call in the new regression and a transport-fixture route allowlist omission.
Those are corrected. UI testing also needed to expand the system-minimized tab
bar before selecting another tab. Two pull attempts did not invoke the masonry
ScrollView refresh action (`/tmp/gatherory-unseen-native-r3.xcresult`,
`/tmp/gatherory-unseen-ui-r4.xcresult`). The delivered manual path is a native
SwiftUI toolbar button; there is no custom pull gesture or UIKit introspection.
Do not claim pull-to-refresh is verified. The original evaluation clock advanced
sessions without advancing request time; it was corrected before final results.

No database migration, production rollout or physical-device acceptance was
performed. History is local to one device; compatible server deployment is
needed for it to affect order. Catalog/listing/preferences can invalidate a
snapshot and trigger recovery. Real repeated visits, cross-device expectations
and usefulness still need product acceptance against the deployed catalog.

### Use to created-event handoff — October 23, 2026

Three smaller Luna agents split native import/recovery, native fixture/UI
coverage, and server content/replay coverage; parent integration ran serial
Xcode checks and reviewed screenshots.

The coordinator now opens the exact receipt scope only after canonical import,
setup-draft cleanup and durable intent completion succeed. A cleanup error
keeps recovery available without selecting the event underneath failed setup.
Another owner is rejected before an intent is written; resume rejects altered
or stale caller intents that differ from the exact stored request.

New native regressions cover wrong-owner writes, altered intent bodies, cleanup
failure followed by successful receipt recovery, and completed receipts whose
workspace is temporarily absent from bootstrap. Both recovery cases import and
open the original scope without another installation POST. Existing focused
coverage also checks customized event/idea content, independent repeated Uses,
account generations, local edits across relaunch, copy request replay and exact
draft cleanup. Imports do not create duplicate local outbox writes.

The expanded UI fixture exercises the production copy, schedule, preview,
installation, receipt and bootstrap transport paths. It passes the actual app
workspace library into the coordinator and keeps persistence, drafts, intents
and history isolated. Discovery/Light success and Yours/Dark transient-failure
retry confirm dates, submit distinct event names, dismiss setup and preview,
and reach the real event Home/Ideas screens with the selected child and ideas.
The retry fixture rejects changed bodies/IDs and requires the idempotency
header to equal the body request ID. Date confirmation/cancellation and
reopened name/time-zone/date progress also pass in normal Light/Dark.

Final native source passed **37/37 distinct checks (35 unit/two UI), 40 test
executions, zero failures/skips**, on iPhone 18 Pro/iOS 27.0 simulator:
`/tmp/gatherory-use-handoff-final.xcresult` and
`/tmp/gatherory-use-handoff-final.log`. The five unit suites are
`BlueprintInstallationImportTests`, `BlueprintInstallationIntentTests`,
`BlueprintSavedCopyResolverTests`, `BlueprintSetupRecoveryTests`, and
`BlueprintInstallReadinessTests`. The UI methods are
`testDiscoveryUseCopiesInstallsImportsAndLandsInCreatedEventWithRetry` and
`testDiscoveryBookmarkAppearsInSavedLibraryCollection`. The former contains
both Discovery/Light and Yours/Dark journeys. The earlier
`/tmp/gatherory-use-handoff-ui-r2.xcresult` passed both the handoff method and
`testBlueprintUseOpensRealSetupAndRequiresExplicitDateConfirmation`; this makes
38 distinct passing native methods across staged runs, not 38 additional tests.

Light/Dark captures were exported and inspected under
`/tmp/gatherory-use-handoff-final-shots` (manifest maps methods and appearances).
The final result contains one instance of the existing frame-dimension warning;
the previous two-method UI bundle contains two. Localization verifies all
1,694 EN/ES strings (`/tmp/gatherory-use-handoff-localization.log`), with the
existing non-literal-key extraction warning at `AppCopy.swift:341`. Onboarding
and its existing creation reference match their pre-task hashes.
The final simulator Release build passed with exit 0 and no compiler diagnostics
in `/tmp/gatherory-use-handoff-release.log`.

Server tests ran against a new loopback-only PostgreSQL 18 container, migrated
with the current 23 migrations. All **three database test files/tests passed,
zero skipped**:

```sh
RUN_BLUEPRINT_DB_TESTS=1 pnpm vitest run \
  tests/integration/blueprint-attribution-copy.database.test.ts \
  tests/integration/blueprint-installation.database.test.ts \
  tests/integration/blueprint-saved-copy.database.test.ts
```

They verify the exact saved/published definition and installation source
snapshot; created main/child dates and metadata; idea notes and category-specific
native configuration defaults; to-do targets; and guide bodies, audiences and
targets. Same-request copy/install replay, changed-copy conflict and a provider
response lost after commit are covered. Provider provisioning runs once after
that lost response. `pnpm typecheck` passed. The disposable container and its
volume were removed; the shared development database was untouched.

Evaluation caught two fixture problems before the passing rerun: compilation
used an inaccessible idea setter, and the simulated copy dropped a description
that came from the discovery summary. The corrected fixture uses the existing
idea mutation API and preserves the submitted portable description. An initial
compile attempt is retained in `/tmp/gatherory-use-handoff-units.log`; the two
failed UI suggestion assertions are in `/tmp/gatherory-use-handoff-ui.xcresult`.
They are superseded by the passing bundles above. An initial
idea-configuration database assertion was corrected to expect the intentional
category-specific native projection rather than a portable version marker.

This is local native protocol/UI plus real PostgreSQL workflow evidence. The
native UI does not connect to that PostgreSQL-backed server during these tests;
server provisioning and cover storage use test adapters. Deployed sign-in,
real-account creation, actual media-byte transfer and physical-device acceptance
remain separate. The existing invalid-frame-dimension warning still appears in
the date/editor journey. No production rollout or onboarding changes occurred.

### Use action and edit sheets — October 23, 2026

The Yours bottom action now says **Use** (Spanish: **Usar**) and opens the
existing event-creation flow. The final form retains its explicit Create Events
confirmation. Main-event, child-event and idea editors (including Add) present
as native large sheets with Save/Cancel and a drag indicator. The Yours Blueprint
preview remains full screen, matching Liked. No new package or onboarding edit.

Focused UI verification checks the Use label and bottom reachability in normal
Light/Dark, native sheet placement for event/idea editors, and Save/Cancel/Add
behavior. **All three focused UI methods passed**, zero failures/skips, on the
Xcode 27.1 / iPhone 18 Pro / iOS 27.0 simulator. Bundle:
`/tmp/gatherory-use-edit-sheets.xcresult`; Debug app compilation is included.
The standard Light/Dark captures in `/tmp/gatherory-use-edit-sheets-shots`
were exported and inspected. Localization passes for **1,694 EN/ES strings**;
scoped source/whitespace and documentation checks pass. The existing frame
warning still appears twice; it is not claimed resolved. No separate Release
build or live server/device creation was run for this small follow-up.

### Yours bottom controls and native creation form — October 23, 2026

Current follow-up moves Create Events and Add from the Yours navigation bar to
native bottom toolbar items. Setup opens full height and uses onboarding's
native grouped-form/date-editor patterns: editable name, common time zone,
explicit main and included-event date confirmations, and a native bottom action.
The onboarding screen/form is unchanged. Per explicit user direction, iOS work
uses the existing Gatherory/SwiftUI design system without ReUI guidance.

The old forced graphical calendar popover is replaced with the shared date/time
editor. Done commits and confirms; Cancel leaves the prior value intact. Child
dates use the common main-event zone. Saved creation selections are restored
without re-projecting legacy Blueprint Decide responses. Readiness and action
entry enforce trimmed event names within 120 Unicode scalars. Stale date edits
must retain the owner/generation/request captured when presented.

Three Luna agents handled native implementation, regression updates and
read-only state/recovery review. Parent integration added naming policy tests,
keyboard focus handling, final route correction and serial Xcode verification.

- `/tmp/gatherory-blueprint-native-creation-r1.xcresult`: **69 distinct checks
  passed** (65 unit and four UI; 73 executions including parameter cases), zero
  failures/skips. Coverage includes native bottom actions, normal Light/Dark
  overview/direct editing/Add, and date confirmation/cancellation/reopening.
- `/tmp/gatherory-blueprint-native-creation-final.xcresult`: **67 distinct checks
  passed** (65 unit and two UI; 71 executions including parameter cases), zero
  failures/skips. The setup journey now runs both normal Light/Dark appearances,
  checks empty-name readiness after all dates are confirmed, and clears name
  focus when date editing starts. Bottom Create Events is fully inside the
  window bounds. This run preceded the final setup-route correction below.
- Screenshot review caught a first-presentation problem missed by the initial
  assertions: the boolean-driven sheet could open with nil creation owner and
  show legacy Continue/inclusion controls. The preview now presents an
  identifiable setup route carrying its immutable owner, and dismisses a route
  after account replacement. UI tests assert Create Events on the first
  presentation, before editing any form field.
- `/tmp/gatherory-blueprint-native-creation-route-final.xcresult`: **both final
  route UI methods passed**, zero failures/skips. The complete Use setup journey
  runs in normal Light/Dark and asserts the Create Events label before editing;
  the Yours Dark entry also verifies the first-presented title/action. Final
  route captures were exported and inspected in
  `/tmp/gatherory-blueprint-native-creation-route-final-shots`.
- OnboardingView and WorkspaceBrowserView hashes match their pre-task values.
  Shared date-editor timezone editing defaults remain unchanged for existing
  callers; Blueprint child-date editing opts out of changing the common zone.
  Native AGENTS.md now records the user's explicit native-only guidance.
- Final simulator **Release build passed** (exit 0):
  `/tmp/gatherory-blueprint-native-creation-release.log`. Scoped source and
  whitespace checks and documentation formatting passed.
- EN/ES coverage passes for **1,693 strings**, with the existing AppCopy.swift:341
  non-literal extraction warning; log
  `/tmp/gatherory-blueprint-native-creation-localization.log`.

Captures in `/tmp/gatherory-blueprint-native-creation-final-shots` were inspected
in normal Light/Dark: a full-height grouped form, keyboard-dismissed creation
button, and reachable bottom-toolbar actions over the masonry overview.
No super-large layouts ran. The existing frame-dimension diagnostic still
appears (two occurrences in r1, one in each subsequent run), without a source
location. It is not claimed resolved.

The setup fixture seeds a private source pin and answers date suggestions only;
it never simulates a successful copy/install. Live server creation, real-account
personal saves, physical VoiceOver/device acceptance and deployment are not
claimed. No dependency was installed and no onboarding behavior was changed.

### Yours full-screen and direct editing — October 23, 2026

Current behavior supersedes the sheet/Edit/Decide iteration below. Yours opens
with the same standard fullScreenCover as Liked. Main-event, child-event and
masonry idea taps open existing native editors directly with Save/Cancel.
Create Events and Add use the native navigation toolbar. Blueprint Decide is
removed; only created event/workspaces provide that workflow. Root previews
and editor forms use system full-screen presentation; date setup retains its
existing sheet.

Library cards resolve their actual customized cover/source instead of always
showing category artwork. New plans include all authored content independently
of legacy preview responses; saved subsets and exclusions survive name/cover/
date edits. Only newly added items default into the selection. Saving reusable source edits retains confirmed dates and allocates a fresh
working request identity. Explicit fresh-workspace-copy date resets remain
unchanged.
Pending-install/account/version guards and retry paths remain intact.

Tests use standard text sizes in Light/Dark. Dedicated super-large/XXXL methods
were removed at the user's request; app Dynamic Type support is retained.
Three smaller Luna agents split native UI, content/selection and regression
coverage; parent integration handled review, source checks, screenshots and
serial Xcode execution. On Xcode 27.1 / iPhone 18 Pro / iOS 27.0:

- **72 distinct focused methods passed across staged runs: 57 unit and 15 UI.**
- `/tmp/gatherory-yours-direct-edit-r3.xcresult`: 67 passed and five failed,
  zero skipped. Twelve UI methods passed, including full-screen recovery,
  standard Light/Dark masonry, read-only public detail, Explore native return
  and retained search. Two unit expectations still required the old Love-only
  selection behavior. Two UI assertions incorrectly compared a native toolbar
  to a scroll view whose accessible bounds start at zero; the working-copy
  test expected a fixture title different from the explicit source default.
- `/tmp/gatherory-yours-direct-edit-final.xcresult`: **62/62 passed**, zero
  failures/skips, on final source (57 unit and five UI). This reruns all six
  unit suites and the three corrected UI journeys, plus final normal-size
  Light/Dark overview and editor/Add checks after keeping the native Create
  Events text label visible. Main/child/idea direct Save/Cancel, no Edit mode/
  Blueprint Decide, native toolbar hierarchy, actual date setup cancellation,
  and the Saved → Use → Yours working-copy journey pass.
- The first two compile attempts stopped at Swift initializer argument ordering
  in the new library-cover call. The final build and tests include that fix.
- Final screenshots in `/tmp/gatherory-yours-direct-edit-final-shots` were
  exported and inspected: standard Light/Dark main overview and editor,
  masonry, Saved/working copy, and date setup. No super-large layouts ran.
- Final simulator **Release build passed** (exit 0):
  `/tmp/gatherory-yours-direct-edit-release.log`.
- Localization passes for **1,693 English/Spanish strings**, with the existing
  non-literal extraction warning at `AppCopy.swift:341`; log
  `/tmp/gatherory-yours-direct-edit-localization.log`.
- Native-adapted C1–C4 source checks, manual system-control/accessibility/state
  review, scoped whitespace and documentation formatting pass. Native lint and
  audit-checklist tooling are unavailable; no dependency was installed.

The final result records two occurrences of the existing **Invalid frame
dimension (negative or non-finite)** runtime warning without a source location.
Passing interaction checks do not resolve it. The setup fixture uses a seeded
private pin and a schedule-only transport: it does not submit live creation or
prove server personal-save/copy/install success. Live signed-in server/device,
physical VoiceOver and Reduce Motion acceptance remain open. No backend/DB
change, deployment or physical-device installation occurred.

### Yours single-scroll preview — October 23, 2026

Historical sheet/Edit/Decide iteration, superseded by the full-screen/direct-edit
correction above. Its tests and XXXL captures do not verify the current design.

Yours now reads as one overview: main event, related events and masonry ideas.
Create Events is the primary action; secondary Edit reveals content editors and
Add controls, while Decide opens a separate native navigation destination.
The existing local response indicators and excluded-event labels distinguish
the full editable content from the subset selected for creation. Saved choices
and installation projection remain unchanged.

Authored, working and previously used Yours cards open a native large sheet.
Back and the system swipe-down gesture return to the library; inner
detail/Decide navigation returns to the overview first. Unsaved choices and an
active save disable sheet dismissal. Native Back retains staged choices when
returning from Decide; overview Back retains Save/Discard confirmation.

At accessibility sizes, secondary Edit/Decide actions use native toolbar
buttons so they do not consume the reading viewport. Child-event editors stack
below their details. The three-section overview uses a regular VStack to avoid
lazy height-estimate jumps when editing changes offscreen sections.

On Xcode 27.1 / iPhone 18 Pro / iOS 27.0, **75 distinct focused methods passed
across staged runs: 61 unit methods and 14 UI methods**. Three UI methods are
new; existing context, working-copy, recovery and dirty-close checks were updated.

- `/tmp/gatherory-yours-single-scroll-r1.xcresult`: 56 unit methods and ten UI
  methods passed. Public preferences, single-scroll details, masonry, search
  return and date-confirmation checks passed. Three new Yours assertions failed.
- `/tmp/gatherory-yours-single-scroll-r3.xcresult`: the 56 unit methods passed
  again, alongside the new Yours Create Events setup/cancellation check and
  four other UI methods. This schedule-only fixture does not submit creation.
- `/tmp/gatherory-yours-single-scroll-final.xcresult`: **all seven Yours UI
  methods passed**, zero failures/skips. This covers Light/Dark reading and
  native sheet dismissal, working/recovery return, rename/save/reopen, nested
  Decide return, actual Maybe queue advancement, dirty swipe prevention,
  close cancellation/discard, date-confirmation handoff and Accessibility XXXL.
- `/tmp/gatherory-yours-single-scroll-polish.xcresult`: **five geometry unit
  methods and two UI methods passed**, zero failures/skips. The editor journey
  and both XXXL appearances were rerun after the Add Idea header was stacked
  and shared cover frames normalized to finite, nonnegative geometry.

Evaluation caught genuine accessibility row/header compression and lazy
height-estimate shifts; responsive stacking and a regular three-section VStack
fix those. It also proved that zoom return bypassed the unsaved-change guard on
this simulator. Attempts to change UIKit zoom options did not solve that;
the final implementation uses a standard SwiftUI sheet, and the temporary
UIKit bridge was removed. Initial test assumptions about card accessibility
bounds, nested Save Changes and swiping a text fragment were corrected. Early
compiler errors in the pending-intent expression and discarded UIKit prototype
are superseded by the passing final builds and runs.

Final Light/Dark masonry and XXXL captures were exported and inspected in
`/tmp/gatherory-yours-single-scroll-final-shots` and
`/tmp/gatherory-yours-single-scroll-polish-shots`, including the readable Add
Idea header and actual setup handoff. C1–C4, Swift parsing and scoped whitespace
checks pass. EN/ES coverage passes for **1,693 strings** in
`/tmp/gatherory-yours-single-scroll-localization.log`, with the existing
dynamic-key extraction warning. Native lint/ReUI audit tooling is unavailable;
labels, ordering, touch targets and native controls were reviewed manually.

The final **Release simulator build passed** with no compiler diagnostics in
`/tmp/gatherory-yours-single-scroll-release-final.log`.

One runtime diagnostic remains: Xcode reports “Invalid frame dimension
(negative or non-finite)” in the collection/personal editor journey, without a
source location. Its behavior assertions pass and cover-frame normalization did
not eliminate it. This is recorded as an unresolved diagnostic, not a clean
runtime-warning result. Live auth/server creation, physical VoiceOver and Reduce
Motion device acceptance remain separate checks. No deployment or DB reset
was performed.

### Explore preview Back and swipe return — October 23, 2026

Explore connects its existing matched card source to the system zoom transition
on the full-screen Blueprint presentation. The discovery preview's top-left
control is a native back chevron with the existing localized Back label. The
same presentation callback resumes the covered feed and retained search query;
personal/library previews retain the library control and unsaved-change guard.

Four UI regressions were added alongside this feature. On Xcode 27.1 / iPhone
18 Pro / iOS 27.0, **31 distinct focused methods passed across two runs**:

- `/tmp/gatherory-preview-back-r1.xcresult`: **27 unit methods and three UI
  methods passed**. Unit suites cover discovery navigation snapshots,
  preview editing/presentation and ad-session lifecycle. UI checks exercise
  Back, normal preview scrolling, edge-swipe dismissal, reopening in Light/Dark,
  a nested event-detail swipe returning to the Blueprint before leaving, and
  the search query surviving swipe return. The fourth UI method reached the
  unsaved-changes prompt but assumed a visible Cancel button.
- `/tmp/gatherory-preview-back-personal-r2.xcresult`: the **personal unsaved
  UI method passed**, zero failures/skips. A Decide change remains dirty after
  cancelling close, and only explicit Discard exits. The native anchored
  confirmation popover on this simulator omits Cancel; the test taps outside
  when that button is absent. No product confirmation controls were changed.

Both Light/Dark Back-arrow captures were exported to
`/tmp/gatherory-preview-back-r1-shots` and inspected. Localization passes for
1,684 English/Spanish strings in `/tmp/gatherory-preview-back-localization.log`,
with the existing dynamic-key warning. No strings or dependencies were added.
C1–C4 source and whitespace checks passed; system controls and labels were
reviewed manually. Native lint and ReUI audit tooling remain unavailable.

The final **Release simulator build passed** with no compiler warnings in
`/tmp/gatherory-preview-back-release.log`.

Feature regression expectations are now recorded outside the managed block in
the native `AGENTS.md`, in the web/server `AGENTS.md`, and in AI onboarding.
These UI fixtures do not verify live auth/creation, real SDK inventory during a
gesture, physical VoiceOver or Reduce Motion behavior on a device. See
[roadmap 15](../../../gatherory-web-app/docs/roadmaps/blueprint-ranking-roadmap/15-single-preview-and-event-creation.md#explore-return-navigation).

### Public preview idea masonry — October 23, 2026

The combined public preview now uses the same `AdaptiveMasonry` as the personal
Ideas view, replacing its row-aligned `LazyVGrid`. Natural card ratios,
12-point spacing, layout direction and the one-column accessibility fallback
remain shared with the existing layout component. The preview remains one scroll.

Two focused UI methods passed across staged runs on iPhone 18 Pro / iOS 27.0.
The existing Light/Dark Accessibility XXXL event/idea-detail check passed in
`/tmp/gatherory-public-ideas-masonry-r1.xcresult`. The new ordinary-size
Light/Dark method passed in `/tmp/gatherory-public-ideas-masonry-r2.xcresult`;
it verifies different card heights, the next card immediately below the shorter
column, and read-only detail navigation. Its initial two-point accessibility
bounds tolerance was too tight (2.27-point difference); four-point spacing
tolerance plus an independent check that the shorter column advances before
the taller card ends distinguishes masonry from a shared grid row.

Both exported Light/Dark captures were inspected in
`/tmp/gatherory-public-ideas-masonry-r2-shots`. C1–C4, scoped whitespace and
roadmap formatting passed. The UI runs compile Debug app/test targets; Release
and broad unit suites were not repeated for this layout-only correction.
No strings, dependencies, motion or creation behavior changed. Native lint and
ReUI audit tooling remain unavailable. Live creation acceptance remains the
next flow check.

### Single public preview and event creation — October 23, 2026

Public discovery, Saved/Liked and shared links now show one read-only scroll
containing the main event, included events and ideas. Tapping opens read-only
details; Home/Ideas tabs and the event picker are absent. Yours retains the
personal planning workspace and an explicit Create Events action, including
reusable previously used sources. Setup confirms dates; legacy setup retains
event-inclusion switches but no longer repeats event/idea editors. Its disabled
primary label uses a semantic secondary foreground.

New explicit Use plans include all authored ideas and events through local
personal inclusion choices and retained child definitions. This fixes the prior
empty-default projection, including events without child-targeted ideas. Public
likes and live votes are unaffected. Existing drafts keep their prior choices,
confirmed dates and pinned sources unchanged.

Three smaller Luna agents implemented the public view, focused setup/copy and
the isolated UI harness. Parent integration fixed accessibility identifier
inheritance, fixture initialization/inclusion, explicit repeat creation from
Yours, and scrolling confirmation above the medium sheet's bottom action bar.
The pure preview presentation policy is nonisolated, avoiding its prior
actor-isolated Equatable warnings.

With Xcode 27.1 on iPhone 18 Pro / iOS 27.0, the staged results cover
**99 distinct passing methods: 94 unit and five UI**:

- `/tmp/gatherory-single-preview-r2.xcresult`: all **93 unit methods** passed,
  including preview policy/session/editing, readiness, date context, recovery,
  disk drafts, saved-copy resolver, installation intents, canonical import and
  library model. The two parameterized methods add six executions. The run's
  two UI failures are superseded below; they exposed inherited identifiers and
  a fixture whose selected child lacked a personal inclusion override.
- `/tmp/gatherory-single-preview-r3.xcresult`: **28 unit methods and four UI
  methods passed**. This includes the additional default-inclusion regression
  and repeated helper/session/editing coverage. UI checks cover Light/Dark
  preferences, public previews without workspace tabs, read-only event and idea
  details at Accessibility XXXL in both appearances, Saved's direct Use,
  Save → Saved → local working copy → Yours, and personal editing/Create Events.
  One setup UI failure is superseded by the final focused pass: the confirmation
  was below the medium sheet's action bar, so the test had not tapped it.
- `/tmp/gatherory-single-preview-setup-r5.xcresult`: the **actual SetupView UI
  method passed**, zero failed/skipped. It checks Create Events disabled before
  confirmations and after the main date alone, scrolls the native form to the
  child confirmation, confirms it, then closes and reopens setup. Both dates
  and the enabled action survive resume. No install action is submitted.
- Localization passes for **1,684 English/Spanish strings**, with the existing
  `AppCopy.swift` dynamic-key warning, in
  `/tmp/gatherory-single-preview-localization.log`.

Ten successful captures are in `/tmp/gatherory-single-preview-r3-shots` and two
setup captures in `/tmp/gatherory-single-preview-setup-r5-shots`. Standard
Light/Dark public previews, Saved, Dark Accessibility XXXL public content/detail,
and confirmed setup were inspected. There is no public picker to truncate at
large text sizes. This is not a full personal-workspace large-text audit.

The final **Release simulator build passed** with no compiler warnings in
`/tmp/gatherory-single-preview-release.log`; fixture-only routes are excluded.
The Debug test build still reports existing unrelated test warnings. The first
attempt was interrupted after detecting an overloaded fixture initializer that
recursed; distinct internal argument labels fixed it before the recorded reruns.

The ordinary DEBUG preview fixture still uses its explicit temporary working-copy
shortcut for the library handoff test. The additional
`-BlueprintSetupDateConfirmationFixture` presents the actual setup view with a
temporary draft store, an already-resolved private pin and the production
coordinator over a schedule-only local URLProtocol. It seeds once, then resumes
the real saved dates. Unexpected routes, including installation, return HTTP
503; it never fabricates creation success. Separate native URLProtocol/import
tests cover copy retries and owner/replaced-draft guards, exact request/body
recovery, canonical bootstrap selection and source retention. These are local
client/transport proofs, not deployed server copy/install or physical-device
acceptance. No server, migration, deployment or database reset occurred.

Scoped C1–C4 and whitespace checks passed; no dependency or custom motion was
added. Manual native review covers system navigation/buttons, explicit labels,
growing hero text, loading/retry and date confirmation. ReUI audit tooling and a
native lint configuration are unavailable; physical VoiceOver remains open.
See [roadmap 15](../../../gatherory-web-app/docs/roadmaps/blueprint-ranking-roadmap/15-single-preview-and-event-creation.md).

### Context-specific Blueprint previews — October 23, 2026

The later single public scroll above supersedes this slice's public Home/Ideas
layout; its context and authorization boundaries remain.

Explore public previews now show Like, Save and More, with Use Blueprint and
Not interested inside More. Saved/Liked previews keep direct Use; shared links
keep direct Use without public preferences. Public Home, Ideas and idea detail
are read-only: no editor, Add, personal response controls, Decide or private
draft overlay. Yours keeps personal editing, Add, Decide and Save Changes.
Preferences require the current account's action store and do not create copies.

Explicit Use creates or resumes a local working plan through
`BlueprintPreviewWorkingCopy.prepare` before opening the existing setup flow.
Existing edits, dates, revision and shared-source identity are preserved;
pending installation and empty-owner guards run before any write. Switching
back to Yours reloads the collection so a newly prepared working copy appears
immediately. Existing backend pin/copy/install and import gates remain in place.

Three smaller Luna agents handled policy/helper tests, read-only workspace
views and the native UI harness; parent integration wired routes, ownership
guards and the library refresh. With Xcode 27.1 on iPhone 18 Pro / iOS 27.0:

- **61 tests passed, zero failed/skipped**, in
  `/tmp/gatherory-preview-actions-r2.xcresult`: 58 unit methods across
  `BlueprintPreviewPresentationTests`, `BlueprintPreviewWorkingCopyTests`,
  `BlueprintPreviewSessionTests`, `BlueprintActionsTests`,
  `BlueprintPreviewEditingTests` and `BlueprintPersonalLibraryTests`, plus
  three `BlueprintPreviewActionsUITests` methods. These check owner/context
  isolation, pending-import protection, unchanged existing working copies,
  acknowledged preferences, Light/Dark discovery controls, Saved's direct Use,
  personal Add/Decide and the fixture Explore → Save → Saved → Use → Yours
  journey. The initial run's missing working card exposed the stale Yours
  collection; reloading on selection fixed it and the journey passed in r2.
- **One additional UI method passed, zero failed/skipped**, in
  `/tmp/gatherory-preview-actions-accessibility.xcresult`. It opens public Ideas
  and idea detail in Dark Accessibility XXXL and checks that Add, Edit, Decide
  and personal response filters remain absent. Together these runs cover
  **62 distinct methods: 58 unit and four UI**.
- Six standard captures are in `/tmp/gatherory-preview-actions-r2-shots`;
  two accessibility captures are in
  `/tmp/gatherory-preview-actions-accessibility-shots`. Light/Dark discovery,
  Saved, working-copy Ideas, public Ideas and idea detail were inspected. The
  existing event picker truncates its label at Accessibility XXXL; this is
  read-only-control evidence, not a full large-text layout pass.
- Localization passes for **1,678 English/Spanish strings** in
  `/tmp/gatherory-preview-actions-localization.log`, with the existing
  `AppCopy.swift` dynamic-key warning. No dependency was added.

The DEBUG-only `-BlueprintPreviewActionsVisualFixture` requires seeded
development data, an ephemeral store, skipped authentication and a nonempty
owner. It uses an in-memory preference transport and a temporary real draft
store. Its Use action calls the production working-copy helper, then closes
preview instead of opening setup; the subsequent Yours card is a local recovery
plan. It does not exercise authenticated server pin/copy/install or canonical
import. Public/shared source separation and cross-owner/pending behavior have
unit coverage. Live copy/install, physical devices and VoiceOver remain separate
acceptance checks. Release excludes the fixture.

The final **Release simulator build passed** with no compiler warnings in
`/tmp/gatherory-preview-actions-release.log`.

Scoped C1–C4 source and whitespace checks passed. Manual native review retains
system controls, icon accessibility labels, loading/retry behavior and current
account guards. The web-specific ReUI audit tool and native lint configuration
are unavailable. No web/server code changed, so web tests were not rerun. See
[roadmap 13](../../../gatherory-web-app/docs/roadmaps/blueprint-ranking-roadmap/13-discovery-and-library-actions.md).

### Unified Yours library — October 23, 2026

Yours is one grid for authored personal records, saved customizations/recovery,
and installation-receipt sources. The Drafts/Installed scope selector is removed
and the primary Yours/Saved/Liked picker stays directly below the navigation
bar, including the empty state. Existing draft files and preference cleanup
remain compatible; no migration or reset is required. Continue setup appears
only for confirmed setup-date progress, with the pending canonical-import
recovery banner retained. Create Blueprint opens the native managed-event
chooser and existing private capture/review flow.

With Xcode 27.1 on the iPhone 18 Pro / iOS 27.0 simulator:

- **42 unit tests passed** for `BlueprintLibraryProjectionTests`,
  `BlueprintLibraryCollectionSelectionTests`, `BlueprintLibraryModelTests`,
  `BlueprintSetupRecoveryTests` and `BlueprintPreviewSessionTests` in
  `/tmp/gatherory-yours-library-r2.xcresult`. Seven new projection tests check
  exact full-payload deduplication, normalized sets, different source/share/
  revision/progress, nested definition changes despite equal hashes, corrupt
  or foreign receipt sources, and contextual setup progress. This run's three
  UI failures were fixed and superseded by r3: an inherited container ID hid
  action identifiers, and two tests tapped the tab before initial routing
  settled. A first compile attempt also caught missing `try` in a test helper.
- **3 UI tests passed, zero failed/skipped** in
  `/tmp/gatherory-yours-library-r3.xcresult`. Light/Dark empty-state checks
  assert the picker near the top, no secondary scope, reachable Create/Explore,
  managed-event chooser presentation/dismissal, and Explore navigation. Mixed
  content checks all three source types, recovery preview return and scrolling;
  pending setup checks the visible recovery row and Continue setup banner.
  Seven captures are in `/tmp/gatherory-yours-library-r3-shots`; Light/Dark empty
  states, chooser, mixed grid, preview and pending banner were inspected.
- **35 additional unit methods passed, zero failed/skipped** in
  `/tmp/gatherory-yours-recovery-regression.xcresult` for
  `BlueprintSetupDraftTests`, `BlueprintPreviewEditingTests`,
  `BlueprintCaptureLinkTests` and `BlueprintPersonalLibraryTests`. One method
  runs three dynamic parameter cases (37 executions, 35 methods).
- Localization passed for **1,677 English/Spanish strings** in
  `/tmp/gatherory-yours-localization.log`, with the existing `AppCopy.swift`
  dynamic-key warning. No dependency was added.

The final **Release simulator build passed** with no compiler warnings in its
log: `/tmp/gatherory-yours-library-release.log`. The fixture remains Debug-only.

The UI harness uses `-BlueprintLibraryVisualFixture` and
`-BlueprintLibraryFixtureState empty|mixed|pending`, guarded by Debug, seeded
development data, an ephemeral store and skipped authentication. Feature API
loads and per-account library/draft files are bypassed; fixture mutations are
disabled. The preview reads its fixture recovery payload in memory. The
Explore return also uses its existing local visual fixture. The chooser lists
seeded manageable events; no authenticated capture, publication, sharing,
installation or live account-switch sequence is performed by these UI tests.
Those boundaries retain unit coverage; physical device/VoiceOver and live
capture acceptance remain separate.

Scoped C1–C4 source and whitespace checks passed with no matches. Native manual
review retains system controls, labels, account/permission gates, Dynamic Type
one-column behavior, and large empty-state buttons. The web-specific ReUI audit
tool and native lint configuration are unavailable. No server code changed;
web tests were not rerun. See [roadmap 14](../../../gatherory-web-app/docs/roadmaps/blueprint-ranking-roadmap/14-unified-yours-library.md).

### Native Search/profile alignment — October 23, 2026

Explore replaces the separate expanded title row with native
`.toolbarTitleDisplayMode(.inlineLarge)`. At the top, Search and the existing
profile action share a row; scrolling uses the compact system title. The
native `.searchable` field and focus bindings are retained.

**7 focused tests passed, zero failed/skipped**, using Xcode 27.1 on the iPhone
18 Pro / iOS 27.0 simulator: six `BlueprintDiscoveryNavigationTests` and
`BlueprintExploreHeaderUITests.testNativeHeaderAlignmentTypingAndScrolling`.
The UI method runs Light and Dark, checks title/profile centers within eight
points, enters `wedding`, scrolls results while preserving the query, dismisses
search, and checks the aligned Browse header and reachable controls. Eight
screenshots were exported; aligned Light/Dark, Light typing, and Dark
scrolled/compact captures were inspected. The first run failed because the
test assumed the dismissal action was named Cancel; the observed native iOS 27
button is Close. The corrected test queries the navigation bar's native
Close/Cancel action. No custom dismissal control was added.

Result: `/tmp/gatherory-inline-search-header-r2.xcresult`; screenshots:
`/tmp/gatherory-inline-search-header-r2-shots`; log:
`/tmp/gatherory-inline-search-header-r2.log`. The Release simulator build passed
(`/tmp/gatherory-inline-search-header-release.log`). C1–C4 scoped source and
whitespace checks passed with no matches; native manual accessibility review
retains the profile label and system focus/keyboard handling. The web-specific
ReUI audit tool and native lint configuration are unavailable. No new strings
or dependencies were added. Existing unrelated compiler warnings in other
test files remain. This local fixture does not test server relevance, live
catalog authorization or physical VoiceOver. The subsequent preview action
implementation is recorded separately above and in
[the action review](../../../gatherory-web-app/docs/roadmaps/blueprint-ranking-roadmap/13-discovery-and-library-actions.md).

### Ads-enabled Explore stability — October 23, 2026

The ad-enabled follow-up prefetches upcoming slots, admits a first creative only
below the viewport, and retains a measured reservation for admitted slots through
lazy remounts and creative expiry. Preview presentation suspends ad work without
discarding unexpired same-account inventory; dismissal resumes Browse without
activating Search. Original expiry deadlines and account/privacy resets remain.
See [advertising behavior](explore-advertising.md#october-23-native-scroll-verification)
and [the roadmap evaluation](../../../gatherory-web-app/docs/roadmaps/blueprint-ranking-roadmap/12-ads-enabled-feed-stability.md).

With Xcode 27.1 on iPhone 18 Pro / iOS 27.0 simulator:

- **38 tests passed, zero failed/skipped**: 35 unit tests covering placement,
  session lifecycle, discovery/navigation and layout dimensions, plus three UI
  tests. These cover real Google SDK sample ads in Light/Dark, 20-to-40-item
  pagination, organic preview return without Search activation, no-ad card
  geometry, and a Dark accessibility XXXL native-ad remount.
- After adding stale geometry callback rejection, **9 follow-up tests passed,
  zero failed/skipped**: the new Light/Dark arrival test checks visible card
  x/y/width/height within one point before scrolling when the prefetched sample
  is ready, and repeats all eight placement-policy tests. These are overlapping
  runs, not 47 distinct tests.
- The inspected Light/Dark SDK captures both report **No implementation issues
  found** in Google's native validator. Accessibility text wraps naturally
  within the one-column width; long content remains scrollable. Preview-return
  and final arrival screenshots were also inspected in both appearances.
- English/Spanish localization coverage passed for **1,671 strings**. The
  existing dynamic-key warning in `AppCopy.swift` remains unrelated.
- The final **Release simulator build passed** without the sample app ID
  override. Its built Info.plist retains `EXPLORE_ADS_ENABLED=NO` and
  `EXPLORE_ADS_TEST_MODE=NO`, with Gatherory's configured production IDs.

Evidence: `/tmp/gatherory-ad-scroll-final.xcresult`,
`/tmp/gatherory-ad-scroll-final-shots` (22 captures),
`/tmp/gatherory-ad-arrival-final.xcresult`,
`/tmp/gatherory-ad-arrival-final-shots` (2 captures),
`/tmp/gatherory-ad-scroll-localization.log`, and
`/tmp/gatherory-ad-scroll-release.log`.

Scoped C1–C4 source checks and native manual accessibility/layout review passed.
The sole duration-pattern match is the existing non-animation impression dwell
calculation in `BlueprintDiscoveryCards.swift:153`. No custom animation or
per-frame state updates were added. Tracked and new native files passed
whitespace checks. The web-specific ReUI audit tool and a native lint
configuration are unavailable; neither was represented as an automated pass.
The web roadmap files passed Prettier checks; no server code changed in this
follow-up, so web application tests were not rerun.

The SDK UI runs use `-BlueprintAdsScrollVerification`, an ephemeral local
40-item catalog with 20-item pages and disabled Blueprint actions/measurement.
Build with `ADMOB_APP_ID=ca-app-pub-3940256099942544~1458002511` for these Debug
tests; the sample native unit is already configured. This uses the existing
exact sample-pair consent exception, not Gatherory's UMP messages. The checked-in
Debug configuration is unchanged. Native Release ads remain disabled.

The broad test selectors were `GatheroryUITests/BlueprintAdsScrollUITests`,
`GatheroryUITests/BlueprintCatalogLayoutUITests`, and `GatheroryTests/` suites
`ExploreAdPlacementTests`, `ExploreAdSessionLifecycleTests`,
`BlueprintDiscoveryNavigationTests`, `BlueprintDiscoveryTests`, and
`LayoutDimensionTests`. The follow-up selected
`BlueprintAdsScrollUITests/testPrefetchedAdDoesNotMoveVisibleBlueprints` and
`ExploreAdPlacementTests`. Both used the repeatable command above with sample
app ID override, the named simulator, and
`-derivedDataPath /tmp/gatherory-admob-release-gate-derived`.

Placement-policy tests exercise late first fill, missing/invalid geometry,
creative loss and reservation retention, fitting visible replacements, taller
below-viewport replacements, width changes, and reset. Original 55-minute
expiry timing was reviewed in code rather than exercised over 55 minutes.
SDK validation popups were dismissed; advertiser actions were never tapped.
This does not verify production authenticated catalog access, Gatherory UMP,
physical-device VoiceOver/scrolling, ad conversions, copy/install attribution,
or frame rate. No-fill estimates can still leave uneven column tails.

October 22, 2026: **Explore card stability and search restoration**. The custom
search field and experimental shared large-title/profile row were reverted to
the standard native title, toolbar profile action and system search field.
Catalog cards no longer resize from decoded cover aspect ratios, retain the
dark text-contrast gradient without Glur, and preserve stable grid identities.
Screens with no ad session no longer allocate phantom ad-slot height estimates.

`BlueprintCatalogLayoutUITests.testCardGeometrySurvivesImageLoadingAndScrollRemounts`
passed in explicit **light and dark app appearances** using forty DEBUG-only
entries with mixed category ratios, long/short titles, and optional bylines.
It waits for decoded artwork, checks card height/placement within one point,
scrolls to the end and back, and checks for oversized empty column tails. Eight
screenshots were exported; selected loaded/scrolled/returned captures were
visually inspected in both appearances. Result:
`/tmp/gatherory-card-stability-no-inactive-slots.xcresult`; attachments:
`/tmp/gatherory-card-stability-no-inactive-slots-shots`.

**32 focused native tests passed** across discovery, navigation, preview session
and layout dimensions (`/tmp/gatherory-card-stability-unit.xcresult`). Localization
coverage passed for **1,671 English/Spanish strings**. The final Release simulator build passed
(`/tmp/gatherory-card-stability-release-final.log`). Native manual accessibility/source review and C1–C4 checks passed;
the existing dwell-duration calculation is not animation. The web-specific
ReUI audit tool and native lint configuration are unavailable. The fixture
skips Explore API actions, ads and measurement; this does not verify live ad
creative sizing, authentication, server search scoring, physical VoiceOver or
scroll frame-rate performance. See [the rendering handoff](explore-performance.md).

The mobile session lifecycle refactor was verified on October 20, 2026 with
**790 tests in 108 suites passed**, running only `GatheroryTests` on the iPhone
18 Pro simulator. English/Spanish localization coverage passed for **1,384
strings**. No automated UI tests ran. The first build found an actor-isolated
test-helper default argument; after fixing that helper, the complete target
passed. Final output: `/tmp/gatherory-auth-lifecycle-native-20261020-r2.log`;
result bundle:
`/Users/nexus/Library/Developer/Xcode/DerivedData/Gatherory-fkdlsthewnqyuwcnvrboywcmoqza/Logs/Test/Test-Gatherory-2026.10.20_15-35-52--0400.xcresult`.

New coverage includes pure chain precedence and safe fallbacks, restoration
unavailability versus expiry, all provider save-before-authentication gates,
guest retention on sign-out, generation/cancellation barriers, A → B → A
preparation, import-before-cleanup, and installed lifecycle hooks against real
in-memory SwiftData. Both remote-account and local fixture onboarding retain
skipped creation for the same account without skipping another account's flow.
Physical-device acceptance and remaining deletion-cleanup hardening are in
the [mobile session lifecycle design](../../../gatherory-web-app/docs/architecture/mobile-session-lifecycle.md).

Optional blueprint To-dos were verified on October 20 with **711 tests in 97
suites passed**, excluding UI tests. Result:
`/tmp/gatherory-blueprint-todos-native-20261020-r2.xcresult`.
Capture starts excluded; tests cover explicit exact-event selection, child
deselection pruning, legacy missing fields/empty wire omission, saved definition
round trips, stable child placement and task-only child previews. Installation
recovery tests retain each frozen request's original capability list and bytes.
English/Spanish localization checks pass for **1,339 strings**. Physical-device
and rollout checks are in the
[blueprint To-do handoff](../../../gatherory-web-app/docs/roadmaps/to-dos-reminders-roadmap/02-blueprint-to-dos.md).

Shared event To-dos were verified on October 20, 2026 with the complete
`GatheroryTests` non-UI target: **706 tests in 97 suites passed** on the iOS
simulator. Coverage includes exact-event planner permissions, required title
and optional date/website validation, assignment/self-claim eligibility,
current-assignee preview priority, claimable fallback, exact-event assignee/profile
lookup and event/account isolation,
completion/undo, legacy archive decoding,
durable outbox retries, account-scoped server versions, bootstrap/pull overlays,
in-flight acknowledgements and unsent create/delete cancellation. The English
and Spanish localization check passed for **1,337 strings**. Result bundle:
`/tmp/gatherory-todo-status-tabs-native-20261020-r2.xcresult`. The editor/date
picker follows the existing Idea editor's grouped fields; the task list uses
Upcoming / Completed segments, one gray grouped surface, separators and one
compact action line. Upcoming includes all unfinished items. Successful Add
returns to Upcoming; edits retain the selected segment. Assignee names and Take
reuse participant avatars with initials fallback. Manage has one outer
preview surface without a nested filled Take control.
Completed rows have quiet status styling and checkbox undo; icon-and-label Take
buttons and haptics after successful local saves still need physical-device
acceptance. UI tests were
excluded as requested. Physical-device accessibility, multi-device/offline and
deployment acceptance remain in the
[shared To-dos handoff](../../../gatherory-web-app/docs/roadmaps/to-dos-reminders-roadmap/01-shared-event-to-dos.md).

| Area                       | Coverage                                                                                                                                                                                                                                                 |
| -------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Authentication             | Canonical Better Auth identity, stored-session restore, verification-required registration, provider token forwarding, sign-out waiting for pending sync, failed sign-in/restore recovery, deletion failure retaining the account until acknowledgement. |
| Local persistence and sync | Atomic workspace/outbox writes, stable mutation IDs, batching, retries, conflict/rejection handling, tombstones, reopening disk stores, canceled/stale work, per-account leases and cache isolation.                                                     |
| Sync HTTP boundary         | Fresh bearer tokens after account switches, missing/empty tokens, bootstrap compatibility, push envelopes and retry identity, pull scope/cursor encoding, remote change decoding, all push dispositions, HTTP/network/decoding error classification.     |
| Event access               | Invitation acceptance and approval states, host/collaborator/guest routing, per-event RSVP and leave behavior, guest projection restrictions, account-scoped invitation/join-request caches.                                                             |
| Presentation               | Account loading renders real UIKit-backed content; UI tests exercise workspace entry, sharing, invitation forms, event deletion/cancellation/archive, editor presentation, and the Decide primer.                                                        |

`PostgresSyncTransportTests` intercepts every request through an injected
`URLProtocol` and uses `.invalid` hosts. Its fixtures have no shared mutable
handler, Keychain access, or live backend dependency. Request assertions check
the wire representation, rather than only round-tripping the same encoder.

The loading presentation test waits up to five seconds for UIKit to connect a
window scene. It still fails if no scene arrives and retains its rendered-pixel
assertions; the wait addresses a test-host launch race, not an app behavior change.

## Verification record — October 14, 2026

Environment: Xcode 27.0 (27A266a), iPhone 18 Pro simulator, iOS 27.0.

- Original native baseline: 209 tests passed.
- Expanded native unit suite: 219 tests passed (10 new test functions, with
  additional parameterized cases).
- Web backend: 163 tests passed; nine opt-in integration tests skipped.
- Generated backend contracts and TypeScript checking passed.
- Functional UI suite: all eight selected scenarios passed across the initial
  run and a targeted rerun. The launch-performance benchmark was intentionally
  excluded, not reported as a functional pass.

One intermediate native run exposed the pre-existing window-scene launch race
in `AccountLoadingPresentationTests`. All new tests passed on that run; the
full unit suite passed after adding the bounded scene wait.

The first functional UI run passed seven scenarios and found outdated Decide
primer feedback expectations. The app and translation catalog already distinguish
personal preferences from explicit team approval. After aligning the test's
English/Spanish expectations with that behavior, the primer passed in light,
dark, accessibility-large-text, and Spanish configurations. The complete 219-test
unit suite also passed again in that final run (220 tests including the primer).
No production app code or permission policy changed.

### Subsequent archive/codec and budget-rule extraction

The same day's refactor expanded the native suite to **241 passing tests**.
Seven functional UI tests passed; the Decide primer's upward-swipe assertion
failed both with the extraction and on the untouched baseline commit `09eaf9f`.
The earlier successful UI run above remains a historical result, not a claim
that the UI suite is consistently green. See
[workspace extraction results](workspace-boundaries.md#verification-results)
for the exact scope, regression coverage, and remaining gesture-test issue.

### Subsequent outbox and remote-merge extraction

The native baseline passed all 241 tests before this stage. After extracting
`WorkspaceOutboxWriter` and `WorkspaceRemoteMerger`, the full `GatheroryTests`
target passed **265 tests** (306 executions including parameterized cases), with
zero failures or skipped native tests. The 24 new tests cover staging without
premature commits, caller-owned rollback, coalescing/retry/deletion semantics,
account isolation, ordered remote merges, failed remote batches, and local-save
rollback without premature notification. Existing debounce/no-echo tests also
passed.

Final result bundle: `Test-Gatherory-2026.10.14_12-58-58--0400.xcresult` in the
project's DerivedData `Logs/Test` directory. The same Xcode/simulator environment
and native-only command above were used. **UI tests were not run**, at the user's
request; the earlier UI results remain historical. No web/server code changed,
and no web, live-backend, or physical-device checks were run in this stage.

### Subsequent media-bookkeeping extraction

The 265-test native baseline passed. After extracting `WorkspaceMediaBookkeeper`,
the full `GatheroryTests` target passed **276 tests** (321 executions including
parameterized cases), with zero failures or skipped native tests. Eleven new
tests cover transfer/file reuse and cleanup, format detection, account isolation,
durable transitions, retry filtering/backoff, sanitization, and stage-only writes.
Failure tests explicitly preserve the existing limitation that database rollback
does not undo file writes or deletions.

Final result bundle: `Test-Gatherory-2026.10.14_13-04-20--0400.xcresult` in the
project's DerivedData `Logs/Test` directory. The same native-only command and
Xcode/simulator environment were used. **UI tests were not run**, as requested.
No live backend, web/server, or physical-device checks were performed.

## iOS 26 compatibility — October 15, 2026

- Lowered the project and unit-test deployment minima to 26.0; app and UI-test
  targets inherit the project setting. `verify-deployment-targets.sh` passed
  all 12 effective-setting checks (three targets, two configurations, two SDKs).
- Compiling with the iOS 27 SDK against the iOS 26 minimum identified the new
  MusicKit picker and asynchronous AVAudioSession activation/deactivation APIs.
  The native picker and asynchronous audio APIs remain available on iOS 27+.
  On iOS 26, the picker uses the existing authorized song-search sheet (one song
  per selection), and audio activation/deactivation uses `setActive` on a serial
  background queue. Activation errors still reach the existing failure path;
  deactivation remains best-effort and notifies interrupted audio sessions.
- Both picker paths retain the same permission checks, track deduplication,
  draft editing, and `workspace.updateIdea` save path. Persistence schemas,
  transaction boundaries, outbox behavior, transports, and account isolation
  code were not changed.
- The Debug simulator app built and the full `GatheroryTests` target passed:
  **337 tests / 404 test runs**, zero failures or skips, on iPhone 17 / iOS 27.0.
  The suite includes offline persistence, outbox, account-switching, and sync
  regressions. Result bundle: `/tmp/gatherory-ios26-final-tests.xcresult`.
- The unsigned Release device build passed. The Debug simulator and Release
  device artifacts declare `MinimumOSVersion = 26.0`; their Mach-O build
  metadata also records `minos 26.0`. English/Spanish localization checks passed
  for all 940 strings. Existing Swift 6 isolation warnings remain outside this
  compatibility change.

Xcode 27.0 (27A266a) was used. Only the iOS 27 simulator runtime is installed:
**the iOS 26 fallback branches have been compiled but not exercised on an iOS 26
runtime/device**. Verify song search/selection/cancel, preview playback/pause/stop
and interrupted-audio resumption on iOS 26 before release, along with the
offline/reconnect/account-switching device checks below. UI automation was
intentionally not run. No live backend or TestFlight upload was performed.

## Checks still needed before release

These local tests are not a release sign-off. With disposable accounts and an
explicitly selected environment, verify:

1. Password, Apple, and Google sign-in, session restoration after relaunch, and
   expired-session recovery on a physical device with the intended signed build.
2. Two-account/two-device sync: offline edits survive relaunch, reconnect drains
   changes, conflicts are surfaced, and switching accounts never exposes the
   previous account's workspace, media, invitations, or pending changes.
3. Real host/collaborator/guest invitation and approval flows, including event
   access without organization membership and per-event RSVP/departure.
4. Media upload/download and retry behavior against the chosen storage provider.
5. Disposable account deletion: server records, sessions, provider tokens,
   storage objects, Keychain credentials, and local caches are handled correctly,
   without deleting another account's shared data.

Live provider calls, destructive account deletion, production database changes,
and permissions/RBAC changes were not part of this verification pass. Historical
deployment notes in other documents are not evidence of the current deployed state.

## Shared album redesign — October 16, 2026

The Home → event card → Shared Album experience now uses adaptive masonry,
contributor attribution, full-photo viewing/zoom, and selection for saving to
Photos. See [the album design and behavior](shared-album.md).

- Added **29 native tests** for geometry/EXIF orientation, selection, viewer state,
  and add-only Photos saving. Existing uploader/event deletion regression tests
  remain in the native suite. The final full `GatheroryTests` run passed
  **510 tests in 71 suites**, with zero failures.
- **Four album UI tests passed**: three iPhone tests cover direct preview routing,
  viewer dismissal, empty state, and multiselect controls in light, dark, and
  accessibility XXXL text; the iPad test confirms four nonzero photo cards in
  more than two columns. The saved app appearance is explicitly set in UI
  fixtures, separately from the system appearance. Screenshots were inspected
  for the gallery, viewer, selection state, and iPad layout.
- The final simulator build passed with the iOS 26 minimum. Deployment-target
  verification passed for all app/test targets and configurations. English and
  Spanish localization coverage passed for all **1,152 strings**.
- Test-driven UI checks caught and resolved first-open preview routing, photo
  card accessibility exposure, and repeated image-loading lifecycle updates
  during an animated viewer transition. Only the selected viewer page retains
  its decoded image; layout metadata is cached across selection changes.

Final result bundles:

- Native: `/tmp/gatherory-album-native-final.xcresult`
- iPhone routing, empty state, and selection: `/tmp/gatherory-album-ui-complete.xcresult`
- Final saved-appearance/large-text matrix: `/tmp/gatherory-album-appearance-ui.xcresult`
- iPad columns: `/tmp/gatherory-album-ipad-verified.xcresult`

Xcode 27.0 and the iOS/iPadOS 27 simulator runtime were used. The iOS 26 minimum
was compiled and checked, but no iOS 26 runtime/device was available. PhotoKit
writes and authorization outcomes were injected in native tests; UI tests did
not add fixture images to the actual Photos library. Before release, verify
real-device grant/denial/Settings recovery and saving, pinch/double-tap/swipe
interaction, and iPad multitasking resizing. Live backend behavior and uploads were not verified in this pass.

## Native QR distribution — October 19, 2026

Owner Create & Share and Share Blueprint now offer an inline QR
and system PNG sharing for the current generated template URL. Normal URL
sharing remains available. Core Image renders locally with opaque black/white
integer-scaled modules and a four-module quiet margin. There is no scanner,
remote QR service, automatic Photos write, or workspace/outbox media record.

The sharing surface derives from the live store URL and now displays the QR
immediately after explicit creation, without an expansion step. Closing the owner flow, account changes, loss of local management
permission, confirmed revocation and definitive server denials clear the
transient credential. Stale responses remain generation guarded. Link creation
and refresh are explicit and online-only; historical raw URLs remain
unrecoverable. Incoming preview, independent saved copies and frozen
installation recovery retain their existing paths and transaction boundaries.

Changed code: `BlueprintShareQRCode.swift`, `BlueprintShareQRCodeView.swift`,
both owner sharing views/stores, `BlueprintCopy.swift` and `Localizable.xcstrings`.
Tests extend both owner-store suites and add `BlueprintShareQRCodeTests`.
The cross-repository handoff is web
`docs/roadmaps/blueprints-roadmap/22-qr-distribution-handoff.md`.

### Local verification

Xcode 27.0, iPhone 18 Pro / iOS 27.0 simulator:

- Complete non-UI suite: **640 tests passed in 93 suites**, **758 executions**
  including parameters, zero failures/skips. App compilation also passed.
- QR tests decode both the rendered image and exported PNG to the exact input
  URL with Apple's Core Image QR detector; invalid URLs, raster dimensions,
  opaque binary pixels, uniform module blocks and the white quiet margin pass.
- Both owner-store suites cover transient state clearing on denials,
  invalidation and A → B → A changes; network failures retain retry behavior.
  Existing preview, independent saved-copy, installation and sync tests passed.
- `bash scripts/verify-localizations.sh`: **1,253 English/Spanish strings** passed.
  The pre-existing generic `AppCopy` non-literal extraction warning remains.
- `bash scripts/verify-deployment-targets.sh`: **12 checks** passed, iOS 26.0.
- Web `pnpm test`: **465 passed / 23 environment-gated skipped**; generated
  contracts and `pnpm typecheck` passed. No web production build was run.
- `git diff --check` passed in both repositories.

Exact native command:

```sh
xcodebuild test -project Gatherory.xcodeproj -scheme Gatherory \
  -destination 'platform=iOS Simulator,id=3A4621C1-A19F-4EDD-A25F-6A1AB7663D6F' \
  -only-testing:GatheroryTests -parallel-testing-enabled NO \
  -disableAutomaticPackageResolution -collect-test-diagnostics never \
  -resultBundlePath /tmp/gatherory-qr-native-20261019-verified.xcresult \
  POSTHOG_ENABLED=NO
```

An initial missing SwiftUI builder annotation was fixed. An intermediate run
passed 639 tests but Vision failed to initialize its simulator inference context;
the test now uses Core Image's software-backed QR detector and still requires
exact payload recovery from both images. The final full run above passed.
UI tests were intentionally not run. Only the iOS 27 runtime is installed;
iOS 26 compilation/configuration checks do not establish device behavior.

### Device and deployment checks still open

- Scan the displayed and exported/printed QR from a second physical device;
  exercise system PNG sharing and confirm scan quality in light/dark appearance,
  large Dynamic Type, VoiceOver and iPad sizing.
- Check iOS 26 and the current OS, owner-flow dismissal, sign-out/account changes,
  and permission loss while the QR or system sharing surface is open.
- Verify HTTPS universal links, association caching, browser fallback and sign-in
  continuation against the intended deployed origin. Scanning must only preview.
- Revoke before first save and verify denial; separately verify independent saved
  blueprints and completed workspaces survive revocation and author deletion.
  Exercise existing frozen-request installation recovery with disposable accounts.
- Confirm earlier sharing/copy endpoints and migrations are deployed before a
  native release. This QR slice needs no new API or migration. No live backend,
  physical-device run, database reset/seed, upload or deployment was performed.

### Simpler sharing follow-up — October 19, 2026

Workspaces Share Blueprint now opens the existing owned-template link flow,
requiring explicit Create Share Link. No template/link/publication is created
on opening. Empty/multiple template cases retain explicit creation/selection;
Save Blueprint remains private. QR appears immediately, with one short
explanation and Share Link / Share QR Code. More → Manage Sharing holds
historical links, versions, Search visibility and revoke controls. Publication
review remains before creation and is not repeated after success.

The views and localization changed; owner stores, transports, permissions and
recovery implementations did not change in this follow-up. Uncertain creates
still require successful explicit refresh before replacement, and dismissal,
account switches, denials and confirmed revocation clear transient credentials.
The workspace card's duplicate Manage Links action was removed; its equivalent
remains available from the sharing toolbar menu.

UI tests are excluded; physical-device and deployed-link checks above remain
outstanding.

Final verification for this follow-up: **640 native non-UI tests passed** in 93
suites (**758 executions** including parameters), zero failures/skips, on
Xcode 27.0 / iPhone 18 Pro / iOS 27.0 simulator with the iOS 26 minimum.
Rendering/PNG decoding, explicit link creation, historical URL handling,
revocation, account isolation, saved copies, installation and offline-sync
regressions passed. **1,255 English/Spanish strings** passed localization
validation; the existing generic AppCopy non-literal extraction warning remains.
Whitespace checks passed in both repositories. UI tests, live backend/device
checks, database changes, uploads, deployment, commits and pushes were excluded.
No server/contracts changed, so the web checks from the first slice were not
repeated for this native presentation follow-up.

Exact commands from the iOS root:

```sh
xcodebuild test -project Gatherory.xcodeproj -scheme Gatherory \
  -destination 'platform=iOS Simulator,id=3A4621C1-A19F-4EDD-A25F-6A1AB7663D6F' \
  -only-testing:GatheroryTests -parallel-testing-enabled NO \
  -disableAutomaticPackageResolution -collect-test-diagnostics never \
  -resultBundlePath /tmp/gatherory-simple-sharing-20261019-verified.xcresult \
  POSTHOG_ENABLED=NO
bash scripts/verify-localizations.sh
```

### Reusable owner sharing links — October 19, 2026

Newly acknowledged owner links are now retained in When Unlocked / This Device
Only Keychain items scoped to account, origin, source event and template. Both
owner creation paths use the same vault. Reopening first reads owned templates
and the authorized link list; only a matching active row restores the same URL
and QR, including its original immutable revision. No link is created on open.

Create Blueprint is available only when no template exists. Replacement has a
separate explicit confirmation and does not revoke previous links; revocation
is separately confirmed. Older unsaved links and links from another device
cannot be reconstructed from server hashes and need explicit replacement.

Dismissal/account changes clear memory, with no offline vault restoration.
Missing/revoked/retired/unauthorized sources clear affected cached credentials.
Normal sign-out retains the account namespace; acknowledged account deletion
clears it after remote success. Vault-save failure keeps the current URL and
supports a local-only save retry. Uncertain HTTP creation retains its existing
successful-refresh requirement; original request/installation/sync boundaries
are unchanged. UI automation remains excluded.

The new vault tests inject fake Security calls, checking namespace isolation,
protected nonsynchronized items, corrupt records, write/delete failures and
account-specific cleanup. Owner-store regressions cover reopening without HTTP
creation, exact pins, stale account callbacks, denied/offline reads, revocation,
save-failure retry and uncertain replacement. Authentication regressions cover
cleanup after successful deletion and retention after sign-out/failed deletion.

Physical-device checks remain: close/relaunch/reopen; A → B → A; development and
production origins; revoke elsewhere and reopen; locked Keychain and retry;
explicit replacement/revocation; iOS 26/current OS; system sharing and deployed
universal-link/preview behavior. No deployment/database reset/upload/commit/push.

Verification for reusable owner links: **665 native non-UI tests passed** in
94 suites (**783 executions** including parameters), zero failures or skips.
Xcode 27.0 / iPhone 18 Pro / iOS 27.0 Simulator compiled against the existing
iOS 26 minimum. The final run includes secure-store error/isolation tests,
reopen-without-creation and exact-pin tests, stale/denied/offline reads, explicit
replacement after an unreadable saved credential, local-only save retry,
revocation, account deletion/sign-out, and the existing copy/install/sync suites.
The app build passed. Localization validation passed **1,262 English/Spanish
strings**; the existing generic AppCopy extraction warning remains. Whitespace
checks passed in both repositories. UI tests were skipped. No new backend/API
code, schema, deployment, database mutation, upload, commit or push was involved.

A failed local restore never displays its credential. After successful server
authorization, the owner may retry reading it or explicitly create a replacement;
a malformed record does not permanently block that explicit recovery action.
Account deletion attempts namespace cleanup after remote acknowledgment, matching
the existing best-effort Keychain cleanup policy. If the OS refuses that local
cleanup, the deleted account's links still fail server authorization; physical
Keychain cleanup failure behavior remains part of device acceptance.

Exact commands from the iOS root:

```sh
xcodebuild test -project Gatherory.xcodeproj -scheme Gatherory \
  -destination 'platform=iOS Simulator,id=3A4621C1-A19F-4EDD-A25F-6A1AB7663D6F' \
  -only-testing:GatheroryTests -parallel-testing-enabled NO \
  -disableAutomaticPackageResolution -collect-test-diagnostics never \
  -resultBundlePath /tmp/gatherory-reusable-sharing-20261019-complete.xcresult \
  POSTHOG_ENABLED=NO
bash scripts/verify-localizations.sh
```

### Blueprint product wording — October 19, 2026

Native fixed UI and accessibility copy now says Blueprint / Blueprints, with
Spanish plano / planos. English fallbacks in library/empty-state/link error copy
and content-editor titles are aligned. Existing localization keys, curated or
user-authored content, payload fields and shared-link paths are preserved.
The web app's fixed authoring/sharing copy is aligned too; it currently has no
Spanish UI catalog beyond translated server errors.

QR generation remains local Core Image rendering of the exact UTF-8 HTTPS
share URL. Its bearer token resolves the pinned published blueprint through the
existing preview; the QR contains no blueprint document or workspace payload.

Wording verification: **665 native non-UI tests** (94 suites, 783 executions)
and **465 web tests** passed; **23 web environment-gated tests** were skipped.
TypeScript and generated-contract checks passed. Native localization validation
passed for **1,262 English/Spanish strings**. The web currently has an English UI
catalog and Spanish server errors only; no incomplete Spanish UI catalog was
introduced. A display-value audit found no remaining template/plantilla terms
in effective native English/Spanish catalog copy; technical keys are unchanged.
Both repositories passed whitespace checks. UI tests were intentionally skipped.

Source files for this wording slice: native `BlueprintCopy.swift`,
`Localizable.xcstrings`, `BlueprintLibraryView.swift`,
`BlueprintLibraryEmptyState.swift`, `BlueprintContentEditors.swift`,
`BlueprintLinkManagement.swift` (localized fallback only), and web
`src/i18n/locales/en.ts`. Existing user-authored/curated content, protocols,
sharing credentials and QR generator behavior are unchanged. Device/deployment
checks from the earlier slices remain open; no deployment/commit/push occurred.

Commands: web `pnpm test`, `pnpm typecheck`, and Prettier checking of the English
catalog; native `bash scripts/verify-localizations.sh` and:

```sh
xcodebuild test -project Gatherory.xcodeproj -scheme Gatherory \
  -destination 'platform=iOS Simulator,id=3A4621C1-A19F-4EDD-A25F-6A1AB7663D6F' \
  -only-testing:GatheroryTests -parallel-testing-enabled NO \
  -disableAutomaticPackageResolution -collect-test-diagnostics never \
  -resultBundlePath /tmp/gatherory-blueprint-wording-20261019.xcresult \
  POSTHOG_ENABLED=NO
```

## Direct first-time workspace sharing — October 19, 2026

Workspaces long-press → Share Blueprint now skips the empty Create Blueprint
landing and initial selection screen when no owned blueprint exists. It loads
the authorized source and prepares the existing read-only review automatically.
The owner sees the actual selected content and Search/privacy disclosures before
choosing **Publish to Search**; **Edit Blueprint** opens the optional selection
screen. Opening this flow never creates a blueprint, publishes or creates a link.
Existing blueprints keep their explicit link creation/replacement flow and saved
credentials still reopen directly to the authorized QR. Multiple blueprints
still require choosing which one to share. A sole blueprint no longer has a
redundant Choose Blueprint section heading.

A failed initial read/review exposes the existing error and explicit retry;
source changes, account/permission checks and frozen creation/link recovery
remain authoritative. Editing does not automatically send another review.
Close dismisses the sharing sheet in the direct route; creation from management
still returns to management. Private Save Blueprint remains unchanged.

Changed native files: `BlueprintLinkManagementView.swift`,
`BlueprintCreateShareView.swift`, and `BlueprintCreateShareStoreTests.swift`.
The new regression verifies read-only preparation makes no template/link writes,
and explicit creation binds to the reviewed selection and hashes. The complete
native non-UI suite passed **666 tests / 784 executions**, with zero failures or
skips, on iPhone 18 Pro / iOS 27 Simulator. Localization validation passed for
**1,262 English/Spanish strings**; no new copy keys were introduced. Existing
AppCopy dynamic-key extraction warning remains. Whitespace checks passed in both
repositories. A final native build also checks the management Close correction.
No server/contracts changed, so web tests were not repeated for this native
navigation change. UI tests were intentionally skipped.

Manual device acceptance: first-time sharing should open review without extra
taps, allow optional editing, and publish only after Publish to Search. Check
Close and swipe dismissal, failed reads/review and retry, source-change reload,
account/permission loss, existing saved QR reopening, multiple-blueprint choice,
and management navigation. The earlier physical scan, iOS 26, accessibility,
system sharing and deployed universal-link checks remain outstanding. No deploy,
database reset, upload, commit or push was performed.

Commands from the native repository:

```sh
xcodebuild test -project Gatherory.xcodeproj -scheme Gatherory \
  -destination 'platform=iOS Simulator,id=3A4621C1-A19F-4EDD-A25F-6A1AB7663D6F' \
  -only-testing:GatheroryTests -parallel-testing-enabled NO \
  -disableAutomaticPackageResolution -collect-test-diagnostics never \
  -resultBundlePath /tmp/gatherory-direct-sharing-20261019.xcresult \
  POSTHOG_ENABLED=NO
bash scripts/verify-localizations.sh
```

## Unlisted sharing and optional Search — October 19, 2026

This supersedes the earlier requirement to publish to Search before sharing.
First-time sharing is now **Share Blueprint → Review → Create Share Link**.
The existing authorized native create produces an immutable unlisted publication
(`discoverable: false`), then creates its link and local QR. No Search listing
is created. Actual selected content and the unlisted/forwardable-link disclosure
remain visible before the explicit action; editing stays optional.

**Manage Sharing → List in Search** is a separate confirmed action. Removing
Search visibility is separately confirmed too. Both use the existing listing
endpoint and exact created template/revision; neither replaces the link, changes
its QR or revokes access. Existing blueprints' visibility is unchanged. Private
Save Blueprint explicitly disables link creation as well as Search publication.

Link creation and Search publication now have separate native flags. The frozen
creation request still binds its reviewed visibility and hash; listing updates
only occur after creation and respect account, permission, mutation and uncertain
link recovery gates. Failure/mismatched acknowledgements preserve the existing
share URL; stale account callbacks are discarded. Listing state survives explicit
link replacement. No server/API/schema or transaction/sync change was needed.

Changed native files for this follow-up: `BlueprintCreateShareStore.swift`,
`BlueprintCreateShareView.swift`, `WorkspaceBrowserView.swift`, `HomeView.swift`,
`BlueprintCopy.swift`, `Localizable.xcstrings` and
`BlueprintCreateShareStoreTests.swift`. Regression coverage includes unlisted
sharing, private saves, separate list/unlist without duplicate blueprint/link
creation, failed acknowledgements, account switching and link replacement.

Manual acceptance still needs two accounts/devices: verify a new blueprint is
absent from another user's Search but opens through its QR; confirm List in Search
and withdrawal leave the same link usable; verify saved copies stay independent.
Check first-time/reopen, management dismissal, offline/denied requests, physical
scanning, iOS 26/current OS, accessibility and deployed universal links as recorded
above. No deployment, database reset, build upload, commit or push was performed.

Verification: native app build and **670 non-UI tests / 788 executions** passed
with zero failures/skips on iPhone 18 Pro / iOS 27 Simulator. **1,263** native
English/Spanish strings passed localization validation (the existing dynamic
AppCopy extraction warning remains). Web `pnpm test` passed **465 tests**, with
**23 environment-gated tests skipped**, including generated-contract checks.
Whitespace checks passed in both repositories. UI tests and live database/device
checks were excluded. Physical-device and deployment checks above remain open.

Native test command:

```sh
xcodebuild test -project Gatherory.xcodeproj -scheme Gatherory \
  -destination 'platform=iOS Simulator,id=3A4621C1-A19F-4EDD-A25F-6A1AB7663D6F' \
  -only-testing:GatheroryTests -parallel-testing-enabled NO \
  -disableAutomaticPackageResolution -collect-test-diagnostics never \
  -resultBundlePath /tmp/gatherory-unlisted-sharing-20261019.xcresult \
  POSTHOG_ENABLED=NO
bash scripts/verify-localizations.sh
```

## Plain-language sharing review — October 19, 2026

The supplied screenshot showed a truncated Review title between three toolbar
actions, raw `planning_scouting` / `part_of_event` values, repeated categories
and arithmetic-style negative day offsets. This presentation review follows the
local apple-design guidance on progressive disclosure (HIG Layout, Visual
hierarchy) and writing for a broad audience (HIG Writing, Getting started).
The screenshot supports hierarchy/copy findings; physical sizing and contrast
were not measured from it.

The review now shows the plan name, a short mode-specific explanation and one
personal-text reminder. **View Included Content** expands the full selected
description, events, ideas/notes and tips/instructions. **Edit Content** is
inline; the primary **Create Share Link** / **Save Blueprint** button is
full-width at the bottom and wraps at larger text sizes. Close stays in the
toolbar and the review title has room. The redundant details heading and repeated
Before You Share paragraphs are removed. Raw purpose metadata is hidden in both
selection and review; category/audience values retain localized mappings.
Repeated main-event labels are omitted.

The new presentation helper renders “The day before · 6:30 PM” or “148 days
before · 11:00 AM” using the user's short-time conventions. It validates clock
input and preserves local time/day-offset semantics; no blueprint data or
schedule proposal is changed. Unlisted creation, Search opt-in, explicit link
creation/replacement/revocation, account/permission checks, source hashes and
uncertain-create recovery remain unchanged.

Additional native files: `BlueprintReviewPresentation.swift` and
`BlueprintReviewPresentationTests.swift`; existing
`BlueprintCreateShareView.swift`, `BlueprintCopy.swift` and
`Localizable.xcstrings` are updated. Non-UI tests cover relative wording,
12/24-hour output, midnight preservation and invalid inputs. No UI automation is
used. Manual acceptance must check the initial compact review and expanded long
content, multiline bottom action, largest Dynamic Type, VoiceOver disclosure and
focus order, light/dark appearance, Spanish, iPad and error/retry states on iOS 26
and the current OS. Earlier physical QR/deployed-link checks remain open.
No deployment, database reset, build upload, commit or push was performed.

Verification: the native app build and **674 non-UI tests / 792 executions**
passed with zero failures/skips on iPhone 18 Pro / iOS 27 Simulator.
Localization validation passed for **1,275 English/Spanish strings**, with the
existing AppCopy dynamic-key extraction warning. Both repositories passed
whitespace checks. UI tests were skipped; no new runtime screenshot was captured,
so the device visual/accessibility checks above remain outstanding. No server
code/contracts changed and web checks were not repeated for this presentation
change.

Commands from the native root:

```sh
xcodebuild test -project Gatherory.xcodeproj -scheme Gatherory \
  -destination 'platform=iOS Simulator,id=3A4621C1-A19F-4EDD-A25F-6A1AB7663D6F' \
  -only-testing:GatheroryTests -parallel-testing-enabled NO \
  -disableAutomaticPackageResolution -collect-test-diagnostics never \
  -resultBundlePath /tmp/gatherory-plain-review-20261019.xcresult \
  POSTHOG_ENABLED=NO
bash scripts/verify-localizations.sh
```

## Compact private saving — October 19, 2026

Save Blueprint from both Home and the Workspaces card now opens the compact
prepared review directly. It skips the initial selection screen; **Edit Content**
still allows naming and selecting content before reviewing again. A single
bottom **Save Blueprint** action creates the private copy. Opening/reviewing does
not write, create a link or list in Search. The saved state shows the plan name
and one saved confirmation, without repeated pre-save instructions. Link-sharing
warnings are omitted from the private-save overview. Included content remains
expandable before and after saving.

Files changed for this follow-up: native `HomeView.swift`,
`WorkspaceBrowserView.swift`, `BlueprintCreateShareView.swift` and the existing
private-save regression in `BlueprintCreateShareStoreTests.swift`. No transport,
server, localization keys, transaction, permission or account-isolation rules
changed. Existing source-change, uncertain-save and explicit retry gates remain.

Manual acceptance: open private save from both entry points; inspect/edit included
content; save once; check confirmation and dismissal, offline/source-change retry,
large text/VoiceOver and account switching. Confirm no link or Search listing is
created. Earlier physical-device/deployment checks remain open. UI tests remain
excluded. No deployment, reset, upload, commit or push was performed.

Verification: **674 native non-UI tests / 792 executions** passed with zero
failures/skips on iPhone 18 Pro / iOS 27 Simulator. The private-save test now
asserts that opening/reviewing makes no writes, followed by exactly one private
blueprint and no links/listing after the explicit save. Localization checks
passed for **1,275 English/Spanish strings** (existing AppCopy extraction warning).
The final build checks the private-only removal of the sharing warning. UI tests
were skipped; device visual checks remain outstanding. No server changes required
new web checks.

Native test evidence: `/tmp/gatherory-private-save-review-20261019.xcresult`,
using the earlier full non-UI test command with that result-bundle path.
Final build log: `/tmp/gatherory-private-save-final-build.log`.

## Sharing actions menu and existing-edit verification — October 19, 2026

The user's latest direction supersedes the earlier separate content-review UI:
workspace and blueprint editing are already the content verification step.
Sharing/saving now use a short name/summary and an explicit creation action.
The mandatory authorized source and review-hash reads still run behind the
scenes. Opening never publishes, saves or creates a link automatically, and
stale-source/account/permission gates remain authoritative.

Manage Sharing and Share Blueprint now both keep the current QR and native
Share Link / Share QR Code controls on the main screen. The toolbar menu contains
**Create Replacement Link**, active-link **Revoke** choices and optional
**List in Search / Remove from Search**, with the existing confirmations.
Historical date/version information is used only to distinguish links in the
revoke submenu; no Search dashboard, link-history table or mode switch replaces
the QR. Missing local credentials are explained briefly and replacement remains
in the menu. A true no-link state offers explicit Create Share Link. Uncertain
creation retains explicit Refresh Links recovery and never retries writes
automatically. Private post-create library-save failures still offer Retry.

The creation store now has a separate guarded replacement action. Ordinary
create cannot replace an existing URL. An explicit replacement keeps the old
URL/Keychain credential until the new response is valid, creates no second
blueprint, preserves Search visibility and does not revoke old links. A lost
replacement response keeps the old URL and requires a successful explicit refresh
before another replacement. Account changes discard late callbacks.
An authoritative refresh still clears a revoked or missing current link; keeping
an old QR while a replacement is uncertain never bypasses that check.

Changed native files: `BlueprintLinkManagementView.swift`,
`BlueprintCreateShareView.swift`, `BlueprintCreateShareStore.swift`,
`BlueprintCreateShareStoreTests.swift`, `BlueprintLinkManagement.swift`,
`BlueprintLinkManagementStoreTests.swift`, `BlueprintCopy.swift` and
`Localizable.xcstrings`. Server/API/schema, offline sync, recipient copies and
installation transactions are unchanged. Earlier narrative describing repeated
UI review, inline admin tables or a second management screen is historical.

Manual acceptance: open both sharing modes, verify QR/link remain immediately
available, and exercise menu confirmations for current/older links and Search
visibility. Verify private save has no link/Search side effect, fresh creation
has no repeated verification page, and uncertain replacement retains the old
URL until refresh. Check account/permission loss, missing Keychain credentials,
Dynamic Type/VoiceOver, iPad, and physical scan/deployed universal-link behavior
on iOS 26/current OS. UI tests remain excluded. No deployment, database reset,
build upload, commit or push was performed.

Verification: native build and **678 non-UI tests / 796 executions** passed
with zero failures/skips on iPhone 18 Pro / iOS 27 Simulator. Replacement tests
cover both stores retaining the old URL/credential during the request, switching
only after acknowledgement, refresh gates, missing/revoked-link invalidation,
listing preservation and stale-account callbacks. **1,276 English/Spanish
strings** passed localization validation; the existing AppCopy dynamic-key
warning remains. Both repositories passed whitespace checks. UI tests were
skipped; physical visual/accessibility/deployed-link checks remain open. No
server/contracts changed, so web checks were not repeated for this native slice.

A final build validates the single-active-link menu shortcut: Revoke is directly
available in More when only one link is active; multiple links use a submenu.
Test result: `/tmp/gatherory-menu-sharing-20261019-complete.xcresult`.
Final build log: `/tmp/gatherory-menu-sharing-final-build.log`.

Native verification used:

```sh
xcodebuild test -project Gatherory.xcodeproj -scheme Gatherory \
  -destination 'platform=iOS Simulator,id=3A4621C1-A19F-4EDD-A25F-6A1AB7663D6F' \
  -only-testing:GatheroryTests -parallel-testing-enabled NO \
  -disableAutomaticPackageResolution -collect-test-diagnostics never \
  -resultBundlePath /tmp/gatherory-menu-sharing-20261019-complete.xcresult \
  POSTHOG_ENABLED=NO
bash scripts/verify-localizations.sh
```

## Simpler blueprint browsing and use — October 19, 2026

The regular-user pass now covers preview, the library, content editors and
workspace setup in addition to sharing/saving. **Use Blueprint** opens setup
directly; the redundant confirmation in front of that date/setup screen is
removed. Its existing account, pending-install and explicit draft-save checks
still run. Opening/scanning/browsing does not create a workspace. The final
**Create Workspace** action and required main/child date confirmations remain
explicit. The regular editor's optional plan summary remains useful for checking
the resulting dates; it no longer shows raw event/configuration fields. Its main
date now has the same confirmation gate as the direct creation route.

The library collections are **Blueprints** and **Drafts**. Cards keep names and
useful workspace context while dropping internal revision/draft-version badges.
Duplicate local-read and network warning cards are consolidated. Existing
creation shortcuts, account-scoped collection preferences, deletion confirmations
and unfinished-workspace recovery remain. Editors use Add/Edit Idea or Event,
“For” instead of Target, and show length errors after input rather than red
missing-title warnings immediately on opening; Save still rejects blank names.

Preview dates now use short localized “Suggested · The day before · 6:30 PM”
wording instead of arithmetic offsets or repeated no-date paragraphs. Confirmed
dates retain their readable time-zone abbreviation. The plan summary's optional
Details explains omitted content in plain language without raw source keys or
capability codes, and repeated reasons are merged. Retry copy says Try Again or
Continue Creating Workspace rather than installation/request terminology.
Independent copies, exact frozen retry inputs, permissions, source pins, local
save/remote transaction boundaries and installation recovery are unchanged.
The public browser preview receives matching short copy only; no web authoring
UI or routes are changed.

Changed native files in this pass: `BlueprintPreviewView.swift`,
`BlueprintWorkspaceHomeView.swift`, `BlueprintWorkspaceEventDetail.swift`,
`BlueprintSetupView.swift`, `BlueprintLibraryView.swift`,
`BlueprintLibraryEmptyState.swift`, `BlueprintContentEditors.swift`,
`BlueprintWorkspaceDecideView.swift` (accessibility labels only),
`BlueprintCopy.swift` and `Localizable.xcstrings`. Web fixed copy is in
`src/i18n/locales/en.ts`. Earlier QR/link/token changes remain uncommitted and
are preserved; this pass adds no API/schema or persistence change.

Verification: **678 native non-UI tests / 796 executions** passed with zero
failures/skips on iPhone 18 Pro / iOS 27 Simulator. A final native build checks
the concise omission explanations and time-zone display. Existing date-readiness,
preview/draft isolation, independent-copy, exact-retry and sync regressions passed.
**465 web tests** passed; **23 environment-gated tests** were skipped.
TypeScript, generated-contract freshness, web locale formatting, and whitespace
checks passed. **1,279 English/Spanish native strings** passed localization
validation, with the existing generic AppCopy extraction warning. UI tests were
skipped. No live DB/device acceptance was inferred from unit tests.

Manual checks: browse → preview → Use Blueprint → confirm dates → Create
Workspace; save/cancel unsaved choices; reopen drafts offline; finish an uncertain
creation; verify foreign-time-zone and DST displays; check library/card naming,
editor validation, long text, VoiceOver, Spanish, iPad and iOS 26/current OS.
Existing physical QR and deployed universal-link checks remain open. No deploy,
database reset, build upload, commit or push was performed.

Native result: `/tmp/gatherory-simple-blueprint-flow-20261019.xcresult`, using
the earlier full non-UI command with that result-bundle path. Final build:
`/tmp/gatherory-simple-blueprint-flow-final-build.log`. Web verification used
`pnpm test`, `pnpm typecheck` and Prettier on `src/i18n/locales/en.ts`;
native localization used `bash scripts/verify-localizations.sh`.

## Sharing badges and public creator names — October 19, 2026

Native owner views show Link active, In Search or Private only from known
sharing metadata. Stale/offline reads withhold badges rather than imply privacy;
retired sources do not display active sharing. First Search publication asks
for a chosen public creator name (trimmed, 1–80 Unicode scalar values), with no
account-name/email default. Later publication reuses that label. Discovery,
shared previews and owned blueprint cards show the byline where available.
Legacy unnamed entries omit it, and curated starters say Gatherory.

Listing acknowledgements must match both requested revision and creator name
before the native state changes. Account changes discard pending callbacks.
No link is created by listing, and unlisting/revocation remain independent.
Duplicate titles are allowed; republishing retains the catalog key; saved copies
remain private and do not inherit the original's public creator label.

Manual acceptance remains: long names and duplicate titles, first publication,
cancel/error/lost-response recovery, unlist/relist, revoke current/older links,
cross-account switching and fresh reads from a second device. Check Dynamic
Type, VoiceOver, Spanish, iPad, light/dark mode and iOS 26/current OS. Complete
physical QR, share-sheet and deployed universal-link checks. UI tests are skipped.
The server requires the additive creator-name migration before release; only a
new disposable local test database has been migrated. No existing database was
reset or migrated; no deployment, upload, commit or push was performed.

Verification: **683 native non-UI tests / 801 executions** passed with no
failures/skips on iPhone 18 Pro / iOS 27 Simulator. New coverage includes legacy
metadata decoding, chosen-name validation, transport and exact acknowledgement
checks, account changes and sharing-count transitions with unknown metadata.
**1,287 English/Spanish strings** pass localization validation, with the existing
AppCopy dynamic-key extraction warning. The web suite passes **471 tests**, with
**23 environment-gated skips**; all **nine blueprint database integration
suites** pass separately against the disposable PostgreSQL 18 database.
TypeScript, portable-contract freshness, changed web source/test formatting and
both repositories' whitespace checks pass. UI tests were not run.

Result: `/tmp/gatherory-attribution-native-final-20261019.xcresult`.
Native log: `/tmp/gatherory-attribution-native-final-20261019.log`.
Use the earlier full non-UI command with that result-bundle path, followed by
`bash scripts/verify-localizations.sh`. Deployment prerequisites and full web/DB
commands are recorded in the web repository's
`docs/roadmaps/blueprints-roadmap/22-qr-distribution-handoff.md`.

## Catalog scope and personal Search controls — October 20, 2026

First-link creation remains unlisted. The server catalog query previously also
included private owner revisions, which made them look published in the owner's
Search. Catalog discovery now uses only curated or exact public listed revisions
for every viewer; direct owner preview and private-library access remain intact.
Personal blueprint long-press menus now offer Publish to Search / Remove from
Search with existing localized confirmation copy. Removal changes only the
listing; links, creator metadata, immutable revisions and saved copies survive.

Native personal visibility writes reject stale/loading rows and duplicate
requests, retain their confirmed version/listing inputs, and update cache only
on a matching server acknowledgment for the same account generation. Publishing
accepts a first publication or legitimate next revision. Search refreshes when
its tab opens or the app returns active.

Manual acceptance: first link → Link active, no In Search, no owner/other-account
Search result; explicit publish → one public result; Remove from Search from
the blueprint menu → hidden for both accounts while the same QR/link still works.
Check failed/lost responses, account changes, long-press confirmations, older
public/newer private revisions, Spanish and VoiceOver. Physical QR and deployed
universal-link checks remain open. Skip UI tests. No deploy, database reset,
build upload, commit or push was performed.

Verification: **684 native non-UI tests / 802 executions** passed with zero
failures/skips on iPhone 18 Pro / iOS 27 Simulator. The unlist transport sends
the confirmed version/listing inputs and requires an explicit null listing in
its response; publication acknowledgment tests cover first publication,
legitimate revision advances and metadata mismatches. Existing link, account,
independent-copy and offline-sync regressions pass. **1,287 English/Spanish
strings** pass localization validation, with the existing AppCopy dynamic-key
warning. Web/server checks pass **472 tests / 23 environment-gated skips**, all
**nine blueprint database suites**, TypeScript, contract freshness, formatting
and whitespace checks. The database suites ran only against a new disposable
PostgreSQL 18 database, which was removed afterward.

Result: `/tmp/gatherory-catalog-controls-native-20261020.xcresult`.
Log: `/tmp/gatherory-catalog-controls-native-20261020.log`. Use the full non-UI
command above with this result path. No UI tests or deployment were performed.

## Device guest V1 candidate — October 20, 2026

Continue as Guest now creates a named device profile for local planning and
public guest invitation attendance. Account sharing/blueprint controls require
sign-in. Guest archives do not enqueue remote writes or media uploads. Account
handover adds to existing plans, remaps authorship/Decide identity and records an
account-bound receipt; failures preserve the source and retry proof. Invited
event projections remain separate from the planner library. Device-only exit
warns before removal and offers sign-in/cancellation.

**735 native non-UI tests in 100 suites pass**, including guest persistence,
authentication and invitation transport/cache regressions. Result:
`/tmp/gatherory-v1-guest-native-final2-20261020.xcresult`; log:
`/tmp/gatherory-v1-guest-native-final2-20261020.log`. A final focused regression
run also builds the recovery wording for using the wrong target account.
**1,363 English/Spanish strings** pass `bash scripts/verify-localizations.sh`
(the existing AppCopy dynamic-key extraction warning remains).

Web/server `pnpm test` passes **480 tests**, with **28 environment-gated skips**;
contract freshness and TypeScript pass. Guest contracts/repository integration
pass separately (3 tests) on a fresh disposable migrated PostgreSQL database;
the guest HTTP authorization suite passes separately (1 test) on a local Vite
server using that database. Those test resources were removed. Changed source
formatting and both whitespace checks pass.

No UI tests were run. No production migration, deployment, existing-database
reset, build upload, commit or push was performed. Physical guest relaunch/offline
planning, provider sign-in/import, host roster/RSVP, failure recovery, Spanish and
accessibility acceptance remain. Follow the full cross-repository
[guest implementation handoff](../../../gatherory-web-app/docs/roadmaps/v1-guest-release-candidate-roadmap/01-device-guest-mode.md)
for commands, architecture boundaries and remaining release checks. Browser-only
guest RSVP and other research priorities remain outside this first native slice.

## Attend as guest; sign in to help plan — October 20, 2026

V1 sharing and invitation wording now separates public guest attendance from
planning access. Public guest invitations offer Attend as Guest; collaborator
invitations require sign-in and retain host approval/access levels. View-only
invitations say Sign In to View Plans. Email invitations still require the
invited account. No sign-in or forwarded link automatically upgrades a guest.
A short sign-in message explains that guest plans and invitations are kept.

Native invitation previews now explicitly follow the active session: anonymous
previews ignore leftover account tokens, signed-in previews use the real bearer,
and requests don't use browser cookies. Pending invitation and guest profile/
proof retention have non-UI regressions. DTO policy tests distinguish public
collaborator previews (which may disclose details without sign-in) from permission
to attend as a device guest. Planning permissions are unchanged.

The browser retains its account requirement, explains iPhone guest attendance,
and accurately separates pending approval from accepted access. Its new pure
presentation tests cover role/access wording, join response state and English/
Spanish invitation-key parity. Full web tests pass 484 tests (28 gated skips),
portable-contract checks and TypeScript pass. **739 native non-UI tests in 101
suites pass**, including the new handover/preview regressions. Result:
`/tmp/gatherory-v1-attend-copy-native-20261020.xcresult`; log:
`/tmp/gatherory-v1-attend-copy-native-20261020.log`. **1,375 English/Spanish
strings** pass localization coverage (existing AppCopy dynamic-key warning).
Both repositories pass whitespace checks; changed TypeScript formatting passes.
No UI tests, deployment, database reset, build upload, commit or push.

## FCM mobile proof-of-concept verification — October 20, 2026

The full non-UI `GatheroryTests` target passed **749 tests in 103 suites** with
parallel testing and PostHog disabled. A focused notification/navigation/guest
authentication run passed 18 tests in 3 suites (included in the full total).
English/Spanish localization coverage passed for **1,377 strings**.

Evidence: `/tmp/gatherory-fcm-native-full-20261020.log` and `.xcresult`,
`/tmp/gatherory-fcm-native-focused-20261020.log` and `.xcresult`, and
`/tmp/gatherory-fcm-localizations-final-20261020.log`.

See [mobile notifications](mobile-notifications.md) for feature-off configuration,
identity/isolation behavior, compatible Firebase pin, and remaining Firebase/APNs
and physical-device acceptance. No UI test target was run, no live push was sent,
and no deployment, build upload, commit or push was performed.

## Account deletion device cleanup — October 20, 2026

The full non-UI `GatheroryTests` target passed **825 tests in 116 suites**.
Coverage includes durable journal failures, confirmed and interrupted deletion,
local-only retries without repeating server deletion, sync cancellation without
uploading pending work, and cleanup of account-owned media and blueprint stores.
Isolation regressions preserve another account's visible graph, pending edits,
preferences and credentials, plus retained guest and unowned legacy data.
English/Spanish localization coverage passed for **1,394 strings**; the existing
AppCopy dynamic-key extraction warning remains. Both repositories pass
`git diff --check`.

Command (from the native repository):

```sh
xcodebuild test -project Gatherory.xcodeproj -scheme Gatherory \
  -destination 'platform=iOS Simulator,id=3A4621C1-A19F-4EDD-A25F-6A1AB7663D6F' \
  -only-testing:GatheroryTests -parallel-testing-enabled NO \
  -disableAutomaticPackageResolution -collect-test-diagnostics never \
  POSTHOG_ENABLED=NO
bash scripts/verify-localizations.sh
```

Log: `/tmp/gatherory-account-deletion-20261020-r3.log`.
Result: `~/Library/Developer/Xcode/DerivedData/Gatherory-fkdlsthewnqyuwcnvrboywcmoqza/Logs/Test/Test-Gatherory-2026.10.20_15-51-25--0400.xcresult`.

Physical-device acceptance remains: use a disposable account to check deletion,
interrupted cleanup and relaunch, retry after a store failure, server rejection,
and an interrupted confirmation followed by explicit device-only removal.
Verify another account and retained guest data remain intact, and that an
account still present on the server can sign in after local-only removal.
Check the recovery screen in Spanish, with VoiceOver and larger text.
No UI tests, real account deletion, database reset, deployment, build upload,
commit or push were performed. Web/server changes for this slice are
documentation only; no server deployment is needed for the local cleanup logic.

## Explicit announcements and event wording — October 20, 2026

The full native non-UI target passes **846 tests in 119 suites**. Announcement
tests exercise Unicode limits, explicit sends, retained retry IDs/drafts,
credential and event isolation, denied access, invalid responses, conflicts,
late responses across A → B → A, and authorized notification navigation.
An existing budget assertion now expects the renamed **Event Budget** label.
English/Spanish localization verification passes for **1,432 strings**, with
the existing AppCopy extraction warning. Rendered copy is checked for obsolete
workspace terminology while internal keys remain stable.

```sh
xcodebuild test -project Gatherory.xcodeproj -scheme Gatherory \
  -destination 'platform=iOS Simulator,id=3A4621C1-A19F-4EDD-A25F-6A1AB7663D6F' \
  -only-testing:GatheroryTests -parallel-testing-enabled NO \
  -disableAutomaticPackageResolution -collect-test-diagnostics never \
  POSTHOG_ENABLED=NO
bash scripts/verify-localizations.sh
```

Log: `/tmp/gatherory-announcements-20261020-r2.log`.
Result: `~/Library/Developer/Xcode/DerivedData/Gatherory-fkdlsthewnqyuwcnvrboywcmoqza/Logs/Test/Test-Gatherory-2026.10.20_17-24-38--0400.xcresult`.

Web/server `pnpm test` passes **505 tests / 33 environment-gated skips**;
TypeScript, portable-contract freshness and targeted formatting pass. The
announcement database integration also passes separately on a fresh disposable
PostgreSQL 18 container, covering transactional rollback, concurrent retries,
permission/guest/claim isolation, notification eligibility and deletion privacy.
The container was removed and existing databases were not changed.

See the [announcement handoff](../../../gatherory-web-app/docs/roadmaps/notifications-roadmap/02-event-announcements.md)
for permissions, online-only send/draft limits, migration and physical-device
acceptance. No UI tests, real push sends, deployment, existing database reset,
build upload, commit or push were performed. The migration must be separately
applied to an approved target before testing this flow on the iPhone.

## One Updates composer with audiences — October 20, 2026

**855 native non-UI tests in 120 suites pass** with the full `GatheroryTests`
target, parallel testing disabled and PostHog disabled. New checks cover
server-authorized audience choices, a Planning default, missing-capability
fail-closed decoding, request IDs bound to message and audience, matching
acknowledgements, exact-event legacy-note privacy, explicit server denial,
offline cached history and device-guest ownership. Existing history fixtures
now declare their child participation through public APIs. English/Spanish
localization coverage passes for **1,447 strings**, with the existing AppCopy
dynamic-key warning.

Command: use the full non-UI Xcode command in the preceding section.
Log: `/tmp/gatherory-audience-native-20261020-r2.log`.
Web/server `pnpm test` passes **512 tests / 33 environment-gated skips**;
TypeScript, contract freshness, formatting and both whitespace checks pass.
Audience database integration passes separately against disposable PostgreSQL
18, including Planning/Guests privacy and current dispatch permissions.

Home and Manage now open one Updates screen; the old team-note composer has no
active entry point. Existing notes remain private Planning history. Device-only
planning retains its private Save path without HTTP or notifications. No old
note is converted or resent. Guests have no send control.

Both additive announcement migrations require application to an approved target
before device testing. Verify each audience with a host, contributor, read-only
planner, account attendee and device guest; test an audience change after failed
Send, account/role changes in flight, the older note history, local guest Save,
VoiceOver, larger text and Spanish. See the shared announcement handoff for the
complete remaining physical-device checks. No UI tests, existing database
changes, real push sends, deployment, build upload, commit or push were performed.

## Share Event Schedule — October 21, 2026

The full `GatheroryTests` target passes **866 tests in 121 suites**, including
**11 new export tests** for manager/active-role authorization, exact runtime
account identity, email/preview fallback rejection, device/account guest privacy,
root/child/scoped-event boundaries, approved public schedule filtering, immutable
allowlisted copies, unscheduled dates, Spanish, DST and inclusive all-day dates.
Account/session generation and live text changes invalidate the open share sheet.

```sh
xcodebuild test -project Gatherory.xcodeproj -scheme Gatherory \
  -destination 'platform=iOS Simulator,id=3A4621C1-A19F-4EDD-A25F-6A1AB7663D6F' \
  -derivedDataPath /tmp/gatherory-schedule-share-derived \
  -clonedSourcePackagesDirPath ~/Library/Developer/Xcode/DerivedData/Gatherory-fkdlsthewnqyuwcnvrboywcmoqza/SourcePackages \
  -only-testing:GatheroryTests -parallel-testing-enabled NO \
  -disableAutomaticPackageResolution -collect-test-diagnostics never \
  POSTHOG_ENABLED=NO
bash scripts/verify-localizations.sh
```

Log: `/tmp/gatherory-schedule-share-native-20261021-r2.log`.
Result: `/tmp/gatherory-schedule-share-derived/Logs/Test/Test-Gatherory-2026.10.21_10-08-33--0400.xcresult`.
English/Spanish localization checks pass for **1,473 strings**, including five
new sharing/export strings. The 23 existing entries without Spanish translations
were completed to clear the required catalog test; existing English and Spanish
values were preserved. The existing AppCopy dynamic-key extraction warning
remains. Both repositories pass `git diff --check`.

Open an event's **…** menu or long-press its Home card and choose **Share Event
Schedule**. This sends a text snapshot through the native share sheet. It never
includes guest/contact records or private planning details, creates no link or
permission grant, and cannot update or recall copies sent elsewhere. Local
cached permissions remain subject to existing sync; offline sharing cannot
discover a server revocation that has not reached the device.

The [implementation handoff](../../../gatherory-web-app/docs/roadmaps/event-schedule-sharing-roadmap/README.md)
records the allowlist, permission policy and physical-device checks for actual
Messages/Mail/Copy sharing, cancellation, account changes, child privacy, dates,
VoiceOver, large text and iPad presentation. Only the non-UI test target ran;
no UI-automation tests, real shares, database changes, deployment, build upload,
commit or push were performed. Existing staged build artifacts and blueprint
edits were preserved.

## CSV schedule sharing and rounded Home cards — October 21, 2026

The full `GatheroryTests` target passes **871 tests in 122 suites**. CSV export
coverage has **13 tests**, including independent RFC-4180 parsing, commas,
escaped quotes, multiline fields, Unicode, formula neutralization, explicit
ISO-8601 offsets, inclusive all-day dates and the existing permission/privacy
boundaries. Three attachment tests cover BOM/file bytes, isolated idempotent
cleanup, release and creation failure without removing existing data. Complete
file protection is requested by the write; metadata verification runs only on
a physical device because the simulator omits it.

Use the preceding Xcode command with the same unit-test target, DerivedData and
package-cache paths. Parallel testing and PostHog remain disabled. No UI-automation
target was selected.

Log: `/tmp/gatherory-csv-native-20261021-r2.log`.
Result: `/tmp/gatherory-schedule-share-derived/Logs/Test/Test-Gatherory-2026.10.21_10-20-30--0400.xcresult`.
Localization log: `/tmp/gatherory-csv-localizations-20261021.log` — **1,481
English/Spanish strings pass**, with the existing AppCopy extraction warning.
Swift parsing and both whitespace checks pass.

The Home card now shares one continuous rounded shape across its content,
native context-menu preview, interaction region and zoom source, with a subtle
shadow outside the border. Physical visual acceptance remains for long-press
lift/dismiss, normal tap/zoom/back, event-switching gestures, light/dark appearance
and accessibility settings. Also verify the actual CSV attachment in Messages,
Mail, AirDrop, Files and a spreadsheet app, plus file cleanup on share/cancel
and account/permission changes. Abrupt process termination can leave a protected
temporary file until OS cleanup; no later share reuses that file.

See the updated [schedule-sharing handoff](../../../gatherory-web-app/docs/roadmaps/event-schedule-sharing-roadmap/README.md)
for schema, security and acceptance details. No real share, database change,
deployment, build upload, commit or push was performed. Existing staged build
artifacts and blueprint edits remain preserved.

## Guest-list CSV export — October 21, 2026

The full native `GatheroryTests` target passes **884 tests in 124 suites**,
with only that target selected, parallel testing disabled and PostHog disabled.
The existing Xcode command, DerivedData directory, package cache and simulator
destination from the schedule-sharing sections above were reused.

Nine guest-export tests cover active exact-account manager authorization,
preview/email fallback rejection, guest/projection isolation, exact root/child
rosters and contextual RSVPs, distinct same-name people, contact/name redaction,
Spanish, CSV round trips/formula controls and lifecycle revalidation. Three
shared request tests verify session generation after sign-out/re-entry, workspace
scope, fresh RSVP payloads, permission loss, kind separation and pending guest
handover. Attachment coverage now also verifies cleanup isolation between two
guest files and an open schedule file. Existing schedule regressions pass.

Log: `/tmp/gatherory-guest-export-native-20261021.log`.
Result: `/tmp/gatherory-schedule-share-derived/Logs/Test/Test-Gatherory-2026.10.21_10-32-57--0400.xcresult`.
Localization log: `/tmp/gatherory-guest-export-localizations-20261021.log` —
**1,492 English/Spanish strings pass**, including 11 new labels/headers/statuses
and errors, with the existing dynamic AppCopy warning. Swift parsing and both
whitespace checks pass.

**Export Guest List** appears in the event menu and the Manage Guest List
toolbar. The attachment contains only Name and RSVP Status for that event;
the existing Guest List includes all attendee roles. Contact records, IDs,
planning roles, join requests and other events' rosters are excluded. Schedule
sharing now uses the same encoder/presenter and retains its own field allowlist.

See the [guest-list export handoff](../../../gatherory-web-app/docs/roadmaps/guest-list-export-roadmap/README.md)
for the remaining device checks: actual attachment handling, contacts absent in
outbound CSV, event-role differences, account/roster changes while sharing,
protection/cleanup and accessibility. No UI-automation tests, real exports,
remote data changes, deployment, build upload, commit or push were performed.
Existing staged artifacts, blueprint edits and earlier notification/export work
remain intact.

## Reusable event invitation QR links — October 21, 2026

The Invite screen now loads existing Guest and Collaborator public links without
creating them. Link creation remains explicit; each audience has its own reusable
link and QR, with selected-role revocation under Link Options. The native share
sheet exports a PNG. Scanning uses the existing invitation preview and explicit
join/RSVP; guest attendance does not grant planning access. Email-bound invitations
remain separate.

Pending requests are fenced by request ID, cancellation, account generation,
exact configured viewer, event, audience, and workspace. A change of account,
event, permission, or collaborator-link enablement clears stale links and QR
presentation. Settings dismissal reloads existing links without creating any.

Verification: **889 tests in 126 suites passed**, with only `GatheroryTests`
selected. QR decoding verifies the exact encoded URL. Public-link transport
tests cover nullable expiry, audience validation, read-only lookup, role-specific
revocation, and rejection of private/email or mismatched response links.
`bash scripts/verify-localizations.sh` verifies **1,500 English/Spanish strings**
with the existing dynamic AppCopy extraction warning.

```sh
xcodebuild test -project Gatherory.xcodeproj -scheme Gatherory \
  -destination 'platform=iOS Simulator,id=3A4621C1-A19F-4EDD-A25F-6A1AB7663D6F' \
  -derivedDataPath /tmp/gatherory-event-qr-derived \
  -only-testing:GatheroryTests -parallel-testing-enabled NO \
  -disableAutomaticPackageResolution -collect-test-diagnostics never POSTHOG_ENABLED=NO
```

Log: `/tmp/gatherory-event-qr-native-20261021.log`.
Result: `/tmp/gatherory-event-qr-derived/Logs/Test/Test-Gatherory-2026.10.21_10-59-23--0400.xcresult`.
Localization log: `/tmp/gatherory-event-qr-localizations-20261021.log`.

See the [event QR handoff](../../../gatherory-web-app/docs/roadmaps/event-invitation-qr-roadmap/README.md)
for server/database evidence, migration compatibility, and remaining physical
Camera scanning, saving/printing, accessibility, account-switch, and production
app-link checks. The compatible schema/server must roll out before the new mobile
build. No UI-automation tests, physical-device shares, deployment, build upload,
commit, or push were performed. Existing staged and uncommitted work is preserved.

## Mobile V1 guest and invitation recovery audit — October 21, 2026

**891 tests in 126 suites passed**, selecting only `GatheroryTests` with parallel
workers disabled. The command uses the QR verification's simulator and cached
DerivedData path, with `POSTHOG_ENABLED=NO` and diagnostics collection disabled.
`bash scripts/verify-localizations.sh` passes for **1,500 English/Spanish strings**,
with the existing dynamic AppCopy extraction warning.

Coverage includes identity-generation-bound invitation acknowledgements,
preview/accept suspension during sign-out, partial guest removal and relaunch,
Keychain/profile cleanup failures, backward-compatible profile decoding,
account-bound completed-handover cleanup, and retry without reimporting,
reclaiming attendance or generating a new proof. The lifecycle integration
fixture removes an already imported account copy to prove cleanup does not
depend on reimporting it. Existing account and guest namespace boundaries remain
in place. Recovery/removal copy now avoids promising that nothing was removed
after partial cleanup and explains that device removal does not change RSVPs.

Log: `/tmp/gatherory-guest-audit-native-20261021.log`.
Result: `/tmp/gatherory-event-qr-derived/Logs/Test/Test-Gatherory-2026.10.21_12-02-21--0400.xcresult`.
Localization log: `/tmp/gatherory-guest-audit-localizations-20261021.log`.

The [current mobile V1 checkpoint](../../../gatherory-web-app/docs/release/mobile-v1-guest-invitation-audit.md)
records the server feed-isolation regression and remaining release blockers.
Source/non-UI checks do not establish physical-device or deployed readiness.
No UI-automation tests, production changes, deployment, build upload, commits or
pushes were performed. The pre-existing staged `.build` tree is preserved.

## Invitation QR actor isolation and Home scroll observation — October 21, 2026

The immutable `GeneratedEventInvitation` value is explicitly `nonisolated` and
`Sendable`, allowing the nonisolated QR renderer to validate it under the app's
default MainActor isolation. A detached-task regression decodes and validates
the actual model outside the main actor, including rejection of a foreign origin.

Home's scroll geometry and phase observers now attach directly to its ScrollView,
before overlays, navigation destinations and sheets, instead of observing the
larger presentation container. This addresses ambiguous scroll-view selection
without changing the existing scroll callbacks or analytics configuration.
Reproduce the originally reported screen with live telemetry enabled to confirm
the runtime diagnostic is gone; no UI tests were run.

**892 tests in 126 suites passed**, selecting only `GatheroryTests`, with the
existing cached simulator command and `POSTHOG_ENABLED=NO`.
An unsigned Debug build for `generic/platform=iOS` also passed, using
`CODE_SIGNING_ALLOWED=NO`, `/tmp/gatherory-qr-actor-device-derived`, and the existing
package checkout cache. It was not installed, archived, uploaded or deployed.

Test log: `/tmp/gatherory-qr-actor-scroll-native-20261021.log`.
Result: `/tmp/gatherory-event-qr-derived/Logs/Test/Test-Gatherory-2026.10.21_12-05-31--0400.xcresult`.
Device build log: `/tmp/gatherory-qr-actor-device-build-20261021.log`.
Earlier guest-audit changes and staged build artifacts remain preserved. Nothing
was committed or pushed.

## Mobile invitation and RSVP usability — October 21, 2026

**901 tests in 127 suites passed**, selecting only `GatheroryTests`, with parallel
workers and diagnostics collection disabled. English/Spanish localization
coverage passes for **1,522 strings**, with the pre-existing dynamic AppCopy
extraction warning. No UI-automation tests were executed.

```sh
xcodebuild test -project Gatherory.xcodeproj -scheme Gatherory \
  -destination 'platform=iOS Simulator,id=3A4621C1-A19F-4EDD-A25F-6A1AB7663D6F' \
  -derivedDataPath /tmp/gatherory-event-qr-derived \
  -only-testing:GatheroryTests -parallel-testing-enabled NO \
  -disableAutomaticPackageResolution -collect-test-diagnostics never POSTHOG_ENABLED=NO
bash scripts/verify-localizations.sh
```

Nine new `GuestAttendanceRecoveryTests` cases cover retrying the actual RSVP,
pending/confirmed feedback and duplicate taps, wrong-event and unknown-status
acknowledgements, event/principal retry isolation, guest A-B-A stale completion,
acknowledgement followed by feed or cache-write failure, and an older delayed
feed being superseded by the acknowledged response. Existing guest planning,
invitation continuation, handover, deletion cleanup and authorization tests
remain in the full target. Swift parsing and `git diff --check` also pass.

Final test log: `/tmp/gatherory-invitation-usability-native-final.log`.
Result: `/tmp/gatherory-event-qr-derived/Logs/Test/Test-Gatherory-2026.10.21_15-31-56--0400.xcresult`.
Localization log: `/tmp/gatherory-invitation-usability-localizations.log`.

See [invitation/RSVP usability](invitation-rsvp-usability.md) for the changed
experience, recovery boundaries, remaining physical-device checks and the
leave-cache recovery (completed in the follow-up below). No server source, database,
production service, build upload, commit or push was changed by this pass.
Existing edits to `project.pbxproj` and `docs/app-store-release.md` were preserved.

## Durable invitation leave-cache recovery — October 21, 2026

**909 tests in 128 suites passed**, selecting only `GatheroryTests` with the
simulator command in the preceding section. Eight new leave-cache cases cover
intent persistence before DELETE, refusal to send without a durable intent, a
feed arriving during departure, cache-write plus cache-delete failure followed
by offline relaunch, exact account/server isolation, uncertain server outcomes,
corrupt-journal repair, cleanup failure ordering and retry, explicit rejoin, and
stale guest A→B→A completion. No UI tests were executed.

The initial run exposed a test-helper directory URL comparison issue (trailing
slash differences); comparing standardized directory paths fixed it. The complete
suite passed after that correction. Existing guest authorization, deletion and
handover tests remain in the full target. No server source or schema changed.

English/Spanish localization coverage passed for **1,523 strings**, with the
existing dynamic AppCopy extraction warning. Swift parsing and `git diff --check`
passed. The new storage-recovery message is translated in both languages.

Final test log: `/tmp/gatherory-leave-cache-native-final.log`.
Result: `/tmp/gatherory-event-qr-derived/Logs/Test/Test-Gatherory-2026.10.21_15-41-54--0400.xcresult`.
Localization log: `/tmp/gatherory-leave-cache-localizations.log`.

See [invitation/RSVP usability](invitation-rsvp-usability.md#durable-leave-cache-recovery)
for journal scope and physical-device acceptance. The device storage interruption,
offline relaunch and explicit rejoin checks remain outstanding. No database,
deployment, build upload or push was performed. The source changes are committed
at the user's request; existing build-number and TestFlight release-note edits
remain outside this commit.

## Mobile notification policy compatibility — October 21, 2026

The server policy keeps draft event edits quiet and classifies eligible schedule,
location, cancellation and reopening alerts in English and Spanish. It preserves
the `event_changed` wire type and the existing principal-bound native navigation;
no iOS source or Release configuration changes are needed for these alerts.

Focused `NotificationControllerTests` and `NotificationNavigationTests` pass:
**12 non-UI tests in 2 suites**, using the cached simulator command above with
only those suites selected and `POSTHOG_ENABLED=NO`. Native localization coverage
passes for **1,523 English/Spanish strings**, with the existing dynamic AppCopy
extraction warning. New server alert wording is verified in the server tests.

Native log: `/tmp/gatherory-notification-policy-native.log`.
Result: `/tmp/gatherory-event-qr-derived/Logs/Test/Test-Gatherory-2026.10.21_15-52-44--0400.xcresult`.
Localization log: `/tmp/gatherory-notification-policy-localizations.log`.
See the [server policy and verification](../../../gatherory-web-app/docs/roadmaps/notifications-roadmap/05-mobile-notification-policy.md)
for the 627 passing server tests, 14 enabled database integration cases, additive
migration and remaining physical-device checks. No UI tests, live push sends,
build uploads, commits or deployments were performed by this pass. Existing
build-number and TestFlight release-note edits remain preserved.

## Native haptic feedback — October 21, 2026

**922 tests in 130 suites passed**, selecting only `GatheroryTests`, with
parallel workers and diagnostics collection disabled. Four new `AppHapticsTests`
verify default-on behavior, opt-out suppression, foreground gating and preference
changes applying to an existing player. Injected emitters keep these tests
independent of physical haptic hardware. Existing guest/account, invitation,
RSVP, persistence, blueprint, album, budget and decision regressions remain in
the full target. No UI automation was executed.

```sh
xcodebuild test -project Gatherory.xcodeproj -scheme Gatherory \
  -destination 'platform=iOS Simulator,id=3A4621C1-A19F-4EDD-A25F-6A1AB7663D6F' \
  -derivedDataPath /tmp/gatherory-event-qr-derived \
  -only-testing:GatheroryTests -parallel-testing-enabled NO \
  -disableAutomaticPackageResolution -collect-test-diagnostics never POSTHOG_ENABLED=NO
bash scripts/verify-localizations.sh
```

English/Spanish localization coverage passes for **1,532 strings**, with the
existing dynamic AppCopy extraction warning. This pass adds only `haptics.title`
and `haptics.help`; all pre-existing catalog entries are preserved. Swift parsing
and `git diff --check` pass. The user’s current layout, blueprint setup, iPhone
Duo, marketing-fixture, build-number and release-note changes remain intact.

Final test log: `/tmp/gatherory-haptics-native-verified.log`.
Result: `/tmp/gatherory-event-qr-derived/Logs/Test/Test-Gatherory-2026.10.21_21-37-55--0400.xcresult`.
Localization log: `/tmp/gatherory-haptics-localizations.log`.

See [haptic feedback](haptic-feedback.md) for semantic mapping, settings, action
coverage and physical-device acceptance. The simulator cannot establish tactile
strength or timing. No device installation, build upload, commit, push, deployment,
backend change, production configuration or database operation was performed.

## Curated Explore cover carryover — October 22, 2026

**272 tests across all 40 Blueprint suites passed**, with only Blueprint unit
suites selected, parallel testing disabled, and `POSTHOG_ENABLED=NO`. New tests
cover validated public artwork in main-event previews, explicit removal of a
public cover without a private asset ID, persisted/encoded nil overrides, and
narrow acceptance of the server-imported main cover in copied snapshots. Child
and idea nil-to-ID enrichment remains rejected. The broader run also updated
previous Home-edit expectations for explicitly customized child inclusion and
compares dynamic palette values by resolved RGBA rather than provider identity.

Result:
`/tmp/gatherory-event-qr-derived/Logs/Test/Test-Gatherory-2026.10.22_12-13-13--0400.xcresult`.
The iPhone Duo simulator build and English/Spanish localization checks passed.
Corresponding server verification passed 289 tests, including a disposable local
PostgreSQL copy-to-install integration using mocked image/storage I/O. See the
[cover architecture](../../../gatherory-web-app/docs/architecture/blueprint-cover-images.md)
for the complete path and rollout requirements. No phone installation or server
deployment was performed, and completed existing copies were not backfilled.

## Current scan-first Blueprint cards — October 22, 2026

The current card keeps the cover/fallback, a prominent purpose-led title, and
small optional creator byline. Titles should say what experience the Blueprint
is for (for example, “Cottage Weekend” or “Backyard Birthday Party”); no title
validation or automatic renaming was added, and card metadata should not
compensate for vague titles. The existing whole-card button still opens the
read-only preview; categories, summaries, highlights, and a visible preview CTA
are omitted. Preview navigation remains read-only and the existing setup flow
stays explicit.

The native build and focused non-UI navigation/content/session suites passed **25
tests in three suites** after this card reduction. English/Spanish localization
validation passed **1,638 strings**, with the existing dynamic AppCopy extraction
warning. No new UI tests were added for the visual reduction.

```sh
xcodebuild test -project Gatherory.xcodeproj -scheme Gatherory \
  -destination 'platform=iOS Simulator,id=3A4621C1-A19F-4EDD-A25F-6A1AB7663D6F' \
  -derivedDataPath /tmp/gatherory-event-qr-derived \
  -only-testing:GatheroryTests/BlueprintDiscoveryNavigationTests \
  -only-testing:GatheroryTests/BlueprintPreviewContentTests \
  -only-testing:GatheroryTests/BlueprintPreviewSessionTests \
  -parallel-testing-enabled NO -disableAutomaticPackageResolution \
  -collect-test-diagnostics never \
  -resultBundlePath /tmp/gatherory-blueprint-scan-cards-20261022.xcresult \
  POSTHOG_ENABLED=NO
bash scripts/verify-localizations.sh
```

Log: `/tmp/gatherory-blueprint-scan-cards-20261022.log`. The isolated synthetic
fixture at `/tmp/gatherory-blueprint-scan-card-visual-20261022` compiles the
production card, cover helper, and portable contracts. Light/dark two-column
cards and an AX3 one-column long-title/byline card were visually inspected for
wrapping and overlap. The fixture stubs cover transport, category/theme values,
and copy lookup; it is not signed-in feed or navigation evidence, and it does
not establish spoken VoiceOver or physical-device behavior. No full target rerun
was performed for this visual reduction. The captures are `light.png`,
`dark.png`, and `large-text.png`.

## Superseded Blueprint discovery highlight prototype — October 22, 2026

The following historical results describe the removed event/idea-highlight
prototype only. They are not current behavior or acceptance evidence for the
title-led card. The projection and its nine tests, as well as preview-label
localization, were removed when the accepted direction changed.

The full non-UI native target built and passed **941 tests in 132 suites**.
After unused count metadata was removed and preview action text was included in
the accessibility label, a rebuilt focused run passed **34 tests in four suites**:
`BlueprintDiscoveryCardContentTests`, `BlueprintDiscoveryNavigationTests`,
`BlueprintPreviewContentTests`, and `BlueprintPreviewSessionTests`.

Nine new projection tests verified deterministic published event/idea highlights,
source identity, caps, empty and one-type content, invalid/unsupported independent
modules, ambiguous keys, orphan targets, blank/duplicate titles, and source
nonmutation. Existing navigation/session tests protect preview source retention
and the existing explicit setup flow. No automated UI tests were run.

```sh
xcodebuild test -project Gatherory.xcodeproj -scheme Gatherory \
  -destination 'platform=iOS Simulator,id=3A4621C1-A19F-4EDD-A25F-6A1AB7663D6F' \
  -derivedDataPath /tmp/gatherory-event-qr-derived \
  -only-testing:GatheroryTests -parallel-testing-enabled NO \
  -disableAutomaticPackageResolution -collect-test-diagnostics never \
  -resultBundlePath /tmp/gatherory-blueprint-discovery-cards-20261022.xcresult \
  POSTHOG_ENABLED=NO
bash scripts/verify-localizations.sh
```

The focused rerun used the same options with one `-only-testing:GatheroryTests/…`
flag per suite above and result path
`/tmp/gatherory-blueprint-discovery-cards-final-20261022.xcresult`.
Full log: `/tmp/gatherory-blueprint-discovery-cards-20261022.log`.
Focused log: `/tmp/gatherory-blueprint-discovery-cards-final-20261022.log`.

English/Spanish localization verification passed for **1,639 strings**, with the
existing dynamic AppCopy extraction warning. This slice added only
`explore.previewBlueprint`; existing localization content was preserved.
Scoped whitespace checks passed. No server code, portable contracts or database
schema changed, so no web test run was needed for this slice.

See [Explore rendering](explore-performance.md#superseded-eventidea-highlight-prototype-history)
for isolated simulator fixture details and visual evidence limits. Physical-device
scrolling, spoken VoiceOver, accessibility settings and real-feed preview opening
remain acceptance checks. No phone installation, release upload, commit, push or
deployment was performed by this slice; pre-existing work remains intact.

## Blueprint card tray removal — October 22, 2026

Blueprint card text now overlays the full progressive blurred cover, with a
smooth contrast fade and no solid tray. The title/byline and single existing
preview action remain. No strings, contracts, server behavior or persistence
changed, and no new tests were added for this visual adjustment.

The simulator app build and **27 tests in three suites passed**, selecting
`BlueprintDiscoveryNavigationTests`, `BlueprintPreviewContentTests` and
`BlueprintPreviewSessionTests`. The command uses the same device, derived-data
path and non-UI test options as the current scan-first card record above, with
result path `/tmp/gatherory-blueprint-card-overlay-20261022.xcresult`.
Log: `/tmp/gatherory-blueprint-card-overlay-20261022.log`.
The full test target was not rerun. No automated UI tests were executed.

See [Explore rendering](explore-performance.md#full-cover-text-overlay-follow-up)
for isolated fixture captures and their limits. Light/dark, missing artwork and
AX3 long-title layouts were visually inspected. Physical-device scrolling and
spoken VoiceOver remain acceptance checks; no phone install or release occurred.

## Blueprint content search — October 22, 2026

The simulator app built and **37 tests in four suites passed**, including two
new `BlueprintDiscoveryTests` feed cases. They prove server-only nested matches
survive the legacy local metadata matcher, relevance order survives page merges,
query/cursor values are forwarded, and a late superseded query page is discarded.
Existing discovery navigation, preview content and preview-session checks pass.
The native public feed already preserves server results; no production Swift,
portable response or display strings changed in this search slice.

```sh
xcodebuild test -project Gatherory.xcodeproj -scheme Gatherory \
  -destination 'platform=iOS Simulator,id=3A4621C1-A19F-4EDD-A25F-6A1AB7663D6F' \
  -derivedDataPath /tmp/gatherory-event-qr-derived \
  -only-testing:GatheroryTests/BlueprintDiscoveryTests \
  -only-testing:GatheroryTests/BlueprintDiscoveryNavigationTests \
  -only-testing:GatheroryTests/BlueprintPreviewContentTests \
  -only-testing:GatheroryTests/BlueprintPreviewSessionTests \
  -parallel-testing-enabled NO -disableAutomaticPackageResolution \
  -collect-test-diagnostics never \
  -resultBundlePath /tmp/gatherory-blueprint-content-search-20261022.xcresult \
  POSTHOG_ENABLED=NO
```

Log: `/tmp/gatherory-blueprint-content-search-20261022-native.log`.
The full native target and UI automation were not run. No new localization
validation was required because no display copy changed. The owning server
[search record](../../../gatherory-web-app/docs/roadmaps/blueprint-ranking-roadmap/02-content-search-and-related-terms.md#verification-and-handoff--october-22)
records web typecheck, full contract/test verification and a final focused
category-scope case. Server implementation is local, not deployed. Actual
signed-in search/preview on a phone remains runtime acceptance.

## Blueprint actions and measurement — October 22, 2026

Native actions require a public catalog `viewerState`. Likes, bookmarks and Not
interested are independent account preferences; commands are serialized,
request-ID retries are idempotent, and local state changes only after an
acknowledgement matching the requested catalog key, revision and hash. Account
generation changes clear in-memory state and cancel action tasks; late responses
cannot update the replacement account's store. Explore and Account settings
share one store when the toolbar sheet opens; dismissal and return to the active
tab/scene refresh preferences, consent, and catalog state. The saved-reference
screen rechecks the exact key in the current public catalog before reopening,
and saved opens submit no discovery signal or copy exposure. Unavailable rows
keep no private title or artwork.

Measurement is separate from functional preferences and starts disabled. The
Account setting uses an explicit PATCH when the person changes it; it does not
submit a signal on initial load. Passive impressions require the card's 50%
scroll-visibility callback plus a one-second uninterrupted dwell in active
Explore with no preview or covering account/category screen; query, category,
scene, account, consent, exposure, or preview changes invalidate the dwell task.
Opens are sent only on an explicit browse/category/search selection with a
matching unexpired server exposure. Recent-history cards and ad slots do not
submit signals. Signal errors do not interrupt the UI.
Optional `viewerState`, `discoveryContext`, and `discoveryExposureId` preserve
decoding and copy behavior when omitted by older payloads.

The new focused suite is `BlueprintActionsTests` (preference retry/acknowledgement,
serialized requests, account reset with late response, in-flight refresh merging,
shared account/Explore state, stale-key removal, failed-refresh preservation,
visibility threshold, expired
exposure and signal deduplication, no consent write on GET, opt-out behavior,
and optional copy-field decoding). Run it together with
`BlueprintDiscoveryTests`, `BlueprintSavedCopyResolverTests`, and
`BlueprintPreviewSessionTests` to cover catalog refresh, copy forwarding, and
existing preview behavior. Parent validation completed on the iPhone 18 Pro /
iOS 27.0 simulator using Xcode 27.1 and `POSTHOG_ENABLED=NO`:

- Simulator build and full `GatheroryTests` target: **949 tests in 132 suites
  passed**, log `/tmp/gatherory-blueprint-actions-native-final4.log`, result
  `/tmp/gatherory-blueprint-actions-native-final4.xcresult`.
- After adding a dedicated consent retry (so a failed opt-out cannot retry an
  unrelated card action) and its regression test, the four named suites passed
  **42 tests** on the final source. Log
  `/tmp/gatherory-blueprint-actions-native-verified.log`, result
  `/tmp/gatherory-blueprint-actions-native-verified.xcresult`.
- Localization coverage passed for **1,658 English/Spanish strings**, with the
  existing dynamic-key extraction warning at `AppCopy.swift:341`. Both repos'
  `git diff --check` passed.

The server passed typecheck, generated contract freshness and 693 web tests;
both new isolated-PostgreSQL suites passed, including quotas and attribution.
See [slice 03](../../../gatherory-web-app/docs/roadmaps/blueprint-ranking-roadmap/03-actions-and-measurement.md#verification-and-handoff--october-22)
for migrations, privacy/retention and rollout boundaries. Automated UI tests,
signed-in deployed-server flows, physical-device/VoiceOver acceptance and
deployment are not claimed here.

## Explicit native Blueprint catalog ranking — October 22, 2026

Paged native catalog transport now sends `ranking=baseline_v1` on every request,
including cursor continuations. The focused transport contract test verifies
the ranking capability, opaque cursor forwarding, category/query retention, and
that the legacy full-catalog request remains parameter-free. Existing
`BlueprintDiscoveryTests` verify that page merges retain server result order.
Browse, category, and search share this paged coordinator path; recent history
continues using its separate full-catalog request.

The simulator app build and **36 tests in four suites passed**:
`PostgresSyncTransportTests`, `BlueprintDiscoveryTests`,
`BlueprintDiscoveryNavigationTests` and `BlueprintActionsTests`. Xcode 27.1,
iPhone 18 Pro / iOS 27.0, `POSTHOG_ENABLED=NO`. Log:
`/tmp/gatherory-ranking-native-verified.log`; result:
`/tmp/gatherory-ranking-native-verified.xcresult`.

The new transport fixture preserves category/query scope across first and
continuation pages; its URL protocol responds with catalog-shaped payloads and
keeps bootstrap checks separate. There is no new display copy, card layout,
analytics call or ad policy. No UI automation or new screenshot fixture was
needed for this transport-only change. Signed-in target-server/device flows
remain rollout acceptance.

The server passed typecheck, 710 web tests with contract freshness, final 17
policy/paging tests and three isolated PostgreSQL suites. Its nullable exposure
policy-label migration was tested only in that disposable database. See
[slice 04](../../../gatherory-web-app/docs/roadmaps/blueprint-ranking-roadmap/04-recommendation-baseline.md#verification-and-handoff--october-22)
for policy, compatibility, migration and rollout details. Nothing was deployed.

## DEV MCP conference import acceptance — October 25, 2026

The signed Debug app at `https://dev.gatherory.com` imported the real MCP-created
IBM TechXchange 2026 planning workspace for the signed-in DEV account. The
persisted SwiftData root had 16 timeline items, 7 ideas, 47 notes and 4 todos;
its owner matched an active host participant with manage permission. Manual
refresh discovered the root after initial account bootstrap. Home, Ideas,
Manage, Notes and task details were inspected in light and dark appearance; the
signed-in view remained available after backgrounding and reopening the app.
No production service or user data reset was involved.

Native regression coverage passed on the separate iPhone 18 Pro test simulator:
`WorkspaceBootstrapDiscoveryTests` verifies discovery without replacing
existing planner data or pending local mutations, repeat-sync deduplication and
discarding a stale response after account switch. `McpPlanningPayloadTests`
verifies actual exported conference payload decoding, and
`EventInvitationTransportTests` covers the invitation transport contracts.
Combined result bundle: `/tmp/gatherory-mcp-dev-ios-derived/Logs/Test/Test-Gatherory-2026.10.25_16-37-16--0400.xcresult`
(25 test cases passed, 0 failed or skipped). The successful Debug app build was
installed over the existing dedicated DEV simulator without erasing its data.
This acceptance includes a signed Debug rebuild and app foreground/reopen, not
a force-quit cold-launch check. See the [DEV MCP rollout and import guide](../../../gatherory-web-app/docs/development/mcp-dev-rollout.md)
for server setup and conference import details.

Related regression coverage also passed **54/54** across `OfflineSyncTests`,
`LocalGuestPersistenceTests`, `AccountDeletionLocalCleanupTests`,
`SessionLifecycleActionsTests` and `AccountDeletionSyncTests` on the separate
test simulator. Result bundle:
`/tmp/gatherory-mcp-dev-ios-derived/Logs/Test/Test-Gatherory-2026.10.25_16-56-08--0400.xcresult`.

A follow-up MCP venue edit changed the root location to **GWCC, Atlanta**. The
foreground app displayed the updated location, and a read-only check of its
SwiftData archive confirmed `mainEventLocation.locationName` was updated while
the 16/7/47/4 timeline, idea, note and task counts remained intact. The archived
owner still matched the active host with manage permission. This confirms a
known-scope MCP edit preserves the imported planning graph in the native store.

## Blueprint library collections — October 22, 2026

The native Blueprint library now has a fixed **Blueprints** title with Yours, Saved, and Liked primary filters. Yours uses existing account-owned Blueprint records, drafts, and installation history. Saved and Liked remain independent private preferences; Not interested remains in Account. The detailed data/privacy boundaries and acceptance checks are in the [web/server roadmap](../../../gatherory-web-app/docs/roadmaps/blueprint-ranking-roadmap/10-blueprint-library-collections.md).

- Targeted native Xcode tests passed: **89/89**, zero skipped, including the final account-switch rendering guards. Result bundle: `/tmp/gatherory-library-collections-native-rerun.xcresult`. The preceding rerun could not launch because Simulator SpringBoard crashed; booting the test simulator again allowed the same built test runner to pass.
- The iOS simulator Release build passed with exit code 0. Log: `/tmp/gatherory-library-collections-release-verified.log`.
- Web tests passed: **771 passed, 54 skipped** across 118 passed and 36 skipped files. Typecheck and generated contract checks passed. Eight Blueprint integration tests across six files passed against disposable PostgreSQL 18. All four ranking artifacts remained unchanged; targeted Prettier and `git diff --check` passed. English/Spanish localization verified **1,671 strings**.
- ReUI C1–C4 source review ran twice on the changed files and found no UI violations. Native accessibility source review covered system picker/buttons/empty states, combined card text, labeled 44-point unavailable-source removal control, accessibility-size one-column layout, full titles, and layout direction. Live VoiceOver and device acceptance were not run.
- Xcode Canvas crashed; the latest recorded failure at 18:24:35 was `EXC_BAD_ACCESS` / `SIGSEGV` in SwiftUI Preview/JIT frames. Visual acceptance remains unverified. The audit checklist tool was unavailable, so review used a manual native-adapted checklist; no native lint configuration or run is claimed. No deployment or phone release occurred.

## Long decision-card content — October 25, 2026

A conference idea with a long title and note could give the resting Decide card
an intrinsic height larger than the space between the native navigation and
tab bars. The shared decision presentation now takes its bounds from the deck,
including its artwork. Live and blueprint Decide summaries use a semantic
`title2` heading and three-line title/note previews. They cannot expand inline;
the existing idea reading destination retains the complete text. Shared idea
detail and notes-card defaults are unchanged.

A DEBUG-only, explicitly opted-in fixture reproduces the reported conference
idea in an ephemeral, signed-out development store. It does not alter or sync
the imported App Review conference. `DecisionCardLayoutUITests` checks that the
card stays below the navigation toolbar and above the tabs, remains tappable,
opens the full note, and still supports a swipe decision followed by Undo.
The native test exercises both standard Light and Dark appearance. Horizontal
visual review uses the screenshots rather than treating the decorative shadow's
accessibility bounds as the visible card edge.

Verification on Xcode 27.1 / the `Gatherory-Decide-Visual` iPhone simulator,
iOS 27.0:

- **Passed:** 25 focused tests in `DecisionCardFlightTests`,
  `DecisionSwipeMappingTests`, and `DecisionReviewTests`.
- **Passed:** one native UI regression covering Light and Dark, full-text
  navigation, swipe, and Undo; zero failures or skips in the final run.
- App and test targets compiled successfully for Debug. Result:
  `/tmp/gatherory-decision-card-fix-final-tests.xcresult`; log:
  `/tmp/gatherory-decision-card-fix-final-tests.log`.
- Final screenshots: `/tmp/gatherory-decision-card-light.png` and
  `/tmp/gatherory-decision-card-dark.png`.
- `git diff --check` passed. No new copy or web UI dependencies were added.

The initial UI check incorrectly treated the card's existing shadow as
horizontal content overflow; inspecting the recorded frame showed the visible
card inside the screen. The final regression retains the navigation/tab-bar
bounds checks. No dedicated super-large text/layout run, physical-device check,
iOS 27.1 ArrangementView runtime check, Release archive, or TestFlight upload was
performed for this change. Nothing was pushed or published.

## Home event context clarity — October 25, 2026

Home now keeps the selected event title in the inline navigation bar. The
visible hero badge names the card context (Main event or Subevent) beside its
status, and child cards identify their parent event when the viewer can also
see that main event. Child-only guests do not receive the hidden parent title.
The card's VoiceOver label includes its full event title, context and any
visible parent title. Existing paging, rail selection and event-specific action
references remain tied to the selected `EventReference`.

`GatheroryTests.homeEventContextPresentation` covers main/child labeling, long
event titles, visible-parent context and the child-only guest privacy boundary.
The complete `GatheroryTests` target passed **1,036 tests**, with zero failures
or skips, on the Gatherory MCP Dev iPhone 18 Pro simulator. Result bundle:
`/Users/nexus/Library/Developer/Xcode/DerivedData/Gatherory-fkdlsthewnqyuwcnvrboywcmoqza/Logs/Test/Test-Gatherory-2026.10.25_20-27-50--0400.xcresult`.
English/Spanish localization verification passed for 1,703 strings. The focused
`GatheroryUITests.testHomeKeepsMainAndChildEventContextVisibleInLightAndDark`
acceptance passed on iPhone 18 Pro / iOS 27.0 (1 test, 0 failures), confirming
the selected native title, main/child context and one-line status badge in Light
and Dark appearances. It also confirms the named parent context appears on the
child card without the duplicate generic subtitle. Result bundle:
`/tmp/gatherory-home-context-ui-final-dynamic.xcresult`; exported screenshots:
`/tmp/gatherory-home-context-export-dynamic-02/`. No dedicated super-large text
layout or physical-device check was run.

## Shared album tile styling restored — October 25, 2026

At the user's request, two Luna agents reverted the latest photo-picker-style
experiment. The previous rounded tiles, wider gutters, contributor sizing,
progressive blur and checkmark selection controls are restored. Numbered badge
copy, selection-order tests and the experiment's acceptance entry were removed.
Unrelated working changes, including the existing standard Light/Dark-only UI
test configuration, were preserved.

Verification passed on Xcode 27.1 / an isolated iPhone 18 Pro, iOS 27.0:
**11 AlbumPresentationTests** and **one native UI test covering standard Light
and Dark**, including viewing, selection and Select All/Deselect All.
English/Spanish localization coverage passed for **1,702 strings**, and
`git diff --check` passed. Result:
`/tmp/gatherory-album-style-restored-20261025.xcresult`.
The restored album Swift sources and native selection tests match their
pre-experiment source. No
physical-device, iOS 26 runtime, real Photos write, or deployment check was run.

## Shared album introductory copy removed — October 25, 2026

Removed the browsing introduction above the collage. Selection guidance remains
in Select mode. UI regressions now locate the gallery by its stable
`album.gallery` identifier and assert that the removed introduction is absent.
Swift parsing and `git diff --check` passed; simulator UI tests were not rerun
for this copy-only edit. Localization checking reported an unrelated missing
Spanish translation for the concurrently edited `Part of %@` key; no unrelated
copy was changed in this pass.

## URL error fixture deprecation — October 25, 2026

`OfflineSyncTests` now constructs URL error metadata with
`NSURLErrorFailingURLErrorKey` and a `URL` value. The existing privacy assertion
still verifies that log attributes include only the numeric error code, without
private descriptions or URL contents. The test target compiled without the
reported deprecated-key warning, and all **35 OfflineSyncTests passed** on
Xcode 27.1 / iOS 27.0 Simulator. Result:
`/tmp/gatherory-url-error-key-suite-20261025.xcresult`.
Swift parsing and `git diff --check` passed; production code was unchanged.

## Events tab long-press actions — October 25, 2026

The complete native unit run passed **1,043 tests**. The focused duplicate UI
acceptance passed on the iPhone 18 Pro / iOS 27.0 simulator in both Light and
Dark appearances. It verifies Events tab long press, the Duplicate Event sheet,
editing the proposed copy name, and opening the independent copy on Home. The
other three focused lifecycle, read-only permission and Home context UI methods
also passed. English/Spanish localization verification passed for **1,711
strings**, and `git diff --check` passed.

Duplicate UI result:
`/tmp/gatherory-event-duplicate-ui-screenshots.xcresult` (1 method, both
appearances, zero failures/skips). Menu, sheet and copied Home screenshots:
`/tmp/gatherory-event-duplicate-ui-screenshots-attachments/`.

The combined run recorded the 1,043 passing unit tests and three passing UI
methods in `/tmp/gatherory-event-menu-duplicate-final.log`; its duplicate
text-clearing assertion failed, then Xcode stalled finalizing its bundle. The
focused retry verifies name editing and the actual copy handoff without relying
on caret-position-dependent clearing. Its finalized result above passed. The
earlier complete lifecycle/badge bundle is
`/tmp/gatherory-event-menu-badges.xcresult`.
Pause Replies remains deferred. No physical-device check, release archive or
TestFlight upload was made.

## Home event layout choices — October 27, 2026

Home options now offers Cards (the existing default) and Overview (a
Blueprint-style main event and compact child-event list, without ideas).
The device remembers the choice. Both modes use the same authorized event
selection and invitation detail screen. Updates is in the native Home options
menu; Add event remains directly accessible.

Three Luna agents handled the overview, integration and focused tests. Final
verification passed on Xcode / iPhone 18 Pro, iOS 27.0 Simulator: **8 tests,
zero failures or skips**:

- Six `HomeEventLayoutTests` cover persisted values and fallback, child-only
  and main-only guest scope, archived children, idea exclusion and deleted-root
  handling. These exercise the projection used by the actual Overview view.
- `testHomeOverviewModeAndSelectionPersistInLightAndDark` covers the native
  options picker, event-only Overview, scrolling to a child, opening its
  invitation, native back, selected-event restoration in Cards, and preference
  persistence after relaunch in both appearances.
- `testHomeKeepsMainAndChildEventContextVisibleInLightAndDark` verifies the
  existing Cards paging and selected-event title in both appearances.

The final run corrected the child-group accessibility identifier that had
overridden each row's identifier in the first Overview test. The final native
captures were inspected in Light and Dark: the main cover and grouped event
rows render without idea sections or lifecycle badges. English/Spanish
localization coverage passed for **1,716 strings**; `git diff --check` passed.
The localization extractor still reports the existing nonliteral AppCopy key
warning.

Final result: `/tmp/gatherory-home-layout-row-ids-20261027.xcresult`.
Build/test log: `/tmp/gatherory-home-layout-row-ids-20261027.log`.
Exported options, main-event and child-event screenshots:
`/tmp/gatherory-home-layout-final-artifacts/` (see `manifest.json`).

These are focused simulator regressions, not a new full-suite release audit.
No physical-device, dedicated super-large layout, live sync or VoiceOver
interaction check was run. No server was started, release archive made,
TestFlight build uploaded or production deployment performed. Feature details:
`docs/home-event-layouts.md`.

## Home Overview date collections — October 27, 2026

Overview now uses larger image-led child-event cards in horizontal collections,
with one heading per calendar date. Vertical scrolling moves between dates;
horizontal scrolling reveals events on the same date. The main-event blue
outline and child selection tint are removed; selection remains in the native
navigation title and accessibility trait. Dates are derived in each event's
stored time zone; unscheduled events form a final undated collection. The
existing Cards mode and event visibility policy are preserved.

Two Luna agents handled the view and grouping/tests. On iPhone 18 Pro / iOS
27.0 Simulator, **11 focused tests passed, zero failures or skips**:

- Nine `HomeEventLayoutTests`, including same-date grouping across time zones,
  midnight boundaries, chronological ordering with stable ties, undated-last
  behavior, guest scope, archived/deleted events and idea exclusion.
- Two native UI methods covering Light and Dark. Overview acceptance now
  scrolls vertically to Ceremony's day, swipes horizontally to Cocktail Hour,
  opens it and verifies the exact selected event after native back, then returns
  to Ceremony. Layout switching, selected-event restoration, relaunch persistence
  and the existing Cards paging regression also pass.

Inspected the final Light/Dark screenshots for date headings, larger artwork,
the next-card peek and absence of blue selection styling. English/Spanish
localization coverage passed for **1,722 strings**. Xcode extraction exposed
six empty aliases for existing Duplicate Event copy; these reuse the matching
reviewed English/Spanish translations already in the catalog. The existing
nonliteral AppCopy extraction warning remains. `git diff --check` passed.

Final bundle: `/tmp/gatherory-home-date-cards-20261027.xcresult`.
Build/test log: `/tmp/gatherory-home-date-cards-20261027.log`.
Screenshots and manifest: `/tmp/gatherory-home-date-cards-final-artifacts/`.
This was focused simulator acceptance, without physical-device, live-sync,
VoiceOver interaction or dedicated super-large layout testing. No dev server,
release archive, TestFlight upload or production deployment was started.

### Quick follow-up: transitions and edge-to-edge carousels

The next code-only pass connects Overview main/child cards to the existing
invitation namespace and native zoom transition, makes each carousel span the
screen with native scroll-content insets, and adds system-localized relative
date headings from yesterday through seven days ahead. `git diff --check`
passed. At the user's explicit request, no tests, build or simulator check was
run for this follow-up; the 11-test result above predates these changes.

## Offline entry, deletion and Photos recovery — October 27, 2026

Three Luna agents handled the native account-entry, remote deletion and Photos
presentation fixes. Integration additionally restores cached guest invitations
before account UI readiness. Implementation and upgrade boundaries are described
in `docs/offline-recovery-2026-10-27.md`, `docs/offline-sync.md` and
`docs/auth-integration.md`. No backend or database changes were made.

The **complete GatheroryTests target passed 1,067 tests in 146 suites** on the
iPhone 18 Pro / iOS 27.0 simulator. This includes:

- Token-matched offline account recovery, an isolated real-Keychain cache
  roundtrip, missing-cache recovery, explicit sign-out and confirmed expiry.
- A real file-backed SwiftData cold relaunch with two account namespaces,
  suspended server bootstrap, continued local routing/editing and retained
  outbox mutation IDs after relaunch.
- Cache-only guest invitation activation without a network request, subsequent
  validation/refresh, network-failure retention and account isolation.
- Root/child tombstones, confirmed missing scopes, child projection cleanup,
  another account's protected archive/outbox and unrelated pending work.
- New offline creates surviving missing-scope rejections, and previously
  acknowledged roots with rejected child edits being removed rather than
  recreated. Generic auth/network failures and empty responses retain data.

Unit execution log:
`/tmp/gatherory-offline-recovery-verified-20261027.log`.
That combined run's initial UI test used an ambiguous Cancel/Close query and
failed; Xcode stalled finalizing its result bundle and was stopped after test
execution. The full unit run above passed before the UI failure. The subsequent
changes affect the UI test's selectors and diagnostic captures only.

The focused native
`PhotoAttachmentPickerUITests.testMainEventPhotoPickerOpensCancelsAndReopensWithoutDiscardingDraft`
then **passed in Light and Dark** (one method, zero failures). It opens the real
system Photos picker twice in each appearance, cancels through its own Photos
navigation bar, waits for the image choices to become interactive and confirms
the unsaved main-event title is preserved after closing image choices. The
test waits beyond iOS's transient `PUPickerUnavailableView` loading hierarchy,
which is not the ready Photos screen.
Native acceptance log: `/tmp/gatherory-photo-picker-native-20261027.log`.
Xcode also stalled finalizing the focused result bundle after reporting the
passing test and was stopped. Its requested bundle
`/tmp/gatherory-photo-picker-native-20261027.xcresult` is incomplete; use the
completed native test log above as execution evidence.

English/Spanish localization verification passed for **1,723 strings**;
`git diff --check` passed. The existing nonliteral AppCopy extraction warning
remains. No physical-device airplane-mode, new library-photo import/save,
iCloud photo download, live-server delete, release archive or TestFlight check
was performed. Previously downloaded content is required offline; older
installations need one successful online validation to initialize the secure
profile cache. No dev server was started and nothing was deployed.

## Invitation full-screen artwork — October 27, 2026

Scope was narrowed by the user to the invitation image's black top/bottom bars;
other pending fixes were left for later. Two Luna agents handled the scoped
layout fix and native regression. The invitation alone opts out of the iOS
27.1 adaptive artwork container's explicit clipping, so its existing backdrop
can draw into safe areas without adding a second image/blur layer.

`InvitationArtworkBleedUITests.testHomeInvitationArtworkReachesSafeAreasInCardsAndOverview`
passed on **iPhone 18 Pro / iOS 27.0** and **iPhone Duo / iOS 27.1**, one
method per runtime, zero failures/skips. Each run covers **Cards and Overview
in Light and Dark**, with screenshot-pixel checks away from controls at the
top and bottom screen edges. The newer runtime exercises the ArrangementView
branch; the older runtime confirms its existing path is preserved. The available
27.1 simulator runtime supports Duo; creating an 18 Pro for that runtime was
rejected as incompatible. No dedicated large-text or expanded-layout matrix
was added.

Finalized results:

- `/tmp/gatherory-invitation-bleed-ios270-20261027.xcresult`
- `/tmp/gatherory-invitation-bleed-ios271-20261027.xcresult`

Exported screenshots/manifests:
`/tmp/gatherory-invitation-bleed-ios270-artifacts/` and
`/tmp/gatherory-invitation-bleed-ios271-artifacts/`.
The 27.1 Light/Dark screenshots were inspected for edge-to-edge image coverage.
`git diff --check` passed. No copy, dependencies, schema, server or production
deployment changed. Physical-device acceptance remains separate.

## Idea detail full-screen artwork — October 27, 2026

The invitation-only correction left the shared idea reader under the same
iOS 27.1 clip. The audited full-screen consumers now all explicitly extend
their artwork into safe areas: `EventInvitationScreen`, `IdeaDetailPresentation`
(workspace and Blueprint ideas), and `BlueprintWorkspaceEventDetail`.
`DecisionCardPresentation` is intentionally bounded to its deck card and keeps
clipping. Existing image decoding, blur, text, response controls and navigation
are preserved; no duplicate background render is introduced.

Two Luna agents handled the scoped consumer fix and regression coverage.
`IdeaArtworkBleedUITests.testIdeaDetailArtworkReachesSafeAreasFromIdeasAndDecide`
passed on **iPhone 18 Pro / iOS 27.0** and **iPhone Duo / iOS 27.1**, one
method per runtime with zero failures/skips. Each run opens an image-backed
idea from **Ideas and Decide in Light and Dark**, samples actual screenshot
pixels at the top and bottom edges, then scrolls the detail and repeats those
checks. Sixteen screenshots cover the two runtimes and before/after positions.
The initial 27.1 attempt used a bottom-tab-only selector; the successful test
uses native buttons accessible in both the bottom bar and adaptive side rail.

Finalized results:

- `/tmp/gatherory-idea-bleed-native270-20261027.xcresult`
- `/tmp/gatherory-idea-bleed-native271-20261027.xcresult`

Screenshot manifests:
`/tmp/gatherory-idea-bleed-native270-artifacts/` and
`/tmp/gatherory-idea-bleed-native271-artifacts/`.
The 27.1 idea-detail capture was inspected for continuous backdrop coverage.
`git diff --check` passed. Blueprint reader changes were audited and compiled;
this focused UI run did not navigate a live Blueprint catalog. No physical
device, large-text matrix, backend, offline/deletion work or deployment was
performed in this pass.

## Simplified invitation calendar tile — October 27, 2026

The calendar tile now emphasizes a localized month/day stamp, weekday and time
range, with the event time zone as secondary text. A year appears when needed;
cross-date ranges and daylight-saving zone changes remain explicit. Category,
status and event-purpose labels are removed from this tile. The separate native
Add to Calendar footer uses a divider, disclosure chevron, 44-point touch target
and short copy-only explanation instead of the oversized filled capsule.
Host date editing and calendar export remain independent actions; a view-only
guest keeps export without date editing. Unscheduled content cannot export.

Three Luna agents handled the native card, localized presentation model and
regressions. Focused checks on iPhone 18 Pro / iOS 27.0 Simulator:

- **9 unit tests passed**: six `InvitationSchedulePresentationTests` plus three
  `CalendarEventTests`, covering same-day/overnight timing, inclusive all-day
  ranges, event-local dates across daylight saving, Spanish, year context,
  unscheduled state and unchanged EventKit draft conversion.
- The host native UI method passed in **Light and Dark**, opening and cancelling
  the focused date editor and native EventKit editor separately, without saving
  a calendar event.
- The guest native UI method passed in **Light and Dark**, retaining calendar
  export and excluding the date-edit action.

The first formatter run assumed a full localized date interval repeats its
start year. Its assertion now checks the actual range boundaries and end year;
the native interval already preserved the correct dates. Both UI methods
passed in `/tmp/gatherory-schedule-card-final-20261027.log`; Xcode stalled
finalizing that combined failed bundle and was stopped after execution.
The corrected unit suite and repeated host acceptance are captured by
`/tmp/gatherory-schedule-card-verified-20261027.xcresult` and its matching log.
Light/Dark card captures were inspected in
`/tmp/gatherory-schedule-card-verified-artifacts/`. The final year-context
polish displays localized weekday and year as separate metadata (`Friday ·
2027`), avoiding the native template's year-first order. Its formatter checks
are recorded in `/tmp/gatherory-schedule-format-20261027.xcresult`; the UI
navigation acceptance above precedes this text-only adjustment.

English/Spanish localization coverage passed for **1,723 strings**, and
`git diff --check` passed. The existing nonliteral AppCopy extraction warning
remains. No physical-device calendar save, provider synchronization, dedicated
large-text matrix, new permission prompt, backend change or deployment was
performed. The existing copy-only EventKit behavior is preserved.

## Invitation opening schedule and RSVP spacing — October 27, 2026

Two Luna agents handled the native layout and focused UI regression. The
invitation hero now fills its available viewport and uses a 12-point standard
bottom inset instead of the capped hero height and larger inset. Full dates,
time ranges or All-day, and the event time zone appear together above the RSVP
row. Long content remains scrollable; Blueprint heroes keep default spacing.

`InvitationHeroLayoutUITests.testMainAndChildInvitationHeroesKeepScheduleAndResponsesAccessibleInLightAndDark`
passed on **iPhone 18 Pro / iOS 27.0 Simulator**, with zero failures or skips.
The method checks both main and child invitations in **Light and Dark**,
requires visible formatted time, verifies the RSVP row does not overlap the
native tabs and remains within 36 points, then saves a long fixture title and
checks schedule and response reachability by scrolling. The child read-only
schedule is checked by visible frame rather than tappability. The captured
child geometry has a **12-point RSVP-to-tabs gap**.

Finalized result and matching log:
`/tmp/gatherory-invitation-hero-verified-20261027.xcresult` and
`/tmp/gatherory-invitation-hero-verified-20261027.log`.
Four main/child Light/Dark screenshots are exported in
`/tmp/gatherory-invitation-hero-verified-artifacts/`; the main Light and child
Dark captures were inspected for readable timing, close response placement
and continuous full-screen artwork.

The six `InvitationSchedulePresentationTests` also passed in the preceding
focused runs, covering same-day/overnight times, all-day, DST, localization/year
context and unscheduled state. Those initial combined runs stopped on UI test
assumptions about scroll direction and read-only element hittability; their
Xcode processes stalled finalizing and were stopped. The corrected UI method
above completed with `TEST SUCCEEDED`; no product changes were needed for
those test corrections.

English/Spanish coverage passed for **1,723 strings**, with the existing
nonliteral AppCopy extraction warning, and `git diff --check` passed. These
checks use isolated local fixtures, with no live RSVP writes. Physical-device
acceptance and a dedicated large-text matrix were not performed. No server,
backend, dependency or production deployment changed in this pass.

## Lean invitation schedule — October 27, 2026

The hero now uses a separate compact presentation instead of repeating the
date tile's full schedule. Single-day events show native localized Yesterday,
Today or Tomorrow when applicable, otherwise a short date, with only the start
time for timed events. Multi-day events show one date interval without times
or a timezone line; all-day events show only dates. Relative-day comparisons
use the event's calendar/timezone, with a periodic native SwiftUI update while
open. Full schedule details remain in the date tile and VoiceOver label.
The calendar footer's copy/synchronization footnote and matching hint were
removed; export and date editing retain their separate native actions.

Three Luna agents handled the presentation model, screen integration and
focused regression updates. **16 unit tests passed** across the new seven-case
`InvitationHeroSchedulePresentationTests`, six detailed schedule tests and
three EventKit conversion tests. They cover relative days, event-local
midnight/DST boundaries, multi-day summaries without times, all-day/start-only
dates, Spanish, year context, undecided dates and complete spoken schedules.

The first compile found the application's existing `TimelineView` name
shadowing the system type. Qualifying `SwiftUI.TimelineView` resolved it before
the passing unit run. No dependency or backend changes were required.

The finalized lean-invitation run completed with **19 tests passed**, zero
failures/skips: the 16 units above plus native hero, host date/calendar and
guest date/calendar UI methods, each in Light/Dark. The UI checks retain
main/child RSVP geometry, long-title scrolling, full spoken schedule, host
date editing, guest view-only boundaries, native EventKit open/cancel and
absence of the removed footer. Results:
`/tmp/gatherory-lean-invitation-verified-20261027.xcresult` and matching log;
eight screenshots in `/tmp/gatherory-lean-invitation-verified-artifacts/`.
Main Dark and date-tile Light captures were inspected. English/Spanish
localization coverage passed for 1,723 strings with the existing nonliteral
AppCopy warning. No physical-device save, live RSVP mutation, large-text matrix
or deployment was performed.

## Connection monitor Swift 6 capture — October 30, 2026

The `NWPathMonitor` callback keeps its weak owner capture, promotes it to an
immutable local, then captures that MainActor-isolated reference in the update
task. This removes the nested mutable weak-capture diagnostic without a stored
retain cycle or concurrency suppression. An explicit Foundation import makes
the DEBUG ProcessInfo reference self-contained.

Both DEBUG and non-DEBUG typechecks passed for the actual AppConnectionStatus
and AppRuntimeConfiguration source files with `-swift-version 6`,
`-strict-concurrency=complete`, `-default-isolation MainActor` and
`-warnings-as-errors`. This verifies the affected code, not a whole-project
Swift 6 language migration; the project language settings are unchanged.
The normal native build and both OfflineConnectionUITests methods passed
(Online/Offline in Light/Dark) in
`/tmp/gatherory-connection-capture-swift6-20261030.xcresult`, log
`/tmp/gatherory-connection-capture-swift6-20261030.log`. These use deterministic
status fixtures rather than physically changing network connectivity.
`git diff --check` passed. No UI layout or production deployment changed.

## Complete-card zoom and context-menu previews — October 30, 2026

Luna agents implemented and independently reviewed the card changes and added
native gesture regressions. Overview main/child and Cards now register the
entire decorated card as their zoom source, including its surface, border and
Manage footer (and Cards shadow). The native context-menu preview uses that
same complete card, outside its rounded clip. Horizontal day rows disable
scroll clipping so the system's lifted card can extend beyond the row bounds.
Artwork remains clipped inside the card; Open and Manage remain sibling buttons
with their existing event references and permissions.

`HomeEventCardInteractionUITests` exercises context-menu opening/dismissal,
primary-card navigation, a short back drag held for half a second that cancels,
a longer held drag that returns Home, and the event-specific Manage footer.
Overview main and child pass in both Light and Dark; Cards main passes in Light
as a compatibility check. The tests use native coordinates within the observed
visible primary-button frame and preserve separate footer interaction.

Initial test attempts exposed two automation errors rather than failed app
outcomes: a menu-dismiss tap activated Share, and a nested scroll accessibility
frame incorrectly excluded a visible child button. The test now dismisses in
the inert screen gutter and computes hit points from the button/window/chrome
bounds while revealing horizontal content separately. No app gesture override
or interaction permission was changed to accommodate those tests.

Verified artifacts: the Cards native method passed in
`/tmp/gatherory-home-card-interactions-final-20261030.xcresult` (that run also
records the subsequently corrected Overview test-coordinate failure). The final
Overview main/child Light/Dark method passed with zero failures in
`/tmp/gatherory-overview-card-interactions-20261030.xcresult`, log
`/tmp/gatherory-overview-card-interactions-20261030.log`. These are behavioral
checks: they do not measure intermediate animation pixels, rounded mask shape,
or shadow clipping. No screenshots were requested by the new tests or inspected
manually. Physical-device held-transition visual acceptance remains unclaimed.
All 16 focused HomeEventLayoutTests and EventManagementAccessTests passed in
`/tmp/gatherory-home-card-interaction-units-20261030.xcresult`; the final diff
check passed.
No packages, backend changes, production deployment or TestFlight upload are
part of this change.

## Overview default, status-free editing and lean date tile — October 30, 2026

Home defaults and invalid stored preferences now resolve to Overview; explicit
Cards preferences remain supported. New/duplicated main events start Ongoing,
copied schedule items start Approved, and full native main/child edit sheets
omit lifecycle Status and Planning Status. A saved legacy draft is promoted to
Ongoing by the full main editor; existing terminal states are preserved. Hosts
and managers retain confirmed deletion of Ongoing roots. Contributors do not
gain that destructive permission. Main and child approval domains remain
separate; no schema or existing-row migration was applied.

The date tile uses a localized month/day stamp, weekday and time. Multi-day
events use separate start/end rows with time-only endpoint formatting, avoiding
DateIntervalFormatter's tendency to reinsert full numeric dates. No visible
timezone line or selector is added; event-local formatting, full accessibility
labels and calendar export keep the exact stored schedule. Cross-year, all-day,
undated, invalid-end, DST and Spanish formatting have focused coverage.

The broad native run initially exposed a real status-default interaction:
Ongoing events with a start at `now` and no end were immediately inferred as
Finished and lost edit permissions. Root lifecycle now follows stored status;
dates alone do not silently lock planning. Explicit Finished/Cancelled and
scoped completion rules are retained. The initial projection tests also needed
their DST assertions moved to the new separate endpoint properties. Both were
corrected before final verification.

Final result: **1,112 unit tests in 152 suites passed**, plus one native UI
method covering Overview fallback, main/child status-free editors, schedule
editing/calendar affordance and no timezone selector in standard Light/Dark
appearances. Result: `/tmp/gatherory-event-simplification-final-20261030.xcresult`;
log: `/tmp/gatherory-event-simplification-final-20261030.log`. The new native
method has no screenshot attachments; existing full-suite rendering tests
retain their normal generated diagnostic images. No manual screenshot or
physical-device visual review was performed. Add-to-calendar export logic is
covered by existing unit suites; no live calendar write was attempted.

Web/server creation defaults were aligned for workspace, direct root event,
and MCP creation. `pnpm vitest run tests/effect/mcp-content-service.test.ts`
passed six tests. The opt-in local MCP database integration passed one test,
including canonical row and native archive Ongoing assertions; it uses fresh
fixture accounts and cleans them up. `pnpm typecheck` passed. No server was
started, production deployed, existing account event migrated, or build uploaded.
English/Spanish verification passed for **1,737 strings** and both repository
diff checks passed.

## Event editing from invitation content — October 30, 2026

Manage has no editing gear or editor sheet. Main invitation title/date/location
continue to use the existing field-specific native sheets. Authorized planners
can tap the corresponding child invitation content, including the information
tiles, to open the existing editor for that captured child. Cancel returns to
the invitation. The child request checks the exact root, child snapshot,
account/device profile, principal generation, active editable membership and
current event access. It closes on stale data or lost access; archived, missing
or deleted events cannot become a new child through a fallback editor mode.
Cancelled/completed events remain editable when otherwise authorized.

Luna agents implemented the entry points and regression coverage. The final
`xcodebuild test` passed **18 tests**, zero failures: 16 units across
ChildInvitationEditingTests, MainInvitationEditingTests and
EventManagementAccessTests, plus two ManageEventEditingUITests methods. The
native tests cover main/child Manage without a gear, title tap → exact editor →
Cancel → same invitation → Back Home in Light and Dark, and guest denial of
editing/Manage. The older child-sharing UI test now expects editable controls
for authorized planners; that separate sharing test was updated and compiled,
not rerun. Date/location entry points reuse the child sheet route but were not
individually navigated in the new UI methods. No screenshots were taken.

Device Hub was opened on Gatherory MCP Dev (iPhone 18 Pro / iOS 27), including
accessibility inspection during the native run. A standalone fixture launch
after XCTest did not expose app accessibility controls in Device Hub, so a
separate manual edit/cancel verification is not claimed. Automated navigation
is verified by `/tmp/gatherory-event-content-edit-verified-20261030.xcresult`
and `/tmp/gatherory-event-content-edit-verified-20261030.log`. English/Spanish
localization verification passed for **1,738 strings**; `git diff --check`
passed. No production deployment or physical-device installation was performed.

## Compact offline UI — October 30, 2026

Luna agents removed the launch offline bar and Events invitation-error inset,
added compact signed-in/guest Account status with native `NWPathMonitor`, and
added screenshot-free native regressions. An independent Luna review checked
monitor lifetime, cached-account override, and recovery access. With populated
Events, invitation refresh recovery deliberately uses pull-to-refresh instead
of a visible error/retry overlay. Empty lists retain inline retry. Blocking
identity restoration screens and offline persistence behavior remain intact.

`xcodebuild test` passed on iPhone 18 Pro / iOS 27 Simulator: **15 tests**, zero
failures: 13 tests in OfflineAccountRestorationTests and SessionRestorationTests,
plus two OfflineConnectionUITests methods exercising Online/Offline in both
Light and Dark appearances. The native tests verify saved library content is
available, intrusive retry banners are absent, and the Account status and Retry
visibility match the fixture. These tests use guarded DEBUG network-status
fixtures requiring ephemeral data and development authentication bypass; they
do not disable the simulator's network or prove a physical airplane-mode
transition. Cached identity and cold archive/outbox recovery are exercised by
the unit suites. Guest Account and empty-library retry compiled but were not
separately navigated in these UI tests. No screenshots were taken.

Result: `/tmp/gatherory-compact-offline-ui-20261030.xcresult`.
Log: `/tmp/gatherory-compact-offline-ui-20261030.log`.
English/Spanish localization verification passed for **1,735 strings**;
`git diff --check` passed. No server, schema, package, deployment or TestFlight
change was made.

## Event-specific Updates audit — October 30, 2026

Two Luna agents audited native scoping and added regressions. No cross-event
feed bug was found: Manage pins its event reference, Updates receives the
corresponding UUID, local planning notes filter the exact event, and legacy
nil-event notes belong only to the main event. The server announcement query
also filters the exact UUID; this was source inspection, not a live server run.
Audience **All** means all permitted audiences within this event.

Added regressions cover main/child/sibling note isolation while Home selection
changes, clearing feed/capabilities on event switch, and ignoring a delayed
response from the previous event. A native UI test follows main and child
Overview → Manage → Updates using the event-specific accessibility identifier,
then returns without changing Home's selection. No screenshots were taken.

`xcodebuild test` passed on iPhone 18 Pro / iOS 27 Simulator: **34 tests**, zero
failures (33 unit tests across EventAnnouncementControllerTests,
ManageNoteHistoryTests, EventAnnouncementPlanningAccessTests and
EventAnnouncementTransportTests, plus one native navigation test covering both
main and child). Result: `/tmp/gatherory-event-updates-scope-20261030.xcresult`;
log: `/tmp/gatherory-event-updates-scope-20261030.log`. The UI test verifies
navigation scope; synthetic unit feeds verify content isolation. A populated
live account feed was not exercised. No production deployment was performed.

## Manage availability for local account identities — October 28, 2026

The management wrapper incorrectly required notification authorization, which
is intentionally unavailable to offline-restored accounts. It also rejected
older valid local participants resolved by the configured viewer email without
a linked user ID. The local management policy now verifies the configured
account or exact local guest profile directly, preserving active participation,
event scope, read-only permissions and captured account-generation checks.
Remote announcement/push checks remain unchanged. Uncaptured scope initially
shows a neutral loading indicator instead of Event Unavailable.

Two Luna agents handled the access fix and regression cases. **20 focused unit
tests passed** across `EventManagementAccessTests`,
`OfflineAccountRestorationTests` and `EventAnnouncementPlanningAccessTests`.
The restored-account integration test uses a token-matched cached account and
network failure, proves both main/child Manage access while notification
principal stays nil, then verifies sign-out removes access. Other cases cover
legacy email-only membership, wrong account, foreign linked user ID,
unconfigured/no principal, local guest profile mismatch, attendees and existing
read-only/revocation boundaries.

An initial legacy child fixture lacked normalized event participation after
assigning its timeline; it now uses the real participant API, without weakening
the access policy. A native helper also expected a mandatory Account back
button after choosing Home layout; it now accepts native auto-return or Done
and verifies the actual requested Home content before continuing.

Results: `/tmp/gatherory-manage-local-access-verified-20261028.xcresult`, with
matching log. The native management test exercises main/child footers in both
Cards and Overview, dashboard/Collaborators/back navigation and unchanged Home
context. It passed: **21 tests total**, zero failures/skips (20 unit tests and
one native method covering all four footer cases). Localization coverage
passed for **1,729 English/Spanish strings**, retaining the existing nonliteral
AppCopy warning; `git diff --check` passed. No screenshot attachments are
requested by that test. No server,
schema, announcement authorization or production deployment changed.

## Budget back navigation — October 28, 2026

The dashboard Budget card now uses an explicit destination with the managed
event reference. The event budget's previous nested workspace-budget link
could add another Budget screen to the stack. **All event budgets** now changes
scope inside the existing Budget screen, with **This event’s budget** restoring
the original reference. Both labels are distinct in English/Spanish. A scoped
workspace never offers the broader overview. The original event's budget is
always the initial scope; projection and allocation permissions are unchanged.
The accessible scope value uses the human-readable event name or All event
budgets, never an internal event identifier.

Two Luna agents audited the routes and added a screenshot-free native
regression. **16 unit tests passed** across `ManageBudgetTests`,
`ManageNavigationTests` and `EventManagementAccessTests`, covering budget
projections, exact event/scoped boundaries, permissions and non-mutating
navigation. Log: `/tmp/gatherory-budget-backstack-20261028.log`.

The first native attempt stopped before Budget because the shared Account
helper matched duplicated native accessibility toolbar nodes. It now selects
one exact navigation-bar button and concrete picker buttons. The subsequent
native run passed for main and child Overview footers, opening Budget twice
each, checking event scope, explicitly switching to the aggregate and back,
and requiring one Back tap to return to the same dashboard. The final run
also checks the human-readable accessible scope labels.

Result: `/tmp/gatherory-budget-backstack-final-20261028.xcresult`, matching log;
the final repeated main/child method passed with zero failures/skips. A second
native method explicitly leaves **All event budgets** selected, presses Back
once and verifies the same Manage dashboard, with no intermediate Budget
screen. It also passed in
`/tmp/gatherory-budget-overview-back-20261028.xcresult` and matching log.
These checks total **16 passing units and two passing native UI methods**.
Localization coverage passed for **1,729 English/Spanish strings**, retaining
only the pre-existing nonliteral AppCopy extraction warning; `git diff --check`
passed.
The
unit results are in `/tmp/gatherory-budget-backstack-20261028.xcresult` (its UI
helper attempt failed as described above). New UI code creates no screenshot
attachments; no screenshots were requested or inspected. This focused check
uses the iPhone 18 Pro / iOS 27.0 Simulator fixture, with no live account writes.
Physical-device and dedicated Light/Dark/gesture matrices were not run.

## Direct Manage dashboard from card footers — October 28, 2026

The pushed destination now opens the existing Manage dashboard directly,
without an intermediary menu or section list. Two Luna agents handled the
direct dashboard reuse and UI regression updates. There is no Manage
workspace tab. A divider, Manage label and chevron
sit below each card's details as a full-width separate button; the card body
still opens the invitation. Floating pills and management context-menu
shortcuts were removed. Management and task notifications use Home's native
navigation stack, with no management sheet or nested stack. Child editing
retains its existing native sheet. Pinned dashboard mode neither initializes
from Home's selected event nor repairs a missing child by falling back to root.
Child settings cannot open root settings, read-only planners cannot edit
settings/review requests, and current-principal checks invalidate stale scopes.

**23 unit tests passed**, zero failures/skips, across
`EventManagementAccessTests`, `HomeEventLayoutTests`,
`WorkspaceTabPolicyTests`, `EventAnnouncementPlanningAccessTests` and
`ManageNoteHistoryTests`. Result:
`/tmp/gatherory-direct-manage-dashboard-20261028.xcresult`, with matching log.
The app and both test targets are compiled by this focused test command.
English/Spanish coverage passed for **1,727 strings** with the existing
nonliteral AppCopy extraction warning, and `git diff --check` passed.

Screenshot-free UI tests cover card and invitation entry, exact main/child
context, guest exclusion, native-back return and unchanged Home selection. They
also assert that the footer is below the primary event button, has at least a
44-point target, and management has no sheet Done button. Dashboard checks now
require its existing Guests/Collaborators cards and exclude the removed People
menu; one native back step returns from Collaborators to the dashboard. The
existing read-only collaborator test was migrated from the old tab. They were
compiled but not executed: the user requested code-only work without
screenshots. Native gestures, Light/Dark layout and physical-device notification
acceptance are therefore unverified in this pass. No server, dependency,
migration, push or deployment changed. See `event-management.md`.

## Home overview compact time ranges — October 28, 2026

Two Luna agents implemented compact event-local time presentation, integration
and focused regressions. Main and child Overview cards show both endpoints
when a valid end exists. Same-day ranges use native localized interval
formatting (for example `4:00–4:30 PM`); overnight ranges add just the end's
abbreviated date, retaining its year when crossing years. Day headings stay
outside child cards. The main card uses a shorter date line and a separate
time row. Missing/invalid ends show the start alone; unscheduled events do not
invent times. Complete dates/time zones remain in accessible card labels,
including an undecided-date fallback. No event permissions or navigation
policies changed.

On iPhone 18 Pro / iOS 27.0 Simulator, **15 unit tests passed**: six new time
presentation cases plus nine existing Home layout/grouping/scope cases.
Coverage includes same-day and overnight ranges, year crossings, DST zones,
Spanish 24-hour output, all-day/undecided/invalid-end states, child-only guests,
deleted/archived events, grouping and ordering. The native Overview method
passed in Light/Dark, checking main/child schedule labels and tapping through
both cards to Invitation and back. A second native method passed in both
appearances using the Birthday fixture's actual main-event `6:30–10:00 PM`
range. The normal seeded main event has no end and correctly shows only its
start. These are **17 distinct passing tests**, with zero failures/skips.

Results and matching logs:

- `/tmp/gatherory-overview-time-20261028.xcresult` (15 units and first UI method).
- `/tmp/gatherory-overview-main-time-20261028.xcresult` (timed main UI method).

Main-event screenshots are exported in
`/tmp/gatherory-overview-main-time-artifacts-20261028/`; the Dark capture was
inspected for the visible compact range. The first child screenshot caught
only its tappable artwork before the time row entered the viewport; its native
test was tightened to expose the whole card above the tabs before capture.
That tightened Light/Dark method also passed in
`/tmp/gatherory-overview-time-visible-20261028.xcresult`; captures are in
`/tmp/gatherory-overview-time-visible-artifacts-20261028/`. The Light child
capture was inspected and shows the complete `4:00–4:30 PM` line above tabs.

English/Spanish coverage passed for 1,723 strings, with the existing AppCopy
nonliteral-key warning. No dependency, backend, schema, dev-server startup or
production deployment changed. Physical-device and dedicated large-text
acceptance remain outside this focused pass.

## Account and workspace chrome cleanup — October 28, 2026

Home and Decide now request an expanded native tab bar while Ideas and Manage
retain scroll minimization. Home exposes Updates directly for planners; the
persisted Cards/Overview choice moved to Account's Home view picker, including
guest Account. UI test helpers now follow that Account navigation path.
Account's haptic control retains its toggle with a blue icon and no explanatory
paragraph. The profile email occupies a separate full-width wrapping row below
name/avatar/edit. Weather attribution places its introductory text above the
official color-scheme mark and Learn More link, preserving the provider URL and
text fallback.

The recommendation toggle and its explanatory prose were removed. The native
signed-in action store now enables the default via its existing server setting
update, retaining acknowledged-only local state, idempotent retry, exposure
validation and account-reset protection. No server or anonymous/private signal
policy was changed. Three Luna agents handled the scoped changes and test
migration. **32 focused unit tests passed** across `BlueprintActionsTests`,
`HomeEventLayoutTests` and `WorkspaceTabPolicyTests`, covering automatic-default
acknowledgement/failure/retry, stale reads/reset and tab behavior policy.
Result: `/tmp/gatherory-account-chrome-20261028.xcresult`, with matching log.
The final app and both test targets also passed `build-for-testing` after the
fallback attribution layout change; log:
`/tmp/gatherory-account-chrome-build-20261028.log`.

Per the user's code-only instruction, no UI tests or screenshots were run in
this pass; actual native collapse behavior and the Account layout need visual
acceptance separately. Existing UI tests were updated and compiled. Localization
coverage passed for 1,723 English/Spanish strings with the existing nonliteral
AppCopy warning. Nothing was deployed or uploaded.
