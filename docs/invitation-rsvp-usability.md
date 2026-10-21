# Mobile invitation and RSVP refinement

October 21, 2026. This follows the
[event-planning research](../../../gatherory-web-app/docs/research/event-planning-progress-2026-10-20.md)
and the [mobile guest/invitation recovery audit](../../../gatherory-web-app/docs/release/mobile-v1-guest-invitation-audit.md).
Source implementation and non-UI verification are distinct from physical-device
acceptance and the deployed release.

## What changed

- The invitation preview has one plain-language access summary, instead of
  overlapping role and permission explanations. Pending and declined requests
  have clear status text. Unknown permissions do not promise editing access.
- The signed-in name is visible and switching accounts is a secondary action.
  Joining, signing in, and account switching cannot overlap pending invite work.
- Loading is labeled. Dismissing an error over a loaded preview keeps the pending
  invitation and any accepted join result so destination loading can be retried.
  With no preview, the banner's explicitly labeled Close Invitation action closes
  the invitation rather than leaving an empty screen. The navigation Close action
  remains available.
- Guest RSVPs show Sending response, Response confirmed, or an unconfirmed state
  beside the choices. A retry names and resends the attempted choice. The old
  Try Again action only refreshed the feed; it did not resend a failed RSVP.
  Feed/cache errors instead offer Refresh Event without pretending to resend.
- Selected responses have a visible checkmark and VoiceOver selected state.
  Response labels are localized and use system text styles without font shrinking;
  accessibility text sizes use a vertical layout. Existing imagery, semantic
  colors, and minimum touch targets are retained.

## Boundaries and recovery

Attend as guest; sign in to help plan. Joining, requesting approval, changing
RSVP and leaving remain explicit. No browser, server, account creation, permission
or sync-schema change is introduced. Invited events remain read-only projections,
separate from owned plans and the planner sync outbox.

The transient attempted response belongs to one event and the active principal
generation. It is cleared on identity changes and is not persisted as an offline
job. A retry must match the failed event and cannot duplicate an in-flight request.
The previous confirmed RSVP stays selected until the server acknowledges a valid
response for that exact event. Wrong-event or unknown-status acknowledgements
cannot update another event or masquerade as a successful RSVP.

An acknowledgement invalidates older feed reads. A subsequent cache-write or feed
refresh failure does not turn a confirmed RSVP into a failed write. The existing
authenticated/device-proof transport and server authorization remain authoritative.
Approval, private-email matching, revoked links, event lifecycle and account
handover follow the existing contract.

## Durable leave-cache recovery

Before sending an explicit leave request, the device atomically records the event
in a small journal scoped to the configured server and exact account or device
guest. If that write fails, no leave request is sent. The journal contains event
identifiers only; it is not an offline mutation queue and never replays a leave.

After a confirmed leave, the event disappears immediately. If both rewriting and
deleting its old cache fail, the durable journal keeps that event and its artwork
out of an offline relaunch. Other invitations and other principals retain their
own caches. An unreadable journal suppresses only its scoped cached feed until a
fresh server response can recover it.

A fresh authoritative feed resolves uncertain leave outcomes and permits a later
explicit rejoin. Its cache must be written atomically before the journal is
cleared. Older feed/artwork completions cannot restore the departed event, and
feeds received during a leave cannot prematurely clear its intent. Account
deletion, guest removal and handover purge the selected cache before its journal;
cleanup failures remain available to their existing recovery paths.

## Verification and remaining acceptance

Verification commands and final counts are recorded in
[testing verification](testing-verification.md). Only GatheroryTests is selected;
UI automation is excluded. English/Spanish catalog checks cover the new copy.
New regression cases cover actual write retry, pending state and duplicate taps,
wrong-event/unknown-status acknowledgements, principal switching including A-B-A,
cache and feed failures after acknowledgement, and delayed feed convergence.

Physical-device acceptance still needs a slow/offline RSVP attempt and explicit
retry, an accepted join whose destination fails to load, private and public links,
pending approval and revocation, guest-to-existing-account sign-in, and cancellation
while an invitation is open. Check English/Spanish, VoiceOver, largest Dynamic
Type, light/dark appearance, and compact iPhone/iPad layouts. No device visual
validation, deployment, database change or build upload is performed
by this pass. Source commits do not establish release readiness.

Physical-device departure acceptance still needs an acknowledged leave followed
by interrupted storage cleanup and offline relaunch, then reconnecting and
explicitly rejoining. Confirm that the event stays closed offline, that unrelated
invitations remain available, and that switching accounts never crosses caches.
The [current mobile V1 checkpoint](../../../gatherory-web-app/docs/release/mobile-v1-guest-invitation-audit.md)
records the server feed-isolation regression and remaining release blockers.
