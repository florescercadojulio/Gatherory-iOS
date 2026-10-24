# Event invitation cards

## Main-event sharing and tap editing — October 23, 2026

Opening an invitation from Home retains native back navigation and adds Share
Invitation beside the back chevron. Home's existing share action remains
available. Detail sharing is pinned to the opened event, including when it is a
child, instead of using a later Home selection. Account/profile, principal
generation, event and permission changes dismiss a stale share presentation.
The existing invitation sharing flow and sign-in requirement still own link
creation; opening it does not create or send an invitation.

Authorized main-event planners can tap the invitation's title, date or location
to open a focused native edit sheet. The date information tile and the address
area offer the same direct edit behavior. Calendar export and Maps remain
separate actions, without nested interactive controls. Missing locations expose
Add location to an authorized planner. There is no additional edit-mode step.

Cancel discards the sheet's draft. Save changes only the tapped field, preserving
current unrelated values, including cover, notes, status and schedule metadata.
Date editing reuses the existing native date sheet, automatic stored timezone,
optional end date and all-day controls. Location editing reuses the existing
native search and optional address details; opening it does not request GPS.

The new tap actions apply to the root main event only. Guest-role attendees,
view-only collaborators, inactive participants, invitation projections and
scoped child records receive read-only content. Existing local event owners can
edit their device-local plan, and sharing keeps its existing Sign In to Share
gate. An open edit captures the exact principal and main-event membership;
identity/permission/scope changes or another edit to the same field invalidate
it before a stale save can overwrite the event. Unrelated field changes do not
get overwritten.

Implementation: `EventInvitationScreen.swift`, `MainInvitationEditing.swift`,
`HomeView.swift` and the shared native date/location editors. The default
`EventReadingHero` remains read-only for Blueprint previews.

October 23 verification (Xcode 27.1, iPhone 18 Pro simulator, iOS 27.0):

- All 1,023 native unit tests passed (1,157 executions, including parameterized
  cases). The four new mutation tests exercise real saves, preservation of live
  unrelated fields, permissions, child/idea rejection and stale principals or
  edited fields. Evidence: `/tmp/gatherory-main-invitation-editing-r5-20261023.xcresult`.
  That combined bundle also contains two UI failures subsequently corrected;
  it is evidence of the passing unit suite, not an all-green combined run.
- All five focused UI methods passed across the final UI run and the focused
  tile rerun. Host save/cancel, date persistence, location clearing and the
  leading Share placement were checked in normal Light/Dark appearances.
  Guest-role and view-only attendees cannot open the editors or share. A child
  invitation shares its own event and retains native Back to Home. Evidence:
  `/tmp/gatherory-main-invitation-final-ui-20261023.xcresult` (four passing
  methods) and `/tmp/gatherory-main-invitation-tiles-fixture-20261023.xcresult`
  (one passing method, no runtime warnings).
- Date/address tiles open their focused sheets; the map remains a separate
  native Link. The initial map assertion used a seed with no coordinates and
  therefore no map. A dedicated DEBUG-only fixture supplies coordinates for
  that test; the existing Maps behavior remains unchanged. Light/Dark hero
  screenshots and the dark information-tile screenshot were visually reviewed.
- English/Spanish localization verification passed for 1,700 strings; the
  existing nonliteral-key advisory remains. `git diff --check` passed.
- The Release simulator build passed for arm64 and x86_64. Evidence:
  `/tmp/gatherory-main-invitation-release-20261023.log`.

These checks use synthetic, ephemeral local data and bypass authentication.
They do not prove production sign-in, invitation-link creation/sending, live
sync or an external Maps launch. There are no server/schema changes. This work
requires a new native build; no TestFlight upload was performed for this change.

## Invitation information cards

The invitation information area uses compact cards over the event artwork.
Schedule dates remain fully localized and use the event's time zone. Timed
overnight or multi-day events include the end date beside the time range;
multi-day all-day events show both dates. Status stays secondary, and the
calendar action and its explanation share the schedule card without an extra
nested card.

Music ideas keep a two-by-two preview of up to four tracks. Artwork tiles are
88 points square (previously 52 points), with a taller preview area; tapping it
still opens the full playlist.

The Updates card previews the newest visible item for its exact event. It
compares server-authorized announcements with private planning notes only when
the existing exact-event planning-access check permits reading them. Invitation
projections do not expose planning notes, and guest access alone does not grant
that access. The byline uses the event member's current name and profile image
when available. Read access does not depend on permission to send updates; the
destination retains its existing audience and sending rules. Account principal
and generation checks keep stale content from a previous session out of the
card. This presentation adds no backend writes or push notifications.

Implementation lives in `Gatherory/Features/Events/EventInvitationScreen.swift`
and `Gatherory/Features/Events/EventInvitationUpdatesPreview.swift`.

Canvas previews use June 13–14, 2027 sample dates. Their names are `Main event
schedule`, `Main event schedule · Light`, `Main event schedule · Large text`,
`Overnight event · June 13–14`, `All-day event · June 13–14`, `Four-song
playlist artwork`, `Invitation Updates · Dark`, `Invitation Updates · Light`,
and `Invitation Updates · Large Text`. They use sample data and do not require
sign-in or backend access.

October 21, 2026 validation: the Xcode 27.1 iPhone Duo simulator build passed
(`/tmp/gatherory-invitation-tiles-final-build.log`).
English/Spanish localization coverage passed for 1,532 strings. Canvas review
covered schedule dark/light and accessibility text, the enlarged four-cover
grid, and update-card dark/light presentations. These are isolated presentation
previews; no live announcement or album write, phone install, or test run was
performed.
