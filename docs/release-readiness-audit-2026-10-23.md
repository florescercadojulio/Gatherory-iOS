# Release readiness audit — October 23, 2026

This audit starts from native `19833ddc` plus the build 6 version increment,
and backend `ee9b6476`. Build 1.0 (6) was already uploaded before this audit.
The invitation preview fixes below are newer working-tree changes and are not
in that uploaded binary or deployed backend. No release/deployment is performed
by this audit.

## Confirmed issues and corrections

Incoming invitation previews could show the wrong calendar day when the event
timezone differs from the viewer's timezone. Both the share-link and private
email preview APIs omitted the event timezone/all-day metadata. The native
preview and public web invitation page then formatted the timestamp in the
viewer's timezone. For example, 04:30 UTC on July 15 is July 14 in Los Angeles
and July 15 in Detroit.

The API now returns additive `timeZone` and `isAllDay` fields for pending and
accepted share previews and private email previews. The native preview uses
the event timezone with backward-compatible optional decoding; the public
invitation page also uses that timezone and omits time for all-day events.
Missing/invalid zones retain the legacy viewer-zone fallback. Invalid timestamps
are omitted. No schema migration is required. The backend rollout and a new
native build are both required to deliver the correction fully.

Regressions cover cross-zone midnight, all-day dates and old/invalid metadata;
the database test verifies exact stored metadata through all three preview
paths. The public formatter has four passing tests. Final native checks are
recorded below.

Home's long-press menu also exposed cancellation/deletion/archive actions while
their confirmation was attached only to the opened invitation detail. The
shortcut could therefore leave an unpresented pending request. Home keeps its
edit/export/save shortcuts, and destructive lifecycle actions stay in the detail
view. The regression verifies absence of destructive Home shortcuts plus detail
Cancel preserving the event and confirmed deletion removing it.

The Decide primer's upward practice drag scrolled the surrounding page instead
of selecting Maybe. A recording and measured card frames confirmed the page
movement. The rounded card now owns drags from touch-down with native gesture
priority; its appearance and flow remain the same. Real Pass/Maybe/Love gestures
and the practice controls pass in English Light/Dark and Spanish Dark.

## Verification matrix

| Area | Evidence and result |
| --- | --- |
| Native final unit suite | 1,029 tests / 1,163 executions passed with zero failures, skips or runtime warnings after all fixes. `/tmp/gatherory-release-audit-unit-source-final-20261023.xcresult`. |
| Native functional UI | All 41 scenario methods have passing evidence across the full run and focused reruns, including two new core flows. Covers Explore, libraries, Blueprint Use/retry/handoff, dates, invitations, sharing, guest/view-only access, cancellation/removal, Decide and shared albums. This is aggregate evidence, not a single green 41-method bundle; details below. |
| Backend final checks | Contract generation check, 839 tests, typecheck and production build passed after the fix. 58 opt-in tests skipped in the default run. Build retains 450 non-fatal vendor `use client` directive warnings. Logs: `/tmp/gatherory-release-audit-web-20261023-final-{test,typecheck,build}.log`. |
| Isolated database | 29 suites / 47 tests passed serially against a throwaway PostgreSQL 18 container; the updated invitation regression also passed its focused rerun. |
| Local HTTP | Device guest, account deletion and mocked Apple token revocation each passed against a loopback server and isolated DB (3 tests). R2 flags stayed off. Logs: `/tmp/gatherory-release-audit-web-20261023-{device-guest-http,account-deletion-http,apple-token-revocation}.log`. |
| Public production entrypoints | Root and sign-in redirect to TestFlight; reset-password and invalid-token public preview pages return HTML; unauthenticated catalog is rejected with 401. This does not establish authenticated data behavior. |
| Recent beta telemetry | Gatherory's PostHog project 662674: no captured Error Tracking issues in the seven-day window, but `$exception` was not seen, so this is not crash-free evidence. The separate native log stream had 149 sync-error entries in seven days and five error/fatal entries in the last 48 hours (four `CloudSyncFailure`, one `NSURLError`). Existing logs lack build numbers and detailed categories, so these cannot be attributed to build 5/6 or a specific failure cause. |
| Native runtime warning | The UI run reproduced `Invalid frame dimension (negative or non-finite)` during setup-field focus/keyboard presentation. It has no app stack; the flow's visible assertions passed, and source review found no negative dimension calculation in the standard Form path. Attribution remains unresolved; this audit does not claim the warning is fixed. |
| Localization / Release build | 1,700 English/Spanish strings verified. Generic Release simulator build passed for arm64 and x86_64 after all fixes; this is not a device archive/upload. Effective Debug/Release app and test settings all use iOS 26.0. Logs: `/tmp/gatherory-release-audit-localizations-20261023.log`, `/tmp/gatherory-release-audit-release-20261023.log`, `/tmp/gatherory-release-audit-deployment-targets-20261023.log`. Existing nonliteral localization-key advisory and AppIntents metadata warning remain non-fatal. |

Native checks used Xcode 27.1 and iPhone 18 Pro / iOS 27.0 simulator. The full
39-method UI run passed 36 and failed three; its bundle is
`/tmp/gatherory-release-audit-ui-20261023.xcresult`. The archive test needed
bidirectional scrolling because the sample ceremony's fixed 16:00 time can sort
before the main event's current clock time. That harness correction and the two
new core journeys passed in
`/tmp/gatherory-release-audit-ui-final-20261023.xcresult` (three passes, two
then-unresolved failures). The Home lifecycle correction passed in
`/tmp/gatherory-release-audit-ui-fixes-20261023.xcresult` (one pass, one
then-unresolved primer failure). The final primer correction passed in
`/tmp/gatherory-release-audit-primer-fixed-20261023.xcresult` with zero runtime
warnings. Failed bundles are retained as diagnostic evidence, not counted as
all-green runs.

The new `ReleaseCoreFlowsUITests` uses real local creation/editing controls in
Light/Dark: Create automatically opens the new event's Home, its invitation
shows the saved title and today's date, and a manually added idea can be edited,
decided with a real swipe, and restored with Undo after the last card. These
are ephemeral local flows, not production transport/provider tests. Selected
setup Light/Dark, primer and album screenshots were visually reviewed; exported
attachments are under `/tmp/gatherory-release-audit-ui-shots-20261023`.

Huge-text cases are excluded as requested; launch performance and the iPad-only
geometry test were deliberately not executed. This does not establish physical
device behavior or runtime behavior on every supported OS version.

Database/HTTP runs used disposable test data, synthetic configuration and,
for the final runs, guards against reading workspace environment files and
against non-loopback networking. Two Blueprint DB tests failed in a parallel
run but passed separately and in the complete serial run, indicating shared
fixture interference. The serial green result is the supported evidence.

During setup, two migration invocations targeted the isolated DB but preceded
the environment-file guard, so automatic dotenv reads cannot be ruled out.
Two excluded storage-dependent suites attempted R2 with synthetic credentials;
those calls failed. They were stopped, and subsequent runs blocked external
connections. The initial preview regression also used the existing local-DB
guard and a transaction that rolls back; the final regression was rerun in the
isolated setup. No successful external-provider write or persistent change to
existing user data was observed. The disposable server/container and temporary
synthetic key were removed after testing; logs were retained.

PostHog was inspected through aggregate counts/facets, without individual
users, recordings or raw event content. See [Error Tracking](https://us.posthog.com/project/662674/error-tracking)
and [Logs](https://us.posthog.com/project/662674/logs). The project timezone is
UTC; these counts are a snapshot taken during the October 23 Detroit audit.
Lifecycle telemetry confirms builds 5 and 6 were seen, but existing sync log
records cannot be joined reliably to a build.

The next native candidate improves the existing `workspace_sync_failed` log
with a validated build number, fixed failure categories and, where available,
a strictly parsed HTTP status or numeric URL error code. It forwards no raw
server code/message, URL, token, account/event identifier or NSError user info.
It adds no analytics event and changes no consent/enablement setting. The final
unit suite verifies these boundaries. Existing historical sync failures still
need a live reproduction; the new metadata cannot retroactively explain them.

## Acceptance that local tests cannot establish

- Real Apple/Google sign-in, credential restoration/expiry and account handover
  on the signed build.
- Host/collaborator/guest invitation acceptance and link delivery with disposable
  accounts against the intended deployment.
- Two-device date/content sync, offline relaunch/reconnect and media retries.
- Actual R2 upload/download and account-deletion storage cleanup. The isolated
  account-deletion test covered the database/API branch with storage disabled.
- Physical-device APNs delivery/tap routing, consent and ad availability; tests
  never click live ads.
- Native system Calendar/share-sheet completion and external Maps launch.

The automated UI journeys use seeded ephemeral DEBUG fixtures and bypass real
authentication. A green local result must not be described as a completed live
production journey. Live-account scope was requested from the release owner;
no credentials, invitations or accounts are created/deleted in production by
this audit.
