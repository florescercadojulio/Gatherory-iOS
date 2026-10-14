# iOS verification

Run the native tests before changing permissions, authentication, or sync behavior.
Use Swift Testing for native unit/transport tests and XCTest for UI automation;
the web backend uses Vitest and `@effect/vitest`.

## Repeatable local checks

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
