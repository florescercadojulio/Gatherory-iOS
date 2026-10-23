# Adaptive iPhone layouts and iPhone Duo

October 21, 2026. This is a native source and simulator checkpoint, not a
TestFlight upload or physical-device acceptance record.

## Platform baseline

Build with **Xcode 27.1** and its iOS 27.1 SDK for native Duo bar placement.
The minimum supported OS remains **iOS 26.0**. New 27.1 APIs are guarded, with
the existing glass toolbar and artwork layouts retained on earlier systems.

The project already declares a launch storyboard, all four iPad orientations,
and no `UIRequiresFullScreen` opt-out. SwiftUI `WindowGroup` owns scenes. The
notification application delegate retains only process initialization and push
callbacks; it is not replaced by a second scene lifecycle.

Apple references:

- [Prepare for iPhone Duo](https://developer.apple.com/iphone-duo/prepare/).
- [Duo design guidance](https://developer.apple.com/design/human-interface-guidelines/designing-for-iphone-duo).
- [Adaptive layouts and reserved regions](https://developer.apple.com/videos/play/tech-talks/111463/).

Apple's bundled App Resizability skill was exported with
`xcrun agent skills export` and used to audit screen, orientation, idiom,
safe-area and scene assumptions. No installed dependency was replaced.

## Layout ownership

- Keep the existing native `TabView`, sidebar adaptation and navigation stacks.
  Their selection, event scopes, destinations and editing state belong outside
  layout calculations. Never add `.id(size)` to force a resize.
- `AdaptiveToolbarActions` exposes individual actions to native toolbar groups
  on 27.1, including vertical placement and system overflow. Earlier systems use
  the previous compact Liquid Glass group. Scroll-edge styling covers all edges
  so side controls receive the same soft treatment as horizontal bars.
- `AdaptiveMasonry` measures the offered width, rather than a screen or device
  model. Ideas, blueprint collections, Explore and timeline cards use paired
  columns as space grows, with a single column for narrow/accessibility layouts.
- `AdaptiveContentLayout` reads active division regions with physical coordinates
  and resolves directional margins explicitly. Masonry places columns on either
  side of an actual vertical fold, including asymmetry caused by side controls.
  Single-column reading chooses the widest usable side without replacing its
  content view. It records only horizontal division geometry, avoiding scroll
  offset updates to layout state.
- `AdaptiveArtworkPresentation` uses native `ArrangementView` with the overlay
  style for complete idea/event readers and the non-scrolling Decide card. The
  scrolling foreground and artwork separate into usable panes when appropriate,
  including tabletop arrangements. The foreground's geometry is measured inside
  its allocated pane. Navigation remains outside the arrangement, and the
  arrangement is never inserted inside a scrolling collection.
- The main Events browser uses one viewport-sized card per vertical target,
  with native view-aligned snapping and a retained focused event ID. Filters
  return to the first matching event. Cards choose a usable reading pane at a
  fold; the invitation schedule carousel begins its blur at 62% of card height.
- Home covers derive their height from the current viewport. Their summaries
  retain readable widths and minimum space for larger text. Artwork may extend
  beneath bars; interactive event-reader content stays inside safe areas.
- Album column counts depend on available width (2/4/6), including same-scene
  growth and shrink. Photo centering still uses local view bounds.
- Google sign-in resolves its presenter through a weak view anchor in the
  initiating window. It never chooses a window from global connected scenes.
  The existing provider-unavailable recovery and authentication behavior remain.

RSVP choices follow the [horizontal-row product rule](invitation-rsvp-usability.md#rsvp-layout-rule)
in every pose and at every text size, using the earlier compact native capsule styling.

These changes affect presentation. They do not alter permissions, event IDs,
archives, sync transactions, invitation grants or server contracts.

## Verification

- Xcode 27.1 (`27A9275`) / iOS 27.1 SDK simulator build passed, including the
  final RSVP and invitation-link layout refinements.
- The full native suite passed: **916 tests across 129 suites** on an iPhone 18
  Pro / iOS 27.0 simulator, built with the 27.1 SDK. This covers the guarded
  fallback alongside the new width, fold-slot and hero-dimension policies.
  This run preceded the final presentation-only RSVP refinements; their final
  build and Duo simulator observations are recorded separately below.
- English and Spanish localization coverage passed for **1,523 strings**.
- Deployment-target verification passed for app and test targets in Debug and
  Release, on device and simulator: **iOS 26.0**.
- Source audit found no remaining layout use of `UIScreen.main`, global scene
  window lookup, device idiom or orientation. The notification delegate was
  reviewed and retained for process/push responsibilities.
- Scoped `git diff --check` passed. Existing unrelated changes and staged build
  artifacts were preserved.

Duo simulator observations (isolated fixture):

| Surface | Observed result |
| --- | --- |
| Ideas | Event selection and six ideas survive open → partial book → closed; four columns open/book and two closed, with an actual gap at the book fold. |
| Decide | Book keeps the complete card clear of the fold; tabletop puts artwork above and summary/team controls below. |
| Manage | Book and tabletop retain readable budget, collaborator and approval tiles; navigation stays intact. |
| Event reader | Initial open, book and tabletop captures verified native artwork/content separation. The book capture used a vertical RSVP fallback that was subsequently removed by product direction: all three RSVP buttons now stay horizontal, using compact native capsules from commit `5825bc8a`. Those captures predate the horizontal-only revision. Hero grows with content instead of clipping. Lower-pane scrolling was not verified because the AX-targeted scroll produced no observable change. |

Evidence is local to this run:
`/tmp/gatherory-duo-visuals/`, including `final-invitation-open.png`,
`final-invitation-book.png` and `final-invitation-tabletop.png`. Build log:
`/tmp/gatherory-duo-build.log`. Native suite log:
`/tmp/gatherory-duo-native-tests.log`. Test result:
`/tmp/gatherory-duo-tests-derived/Logs/Test/Test-Gatherory-2026.10.21_17-37-08--0400.xcresult`.

Simulator checks use the existing isolated birthday fixture, not account data:

```sh
xcrun simctl launch <simulator-id> com.guide-systems.gatherory \
  -SkipAuthentication -DisableProductionFlowSimulation -SeedDevelopmentData \
  -UseEphemeralDataStore -UseBirthdayMarketingFixture -UseProductionOnboarding \
  -hasSeenDecideTimelinePrimer YES
```

Use Device Hub to switch between open, partially open and closed, then rotate.
Check Ideas with an event filter selected, a pushed idea/event reader, Decide,
Manage and a focused draft. Navigation, selected event and draft must survive
the change. Also inspect light/dark appearance, large text and RTL.

The fixture's development-account access correctly prevents opening an Updates
composer. No credential or guest-principal check was bypassed. A focused Updates
draft still needs an authorized guest/announcement preview fixture for visual
acceptance. The Add Idea category sheet opened in light mode, but Device Hub's
accessibility tree did not expose its modal controls, so keyboard behavior was
not accepted from that observation. Large Dynamic Type and RTL have source and
geometry-policy coverage, but still need interactive visual acceptance.

One simulator transition (tabletop → book rotation → open) left the entire
rendered scene, including native navigation and tab controls, distorted with
missing accessibility descendants. Relaunching restored the scene; the final
book capture uses that recovered run. This has not been attributed to app code
or accepted as a passed repeated-rotation stress check.

Physical Duo hardware, provider sign-in in multiple windows, and release/archive
acceptance remain separate checks. Do not infer App Store support metadata or
physical delivery from a simulator build.
