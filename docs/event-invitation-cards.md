# Event invitation cards

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
