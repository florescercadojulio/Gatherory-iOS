# Blueprint preview and event creation feedback

## Current flow — October 23

Public preview is now one read-only scroll containing the main event, included
events and ideas. Like/Save remain references; explicit Use creates or resumes a
working plan and opens date confirmation. New plans include authored content by
default; saved plans retain prior choices. Yours uses the same full-screen
presentation as Liked with one scrolling overview and masonry ideas. Tap event
or idea content directly to edit in a native sheet; Use and Add use native
bottom-toolbar controls. There is no Edit mode or Blueprint Decide; Decide belongs to created
events/workspaces. Cards and opened previews use matching customized artwork.
Setup uses a full-height native grouped form inspired by onboarding, with an
editable event name, date rows opening the shared Cancel/Done date editor, and
a native bottom action. Onboarding remains unchanged. Creation preserves saved
selections without legacy Decide projection; it does not repeat content editors. Canonical creation, retry and source-retention boundaries
remain. Current acceptance uses standard Light/Dark text sizes; dedicated
super-large tests were removed at the user's request. See
[roadmap 15](../../../gatherory-web-app/docs/roadmaps/blueprint-ranking-roadmap/15-single-preview-and-event-creation.md)
and [current verification](testing-verification.md#use-to-created-event-handoff--october-23-2026).
The creation handoff now has native transport/import/UI and disposable-database
content/replay coverage. The event opens after import and exact-request cleanup;
failed cleanup or a missing bootstrap scope remains recoverable through the same
receipt. Deployed-account, actual media-transfer and physical-device acceptance
remain open.
The dated notes below record earlier iterations.

October 21, 2026. Native UI changes; no server rollout or installation-contract
change is implied.

## Flow

- Events → plus offers Explore Blueprints first, which selects the existing
  Explore tab. Start from Scratch opens the blank event form. The empty Events
  screen offers the same two choices. Routing preserves Explore's existing
  account/guest gates and never creates an event just by selecting the tab.
- Search opens the existing editable blueprint preview. Saving does not create
  an event or publish the blueprint to Search.
- A successful save must give visible confirmation instead of only removing the
  dirty-state checkmark. A pending personal save must display progress. Failures
  keep the current edits available and offer an explicit retry.
- Use Blueprint is a visible action on the preview's Home tab. It opens date
  confirmation; Create Event remains the explicit creation action.
- Date suggestions have visible Confirm date actions alongside manual editing.
  Swipe/context-menu confirmation remains available.
- Disabled creation explains whether the main date or remaining event dates
  still need confirmation. Creation progress stays visible while both preparing
  and installing; recovery actions appear when the operation fails.
- Editor forms use native grouped backgrounds in light and dark appearances.
- Use Blueprint has a concise sheet title, an event-name section and consistent
  date rows with confirmation marks. Suggested-date errors live in supporting
  footer text. Create Event and Continue sit in a native bottom safe-area bar,
  outside the grouped form; review uses the same standalone action treatment.
  Never wrap a primary creation button in another form card. The preview's
  confirmation sheet starts at medium height, expands to large, and uses large
  height for accessibility text sizes.
- `BlueprintSetupPresentation.swift` includes interactive light/dark previews of
  the actual row and action components, without sign-in or server writes.

## Boundaries

Drafts, personal-template saves and installation recovery retain their existing
exact-account ownership, generation checks and frozen request identities.
Personal-template server saves remain distinct from local setup drafts. A failed
server save retains its staged local request identity for retry; a successful
server response retains the acknowledged revision even if the local cache write
fails. No
category or portable blueprint schema is expanded. Music remains outside the
portable blueprint customization contract.

An installation error can retry the same prepared request. Changing selections
or dates still invalidates review through the existing flow; no automatic
installation, publication or invitation is introduced.

## Acceptance

The integrated Xcode 27.1 / iOS 27.1 SDK simulator build passed. The subsequent
sheet presentation pass was rendered in Xcode Canvas in light and dark mode;
the creation action is visually separate from form groups. The Ready preview
was also rendered with confirmed dates and the enabled action, without any
installation call. The sheet build passed; log:
`/tmp/gatherory-blueprint-sheet-build.log`. English and
Spanish localization coverage passed for 1,528 strings. Build log:
`/tmp/gatherory-blueprint-polish-build.log`. No automated tests were requested
or run for this task. Device acceptance should cover:

1. Search, open a blueprint, edit its event name or idea and save.
2. Verify Saving/Changes Saved feedback, including personal-blueprint failure
   and retry without closing the preview.
3. Use Blueprint, confirm the main/child dates, then Create Event.
4. Verify continuous creation progress and recovery after a failed request.
5. Check light/dark, VoiceOver and compact/folded layouts.

No live installation or personal-blueprint write was performed during this pass.

## Blueprint Home editing — October 22

- Each Home event card has a labeled glass **Edit** action; opening a detail
  retains a labeled Edit toolbar action. Long press remains a shortcut.
- The main event uses one native grouped editor for name, date/time, and
  cover. As of October 23, new dates start today and the date sheet uses the
  stored event timezone automatically, without a timezone picker. The row and
  cards format dates in that same zone. Only completing the sheet confirms a date; saving a
  name or cover leaves date confirmation unchanged. Confirmed main-event dates
  appear on the Home card and detail.
- Add Sub-event is a separate plus action. The opaque editing overflow menu was
  removed, and pending draft changes use a visible Save label.
- Customized sub-events stay in the Home projection even when they have no loved
  idea or to-do. This survives draft reload and personal-blueprint revision
  rollover by retaining the acknowledged customized children as local overrides.
- All writes still use the existing exact-account/generation guards and draft /
  personal-save paths. The editor stages its values until Save; a changed cover
  is committed only when its ID differs. Use Blueprint remains the explicit
  entry to event creation.
- Canvas previews: **Edit Blueprint Event · Light / Dark** in
  `BlueprintContentEditors.swift`. These render the real editor without a
  backend; uploading still requires an account.

Validation: iPhone Duo simulator build succeeded, English/Spanish localization
coverage passed (1,638 strings), and `git diff --check` passed. No automated tests,
phone installation, or on-device visual acceptance were performed for this pass.

## Explore idea artwork after restoring a preview — October 22

A saved preview pins its Blueprint definition and revision. Its discovery artwork
can change independently of that definition, so reopening from Explore refreshes
discovery metadata when catalog key, revision, and content hash all match. Saved
choices and explicit cover removals remain intact; metadata from another revision
or hash is not merged. Saving explicitly retains the refreshed metadata in the
local draft. Paged Explore results apply the same rule for duplicate revisions.

Regression tests cover stale saved/source previews, image URL projection into
Ideas, explicit removal, persisted metadata, and revision/hash mismatches. The
focused preview-session and discovery suites passed (16 tests), and the iOS
build passed.
The updated Debug build was installed and launched successfully on the connected
Julio’s iPhone using `scripts/push-to-phone.sh`. This confirms installation, not
on-device visual acceptance.
