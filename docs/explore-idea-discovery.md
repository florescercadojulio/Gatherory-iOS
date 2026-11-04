# Explore ideas and Add to Event — V1

November 2, 2026. Implemented locally in native and server source; no deployment
or upload is implied. The owner explicitly included this feature in V1.

Explore offers All / Blueprints / Ideas through one native menu displaying the
selected value, with All as the default. There is no separate Search heading,
filter icon, segmented row or Ideas/More section. The native search bar remains.
All interleaves Blueprint and idea cards in one masonry feed; individual content
streams retain their server order. The initial mix waits for both first requests
to load or fail, and subsequent pages append without moving existing cards.
Refresh stays in the selected-value menu. Ideas uses the existing image-led
masonry presentation. Opening an idea shows its details,
source Blueprint and creator, with **Add to Event** as the primary action.
The source is a currently published, catalog-visible Blueprint, not a private
workspace or an independently published idea.

## Add and recovery behavior

The native sheet first shows existing workspaces as image-led masonry cards,
with native search across workspace and eligible child-event titles. Tapping a
workspace pushes its destination screen inside the same NavigationStack. That
screen shows the main event and eligible subevents as image cards; choosing one
enables explicit Add Idea confirmation. Native Back returns to the search and
collection without losing the query. Searching for a child does not restrict
the next screen to that child: all eligible destinations remain available.

Only an active host or contributor/manager can add to the exact destination;
guest, view-only, finished, cancelled, removed and invitation-only projections
cannot receive a copy. A writable child can remain available when the main
event is view-only. An event-type idea targets the main event, preserving
the existing two-level schedule boundary.

Adding creates a fresh proposal in Ideas. It does not schedule an event, choose
a team decision, copy votes/tasks, or commit spending. The destination planner
is recorded as submitter; a short source Blueprint/creator credit is retained
in the note. The current portable source configuration is only `{version: 1}`,
so category defaults are used and no estimates, links or dates are invented.
Standalone public idea publishing and idea-specific likes/bookmarks are outside
this slice. Existing Blueprint preferences retain their behavior.

Artwork is copied as local JPEG bytes, never as a reusable source media ID.
Curated immutable CDN images use the existing bounded, redirect-free public
loader. Uploaded Blueprint covers use source-authorized download with the exact
published Blueprint ID/revision. The destination subsequently uploads its own
media through the ordinary offline media pipeline. Image failure leaves the
event unchanged and the sheet open for retry.

The account ID/generation, library object and event permission are checked
before and after image loading and again before saving. One sheet retains one
copy UUID. Retrying that operation cannot duplicate the proposal; a later
intentional copy is allowed. Success follows durable local archive/outbox save.
Save failure rolls back the new idea and expenses. Relaunch restores the copy
without requiring a server connection; sync follows the existing outbox.

After a confirmed add, native presentation closes the destination picker and
then the idea detail, returning directly to the existing Explore feed and
query. There is no success page or extra Done step. Cancelling returns to the
detail; a failed save or image download keeps the picker open without marking
the source.

An **Added** checkmark overlays the source card in both All and Ideas without
changing its height. Account-scoped device-local receipts store only source,
workspace, event and copy identifiers. The badge requires that copy to remain
present and readable in the current account's library; removing a copy or
workspace hides it unless another recorded copy still exists. Temporary loading
gaps do not erase receipts. Refresh and relaunch preserve the marker when the
copy is restored. Account deletion purges that account's receipts, and stale
account-generation callbacks cannot record additions for a later session.
Markers do not synchronize to other devices in this slice.

Added is informational: opening the card still offers Add to Event for another
destination or an intentional later copy.

## Search and session boundaries

The account-bound coordinator reads `GET /api/blueprints/ideas` using `q`,
`cursor` and `limit`. It preserves server relevance order. The server reuses
phrase, English/Spanish alias/related-term and bounded typo matching against
individual idea text. A parent Blueprint title alone cannot match every idea
inside it. Cursors bind the query and result snapshot.

Native query/account changes invalidate late responses. Pagination deduplicates
rows, stops cursor cycles, retries failures and restarts an invalid continuation
once. Switching between All and Ideas retains the current query stream; merely
returning to Explore does not rebuild it. Blueprint stable browsing sessions,
repeat cooldowns and relevance remain separate and retain their existing policy.
Ideas do not yet have individual exposure history or personal recommendation
measurement. Ads are enabled in All, Blueprints and Ideas, including typed
search, using the shared native-ad renderer and consent gates. Placements follow
6 then every 12 organic cards across either type, preserving relevance order.
Recent history stays ad-free. Ads/Blueprint measurements pause while idea detail
covers the feed; idea content and queries are not sent to ad targeting.

The Ideas stream requests **20 records per page**. All can prepare that first
page before the Ideas filter is selected, so switching often uses already-loaded
data. The Ideas view uses the shared lazy masonry feed; image tasks start with mounted
cards. Another page is requested only when one of the last four loaded cards
becomes visible, not merely when SwiftUI creates a card. Mixed All uses the same
visibility trigger. Only an empty cursor page may advance through a visible
sentinel. This replaces an eager masonry/onAppear combination that could drain
successive pages without scrolling.

Client paging is separate from database paging: the current server still reads
the complete eligible public Blueprint catalog, extracts/ranks its ideas, then
returns a page. It does not send the complete idea list to the phone, but
database-side candidate selection and pagination remain server scaling work.
Blueprint responses also retain their existing complete public definitions;
this change does not introduce a lightweight Blueprint-card response.

See the [server contract and policy boundaries](../../../gatherory-web-app/docs/architecture/public-blueprint-idea-discovery.md),
including existing public-catalog moderation/blocking limits.

## Verification and remaining acceptance

The all-channel advertising pass verifies visible Google sample ads in browsing
and typed search for All, Blueprints and Ideas, in Light and Dark. It also
checks that the first organic result is present after typing a query following
scrolling. The shared renderer retains the 20-record lazy paging boundary. See [final advertising evaluation](testing-verification.md).

The current automatic-close/Added-marker pass passed **1,202 registered native
unit tests / 166 suites** (1,201 executed; one opt-in live skip), and two UI
methods covering Cancel plus the full Light/Dark main/child add journey. Result:
`/tmp/gatherory-added-idea-final-20261102.xcresult`. Receipt tests cover reload,
account isolation/purge, callback generations, duplicate receipts, loading gaps,
multiple copies and readable/deleted destination boundaries. Localization
coverage is now 1,800 strings. See [iOS verification](testing-verification.md)
for final durations and limits.

The current flat-feed/workspace-picker revision passes **1,196 registered
native unit tests in 165 suites**, with one opt-in live skip (1,195 executed).
The final search/workspace/native-Back/main-or-child add journey passed in Light
and Dark in **90.831 seconds**, and the existing Blueprint browsing-session
regression passed in **75.664 seconds**. English/Spanish coverage passes for
1,798 strings. See [iOS verification](testing-verification.md) for the final
bundles, regression boundaries and corrections. The initial implementation
evidence below predates this layout revision; its Release build is not a signed
archive of the latest layout.

The new native unit coverage checks portable copying and source credit,
destination permissions, save rollback, durable archive/outbox reload, image
failure, removal/permission/account changes during loading, cancellation,
idempotent retry, transport/auth, query ordering and cursor recovery.

The Light/Dark native UI journey types Garden into the native search field,
adds Garden brunch to a seeded host event, closes both native sheets, opens
that event from Events and finds the independent copy in Ideas. The final
focused run passed **21 unit tests and one UI method** (67.019 seconds):
`/tmp/gatherory-idea-search-handoff-20261102.xcresult`. The earlier add-only
journey passed in 78.314 seconds in
`/tmp/gatherory-idea-discovery-acceptance-20261102.xcresult`. That combined run
also exposed a permission-test fixture mutating legacy member fields rather
than normalized event participation. The fixture was corrected through the
actual participation API; the subsequent full unit run passed **1,182 registered
tests in 163 suites**, with one opt-in live test skipped (1,181 executed).
Result: `/tmp/gatherory-idea-v1-regression-20261102.xcresult`.
That result also includes the existing Blueprint discovery-session UI method,
passing in Light/Dark in **72.244 seconds**: preview/tab return preserves the
browse session and scroll position, and meaningful views change the next
explicit refresh rather than reordering the active session. The existing test
records automatic attachments; no manual screenshot or large-layout pass was
performed.

English/Spanish localization coverage passes for **1,792 strings** with the
existing nonliteral AppCopy extraction advisory. Server typecheck, generated
contract checks and 22 focused tests pass. Its full suite exposed dependency
import errors in the database CLI and Android/Apple sign-in tests; see the
server guide for exact results. The real-database visibility scenario was
attempted in an isolated temporary PostgreSQL 18 container: migrations succeeded,
but the Drizzle import error prevented assertions. The temporary container and
configuration were removed; no shared database was used.

The final generic **Release simulator build passed** (arm64 and x86_64), with
signing disabled: `/tmp/gatherory-idea-v1-release-20261102.log`. The existing
constant-fixture branch and absent App Intents metadata warnings remain. This
is compilation evidence, not a signed device archive or upload.

The native tests use ephemeral storage and synthetic network/cover responses.
Physical-device acceptance with an authenticated deployed endpoint, actual CDN/
R2 copying, destination media upload and a second collaborator remains open.
No database migration, new dependency, shared-account mutation, dev-server
startup, deployment or TestFlight upload was performed for this feature.
