# Event invitation cards

## Current schedule tile and lifecycle — October 30, 2026

The schedule tile uses a month/day stamp as its date anchor. Single-day events
show a compact weekday and start–end time beside it. Multi-day and overnight
events use two rows, each pairing its own stamp and weekday with its own time.
There is no second full date range, numeric date/time interval, or visible
timezone abbreviation. Cross-year and other-year stamps retain the year;
all-day and undecided schedules keep their existing meaning. Event-local
calendar formatting, stored IANA identifiers, calendar export and complete
VoiceOver schedule descriptions remain intact. Users do not choose a timezone
in the date editor. Add to Calendar remains a separate native footer action.

Overview is the default Home layout, with Cards still available in Account.
New and duplicated main events start Ongoing; copied scheduled children start
Approved internally. Neither lifecycle Status nor Planning Status appears in
the native event edit sheet. Saving a legacy draft in the full main editor
promotes it to Ongoing; explicit Finished/Cancelled states and existing imported
records are preserved. Dates no longer silently mark an Ongoing root event
Finished or lock planning. Hosts and managers retain deletion of Ongoing main
events; contributing-only collaborators do not gain that destructive action.

Main and child invitation content supports permission-checked tap editing;
Manage has no editing gear. The original main-only rules and timezone line
described in the historical sections below are superseded by these updates.
See `testing-verification.md` for the final test results and limits.

## Lean opening invitation schedule — October 27, 2026

The opening artwork is for scanning: a single-day event shows Yesterday,
Today or Tomorrow in the event's local calendar, or a short date for other
days. Timed events add only the start time. Multi-day events show a compact
date range, with no repeated timestamps or time-zone line. Other-year dates
retain their year. All-day events use the date alone and undecided schedules
stay undecided. Relative labels use native localized formatting and refresh
while the invitation remains open.

The date tile below remains the place for the complete date/time range.
VoiceOver retains that full schedule even when the hero's visible
summary is short. The Add to Calendar footer keeps its native action without
the visible copy/synchronization footnote.

## Opening invitation RSVP spacing — October 27, 2026

The invitation hero uses the available reading viewport instead of a fixed
640-point cap. Its RSVP row has a 12-point normal-size bottom inset, bringing
Going, Not Sure and Not Going closer to the native tabs without overlaying
them. Responses remain part of the scrollable invitation. Long titles and
schedule text can grow beyond the initial viewport and remain scrollable.
Blueprint event heroes retain their existing default spacing.

The main-event date button keeps its existing focused editor and permission
checks; response state, pending/saved/error feedback and retry behavior are
preserved. The lean schedule above supersedes the earlier full-schedule hero.

## Full-screen artwork regression — October 27, 2026

Invitation artwork must extend behind the status/navigation controls and bottom
tabs. The iOS 27.1 adaptive artwork container was explicitly clipping its
secondary artwork to content bounds, exposing the black root background above
and below it. `EventInvitationScreen` now opts into
`AdaptiveArtworkPresentation.artworkExtendsIntoSafeAreas`, retaining a single
backdrop and its existing blur/scrim. The same setting also applies to the
shared idea-detail reader (Ideas, Decide and Blueprint ideas) and Blueprint
event details. The bounded decision deck card retains clipping. Both Home
entry layouts retain native zoom navigation.

The focused native UI regression opens the real cover fixture through Cards
and Overview in Light/Dark, samples top/bottom safe-area image pixels and saves
screenshots. It passed on iOS 27.0 and 27.1; see `testing-verification.md` under
Invitation full-screen artwork. Other pending fixes were deferred for this pass.

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
sync or an external Maps launch. There are no server/schema changes. The
subsequent [TestFlight build 6 upload](app-store-release.md#testflight-build-6--october-23-2026)
includes these changes; device acceptance remains separate from the local checks.

## Invitation information cards

The invitation information area uses compact cards over the event artwork.
The schedule card leads with a localized month/day stamp, weekday and readable
time range; a year is added when it differs from the current event-local year.
The event's time zone is secondary, including both zone abbreviations across
a daylight-saving transition. Overnight and multi-day events retain a compact
date range, and all-day ranges keep their inclusive displayed end date. Full
dates and times remain in the accessibility label.

Category, status and purpose are omitted from this focused schedule tile.
Add to Calendar is a native footer row separated by a divider, with a short
copy-only explanation, a disclosure chevron and a 44-point touch target. It
opens the existing EventKit editor; it does not automatically save an event or
create a synchronization link. Host date editing is a separate date-row action;
guest/read-only viewing retains export without gaining edit controls.
Unscheduled events offer date editing only when allowed and never fabricate a
calendar export. See `InvitationSchedulePresentation.swift` and the schedule
card acceptance in `testing-verification.md`.

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

## Main-event Photos presentation — October 27, 2026

Choose from Photos now presents the system picker explicitly from the image
choices screen's navigation host, instead of nesting a PhotosPicker control
inside its Form row. Cancelling returns to image choices without discarding
the main-event editor draft. The existing import, image preparation, file,
camera and curated-cover paths remain in place. See
`offline-recovery-2026-10-27.md` and `testing-verification.md` for this pass's
executed native acceptance and remaining device checks.
