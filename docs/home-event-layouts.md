# Home event layouts

Updated November 2, 2026. This is a native SwiftUI change; nothing is deployed
or uploaded to TestFlight by this work.

## Choosing a view

Open the profile button, then **Account → App Settings → Home view**, and choose:

- **Overview** (default): a Blueprint-style main-event cover with title, schedule,
  location and description, followed by date-grouped, image-led event cards.
  Each date has a horizontal collection; scroll vertically between dates and
  horizontally between events on the same day. No idea cards,
  idea counts or idea sections appear in this view.
- **Cards**: the optional vertical event cards, snapping, event rail and
  pull-to-create behavior.

The native picker marks the active choice. Guest Account has the same picker.
The device stores the preference
under `home.layout`; reopening Home or the app preserves it. Unknown stored
values safely display and select Overview. Explicitly saved Cards preferences
remain Cards. This is a display preference, not a
field in the event archive or sync API.

## Date ordering

Home keeps its main-event card at the top. The schedule starts with today and
upcoming dates, followed by past dates from newest to oldest; undated items
sort last wherever they are available. Overview retains horizontal rows grouped
by each event's local calendar date and chronological times within each row.
Cards uses the same today/upcoming-first policy for its children and event rail.

The Events tab also sorts its filtered results by date rather than insertion
order. Events spanning today remain with current/upcoming events, including
all-day events whose last day is today. Date classification uses each event's
stored timezone; people do not need to choose a timezone to browse. Exact ties
use stable event IDs. Existing filter membership and permission rules remain.

This ordering is derived at display time. It does not rewrite the library,
timeline, saved dates or sync records, and it does not reset the selected event
or override a navigation destination. A return to a selected past event still
returns to that event rather than redirecting the person to a different one.

An event idea appears here after an authorized planner confirms **Schedule**.
Votes alone never add a Home event. The proposal and scheduled child keep their
existing link; opening or cancelling the Schedule sheet creates nothing. See
[event idea scheduling](idea-scheduling.md).

In Overview, open an event's **Manage → Updates** to read or post updates;
the Home toolbar has no announcement/note shortcut. Cards retains its direct
megaphone button for planners. Add event and the profile control retain their
direct toolbar positions. The Home and Decide
tabs keep the native tab bar expanded while scrolling.

Verified October 30: the native regression
`EventManagementUITests.testOverviewUpdatesOpensThroughManagementInsteadOfHomeToolbar`
passed on iPhone 18 Pro / iOS 27 Simulator. It checks the Cards shortcut,
its absence in Overview, and Overview → Manage → Updates navigation.
Result: `/tmp/gatherory-overview-updates-20261030.xcresult` (one test,
zero failures). No screenshot review was performed.

Manage is now an event action rather than a workspace tab. Each accessible
Home card has a Manage footer below its details, with a chevron. Only that
footer opens the event-pinned management view; the card body still opens the
invitation. Management uses native push/back navigation from the Home card's
footer; the invitation toolbar does not repeat that action. See [event management from Home](event-management.md) for scope,
permissions, notification routing and verification limits.

## Event context and permissions

Both layouts use the existing workspace selection and invitation detail flow.
Opening an Overview event selects that exact event and uses native push/back
navigation. Switching back to Cards restores its selected card. Cards retains
its existing zoom presentation. Selecting the Home tab again uses the existing
main-event/next-event shortcut and scrolls the Overview to that selection.

Overview has no blue selection outline or tinted selection background. The
native navigation title identifies the active event, and VoiceOver receives a
selected trait. Text and surfaces use the existing iOS design system. Larger
artwork leads each child-event card, with its title, time and location below.

Date headings use each event's own calendar date in its stored time zone, so
travel or the device time zone does not shift events into the wrong day.
Events sharing that calendar date share a collection, ordered by start time.
Undated events appear together after dated groups under “Date to be decided.”
Near dates use localized relative headings such as Today, Tomorrow and In 3
days (yesterday through seven days ahead); farther dates retain full dates.
Horizontal collections extend to the screen edges, with content insets only
at the start and end. Cards use the existing invitation namespace for the
native zoom transition into event detail and back. The transition source and
native context-menu preview belong to the complete decorated card, including
its Manage footer, surface and border. Hiding just the inner button during an
interactive dismissal must not leave an empty rounded shell behind. The
context-menu modifier sits outside the card's own rounded clip, and horizontal
day rows disable scroll clipping so the system's lifted preview can extend
above and below the row. Artwork still clips inside its card; body and Manage
remain separate tap targets.

Overview cards show compact start–end time ranges when a valid end exists,
using the event's time zone and native localized formatting. Same-day times
share AM/PM where the locale permits it; child cards do not repeat the date
already shown by their day heading. Overnight ranges add only the abbreviated
end date (and year when crossing years). The main card uses a short separate
date and a timed range. All-day children retain All-day, undecided events do
not invent a time, and missing/invalid ends show the start alone. VoiceOver
retains complete dates, times and time zones.

`HomeEventsOverviewProjection` is the shared rendering policy: it starts from
`visibleEventContexts`, exposes the main event only when authorized, and
includes only direct, visible, non-archived child events. Guests with access to
one child do not receive the main-event cover, title or other children.
Unscheduled events say “Date to be decided.” Deleted-main handling reuses the
existing empty state and creation permissions.

Switching layouts cancels card gesture/reselection timers. The Cards restore
task is keyed to the layout, checks cancellation, and reads the current visible
selection after yielding. Overview scrolls through its authorized projection;
card snapping, event rail and pull-to-create handlers stay inactive there.

## Implementation

- `Gatherory/Features/Home/HomeEventLayout.swift`: persisted mode values and
  safe fallback.
- `Gatherory/Features/Home/HomeEventsOverviewView.swift`: projection,
  event-only layout, date collections and refresh.
- `Gatherory/Features/Home/HomeEventsOverviewDayGroup.swift`: calendar-date
  grouping, stable ordering and unscheduled group.
- `Gatherory/Features/Home/HomeEventTimePresentation.swift`: compact event-local
  overview time ranges and complete accessible schedule.
- `Gatherory/Features/Account/HomeEventLayoutPicker.swift`: Account layout choice.
- `Gatherory/Features/Home/HomeView.swift`: Updates and common navigation,
  actions and presentation state.
- `GatheroryTests/HomeEventLayoutTests.swift`: projection, guest scope,
  archived/deleted events, proposal exclusion, preference fallback and grouping.
- `GatheroryUITests/GatheroryUITests.swift`: Light/Dark mode switching,
  vertical/horizontal scrolling, event detail/back, selected-event restoration
  and relaunch persistence.

No new packages, backend fields, migrations or changes to Blueprint rendering
are required. The dev server remains stopped.

## Verification

Actual simulator results and remaining acceptance limits are recorded in
`docs/testing-verification.md`, under Home event layout choices.
