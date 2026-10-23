# Explore Rendering Handoff

## Yours single-scroll overview — October 23

Yours uses one regular VStack scroll for the main event, related events and
masonry ideas. Tapping content opens its native editor sheet directly. Use
and Add use the native bottom toolbar; the pinned action panel, Edit mode,
response indicators and Blueprint Decide route are removed. Event/workspace
Decide remains available after creation.

Yours uses the same standard full-screen presentation as Liked with Back to the
collection. Public contexts stay read-only, and Explore retains native zoom
return. No custom gesture recognizer or dependency was added. Library cards
resolve their customized cover and source identity, matching opened content.
Creation no longer uses Love-only preview projection; saved selections and
confirmed dates are preserved, while new content defaults included.

Current acceptance uses normal text sizes in Light/Dark. Dedicated super-large
layout methods were removed per user direction; Dynamic Type implementation is
retained. See the [current verification record](testing-verification.md#yours-bottom-controls-and-native-creation-form--october-23-2026)
for the current native creation follow-up (69 distinct passing checks across
staged runs), exact bundles and remaining runtime acceptance. The previous sheet/Edit/
Decide results remain historical in that record.

## Explore preview return — October 23

The Explore preview now has a native back chevron and native interactive zoom
dismissal, using the existing matched card identity. Public event details keep
their inner navigation stack. The dismissal callback still restores retained
search state and resumes the covered feed; personal unsaved-change behavior is
retained. No custom drag recognizer, threshold or timing was introduced.

Across staged runs, 27 focused unit methods and four new UI methods passed.
UI checks cover Back and edge-swipe return, scrolling and reopening in Light/Dark,
plus nested detail return, retained search text and personal close
cancellation/discard.
Both Back-arrow captures were inspected. See the
[verification record](testing-verification.md#explore-preview-back-and-swipe-return--october-23-2026)
for bundles, appearance coverage and remaining device/live acceptance.
The Release simulator build and EN/ES localization checks passed.

## Single public preview and event creation — October 23

Discovery, Saved/Liked and shared links now use one read-only scroll: main event,
included events and ideas, with tappable event and idea details. Public workspace
tabs and the event picker are removed. Main-event text grows below reserved
artwork rather than clipping inside a fixed-height cover. Ideas use the existing
`AdaptiveMasonry`, matching the personal Ideas view: independent columns,
12-point spacing, natural card ratios and one column at accessibility sizes.
The later Yours single-scroll follow-up above supersedes its Home/Ideas/Decide
tabs and supports direct taps into native editors.

The masonry correction passed two focused UI methods across staged runs:
ordinary-size independent columns and detail navigation in Light/Dark, plus
the existing Accessibility XXXL read-only check in both appearances. Exported
Light/Dark masonry captures were inspected. See the
[focused verification](testing-verification.md#public-preview-idea-masonry--october-23-2026).

Explore retains Like/Save/More, with Use and Not interested in More; collections
and shared links retain direct Use. New explicit Use plans include the authored
ideas and events, including child events without child-targeted ideas. This
initializes personal inclusion choices only; public likes and live votes are
unchanged. Existing working plans retain their exact choices and pinned source.

Yours keeps Create Events for reusable plans, including previously used sources.
Setup confirms event dates and keeps content editing in the personal workspace.
The legacy setup entry retains event-inclusion switches. Canonical bootstrap,
exact request recovery and reusable history-source retention remain owned by the
existing coordinator. No server or database behavior changes.

Verification covers 99 distinct focused passing methods across staged runs
(94 unit and five UI), including actual setup confirmation/cancel/resume and
separate canonical-import/retry contracts. Light/Dark public previews and
Accessibility XXXL details passed; captures were inspected. Release simulator
build and localization coverage for 1,684 EN/ES strings passed. The setup UI
fixture uses a seeded private pin and schedule-only local transport; it never
submits an installation or simulates creation success.

See [roadmap 15](../../../gatherory-web-app/docs/roadmaps/blueprint-ranking-roadmap/15-single-preview-and-event-creation.md)
and [verification](testing-verification.md#single-public-preview-and-event-creation--october-23-2026)
for final results and test boundaries.

## Context-specific Blueprint previews — October 23

Historical tabbed-preview verification; the single public scroll above supersedes
that layout while retaining the context and authorization boundaries.

Public discovery previews now show Like, Save and More. Use Blueprint and
Not interested are in More; Saved/Liked keep direct Use and shared links keep
direct Use without preferences. Public Home and Ideas are read-only, with no
personal editor, Add, Decide, response filters or private draft overlay. Yours
retains editing, Add, Decide and Save Changes. Like/Save create no working copy.

Explicit Use prepares or resumes the local working plan before the existing
setup flow, preserving saved edits and pinned revisions. Yours refreshes on
collection selection so this plan appears immediately. Existing pending-import,
owner/version and duplicate-use checks remain in place.

Verification passed in two final runs: 58 unit methods and four UI methods.
Light/Dark discovery, Saved and working-copy controls were inspected, with public
Ideas/detail checked at Dark Accessibility XXXL. The existing event-picker label
truncates at that text size. The Release simulator build and EN/ES coverage for
1,678 strings passed. The isolated
DEBUG journey uses the real helper and a temporary draft store, but bypasses
actual setup/server install. Exact results and acceptance limits are in
[native verification](testing-verification.md#context-specific-blueprint-previews--october-23-2026)
and [roadmap 13](../../../gatherory-web-app/docs/roadmaps/blueprint-ranking-roadmap/13-discovery-and-library-actions.md).

## Unified Yours library — October 23

Yours no longer has a secondary Drafts/Installed selector. Personal records,
recoverable customizations and prior-use sources share one masonry grid.
Only an exact full-payload recovery/receipt duplicate is suppressed; different
edits and source identities stay visible. The initial personal ownership lookup
still prevents receipt-card flicker. Internal saved-draft files remain intact;
editing still uses explicit save and existing account/version checks.

The primary Yours/Saved/Liked picker is top aligned below the native navigation
bar. Removing the whole-stack minimum height fixes the large empty gap above
it. One Yours empty state offers Create Blueprint and Explore; creation chooses
an event the account can manage and reuses private capture/review. Continue
setup is contextual to confirmed date progress, and pending imports retain
their separate recovery action.

Verification: 77 unit methods across the library/recovery and editing/capture
passes, plus three UI tests, passed. Light/Dark empty states, chooser dismissal,
mixed content, recovery preview return and pending recovery were checked; seven
captures were exported and selected captures inspected. EN/ES coverage passes
for 1,677 strings. Exact logs, staged results and bounds are in
[native verification](testing-verification.md#unified-yours-library--october-23-2026)
and [roadmap 14](../../../gatherory-web-app/docs/roadmaps/blueprint-ranking-roadmap/14-unified-yours-library.md).
Public-preview controls were implemented in the subsequent slice recorded
above. This library slice does not change search/ranking, database schema,
publication or advertising behavior.

## Native Search/profile alignment — October 23

Explore now uses `.toolbarTitleDisplayMode(.inlineLarge)` so the Search title
and profile button occupy the same native toolbar row at the top. The title
collapses to the compact native presentation on scroll. The system search
field, keyboard, clear and dismissal behavior remain unchanged. The public
preview's Use Blueprint/Edit/+ controls were not changed by the header fix;
the subsequent
[discovery/library action implementation](../../../gatherory-web-app/docs/roadmaps/blueprint-ranking-roadmap/13-discovery-and-library-actions.md)
is recorded separately above.

Seven focused tests passed, including the new Light/Dark header UI test and six
discovery navigation tests. The UI test checks row alignment, types `wedding`,
scrolls results, dismisses search and returns to Browse. Eight captures were
exported; inspected captures confirm the aligned and collapsed presentations
and native typing behavior. See [verification](testing-verification.md#native-searchprofile-alignment--october-23-2026).

## Search restoration and stable card geometry — October 22

The custom search field and experimental shared large-title/profile layout were
reverted at the user's request. Explore retains the standard native navigation
title and profile toolbar action with SwiftUI `.searchable`, `.searchFocused`,
and the system's clear, Cancel, keyboard and search presentation behavior.
Category tiles and All Blueprints remain removed. Search scoring is documented
in the [web roadmap](../../../gatherory-web-app/docs/roadmaps/blueprint-ranking-roadmap/11-search-relevance-and-scroll-header.md).

Catalog cover decoding no longer changes card geometry. Each listing card uses
its category's predetermined cover-area ratio from its first render through
image load, failure, caching, and lazy remount. The image fills/crops inside that
reserved space. Removing the decoded-image ratio callback avoids moving the
cards below it when an image arrives or a card remounts. Glur is removed from
catalog cards; the existing dark gradient keeps overlaid text readable. Preview
and other image surfaces retain their own behavior.

Screens without an ad session no longer schedule phantom ad slots in the masonry
height estimates. Recent and ad-disabled catalogs therefore allocate columns
from the organic cards they actually render. The October 22 visual fixture did
not exercise live ad creative sizing; current ad-enabled behavior is recorded
below.

The paged grid retains stable entry identities instead of resetting its entire
content identity for each query/source change. The content uses native container
width sizing without an outer GeometryReader or width-measurement state; the
existing lazy masonry columns remain responsible for offscreen card lifecycle.

The DEBUG-only `-BlueprintSearchVisualFixture` flag supplies forty local entries
with mixed category ratios and public cover URLs, with Explore API actions,
measurement and ads disabled. Its presentation checks do not test production
search relevance or ad loading. Card UI regression coverage compares heights and
relative placement through image settling and repeated offscreen/return scrolls
in explicit light and dark app appearances. The final light/dark card UI test passed on the iPhone 18 Pro simulator (iOS
27.0): card heights and first-screen relative placement remained within one
point through decoded artwork and offscreen/return checks. Both column tails
remain populated with at most one card-height difference when ads are absent.
Eight screenshots were captured; loaded, scrolled and returned views were
inspected in both appearances. Result bundle:
`/tmp/gatherory-card-stability-no-inactive-slots.xcresult`; attachments:
`/tmp/gatherory-card-stability-no-inactive-slots-shots`.
Thirty-two focused discovery/navigation/preview-session/layout tests also passed
in `/tmp/gatherory-card-stability-unit.xcresult`. English/Spanish coverage passes
for 1,671 strings. The final Release simulator build also passed
(`/tmp/gatherory-card-stability-release-final.log`).

Native checks adapt the installed ReUI guidance: no dependencies or motion were
added, loading/fallback/retry behavior and Dynamic Type handling are retained,
and C1–C4 source checks passed after manual review of the existing non-animation
dwell measurement (`visibleDuration`). The web-specific audit tool and native
lint configuration are unavailable; accessibility labels, decorative artwork,
contrast, scroll mechanics and focus ownership were reviewed manually. This is
simulator presentation evidence, not a physical VoiceOver, live inventory,
server authorization or frame-rate evaluation.

## October 23: ad-enabled scroll stability

The paged Explore grid prefetches the next three scheduled ad slots. A loaded
creative is first admitted only while its organic anchor's insertion edge stays
below the viewport; a response that arrives after the edge is reached is skipped
for that feed identity. The native renderer measures the creative's natural full
height at the anchor width and current Dynamic Type size. Its height becomes the
slot's minimum reservation, retained through lazy remounts and creative expiry.
Expiry removes the creative immediately and leaves the reservation only for
slots that were already admitted. Replacements that fit the existing height can
render without shrinking it; a taller replacement grows the reservation only
while the insertion edge is below the viewport.

Masonry continues to assign rows using a 372-point ad estimate (360-point
creative estimate plus 12 points of row spacing), regardless of fill. This keeps
page appends and ad admission from reassigning later organic cards between
columns. A never-admitted no-fill slot renders no blank cell, though its estimate
can make the column tails uneven. Width, feed scope, session reset generation,
Dynamic Type size, and locale changes invalidate slot measurements.

The current-source suite passed **38 tests** (35 unit and 3 UI; zero failures or
skips) in `/tmp/gatherory-ad-scroll-final.xcresult`. Eight pure placement tests
cover late initial fills, reservation after creative loss, fitting visible and
taller offscreen replacements, width reflow, and reset. Light and Dark UI runs
covered Google sample ads, pagination from items 1–20 to 21–40, preview return,
and stable no-ad card geometry. Dark appearance also covered ad remount at
accessibility XXXL text size. Captures are in
`/tmp/gatherory-ad-scroll-final-shots`; the inspected Light and Dark loaded-ad
screens both showed **“No implementation issues found”** in Google's validator.
The accessibility-size ad retained its multiline copy without horizontal
overflow.

A final ad-arrival follow-up passed **9 tests** with zero failures or skips in
`/tmp/gatherory-ad-arrival-final.xcresult`. It records a visible organic card's
x/y position and width/height before scrolling as a prefetched sample ad becomes
ready, in both Light and Dark. Geometry remained stable after the stale geometry
identity guard landed. The follow-up repeats the eight placement-policy tests,
so its result overlaps with the 38-test suite rather than adding nine unique
tests.

This is simulator and Google sample inventory evidence. It does not establish
Gatherory UMP behavior, production authenticated catalog behavior, physical
device scrolling, the 55-minute expiry path, ad-click handling, or frame rate.
The Release result is recorded separately in
[native testing verification](testing-verification.md).

Curated Explore catalog cards can load optional `discovery.coverImageURL`
artwork from immutable paths on `cdn.gatherory.com`. Public image streaming and
ImageIO decoding run in a cancellable utility task, capped at 6 MiB and a
1600-pixel decoded long edge. Existing cover caching and fallbacks are preserved; listing cards no longer
subscribe to aspect-ratio callbacks or apply progressive blur. Private `coverAssetID` reads
remain preferred. The October 22 carryover implementation now imports curated
artwork into a private Blueprint cover during creation of a new personal copy,
then installs it through the existing private event media projection. Completed
older copies retain their original artwork. The updated server/native carryover
path has not been deployed or installed on the phone.

The former Explore category tiles used `AdaptiveLazyGrid`, backed by SwiftUI `LazyVGrid`.
Each tile uses a dedicated vivid solid category color, an SF Symbol, and a title.
The palette includes emerald, mint, yellow, pink, cobalt, periwinkle, orange,
coral, and violet, with stable category assignments in light and dark appearance.
These tiles are no longer rendered in Explore; their compatibility components
remain available. Paired foreground colors retain at least 4.99:1 text contrast; symbols use the
same foreground without hierarchical fading. Accessibility text sizes wrap
without a line limit. Catalog cards apply
a dark gradient to unblurred full-card cover artwork while keeping the overlaid title
and byline sharp. A smooth contrast fade supports media foreground text, with no
solid text tray. Catalog artwork has no blur in either transparency setting.
The card presents a prominent purpose-led title and a small optional creator
byline; there is no category label, summary, event/idea highlight, or visible
preview CTA. The existing whole-card button opens the preview. Titles should say
what experience a Blueprint is for (for example, “Cottage Weekend” or “Backyard
Birthday Party”); there is no new title validation or automatic renaming, and
extra card metadata should not compensate for vague titles.
Blueprint catalog cards use `AdaptiveLazyMasonry`: source-ordered items are
assigned to the shortest estimated column, and each column uses `LazyVStack`
to keep offscreen organic card views and their image work unmounted. Ad loading
is managed by a separate bounded prefetch for the next three scheduled slots.
Estimates use the category ratio (0.70–0.92) multiplied by column width for the artwork's
clear upper area, plus a 104-point text-height estimate. The cover fills both
areas. Active ad-enabled layouts add a 372-point estimate to scheduled rows for
column assignment even before an ad fills. This is separate from the rendered
slot: a creative enters only after it is ready and its insertion edge remains
below the viewport, and its measured native height determines the actual
reservation. Decoded image dimensions do not resize listing cards;
the masonry estimate stays category-based so asynchronous image sizes do not
reassign cards between columns. Text content determines actual height and can
grow with Dynamic Type; the estimate is not a text height constraint. An
ad-enabled slot remains absent until safe admission; after admission its
reservation survives lazy remount and creative expiry. The constant column
estimate means loading an ad does not move later items between columns. Stable
catalog/ad IDs and source-order accessibility priorities preserve pagination
and reading order. Accessibility Dynamic Type keeps catalog cards in one column.

Both layouts adapt across one, two, four, and six columns on wider displays and
use fold-aware slot widths, gaps, and physical edge insets. RTL maps physical
slots into reading order. No scrolling performance measurement has been
collected for the lazy masonry implementation.

## October 22: paged discovery

Browse, search, and category results now use `BlueprintCatalogFeedModel` with
server cursor paging; the legacy model remains for finite recent history.
Category metadata comes from the authorized catalog rather than only the first
loaded page. Search is debounced and matched on the server. The content-search
follow-up below adds published event/idea content, whole-word/phrase concepts,
bounded bilingual aliases and related terms, and deterministic query relevance.
See [Explore advertising and paging](explore-advertising.md) for loading,
inventory, consent, release configuration, and current build evidence.

Paged native catalog requests explicitly send `ranking=baseline_v1` on every
browse, category, and search page, including cursor continuations. The feed
retains server page and entry order. The legacy full-catalog request used by
recent history does not send the ranking capability, so it keeps the existing
catalog behavior. Older servers can ignore the additive query parameter.

## October 22: personal Likes and cursor recovery

The server now supports an experimental `blueprint-personal-likes-v2` rule behind
the same `ranking=baseline_v1` request. It uses only the requesting account's
current exact public Likes and bounded public-content overlap; measurement opt-in
is independent. Bookmarks, installs and other accounts' Likes do not contribute.
The native client preserves server order and performs no local affinity ranking.
Account settings explain in English and Spanish that Likes tailor recommendations
and can be undone. See the server's [personal Like rule and evaluation](../../../gatherory-web-app/docs/roadmaps/blueprint-ranking-roadmap/08-personal-like-ranking.md)
for the original implementation history. The server-only [v2 precision tuning](../../../gatherory-web-app/docs/roadmaps/blueprint-ranking-roadmap/09-personal-like-precision.md)
separates title/summary/notes roles, downweights common content and normalizes
similarity. Its policy fingerprint restarts incompatible v1 cursors even if order
is unchanged. No native code or wire change is needed. The wedding diagnostic
improves; the fresh challenge shows no overall precision/recall gain over v1.

Like/source changes can invalidate a continuation even when order is unchanged.
On a typed `BLUEPRINT_CATALOG_CURSOR_STALE` continuation error, the feed clears
the old stream and requests page one once for the active query/category. It
replaces old ordering rather than merging incompatible pages. A failed restart
or stale first page shows the existing retry state; ordinary errors retain their
cursor. Generation/cancellation guards discard late responses after an account
or scope change.

Historical verification from the initial personal Like slice (not rerun for the
server-only precision change): the reported unused task-result, saved-preview
adapter isolation and shared date formatter isolation diagnostics are fixed. A local iPhone 18 Pro simulator build
and the final 30 tests across `BlueprintDiscoveryTests`, `BlueprintActionsTests`
and `BlueprintCatalogContractTests` passed; English/Spanish localization coverage
passed for 1,659 strings. Result: `/tmp/gatherory-personal-like-native-feed-final.xcresult`;
log: `/tmp/gatherory-personal-like-native-feed-final-test.log`. This is simulator
evidence, with no new physical-device or production-quality claim.

## October 22: Blueprint actions and qualified discovery signals

Public catalog entries can expose account-scoped like, bookmark, and Not
interested actions through the card context menu and preview toolbar. Cards keep
their cover, title, and optional byline; no counters or nested card controls are
added. The native client enables these actions only when the public catalog
response includes `viewerState`. Shared-link previews, saved private copies,
personal-library entries, and installed previews do not gain social actions from
a source key alone. Not interested removes the item from browse/category results
after acknowledgement while search and saved references remain available.

Saved Blueprints keeps a bookmark as a return reference, then looks up that exact
key in the current public catalog before opening its existing preview. Saved
opens carry no discovery exposure and submit no open signal. If the publication
is no longer available, the list shows a generic unavailable row and allows the
account to remove its saved reference. The Hidden list exposes the reversible
Not interested choice and shows current public titles where available. A failed
preference refresh keeps existing rows visible and offers a retry; an empty
initial load shows progress instead of a false empty state.

Explore passes its account-bound action store into Account settings, so consent
and saved preferences are immediately shared between both surfaces. Closing
Account settings and returning to Explore after a tab or scene transition
refreshes preferences, consent, and the current catalog page. The impression
dwell pauses while Account settings or a category screen covers Explore.

The account setting **Improve Blueprint recommendations** is off by default and
describes organic views, opens, and public source usage. Until the setting is
enabled, the client does not submit measurement signals; preferences remain
fully functional. Public catalog responses may include an expiring
`discoveryContext` only for eligible opted-in viewers. A passive impression is
claimed after SwiftUI reports at least 50% scroll visibility continuously for
one second while Explore is active and no preview or covering screen is
presented. The card task is keyed to the account, consent state, exposure ID,
query/category, scene, and preview state so leaving that context cancels its
dwell timer. Recent-history cards and ad slots do not submit measurement
signals. An explicit preview selection from browse, category, or
search can submit an
open only with that entry's current, unexpired exposure ID. Signal failures are
best effort and never block a preview. Native code sends no private content or
PostHog events.

The optional `discoveryExposureId` on a saved-copy source is forwarded only from
an unexpired public catalog context. Missing or expired context remains valid
for ordinary copy behavior; the server independently verifies actor, source
revision, exposure, consent, and eligibility before it grants attribution.
Optional catalog viewer/measurement fields and the copy source field decode as
absent for older server responses and requests.

Native checks recorded during implementation were Swift frontend parsing, scoped diff
whitespace validation, and English/Spanish localization coverage. The parent
simulator build, full unit target and final focused suites subsequently passed;
see the verification record below. No runtime visual inspection or physical-
device acceptance is claimed here.

## Previous catalog loading

Before the paging change, `BlueprintDiscoveryModel` derived category entries and localized searchable
text from the loaded catalog. Search text is indexed by entry ID, normalized
for the current locale, and rebuilt when the locale changes. Category IDs use
stable raw values; catalog entry IDs remain the `ForEach` identity. Preview
navigation retains the source entries and query while a preview is presented,
and transition IDs combine catalog source and entry ID. Catalog loading remains
guarded by active Explore state, active scene phase, and an available signed-in
installation coordinator.

No frame-time measurements have been collected yet; the expected improvement
is reduced offscreen card creation and removal of all-card layout measurement.

Validation on October 21, 2026: Xcode 27.1 simulator build succeeded for iPhone
Duo with the cached package checkout. Scoped diff whitespace checks passed.
No tests were added or run, and physical-device scrolling has not been measured.
Build log: `/tmp/gatherory-explore-performance-build.log`.

October 22 masonry build: Xcode 27.1 simulator build succeeded. Scoped diff
whitespace checks passed. No tests were added or run, and physical-device
scrolling has not been measured. Build log: `/tmp/gatherory-explore-masonry-build.log`.

## October 22: viewport sizing correction

Catalog ScrollViews now take their content width from an outer viewport
GeometryReader, subtract screen insets, and apply the 760/1200-point content
limit explicitly. The masonry container expands before measuring geometry,
and each cell receives an explicit column width. This removes reliance on
content ideal widths during empty/loading states.

The simulator app build passes. An isolated render fixture using the production
catalog tile/grid and masonry code, with synthetic data and artwork, showed
two full-width columns after asynchronous loading on iPhone 18 Pro (iOS 27.0)
and the Duo outer display (iOS 27.1). This is layout evidence, not a check of a
signed-in account screen or physical-device scrolling. Diagnostic screenshots:
`/tmp/gatherory-masonry-render/verified-phone.png` and
`/tmp/gatherory-masonry-render/verified-duo.png`. No test suite was added or run.

October 22 visual polish validation: app simulator build succeeded; scoped
diff checks and English/Spanish localization verification passed. An isolated
fixture rendered the production category/card/grid views with a bundled
portrait cover and the Glur shader on iPhone 18 Pro. The fixture uses synthetic
entries and sample theme values; it is not a signed-in account screen.
Screenshot: `/tmp/gatherory-masonry-render/polish-dark.png`.
The AdMob validator investigation was deferred at the user’s request; no
ad implementation or environment-secret change was retained in this pass.

## October 22: Blueprints library card stability

The main **Blueprints** tab uses library tiles, separate from Explore catalog
cards. Its scroll content now reserves its viewport-derived width from the first
layout pass. Draft cells use their persistent request IDs instead of array
positions. The saved collection preference is applied during initialization,
not after the first network refresh. Installed tile category/aspect ratio comes from the saved blueprint
source, with a stable Events fallback for legacy receipts; it no longer changes
when live event data hydrates.

Personal blueprint cache rows are loaded during view initialization so an owned
blueprint is not first painted as an installation receipt. When no personal
snapshot exists yet, initial cards wait for the first ownership lookup to finish;
subsequent refreshes retain the displayed collection. A failed cache reread also
preserves existing rows. Sharing metadata stays visible during refresh (existing
action guards still apply), and the personal tile reserves enough space for both
status badges, including their narrow-width layout, before metadata arrives.

This pass changes only the library; Explore's portrait-aware artwork sizing and
its ad/paging layout are unchanged. No tests were added or run. Physical-device
scrolling and visual acceptance remain unverified for this change.

Validation: the iPhone Duo simulator build, English/Spanish localization coverage
(1,638 strings), and `git diff --check` passed for this library stability pass.
Build log: `/tmp/gatherory-blueprint-card-stability-build.log`.

## October 22: scan-first Blueprint cards

Historical visual pass: the blur described below is superseded by the stable,
unblurred catalog cards documented at the top of this handoff.

The current `BlueprintCatalogTile` keeps the existing cover/fallback and outer
card action, with a prominent purpose-led title and small optional byline.
The preview remains read-only and shows the plan's events/ideas. Title and byline
now overlay the full blurred cover with a smooth contrast fade; the solid tray
was removed in the next visual follow-up. The text-height estimate remains
104 points; title and byline wrap at accessibility sizes, and the
grid retains its existing single-column layout at Dynamic Type accessibility
sizes. Catalog ordering, paging, ad boundaries, and account isolation are
unchanged.

Earlier verification before tray removal: native build plus 25 focused
navigation/content/session tests passed; English/Spanish localization validation
passed 1,638 strings. The isolated fixture at
`/tmp/gatherory-blueprint-scan-card-visual-20261022` compiles the production tile,
cover helper, and portable contracts with synthetic catalog entries. Settled
`light.png` and `dark.png` two-column captures and a `large-text.png` AX3
one-column long-title/byline capture
were inspected for wrapping and overlap. The fixture stubs cover transport,
theme/category values, and localized copy; it does not establish signed-in feed
behavior, preview navigation, or spoken VoiceOver quality. Physical-device
acceptance remains.

### Full-cover text overlay follow-up

The solid semantic text tray is removed. Artwork now fills the card behind its
sharp title and byline; progressive Glur and a smooth media contrast fade support
readability. `estimatedTextHeight` retains the 104-point layout estimate without
constraining actual Dynamic Type text height. Source identity, cover callbacks,
whole-card preview selection, paging and ad estimates are preserved.

The app build and **27 focused tests in three suites passed** on the iPhone
18 Pro simulator (iOS 27.0). The updated fixture at
`/tmp/gatherory-blueprint-card-overlay-visual-20261022` rendered the production
tile/helper with synthetic data, local artwork and stubbed theme/transport.
Settled `light.png`, `dark.png`, `missing-artwork.png` and `large-text.png`
were inspected; text remains visible and wraps without overlap. These fixtures
are layout evidence, not physical-device or signed-in feed acceptance.
See [testing verification](testing-verification.md#blueprint-card-tray-removal--october-22-2026)
for the current log and result bundle. No automated UI tests were run.

### Superseded event/idea-highlight prototype history

`BlueprintDiscoveryCardContent` was a pure projection of each catalog entry's
exact published definition. It independently accepted supported tree/idea modules,
rejected ambiguous source keys and orphan idea targets, and selected at most three
nonblank, distinct titles. Mixed content started with one child event and one
idea, then another idea when available. Main-event-only plans omitted highlights
without showing an empty section. Source identities included the catalog key,
revision and nested source key. No private live-event lookup, new request,
tracking, sorting, mutation or installation was involved.

The earlier `BlueprintCatalogTile` retained its cover transport/fallback, source
identity and outer selection button in both catalog grids. That implementation
included highlight rows and a localized Preview Blueprint affordance. This
prototype, its projection and its copy are superseded; they are not current
card behavior or acceptance criteria.

The superseded highlight prototype's full non-UI native target passed **941 tests in 132 suites**, followed by
**34 focused tests in four suites** after final review. Nine new projection tests
cover mixed/one-type/empty content, caps/order/identity, unsupported and malformed
modules, ambiguous keys, orphan targets, blank/duplicate titles and nonmutation.
English/Spanish verification passed **1,639 strings**. See
[testing verification](testing-verification.md#superseded-blueprint-discovery-highlight-prototype--october-22-2026)
for historical commands and result bundles.

An isolated simulator fixture compiled the production tile, projection and
portable contracts against synthetic entries and bundled artwork on iPhone
18 Pro (iOS 27.0). Cover transport, category/theme values and localized copy
lookup were stubbed. Settled renders were inspected for normal two-column
mixed/main-event-only cards, event-only content, light/dark appearance, the
Spanish preview label, missing artwork, and large-text title wrapping in a single
column. These are layout checks, not signed-in feed or spoken VoiceOver evidence.
The large-text capture showed the upper portion of a scrollable long card; its
lower content still needed device acceptance.

Historical fixture directory: `/tmp/gatherory-blueprint-card-visual-20261022`.
Inspected captures: `light.png`, `dark.png`, `spanish.png`,
`missing-artwork.png`, `large-text.png`, `events-only-settled.png`.
The fixture changed no repository configuration and used no account or server.
Physical-device scrolling, spoken VoiceOver, Reduce Motion/Transparency settings,
and opening the preview from real paged/category/search screens remain acceptance
checks. These renders were for the superseded prototype. No UI tests or
physical-device installation were performed for it.

Current card implementation is in
[`BlueprintDiscoveryCards.swift`](../Gatherory/Features/Blueprints/BlueprintDiscoveryCards.swift).
Content search is next in the [Blueprint discovery roadmap](../../../gatherory-web-app/docs/roadmaps/blueprint-ranking-roadmap/02-content-search-and-related-terms.md).

## October 22: published Blueprint content search

The server now searches public Blueprint name/summary, supported child-event
titles and idea titles/notes. Its explicit EN/ES aliases and one-hop outdoors
expansion find relevant nested content without adding topics or hashtags.
Empty browse order is unchanged; query relevance uses all concepts and stable
catalog-key ties. Search source/rule changes invalidate old cursor snapshots.
See the [implemented search slice](../../../gatherory-web-app/docs/roadmaps/blueprint-ranking-roadmap/02-content-search-and-related-terms.md)
for the precise dictionary, source boundaries and staged web verification.

No native production change was needed: `BlueprintExploreView` sends the query
through `catalogPage`, and `BlueprintCatalogFeedModel` preserves server result
order without using the legacy local metadata matcher. Cards remain cover,
title and byline; source details are in the existing preview. Two new native
feed tests protect server-only nested matches, relevance across pages, forwarded
query/cursors and rejecting a late page after the query changes.

The simulator build and **37 tests in four discovery/preview suites passed**.
Log: `/tmp/gatherory-blueprint-content-search-20261022-native.log`.
Result: `/tmp/gatherory-blueprint-content-search-20261022.xcresult`.
No new display strings, response fields, analytics, ads or private-data paths
were introduced. No UI tests or new visual fixture were needed for the unchanged
presentation. Signed-in device search/preview and physical scrolling remain
runtime acceptance after compatible server rollout; nothing was deployed or
installed on a physical phone by this pass.

Parent integration verification for actions/measurement: the simulator build and
full unit target passed 949 tests; after the final consent retry fix, 42 focused
Blueprint tests passed on final source. Localization verified 1,658 EN/ES strings.
See the [current verification record](testing-verification.md#blueprint-actions-and-measurement--october-22-2026)
for logs, staged results and remaining device/server rollout acceptance.

## October 22: recommendation baseline capability

Paged browse/category/search opts into the deterministic server baseline while
history and saved-reference rechecks keep the full-catalog path. The server
preserves exact query relevance before editorial priority, creator diversity
and recent-authored opportunity. Its ranked cursor freezes time/configuration
and restarts incompatible snapshots. The native feed retains the resulting
order and existing ad positions, with no new card details.

The app simulator build and 36 focused transport/discovery/navigation/action
tests passed. See [native verification](testing-verification.md#explicit-native-blueprint-catalog-ranking--october-22-2026)
and [server slice 04](../../../gatherory-web-app/docs/roadmaps/blueprint-ranking-roadmap/04-recommendation-baseline.md)
for logs, policy choices, versioned exposure labels, migration and rollout order.
No server deployment or physical-device acceptance is claimed.
