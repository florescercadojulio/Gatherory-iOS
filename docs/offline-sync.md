# Offline and PostgreSQL synchronization

Gatherory uses a local-first outbox/inbox design. SwiftData remains the UI's
source of truth, while the authenticated web API replicates independently
versioned planning records to PostgreSQL. A complete workspace snapshot remains
as a compatibility and web-companion materialized view. Losing connectivity
does not block editing: changes remain in the durable outbox and retry when the
app becomes active or another local edit is made.

## Invariants

1. The local database is the UI's source of truth.
2. A workspace edit and its `PendingMutation` are saved in one `ModelContext`
   transaction.
3. Mutation IDs are stable idempotency keys and survive retries and launches.
4. Delivery is at least once. PostgreSQL mutation receipts make duplicates
   safe.
5. Applying a remote change page and advancing its cursor is one local
   transaction.
6. Deletes are durable tombstones until the server acknowledges them.
7. Every local row and remote snapshot is scoped to the canonical Better Auth
   user ID.
8. A server-version conflict preserves the local edit for later resolution;
   it does not overwrite the visible workspace with the server snapshot.
9. Large media will use file-backed S3 uploads, separate from JSON sync.
10. A foreground run drains every ready outbox batch before pulling remote
    changes; the server's 50-mutation request limit cannot strand later rows.
11. Local workspace records, cursors, receipts, and leases are account scoped.
    The same shared workspace may be cached independently for two accounts on
    one device.
12. A child-event planning workspace is an isolated projection keyed by the
    child event UUID. Its archive's optional `isScopedEvent` marker defaults to
    false for older archives; scoped projections contain only that child's
    planning data and never its parent or sibling identifiers.
13. Scoped edits enqueue entity mutations only. They never write the root
    workspace snapshot; the child event's metadata is represented by the event
    entity at the scope UUID, without parent or linked-idea references. Root
    workspace transaction behavior is unchanged.
14. A full scoped pull replaces collaborative arrays from the authoritative
    projection while retaining downloaded media. Pending entity edits are
    overlaid for display after the pull, but server-owned participant roles,
    permissions, invitation state, and RSVP remain authoritative. Bootstrap
    omissions do not discard an offline scoped workspace.
15. `SCOPE_READ_ONLY` triggers that authorized pull even when a draft is marked
    attention; the draft remains queued while refreshed roles lock editing.
    Only a scoped `SYNC_SCOPE_NOT_FOUND`/`SCOPE_WRITE_FORBIDDEN` response or an
    authoritative scoped workspace delete clears the cached projection and
    its pending work. Generic authorization failures and network errors never
    purge it.

## Shared event To-dos

Manage → To-dos uses the existing transactional archive/outbox path. Each
`EventTodo` belongs to one exact event; active hosts and collaborators can read,
while hosts and Manage/Contribute collaborators can write only while the event
is writable. Guests receive no task payloads. The optional archive `todos`
array keeps older version-1 archives readable; the dedicated `todo` entity owns
server writes. Embedded workspace arrays are replaced from canonical authorized
storage and cannot bulk-edit or erase tasks.

`RemoteEntityVersionRecord` stores task versions by account, replication scope
and entity. Bootstrap, pull and push acknowledgement stage these records with
the existing transaction. Root workspaces and isolated child workspaces use
their own replication scope; child projections include supplemental task entity
versions from the same canonical server log. A pending edit keeps its original
comparison version across pulls. An acknowledgement can advance a later edit
queued while the first was in flight. Conflicts preserve the local draft for
the existing recovery controls; deleting an unsent create cancels the pair.

Website and assignee fields are optional; clearing them emits explicit JSON
null. New/changed assignees must be linked active writers for the exact event.
Taking an unassigned task is an ordinary versioned assignment update: concurrent
claims do not silently overwrite each other. Assignment itself grants no access.
The native client advertises `event-todos-v2`. Servers return recoverable HTTP
426 `todos_client_upgrade_required` to older clients for readable scopes with
task state or tombstone history, including older v1 clients that would strip
website/assignment data. Upgrade-required errors retain saved changes.
Account deletion and scope removal purge the matching version records;
sign-out retains them under their account namespace with the offline data.

Due dates are date-only values; there is no notification scheduler or reminder
consent in this slice. See the server repository's
[implementation and release checks](../../../gatherory-web-app/docs/roadmaps/to-dos-reminders-roadmap/01-shared-event-to-dos.md).

## Decide and idea response bars

Decide records an individual preference without changing the idea's shared
approval status. Ideas, Decide, and idea details derive their response bars from
active hosts and collaborators with write access to the idea's own event.
Guests, invited contacts, and read-only planners do not count. Root and scoped
child projections use the same event roster; unrelated parent/sibling responses
are excluded. Gray represents eligible planners who have not answered, so one
response in a four-person planning circle fills one quarter of the bar.
Closed ideas (approved, passed, or archived) retain the bar's footprint but show
a solid system-blue status bar instead of unanswered input. Their visible
status and VoiceOver label identify the outcome; saved responses are unchanged.
Active ideas retain green/yellow/red/gray response segments.
Local decisions and undo update the bar immediately, while responses continue
to use the existing independent entity outbox and remote-merge flow.

Decide's response filter offers **Unanswered**, **My Maybes**, and **My Passes**,
independently of the event filter. Review queues use only the current viewer's
saved Maybe or Pass responses, not the idea's shared approval status or other
planners' responses. All queues apply the existing event, lifecycle, and
write-access rules; shared passed/archived/chosen ideas stay closed.
When a queue is empty, shortcuts open the other nonempty review queues.

Review is a finite, view-local pass: keeping Maybe or Pass retains the saved
response and advances to the next card. The review-again action or switching
filters restarts the pass; undo restores the previous response, selects its
matching queue, and makes the card available again. Filter
and review progress never enter the archive or outbox and reset on account
changes. Reviewing offline uses the same response mutation/coalescing path as
the original deck, without changing transaction or remote-merge boundaries.

## Manage and event join-request review

The planning tabs are **Home**, **Ideas**, **Decide**, and **Manage**. Manage
contains a dashboard for an explicitly selected event: Budget and Guests stack
on the left, Collaborators spans the right, and Notes sits below. Narrow widths
and accessibility text sizes use a single column. The compact event context
card opens a native selection menu only when multiple permitted events exist.
Its selection is view-local and never writes Home's selection or the outbox.
Destinations capture their event reference instead of reading a later Home
selection. Account/workspace changes reset Manage navigation.

The Guests header opens Guest List and sits above a proportional RSVP bar, with
counts available to VoiceOver rather than a visible legend. Collaborators shows
the pending count prominently and the newest pending request below it,
with approve/decline icon buttons for exact-event managers. Quick review uses the
existing online review store and refreshes collaboration after success; failures
retain the request and show the error. No planner count or voting controls appear.

Notes previews the latest visible event note and opens newest-first history.
Preview and history share event scoping and blocked-author filtering. Read-only
planners can read history without gaining send permission. Home's note shortcut
and the Notes history toolbar open a compose-only sheet, using the existing note
permission checks and durable save/outbox flow. Notes are in-app planning-team
updates, not guest broadcasts, emails, or push notifications.

Budget shows the selected event only. Root planners can additionally open the
explicit Workspace Budget overview; child-only projections cannot navigate to
parent/sibling data. Guest List shows event attendees and their RSVP independently
of planning role. Collaborators shows the planning circle and invitation tools.
No new RSVP, payment, or task workflows are introduced by this navigation change.

**Join Requests** now lives under **Manage → Collaborators**, not beside
**Who's Coming** in the invitation. Only hosts and collaborators with manage
permission on that exact event can review requests or manage invitations. Other
planners can read permitted event information without gaining those controls.
Child-only workspaces expose only their own event and no workspace sharing settings.

Requests remain transient, account-scoped state in `EventJoinRequestStore`.
Approval and decline use the existing online invitation API and refresh
collaboration after success; they do not enqueue offline mutations or change
archive, outbox, or sync transaction boundaries.

## Scoped location restore recovery

A missing location in a scoped event stays `nil` when its archive is restored.
Root workspaces retain their legacy venue/address fallback. Merely opening a
child invitation or switching accounts must not enqueue an event metadata edit.

Older builds could queue an empty-location update and receive
`EVENT_SCOPE_FORBIDDEN` for a contributor. A fresh authoritative scoped pull may
remove that rejected update only when its account, scope, entity, operation,
and failure code match, and every payload field except the empty location is
identical to the server projection. Unknown fields and genuine changes prevent
automatic cleanup. Other pending edits retain their payloads and mutation IDs.
This recovery also handles an already-applied projection envelope and commits
with the normal archive/receipt/cursor transaction; a page failure rolls it back.
No server receipt, membership, or workspace reset is required.

## Runtime flow

- `WorkspacePersistenceController` restores only the signed-in account's
  records, observes workspace edits, and writes a coalesced mutation.
- `WorkspaceCloudSyncController` bootstraps the account from the server and
  schedules foreground synchronization.
- `PostgresSyncTransport` sends the Keychain-backed Better Auth bearer token
  to `/api/sync/bootstrap`, `/api/sync/push`, and `/api/sync/pull`.
- `SwiftDataSyncStore` leases only the active account's outbox entries and
  records acknowledgement, retry, or attention state.
- `OfflineSyncCoordinator` drains ready mutations in server-sized batches,
  then applies cursor-based server changes.
- The web app stores the current compatibility snapshot, independently
  versioned child records, idempotency receipts, and an ordered change log in
  PostgreSQL.
- Pull-to-refresh is the explicit collaboration control. Opening/foregrounding
  the app and saving a local edit also synchronize automatically.

Events, ideas, participants, expenses, registry items, notes, and moments each
have an independent synchronization identity. This lets collaborators change
unrelated records without replacing one another's work. Same-record edits use
last-writer-wins for now; version fields preserve the path to a later review UI
without requiring sockets or real-time presence. Accepted native mutations are
transactionally projected into the canonical PostgreSQL workspace, event,
idea, participant, expense, registry, note, and moment tables. The compatibility
snapshot remains available while the web companion transitions to those
normalized records.

## Shared albums and event idea names

The invitation album previews up to four photos as a masonry collage with a
compact gallery/upload footer. Every photo opens directly into the full-screen
viewer. The album uses two columns on iPhone; iPad adapts from two to six columns
to match the available window width. Cards retain portrait/landscape proportions
within readable limits and show the uploader's avatar and tail-truncated name.
Avatars resolve by authenticated user ID within the event's participants, with
initials for legacy or departed contributors. Full names remain available to
VoiceOver. Lazy columns and display-sized ImageIO thumbnails limit image memory;
the full viewer shows the uncropped image with paging and pinch/double-tap zoom.

Select mode offers individual selection, Select All/Deselect All, a selection
count, and Save to Photos. Selection is reconciled against currently visible
photo IDs before export. Saving requests PhotoKit **add-only** access only after
an explicit save and writes the original stored bytes in one batch transaction.
Invalid photos or denied access retain the selection; permission denial offers
Settings recovery. The viewer also supports saving one photo. Library browsing,
editing, filters, and photo organization remain outside this event experience.

Hide/report controls remain available in the viewer. Guests can browse and save
accessible event photos; this does not add guest upload or planning permissions.
Icon controls retain 44-point touch targets and localized accessibility labels.
Large text adapts the action/footer layout, reduced transparency removes photo
blur, and VoiceOver exposes selection state, photo navigation, and zoom actions.

Active upload-capable planners can remove their own photo after confirmation.
The local operation checks the stored photo's owner and exact event, including
legacy main-event photos with no event ID. Archive removal and the account-scoped
moment tombstone use the existing persistence/outbox transaction. Server checks
use the canonical gallery placement and uploader; a trusted first native create
covers an upload still awaiting media registration. Root-workspace and isolated
child scopes keep their existing boundaries, receipt replay and management grants.

Event-idea editors now accept an explicit name rather than always regenerating
the category title. Existing `updateIdea` handling updates the approved linked
Home event in place and queues the ordinary idea/event mutations; no IDs, dates,
approval states or sync formats are replaced by a rename.

## Local development

### Wedding template installation

Search opens a workspace-style template preview before setup, with personal
inclusion choices staged in memory until an explicit Save Draft.
Installed templates remain editable in the ordinary preview: event/idea editors,
Decide choices and Save Draft remain available, but inline Install stays hidden.
Only the library card's explicit Create Workspace action starts another setup.
Opening a saved source is read-only with respect to storage, not editing controls:
the first explicit save forks a fresh account-owned draft/request, preserving all
source customizations and decisions without reusing its installation request or
confirmed dates. Discard restores the source. Later opens prefer the saved draft.
Saving also updates only that library entry's reusable local source, preserving
receipt/scope identity; edits survive consumption of the setup draft by a later
installation. Existing workspace archives and outbox payloads are untouched.
These are personal local blueprint edits, not publication to the original author
or propagation into already-created workspaces. Pending installations and draft
concurrency checks still block unsafe writes.
Tapping an installed card opens that blueprint, never its created workspace.
The account-bound, revision-checked source snapshot supplies the installed
blueprint preview without writing a draft or changing workspace selection.
Older entries resolve their exact published revision when a local source is absent.
Library cards offer long-press Create Workspace and Delete Blueprint actions.
Deleting an in-progress draft uses its exact account/catalog/link/request identity;
pending installations block deletion. Deleting an installed card records an
account-scoped, device-local visibility tombstone, leaving its receipt, workspace,
and outbox intact. Refreshes apply these tombstones even to responses already in
flight. Installation detection still reads the original receipt cache.
New installation history also retains the account's source draft for offline
reuse, including customizations and unlisted-link identity. Server refreshes
preserve this local source. Creating another workspace uses a new request ID
and requires date confirmation again; it never overwrites another active draft.
Older receipts without a source snapshot use the published catalog setup path.
Create Workspace routes directly to the existing confirmation-only installer,
not to the blueprint editor. It confirms missing dates, installs through the
ordinary durable intent/import flow and opens the new collaborative workspace
in Home. Old receipts resolve their exact published catalog revision first;
unavailable revisions fail rather than silently substituting another blueprint.
Draft tiles omit the visible Resume Setup line (the accessibility hint remains).
Date review keeps every selected activity visible after confirmation. Tapping a
row opens the manual editor without accepting a suggestion; native trailing swipe
actions offer Edit and explicit Confirm Date (full-swipe execution is disabled).
The manual editor is a native calendar/time popup rather than a pushed screen;
main-event and activity dates share this editor, anchored to their own visible
date row rather than the entire form. The calendar scrolls within bounded popup
height while Cancel and Confirm Date remain reachable, including in compact
vertical layouts. There is no forced intrinsic height that can place controls
outside the visible screen. Opening or dismissing either editor does not mutate
the saved event date; only confirmation applies the temporary choice.
Cancel or outside dismissal does not confirm changes. Explicit Confirm Date
updates the same draft instant and preserves the existing event zone.
A context menu provides the same alternatives. Confirmed rows display a status
checkmark and remain editable. An explicit Create Workspace button replaces
automatic installation on the final confirmation, so people can review or revise
every date before creation. Editing the main date requires reconfirming it.
Routine setup hides the time-zone picker, IANA
identifier, GMT offset and repeated scheduling explanation. New date contexts
still use the device zone; restored drafts retain their saved event zone and
confirmed instants. Only ambiguous DST candidates show offsets so repeated wall
times remain distinguishable. This is presentation-only; explicit confirmations,
suggestion tokens and offline draft/installation boundaries are unchanged.
Home's editing menu no longer offers Add Idea; adding ideas belongs to Ideas.
Query results, recents and category results now use artwork-led masonry tiles
through the same `MasonryLayout` as workspace ideas (two columns, one at
accessibility text sizes, with RTL support). Search and category tiles open the
preview using the ordinary full-screen workspace flow, not a tile zoom.
Category results own their preview destination at their own navigation level;
their tiles never drive the Search screen's preview binding.
Transient `BlueprintDiscoveryNavigation` snapshots retain the active source mode
and entry order while a preview is presented: losing search focus cannot swap
the source grid for categories, and access recording cannot reorder it mid-presentation.
Returning restores the query/focus before releasing a Search snapshot; category
navigation does not activate Search. This state is not persisted or synced and
is recreated with the account-bound Explore view.
Tile and main-preview artwork share the same browse-category symbol/palette;
this does not copy source-event photos or require identical bitmap images.
The preview now owns Home, Ideas and Decide through the same `WorkspaceTabShell`
as live workspaces. Explore/category tiles present this session full-screen,
replacing rather than nesting the library tabs. Shared links use the same session.
The exit button uses the workspace library icon rather than an X.
Home reuses `WorkspaceEventHero`, vertical event paging and `EventContextRail`;
rail entries use authored identities and relative timing, never invented dates.
The preview's scrub bubble is a single-line, intrinsic-width event-name capsule
(long names truncate). Scheduling explanations stay in the detail view and the
rail's VoiceOver value, not the visual bubble. Live workspace date bubbles keep
their existing presentation.
Scrubbing the preview rail moves cards immediately, not just on release. Actual
card frames determine the current selection during normal scrolling; requested
scroll targets are tracked separately so observing a card cannot initiate a
feedback loop. Selection haptics follow event changes, not every drag update.
Interrupted rail animations return control to direct scrolling. Reduce Motion
disables programmatic scroll animation; the rail remains adjustable with VoiceOver.
Ideas reuses
`IdeaCollectionPresentation` and masonry; Decide reuses
`DecisionCardPresentation`. Event details share `EventReadingHero` and the
invitation's section surface. These are shared presentation components, not a
second live `PlanningWorkspace` with controls merely hidden.

Ideas and Decide can filter all authored ideas or one event. Ideas defaults to
All on each tab entry, independently of Home and Decide context. Home selection
is separate from Decide's explicit event filter: scrolling the Home rail or
opening a Home event never silently narrows the decision queue. Decide starts
at All; choosing its own filter still deliberately limits the queue.
Blueprint Home always starts with the main event and projects only Love ideas;
a child event appears when at least one of its targeted ideas is loved. Pass,
Maybe and unanswered ideas do not reveal a child. Reconsidering the final Love
removes that child again; the rail falls back to the main event if necessary.
Ideas and Decide still read the complete authored/customized content, including
hidden Home activities. Preview Save Draft and Install use that same projection:
only loved ideas and their targeted child events are selected, with the main
event always retained. New/custom ideas are not implicitly selected. Existing
draft defaults are normalized when entering preview installation; confirmed
dates, authored content, account ownership and request identity are preserved.
Pending installation intents retain their frozen payload/idempotency key and
are never rebuilt from new preview choices. Main/child identities cannot
collide even if a child key is `main`. Scoped guidance/ideas preserve authored
order and never pull in sibling content. Relative schedule proposals remain
suggestions, not confirmed dates. Decide shares the live swipe interaction
and feedback: right/Love includes an idea, left/Pass excludes it, and
up/Maybe defers without inclusion. Unanswered ideas are excluded from the plan.
Review filters and Review All Ideas support reconsideration.
The preview deck has no separate Pass/Maybe/Love button row: swipes are primary,
with named accessibility actions for those choices and opening details.
Responses live in `BlueprintPreviewSession`; navigating and swiping do not write
files, cast live votes, create installation intents or touch the outbox.
Save Draft explicitly writes the account/link-scoped setup with an optional
`previewDecisions` field. Existing draft identity, pinned publication, customized
content, selected events and confirmed dates are preserved. Pending installation
or a replaced draft blocks the save. Old drafts decode without this metadata,
which is never sent as a vote or included in the install API body.
Exit and Review & Install offer save/discard/cancel when choices are unsaved.
No Manage, notes,
invitations, approvals, uploads, team responses or live collaboration controls
are exposed in this preview.
Opening an idea uses the same `IdeaDetailScreen`, full-height opening layout,
scroll-driven artwork treatment, material summary and `IdeaCategoryDetailContent`
renderer as workspace idea details. There are no preview-specific layout or
blur flags in the idea screen. Event cards and event details resolve the same
artwork descriptor, including authored snake_case child categories. Event detail
starts clear and adds scroll-driven blur instead of an unconditional full blur;
it does not substitute lower-resolution source photos.
The shared card renderer reads display content and optional typed configuration;
only a real live-idea binding enables external actions, playlist controls, picker
callbacks or live event tools. A surrounding workspace environment alone cannot
activate those controls. Current portable templates contain title/category/notes
but not typed category facts or source media, so their supported content follows
the same renderer's notes fallback without manufacturing settings or currency.
The live screen still supplies its existing response controls, metadata, refresh action
and media; catalog previews supply authored title/category/notes without fake
votes, authors, a mutable workspace or live-event actions. No source media or
installation dates are manufactured for browsing.
Home's compact actions menu opens focused name, date/time, idea and sub-event
editors. Ideas groups the library exit first and scope menu on the leading side;
Add Idea and Install are trailing icons. Dirty drafts can still be saved
from the scope menu. Install always asks for confirmation; Cancel leaves the
editor untouched, while continuing saves the current choices before entering a
date-only completion flow. The setup editor and plan-review form are not shown
again. It asks only for an unconfirmed main date and missing dates of selected
children, then automatically validates and installs through the existing
coordinator. Confirmed instants, excluded children, customizations, request IDs
and source/link pins remain unchanged. The optional local `mainDateConfirmed`
field keeps older drafts readable; absent confirmation is never inferred from
a suggested/default date. New preview drafts include their displayed children;
saved selections (including an empty selection) are retained. It never installs merely on the first
toolbar tap or silently discards edits. Idea
tiles/details can open their personal content editor. Their shared workspace bars
show personal preview choices (green Love, yellow Maybe, red Pass, gray unanswered),
not fabricated team votes. These update in memory before an explicit save. Decide has no
exit or Customize button: its heading follows the current idea's
target on the card. Its toolbar uses an icon-only event selector and the response
inbox (including Save Draft), with Account on the trailing side. Live and preview
cards share a target-event heading instead of persistent swipe-direction pills;
swipe feedback appears above the softly blurred incoming card on the edge exposed by
the drag, rather than in the outgoing card's center. The incoming card is
non-interactive and hidden from accessibility until it becomes current; lookahead
does not record a decision. Cards keep stable identities in a two-card stack:
a completed choice saves immediately while the incoming card animates from an
8-point native blur and 97.5% scale to clear/full size, and the outgoing card
exits in the chosen direction. No delayed animation callback writes decisions.
Dragging follows the finger without an implicit spring; only an unconfirmed
drag animates back. Confirmed exits use a 0.22-second ease-out. A single
identity-keyed rendering lane contains the active/next pair plus at most one
departing card; the card being dragged is never replaced by a separate flight
view. A shared motion modifier retargets that mounted card synchronously when
its command changes, without a task/yield handoff. Queue cards have identity-only
insertion/removal: SwiftUI does not retain a growing trail of removed cards.
Rapid decisions replace the one departure command. Immediate Undo supplies a
fresh return token and the recorded direction while preserving the mounted
card's animation state. If Undo arrives before the first exit update, its
initial position is the drag origin, not the far edge. Completed exits return
from their recorded edge. Stale completion callbacks are ignored; they can only
clear their matching visual token, never write responses. Only the card's artwork
is masked to its rounded shape; the deck does not clip moving cards or shadows
at its padded layout bounds. Native navigation/tab chrome remains above content.
Departures finish fully outside the deck's bounds. Live Undo
keeps the existing response/outbox operation, then uses a presentation-only
direction history to return the restored card from its former exit edge. The
stack stays mounted when empty so the final card can animate out and back in.
Account changes, filter/review resets, and leaving the screen clear transient
flights without touching saved responses or the outbox. An event handler for a
card that is no longer current cannot record a duplicate decision.
Reduce Motion disables the depth movement and animated handoff; Reduce
Transparency disables the added blur. The final card uses a neutral
backdrop rather than repeating an idea. Accessible Pass/Maybe/Love actions remain
available. The live
queue retains Undo and its existing account/filter behavior.
Search and shared links use the same presentation, with adaptive content
surfaces and accessibility fallbacks.
`BlueprintPreviewContent` reads only the authorized catalog document and groups
ideas/guidance under their main event or matching child. Activity and idea
details show authored content without manufacturing a `PlanningWorkspace`,
RSVPs, absolute dates, or source-event media. Merely browsing never saves a
setup draft or installation intent. Focused editor Save explicitly persists the
personal draft (including staged choices); Cancel does not apply editor values.
Failure retains staged changes with a retryable save action. Editors are owner/
generation checked and blocked while an installation is pending. They never
manufacture a live workspace or publish to the source template. Review & Install
opens the existing setup/review flow, retaining account isolation, confirmed
dates and recovery behavior. On a
successful catalog installation the setup sheet closes, then the preview
closes, then the root presents the installed workspace. A transient root
presentation gate prevents a competing workspace cover during that handoff;
it does not clear the selected workspace while gated and resets on account
change. This is presentation state, not a new persistence transaction.
Shared-link entry now resolves its exact token-pinned publication and uses the
same preview before setup. It never falls back to a public catalog grant or
records the bearer token in Search history. A saved account/link-scoped setup
may supply the preview on network loss; server denials, invalid responses and
TLS failures do not use that fallback. Reading the saved setup does not change
its UUID, selections or confirmed dates. Pending installation recovery remains
available even while resolving or after a link is revoked, through the existing
account-bound receipt path. Closing setup returns to the preview; successful
installation closes the shared-link handoff. Draft recovery in Blueprints opens
the saved workspace-style preview, with Review & Install leading to setup. Pending
installation recovery retains its direct setup entry. No archive, outbox, receipt
or transaction format changed.

Focused sheets support adding/editing portable ideas and sub-events with shared
workspace editor fields and category/purpose controls. The main date/time action
uses the live `EventDateTimeEditorView`, limited to a timed start because portable
installs do not yet carry end dates or all-day semantics. Existing live callers
retain their full schedule controls. Main date edits never reschedule confirmed
child dates; added children still require explicit confirmation during review.
`BlueprintCustomization`
stores versioned upserts separately from the immutable catalog entry in the
existing account/link-scoped draft. Old drafts decode without the optional
overlay. New entries receive stable local source keys, not live event IDs.
New sub-events require date confirmation; content edits keep confirmed dates.
Saved editor callbacks are account/generation checked and disabled once an
installation attempt begins. Cancel never changes the saved draft.

Review/install carries the overlay in the exact request body. The server checks
the source pin and permissions before validating/expanding the effective plan.
The existing intent/receipt/bootstrap path owns installation; there are no
temporary live workspaces, pre-install outbox edits or new import transactions.
An older server rejects customization rather than silently installing the
unchanged source, so deploy the matching server before the native release.

Root navigation now includes a **Blueprints** library beside Workspaces and
Explore. In Progress reads the existing account/link-scoped setup drafts and
pending installation intents, with receipt recovery taking priority. Used
Templates reads completed personal installation metadata from the authenticated
`/api/blueprints/library` endpoint and a separate `BlueprintLibraryCache` file.
The endpoint requires current host access to each installed root and returns
at most 200 recent receipts, without source documents, people or bearer tokens.
It does not require the original sharing link to remain active.
The library projects receipts into one card per catalog key and revision,
retaining the original receipt identity and local editable source. Creating
another workspace (including changing its suggested dates) adds a receipt, not
another blueprint card. All receipts remain cached for recovery; no workspace
or outbox is deleted by this display grouping.
Both draft and used-template sections use the shared masonry collage, with one
column at accessibility text sizes. Opening uses the standard workspace flow.
The tab replaces its redundant Blueprints title and category filter with a native
Installed Templates / In Progress title dropdown. The account's most recently
visited collection is restored if it has content, otherwise a collection with
content is selected. Pending recovery counts as in-progress content. A manual
empty-collection selection is respected for the current visit. Only the selected
content collection is rendered, without duplicate
section headings or an Explore shortcut. Pending-install recovery remains visible
in either collection. Selection is account-local presentation state and does not
rewrite drafts/history or fetch private sources.
An empty collection retains its explanatory message and offers a button to
switch to the other collection. This uses the same manual-selection preference
as the title menu, without creating a draft or installation.
Empty states use a native symbol/heading, concise collection-specific guidance
and a compact capsule action. They center within the available scroll viewport
only when no recovery or error needs attention; longer accessibility text can
still grow and scroll. No Explore shortcut or placeholder template is inserted.

Explore supports eighteen localized browse categories backed by seventeen
production starters. Only categories populated by the authorized server catalog
are shown, so older servers do not expose empty new destinations. Category keys
remain discovery metadata, not live event types or permissions; unknown future
keys retain the Other Events fallback. The generated expanded catalog fixture
is shared with server tests. Existing independent installation, account-scoped
history and offline sync are unchanged. Preview Ideas now has Add only on its
trailing toolbar; Install remains in the Home actions menu.

Successful import records a history row after draft/intent cleanup; history
cache failures cannot fail the installation. A later server read backfills older
uses and replaces cached history. The tab loads local data first and keeps it
on network failure; stale/cancelled/account-invalidated responses cannot replace
the visible account's cache. Used rows open their independent local workspace,
not the source event. Missing local workspaces remain a history-only entry.
Resumed shared-link drafts close their local sheet without changing the incoming
shared-link router; the root presentation gate lets setup close before opening
the installed workspace. None of this introduces workspace mutations or changes
the bootstrap transaction. A template version, a setup draft and an installed
workspace retain separate identities.

The first template slice uses authenticated catalog, preview, install and receipt
status endpoints. `BlueprintInstallationCoordinator` saves the exact reviewed
request and UUID atomically in an account-scoped intent file before submission.
Retry recovers that same receipt; it does not create a fresh event request. After
success, import uses the existing `applyBootstrap` transaction and server IDs,
then opens the installed workspace and removes the intent. Account activation
generations prevent stale requests from importing after A→B→A switching.

Date-aware setup also calls a read-only schedule endpoint with the catalog pin,
main instant and named event zone. Temporal runs on the server, not the device.
Suggestions stay in `BlueprintScheduleDraft` until an explicit confirmation;
refreshes preserve confirmed/edited instants and reject stale response tokens.
Only confirmed dates enter the reviewed installation body. Suggestion failures
leave manual entry available and never create install intents or outbox entries.
The manual picker starts with the existing confirmed edit, otherwise the latest
single, unambiguous suggestion, otherwise the main event date. Opening/cancelling
does not confirm anything, and an asynchronous refresh cannot replace the open
picker's draft. Ambiguous clock-change occurrences still require an explicit
choice; the picker does not silently pick the first candidate.
Unfinished setup now saves in a separate versioned `BlueprintSetupDraftStore`
under Application Support, keyed by canonical account ID and catalog key. It
retains the exact source revision/hash and definition, request UUID, untrimmed
event name, main instant, time zone, selections (including deliberately empty
sets), and only explicitly confirmed child dates. Edits save atomically; a write
failure is visible and blocks review until retry succeeds. Close/background save
the current setup, while cancellation of an unconfirmed manual picker discards
only that picker's temporary value.

The Blueprints **In Progress** section works without a live catalog. Search
keeps its discovery flow without a resume banner. Restoring uses the
saved source rather than merging a newer publication into edited selections;
suggestions refresh separately and never overwrite confirmations. Preview and
installation still require connectivity. Saved drafts privately copy their
portable snapshot under the recipient's ownership before server suggestions,
preview or installation, rather than rechecking the original author's source.
Author edits, deletion and entry-link revocation therefore cannot invalidate a
saved draft. Fresh incoming links without a saved snapshot still require access.
**Start over** requires confirmation, discards only that account/template draft,
then fetches the latest available source. These drafts are device-local and
survive sign-out for the same account; they are not cross-device backup.

Pending installation intents take priority over setup drafts. The reviewed
request keeps the draft's UUID; after canonical bootstrap import, the coordinator
removes only a draft with that same request UUID, then removes the install
intent. A failed response/import/cleanup retains recovery through the existing
receipt. Account changes reset view state and reject stale callbacks. No draft
write creates a workspace or outbox mutation, and existing bootstrap/outbox/sync
transaction boundaries remain unchanged. See web roadmaps `08-date-aware-setup.md`
and `12-resumable-setup.md` for behavior and test coverage.

Independent draft copies retain their original local account/catalog/link file
identity and all selections, overlays and confirmed instants. Optional fields
hold a distinct durable copy UUID and private server pin. Copy retries reuse
the same full base snapshot, excluding installation dates and personal overlays;
late callbacks preserve newer same-request edits and reject account switches,
replaced drafts or a newly frozen install. Legacy drafts migrate lazily. The
private copy stays unlisted and hidden from author-library cards. Import cleanup
matches the installation UUID plus private pin back to the original draft file;
it never rewrites an existing installation intent or produces workspace outbox
mutations. Shared-link reopening prefers an already-saved account/link snapshot.

Blueprint setup captures the device clock and system time zone together when
opened. It does not request GPS access just to determine local time. The explicit
Use Device Time Zone action can restore the current system zone after a manual
override, without changing the main or confirmed child instants. System-zone
changes never silently overwrite an open draft. Time-zone picker options are
cached and include the selected system alias even if it is absent from the known
identifier list. Coordinate access remains an explicit, permission-gated action
in the event location editor, with manual search available when denied.

Long-pressing a card in **Workspaces → Share Template** opens native content
selection, name entry, review and **Create & Share**. The source is the card's
root event (the accessible child for a scoped card), not its last selected event.
The action is also available to assistive technologies and is hidden without
event-management permission. All authorized supported content and idea notes
start selected; authors can deselect them before review. Server review shows
the exact reusable content. Source management and ownership are checked
independently. Save To is removed: on creation the server resolves/provisions the
actor's personal template owner without changing the active workspace or source
membership. Review explicitly discloses publication to Search. New requests send
`discoverable: true`, with no destination organization ID; source reads still make
no writes. Existing private/unlisted templates remain private.

Capture/save and publication share a server transaction. Native creation retains
the exact reviewed request UUID/body in sheet memory after an uncertain response;
retry recovers the same first publication rather than creating another template.
Source conflicts require a fresh review. Linking is a separate step; a failed
link response leaves the template created and requires explicit successful link
refresh before replacement. Ordinary event edits, outbox writes, installation
intents and bootstrap transactions remain unchanged. Capture observes the server
snapshot; unsynced local edits arrive through normal sync, without an implicit
flush. Capture state clears on dismissal/account changes and cannot continue
through late callbacks. Persistent capture drafts are outside this slice.

The card's **Manage Links** sheet uses authenticated, source-event-scoped
requests to list owned captured templates and create/list/revoke published links.
Owning an installed event does not grant control over the original template.
Link controls remain available after an event becomes read-only while the
host/manager grant remains, without re-enabling editing of that source event.
Empty/draft states offer native creation. Native screens do not offer or refer
to a web editor until that experience is explicitly enabled.

Home's main-event long press and the workspace-card menu offer **Save Blueprint**.
This is a private, explicit server capture, using the existing selection/review
and permission checks without listing it in search or creating a share link.
Create & Share also registers its owned template in the account-scoped Blueprints
library. Owned records are separate from workspace installation receipts; receipt
cards for the same owned catalog key are suppressed, not deleted.

The personal library caches its portable content for offline browsing. Publishing,
saving owned author content, and withdrawing a publication are explicit online
operations outside the workspace outbox. An acknowledged author save creates a
new immutable publication and advances search only if already listed; private
templates stay private. Date confirmations are local setup values, not portable
publication content. Deleting an owned library record retires/unlists it and
revokes its links before removing it locally. Deleting a non-owned copied record
remains a local library action. Neither operation deletes existing workspaces.
Other people's copies retain pinned content rather than following author edits.
Owners can list or withdraw a published version through Manage Links. Visibility
changes update only after acknowledgment and use the same account/permission
guards. Search withdrawal and link revocation are independent; neither changes
installed copies.
Publication is explicit; event edits never update installed copies or publish
automatically. Playlist capture remains unsupported. These operations are
online-only and never become pending sync mutations.
Account changes invalidate in-flight responses and clear transient generated
URLs. Failed revocations remain unconfirmed; uncertain creation requires an
explicit successful refresh before another creation attempt.

Birthday Party and Thanksgiving now use that same catalog/setup/install path.
`CuratedBlueprintTests` imports their server-produced archives and verifies
hierarchy, host controls, confirmed dates, no-op saves, and offline edit/relaunch
behavior. Their content does not require new native mutation or archive types;
see web roadmap `09-curated-starters.md`. Catalog availability requires running
the explicit server seed, not resetting the native or development database.

Guides and experience configuration are optional fields in archive/sync v1.
They are read-only in this slice and delivered with authoritative workspace
snapshots; they are not new outbox mutation types. Ordinary event/idea edits
retain the existing outbox behavior. Child-only projections contain only the
child's guides; invitations display only public guidance for the exact event.

Native requests advertise `X-Gatherory-Capabilities: blueprint-guides-v1`.
Unsupported clients receive HTTP 426 (`blueprint_client_upgrade_required`)
before accepting installed-scope writes or advancing cursors. An upgrade error
must retain pending edits for retry. The web blueprint roadmap's
`06-wedding-installation-proof.md` records deployment requirements and evidence;
the shared fixture lives in `GatheroryTests/Fixtures/wedding-install-native.v1.json`.

### API connection

Debug defaults to production-like account behavior and
`https://dev.gatherory.com`. Start `gatherory-web-app` with `pnpm dev`, expose
port 3003 through the named Cloudflare tunnel for that hostname, then run the
iOS app. The Simulator and physical devices use the same Better Auth origin,
so the normal scheme does not need launch arguments.

For a one-off endpoint test, `-AuthenticationBaseURL` remains available as a
temporary scheme override:

```text
-AuthenticationBaseURL
https://temporary-development-origin.example
```

If the stable development hostname changes, update `AUTH_BASE_URL` in
`Config/Debug.xcconfig`, update the web app's `BETTER_AUTH_URL`, and rebuild the
iOS app. Production changes belong in `Config/Release.xcconfig` and the
production authentication provider configuration.

The local PostgreSQL database must have the generated Drizzle migrations
applied with `pnpm db:migrate`.

Release verification and the physical-device persistence checklist live in
[`app-store-release.md`](app-store-release.md).

## Still to connect before full collaboration release

- Move cover and gallery bytes out of the JSON archive and use the existing
  `PendingMediaTransfer` records with presigned S3 uploads.
- Add background refresh and background media uploads after foreground and
  pull-to-refresh behavior has been exercised on device.
- Add conflict-resolution UI for mutations marked `requiresAttention`.
- Exercise organization membership and event-scoped participant authorization
  with two real production accounts before advertising collaboration broadly.
- Keep workspace-wide sync membership limited to explicit planning roles;
  a child-event planning invitation resolves to its own scoped workspace,
  while guest invitations remain guest-only.
- Expose a small sync-status surface for retryable and attention states.
