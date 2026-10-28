# Event card actions

Updated October 25, 2026. Native SwiftUI implementation only; no production
deployment or TestFlight upload is included.

## Cards

The Events library and in-event Home no longer show lifecycle/context capsules
such as Draft, Approved, Main event or Subevent. Lifecycle state remains in the
models, filters, event details and card accessibility descriptions. Home keeps
the native selected-event navigation title and the named parent subtitle.
This supersedes the visible-badge portion of the earlier Home context change.

## Events tab long press

The native context menu retains Blueprint actions and adds:

- **Duplicate Event** for the current active host or manage collaborator.
  Finished/cancelled source events can be copied without modifying them.
- **Cancel Event** where the existing lifecycle policy permits it, with the
  existing destructive confirmation and a permission recheck.
- **Delete Event** for eligible drafts, with the existing confirmation and
  lifecycle recheck. This retains existing main-event deletion semantics:
  the main event is marked deleted and child events are cleared, while the
  planning container remains available. This does not delete the account or
  silently remove the entire planning container and its remaining ideas.

Read-only collaborators and guests do not receive management actions.
VoiceOver exposes equivalent actions. Pending confirmations capture the
authentication principal generation and reject sign-out, a different principal,
departure, and a replacement workspace instance, even if its ID is unchanged.

**Pause Replies is deferred**, per the explicit product decision. No pause
column, migration, API field or nonfunctional menu item was added.

## Duplicate content

The native sheet has a name field, a copy summary, Cancel and Duplicate Event.
The prefilled name is “Copy of …”; a blank name cannot be submitted. Schedule
and ideas are included without an additional opt-in choice.

The factory constructs new records explicitly rather than cloning an archive:

- Fresh root, child-event, idea and host identities, with remapped event and
  linked-idea references.
- Main event details, dates/time zones, locations, budget metadata, unarchived
  schedule and ideas. Structured idea values and ordinary resource URLs remain.
- A draft main event and draft/upcoming schedule, with ideas reset to new.
- A new host-only roster; no copied participants, RSVP responses, votes, tasks,
  note history, expenses, albums, media identities or invitation/Blueprint
  sharing state. Photos/artwork are excluded, as the sheet explains.
- Scoped-event copies use only the visible event's own content and budget;
  they do not bring in hidden parent/sibling content.

The existing library/persistence flow adds and opens the new event. The source
is unchanged. Submission rechecks the current actor, permissions, principal
generation and exact library instance. The operation uses the existing native
persistence and sync paths; it does not publish a Blueprint or create share links.

## Regression coverage

`EventRemovalTests` covers lifecycle eligibility, role restrictions, stale
confirmations, principal changes, departure/replacement and persistence.
`PlanningWorkspaceDuplicateFactoryTests` covers independent identities,
relationship remapping, structured ideas, reset outcome state, cleared private
history, actor/permission checks, closed sources and scoped-event isolation.

The first simulator pass verified hidden badges, long-press Cancel/Delete,
cancellation of confirmations, read-only restrictions and selected Home title
updates: 21 unit tests plus three native UI methods passed (parameterized cases
included in the unit suite). The later complete native unit run passed
**1,043 tests**. Final duplicate sheet UI acceptance is recorded in
`docs/testing-verification.md` with its actual result bundle.

Standard Light/Dark iPhone layouts are the acceptance target. No dedicated
super-large text test, physical-device run, release archive or upload was made.
