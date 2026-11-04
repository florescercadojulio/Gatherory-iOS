# V1 release checkpoint — November 2, 2026

The next step is to freeze V1 feature scope and validate a signed candidate
against its matching backend. Local checks are green; they do not establish
current production deployment, physical-device acceptance or App Store approval.
No server was started, shared data changed, build uploaded or deployment made
for this checkpoint.

The owner subsequently added [Explore idea discovery and Add to Event](explore-idea-discovery.md)
to V1. It is now implemented locally, with its own native/server test evidence.
The candidate acceptance run must include searching for an individual idea,
copying it into the correct event, and verifying offline restore and shared media.
The latest generic Release build includes these local additions.

The owner also added the [Ideas Liked and approval shortcuts](ideas-liked-and-approval.md).
They are implemented locally. Signed-candidate acceptance should include personal
Love It → Liked → long-press approval with Cancel/Confirm, plus event Schedule.
Approval does not promote a draft parent; budget and invitation visibility retain
their own rules.

The owner also added the [swappable Movie Night onboarding](movie-night-onboarding.md).
The classic onboarding remains available through `-ClassicOnboarding`. First run
now offers Start tour or Skip. Start points at the actual native Explore tab. Guided
Explore retains its regular chrome and feed, with only the outlined, pinned
bundled Movie Night selectable; other cards and controls are disabled. Text
Previous / Skip tour / Next controls guide entry. Selecting Movie Night creates
an owned local workspace without depending on a catalog/network response. Account → Redo tour and
post-tour Decide/Search primers are included. Finishing or skipping an installed
lesson now asks whether to keep or remove its practice event; removal is scoped
to the exact owned lesson and persisted for offline reconnect. Explore itself
still uses the server catalog; onboarding no longer depends on its Movie Night seed.

## Verified locally

- November 3 Duo follow-up: the complete real tour and keyboard Search pass on
  iPhone Duo / iOS 27.1 in its current 466×678-point portrait app window. The tour
  now measures native vertical-toolbar controls as well as tab bars, including
  the Ideas filter outside the content lane, with bounded startup retries.
  A current-source iPhone 18 Pro / iOS 27.0 regression passes 24 focused unit
  tests and two native UI cases. The earlier three-size full journeys below
  predate this compatibility change. Fold/unfold, expanded-window, hardware,
  minimum-iOS and new Release-archive acceptance remain open. See
  [Duo evidence and limits](testing-verification.md#movie-night-tour-on-iphone-duo--november-3-2026).

- November 3 tour device-size matrix: the same complete planning/search UI
  regression passes on iPhone SE (3rd generation), regular iPhone 17 and iPhone
  18 Pro Max simulators on iOS 27.0, using each device's default appearance.
  Text/control fit, measured tab pointers, approval, scheduling, completion and
  keyboard/search handoff pass. No app layout fixes were required. This does not
  establish physical-device, iOS 26, iPad or accessibility-text-size acceptance.
  See [artifacts and boundaries](testing-verification.md#movie-night-tour-across-iphone-sizes--november-3-2026).

- November 3 planning-pointer follow-up: 20 focused unit tests and one native UI
  flow pass in the simulator's default appearance. Added Decide/Ideas/Home tab
  arrows use measured native targets; card/filter pointers remain. Light/Dark
  testing was skipped at the owner's request. This addition has a Debug build;
  the November 2 Release log below predates it. See
  [current pointer evidence](testing-verification.md#planning-tour-tab-pointers--november-3-2026).

- The completion cleanup prompt passes 25 focused checks (22 unit / three native
  UI): Keep after Finish and Skip in Light/Dark, Remove after Skip in Light,
  rollback, exact receipt/authority checks, and durable acknowledged deletes.
  See [the current cleanup results](testing-verification.md#tour-completion-keep-or-remove-movie-night--november-2-2026).

- The latest regular-Explore tour passes **1,269 unit tests**, with one opt-in
  live test skipped (1,270 registered in 180 suites), and **eight distinct native
  UI cases** across the full run and corrected search-selector rerun. Light/Dark
  checks prove native target pointing, text navigation, regular feed/control
  locks, Movie Night selection, real planning, replay and restored native search
  typing/scrolling. The full bundle's one stale-placeholder selector failure is
  superseded by the corrected passing case; the full bundle alone is not green.
  See [current artifacts and limits](testing-verification.md#regular-explore-tour-and-text-navigation--november-2-2026).

- Events keeps the main Events / Blueprints / Explore tab bar expanded while
  scrolling. Blueprints and Explore retain their existing scroll minimization.
  The native UI regression passed in Light and Dark on iPhone 18 Pro / iOS 27.0,
  including switching to Blueprints and back. Result:
  `/tmp/gatherory-events-tab-bar-20261102.xcresult` (39.426 seconds).
- The November 2 native source snapshot builds in Release for generic iOS Simulator with
  signing disabled for arm64 and x86_64, including the current onboarding. Log: `/tmp/gatherory-tour-clarity-release-20261102.log`.
  This is not a signed device archive. Warnings remain for a Release-constant
  fixture branch and skipped App Intents metadata extraction; no build errors.
- The earlier November 2 full unit run passed 1,160 executed tests, with one
  opt-in live test skipped. Date-ordering, invitation navigation and budget UI
  checks have separate passing evidence in [iOS verification](testing-verification.md).
  These runs cover different slices; their counts must not be added together.
- Release configuration targets production auth, enables push, PostHog and
  production ads, and disables development seeding/authentication bypasses.
  Configuration alone does not prove service delivery or consent behavior.
- The earlier Movie Night mascot-overlay regression reported 1,237 passed and one
  opt-in live test skipped, including three UI methods. The Light/Dark journey
  proves unchanged content frames, measured card/native-filter pointing,
  hide/resume/skip, actual-tab navigation, detail push/back, native sheets, and
  Use → Love It → approval → Schedule → reopening without restarting the guide. These use the production installation coordinator with
  a local URLProtocol. See the [current artifacts and live acceptance
  limits](testing-verification.md#control-pointing-movie-night-mascot-overlay--november-2-2026).
- Project version remains **1.0 (6)**. Build 6's October 23 TestFlight upload is
  historical evidence; it does not contain the current changes.

## Server test runtime compatibility

The web repository has a local compatibility patch for the installed
Drizzle `1.0.0-rc.4` / Effect `4.1.1` pairing. Its patch file
[`drizzle-orm@1.0.0-rc.4.patch`](../../../gatherory-web-app/patches/drizzle-orm%401.0.0-rc.4.patch)
updates the generated Effect 4 ESM and CommonJS adapter references from
`TaggedErrorClass` to `TaggedError`. With that local patch, the bare adapter
import, server typecheck, and contract checks pass; the recorded suite result is
1,012 passed and 74 skipped across 169 files (46 files skipped). This is local
dependency/runtime verification only. No database migration, catalog seed, or
production deployment was performed or accepted by this checkpoint.

## Remaining release gates, in order

| Gate | Acceptance needed |
| --- | --- |
| Compatible candidate | Record exact native and server revisions, including pending changes. Verify required migrations and authenticated sync against the intended environment. New native budget writes require the matching atomic-budget server protocol; source tests alone cannot prove it is deployed. Increment the build number beyond 6 when preparing the next upload. |
| Server test environment | Reproduce the patched Drizzle/Effect checks from the compatible web checkout, then run the target environment's authenticated catalog and sync acceptance. The local patch does not establish that the patch is deployed or that the Movie Night catalog seed is present. |
| Real planning and recovery | On two physical devices/accounts, create/share/join an event, RSVP as guest, sign in with existing account data, use a Blueprint, vote on an idea and schedule it. Verify exact main/child context, read-only guest boundaries, two-manager budget conflicts and retries, photo replacement and deletion propagation. Disconnect, edit, terminate/relaunch, reconnect and confirm saved content, queued intent and account isolation. Include an upgrade over the existing TestFlight install and the minimum supported iOS version. |
| Device services and privacy | Exercise Apple/Google sign-in and session restoration, account deletion/provider revocation, shared-event/media cleanup, real APNs delivery and tap routing, Calendar save/cancel, invitation links/QR cold and warm entry, Maps and WeatherKit. Validate ad consent/privacy controls and organic fallback when no ad is available; live ad fill itself is not a core-flow gate. Notification reminder/retry workers remain deferred for V1. |
| Submission | Produce and validate a signed Release archive with the expected production origin, entitlements and privacy manifests. Check working reviewer access, current walkthrough, support/privacy URLs, SDK data disclosures, screenshots, age rating, export compliance and agreements in App Store Connect. Verify user-content filtering/report/block/support paths in the candidate and the operational response behind them. Upload or production deployment requires explicit owner instruction. |

The Movie Night locator and navigation overlap issues are resolved in the
final native UI rerun. The current source checkouts remain uncommitted: native
base `cabef2a2` and web base `93902bb`, with pending changes. Record the final
commits when preparing a signed candidate; those base revisions alone do not
contain this implementation. The Movie Night revision was verified in local dev;
production catalog/backend acceptance remains open. The native bundled tour does
not require that remote revision.

These are open acceptance checks, not confirmed current failures. Historical
October 11 sync 404s, missing media transfer and disabled-push notes in older
audits must not be treated as current defects without fresh evidence. The last
recorded AdMob app review state is also dated; this pass did not inspect its
current console status.

Apple's current [review guidelines](https://developer.apple.com/app-store/review/guidelines/)
call for functional reviewer access and available backend services, and describe
user-content safeguards. [Account deletion guidance](https://developer.apple.com/help/app-review/guideline-reference/5-1-1-account-deletion)
covers in-app deletion and Sign in with Apple token revocation. These checks
support submission preparation; they do not guarantee approval.

Keep recommendation tuning, additional MCP capabilities, Android, billing and
reminders outside this V1 completion pass. The best next task is one recorded
two-device candidate acceptance run, fixing only reproducible release defects.
The [guest/invitation audit](../../../gatherory-web-app/docs/release/mobile-v1-guest-invitation-audit.md)
and [team budget safety](team-budget-safety.md) detail the highest-risk boundaries.
