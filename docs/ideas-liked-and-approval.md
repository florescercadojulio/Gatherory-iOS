# Ideas: personal Liked and approval shortcuts

November 2, 2026. Native source only; no production deployment, database change,
or TestFlight upload.

## Finding and accepting ideas

The existing Ideas filter menu now includes **Liked** directly after All. Liked
means the current viewer's personal **Love It** response in Decide or the idea
detail. It does not mean the shared Shortlist status, another person's response,
or a Blueprint Like. It preserves the current event scope, blocked-author
filtering and image-led masonry layout. Archived ideas stay in Archive; other
liked ideas can remain visible after acceptance because their personal responses
are retained. Switching accounts resolves the new viewer's own responses.

Long-pressing a pending idea, or using its accessibility action, offers:

- **Approve** for eligible non-event ideas. The native confirmation sheet shows
  the idea, destination event, estimated cost when present, and compact team
  input. Cancel leaves the idea unchanged. Confirmation marks it Approved.
- **Schedule** for eligible event ideas. This opens the existing date/location
  Schedule sheet and retains its atomic, idempotent linked-event handoff.

The existing non-event detail Approve action opens the same confirmation sheet.
Opening a menu or sheet does not accept an idea. Already accepted ideas and
shared music playlists do not get duplicate approval actions. Passed/archived
ideas must be restored to a pending state first.

Non-event approval retains existing active-planner permissions, including
contributors; guests, view-only or invited members cannot approve. Scheduling
an event still requires a host or collaborator with Manage permission. Approval
rechecks the exact idea, parent identity/name/status, target-event participant
and account generation. Stale edits, missing/deleted parents, lost permissions
and account changes invalidate the request. An exact successful retry reuses
the same committed expense rather than creating another.

## An idea whose event is not approved

An event proposal in Ideas is not yet an event destination. Schedule that event
idea first; scheduling accepts it and creates its linked first-level Home event.
The current hierarchy does not attach other ideas to an unscheduled event idea.

An existing draft event is different: its own food/decor/etc. ideas can be
accepted as planning decisions. Accepting one changes neither the parent event's
status nor its schedule, participants, sharing links or budget allocation. A
positive cost estimate is reconciled into a committed expense on that exact
event, so the action matters financially even while the parent is draft.

Draft status is not a privacy switch. Authorized planners can already see dated
draft events on Home. Guest content follows event access and the idea's existing
invitation visibility: approval alone does not create a guest link, but an
approved idea explicitly marked for the invitation can appear to guests who
already have access. Planning-only ideas remain planning-only. New V1 main
events normally start Ongoing; this distinction also preserves older draft
records rather than silently publishing or promoting them.

## Verification

The focused native unit checks cover personal/account-bound Liked behavior,
shared-shortlist separation, exact approval/retry, expense reconciliation,
draft-parent preservation, visibility, missing/stale parents, source edits,
account changes, and role/permission denial. Existing filter, event scheduling,
linked-event and budget tests are included. See [executed results](testing-verification.md).

The final run passed **29 focused unit tests** across five suites and **two native
UI methods**, each covering Light and Dark. Unit result:
`/tmp/gatherory-ideas-approval-units-20261102.xcresult`. UI result:
`/tmp/gatherory-ideas-approval-ui-final-20261102.xcresult` (Schedule **43.327 seconds**;
personal Liked/Approve **84.764 seconds**). Both report `TEST SUCCEEDED`.
English/Spanish coverage passes for 1,807 strings; tracked and new-file whitespace
checks pass.

Native UI checks exercise Love It in Decide → Liked in Ideas → long-press
Approve → Cancel/reopen/confirm, plus event long-press Schedule, in Light and
Dark. They use ephemeral seeded data, take no screenshots and perform no server
writes. Live multi-device sync and the signed release candidate remain separate
acceptance work.
