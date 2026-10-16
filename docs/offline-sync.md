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
contains Budget, a combined Guests/Collaborators card, and Notes for an explicitly selected event.
Its selection is view-local and never writes Home's selection or the outbox.
Destinations capture their event reference instead of reading a later Home
selection. Account/workspace changes reset Manage navigation.

The Guests header opens Guest List and sits above a proportional RSVP bar, with
counts available to VoiceOver rather than a visible legend. Collaborators shows
the pending count beside its chevron and the newest pending request below it,
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

Search opens a read-only, invitation-style template preview before setup.
Query results, recents and category results now use artwork-led masonry tiles
through the same `MasonryLayout` as workspace ideas (two columns, one at
accessibility text sizes, with RTL support). Each whole tile is a native zoom
source, keyed by catalog key/revision **and** its results/recent/category surface
inside a screen-owned namespace. Reduce Motion retains standard navigation.
Category results own a separate namespace and preview destination at their own
navigation level; their tiles never drive the Search screen's preview binding.
Transient `BlueprintDiscoveryNavigation` snapshots retain the active source mode
and entry order while a preview is presented: losing search focus cannot swap
the source grid for categories, and access recording cannot reorder it mid-zoom.
Returning restores the query/focus before releasing a Search snapshot; category
navigation does not activate Search. This state is not persisted or synced and
is recreated with the account-bound Explore view. Shared-link entry is unchanged.
Tile and main-preview artwork share the same browse-category symbol/palette;
this does not copy source-event photos or require identical bitmap images.
Its artwork fills the background, while an opening `IdeaSummaryContent` card
uses the idea detail's category label, left-aligned title, description, material
and spacing. Suggested relative timing and saved-preview context sit inside the
same card rather than floating over artwork. The scroll content respects the
navigation safe area, with priorities and the first content cards directly below.
The background starts fully Glurred, including the top edge, and no longer
depends on scrolling. Reduce Motion keeps this static treatment; Reduce
Transparency retains the unblurred artwork and opaque card fallback.
Native iOS 26+ scroll-edge
effects remain beneath navigation, without an extra black dimmer or painted
status-band gradient. The artwork extends beneath the floating tab bar.
Summary and scoped planning guidance precede the content pages. Events use
horizontal pages of four in a 2×2 grid (two single-column entries at accessibility
sizes); ideas use horizontally swipeable columns of up to three compact rows.
The carousel viewports span the screen; scroll-content margins align their
resting cards with the headings without clipping swipes to an inset container.
There is no solid light/dark content-section backing: the Glur artwork remains
visible throughout. Individual cards reuse the idea detail's adaptive material
surface (including its Reduce Transparency fallback), with semantic card text
independent of the white artwork headings.
Grouping preserves authored order, full detail content and audience boundaries.
Main and sub-event previews share `BlueprintEventPreview`; the read-only event
projection gives only the main event children. A sub-event shows only its own
guidance, ideas and relative schedule proposal, never a parent/sibling carousel.
Opening an idea uses the same `IdeaDetailScreen`, full-height opening layout,
scroll-driven artwork treatment, material summary and `IdeaCategoryDetailContent`
renderer as workspace idea details. There are no preview-specific layout or
blur flags in the idea screen. Full-area static Glur belongs to the surrounding
main/sub-event template previews, not a special idea-detail presentation.
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
Use Template is a compact native trailing
toolbar action, not a full-width bottom bar. Search and shared links use this
same presentation, with adaptive content surfaces and accessibility fallbacks.
`BlueprintPreviewContent` reads only the authorized catalog document and groups
ideas/guidance under their main event or matching child. Activity and idea
details show authored content without manufacturing a `PlanningWorkspace`,
RSVPs, absolute dates, or source-event media. Merely browsing never saves a
setup draft or installation intent. Use Template opens the existing setup
sheet, retaining its account isolation, confirmed dates and recovery behavior.
Shared-link entry now resolves its exact token-pinned publication and uses the
same preview before setup. It never falls back to a public catalog grant or
records the bearer token in Search history. A saved account/link-scoped setup
may supply the preview on network loss; server denials, invalid responses and
TLS failures do not use that fallback. Reading the saved setup does not change
its UUID, selections or confirmed dates. Pending installation recovery remains
available even while resolving or after a link is revoked, through the existing
account-bound receipt path. Closing setup returns to the preview; successful
installation closes the shared-link handoff. Workspaces draft recovery retains
its direct setup entry. No archive, outbox, receipt or transaction format changed.

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

The Workspaces **+ → Resume Setup** menu works without a live catalog. Search
keeps its discovery flow without a resume banner. Restoring uses the
saved source rather than merging a newer publication into edited selections;
suggestions refresh separately and never overwrite confirmations. Preview and
installation still require connectivity and authoritative server access checks.
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
Empty/draft states offer native creation; advanced web editing remains optional.
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
