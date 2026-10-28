# Home event layouts

Updated October 28, 2026. This is a native SwiftUI change; nothing is deployed
or uploaded to TestFlight by this work.

## Choosing a view

Open the profile button, then **Account → App Settings → Home view**, and choose:

- **Cards**: the existing vertical event cards, snapping, event rail and
  pull-to-create behavior. This remains the default.
- **Overview**: a Blueprint-style main-event cover with title, schedule,
  location and description, followed by date-grouped, image-led event cards.
  Each date has a horizontal collection; scroll vertically between dates and
  horizontally between events on the same day. No idea cards,
  idea counts or idea sections appear in this view.

The native picker marks the active choice. Guest Account has the same picker.
The device stores the preference
under `home.layout`; reopening Home or the app preserves it. Unknown stored
values safely display and select Cards. This is a display preference, not a
field in the event archive or sync API.

Updates has a direct megaphone button in Home for planners. Add event and the
profile control retain their direct toolbar positions. The Home and Decide
tabs keep the native tab bar expanded while scrolling.

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
native zoom transition into event detail and back.

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
