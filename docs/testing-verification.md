# iOS verification

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

| Area | Coverage |
| --- | --- |
| Authentication | Canonical Better Auth identity, stored-session restore, verification-required registration, provider token forwarding, sign-out waiting for pending sync, failed sign-in/restore recovery, deletion failure retaining the account until acknowledgement. |
| Local persistence and sync | Atomic workspace/outbox writes, stable mutation IDs, batching, retries, conflict/rejection handling, tombstones, reopening disk stores, canceled/stale work, per-account leases and cache isolation. |
| Sync HTTP boundary | Fresh bearer tokens after account switches, missing/empty tokens, bootstrap compatibility, push envelopes and retry identity, pull scope/cursor encoding, remote change decoding, all push dispositions, HTTP/network/decoding error classification. |
| Event access | Invitation acceptance and approval states, host/collaborator/guest routing, per-event RSVP and leave behavior, guest projection restrictions, account-scoped invitation/join-request caches. |
| Presentation | Account loading renders real UIKit-backed content; UI tests exercise workspace entry, sharing, invitation forms, event deletion/cancellation/archive, editor presentation, and the Decide primer. |

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
