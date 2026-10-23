# Haptic feedback

October 21, 2026. The native app uses short system haptics to reinforce deliberate
actions, alongside its existing visual feedback. This is a presentation change;
permissions, guest access, authentication, storage transactions, offline sync and
notification consent remain unchanged.

## Feel and controls

- **Selection:** changing tabs, custom filters, event scopes, RSVP choices,
  participants, funding sources and photo selection; undoing a decision.
- **Light impact:** committing a decision swipe, opening an event card, and
  crossing Home's pull-to-create threshold. Arming the gesture is not presented
  as a successfully created event.
- **Success:** applied saves, completed to-dos, allocations, registry reservations,
  acknowledged invitation/review/sharing actions, blueprint saves/installation,
  explicit clipboard copies and successful PhotoKit saves.
- **Error:** an explicit RSVP or Update send fails, or a to-do persistence failure
  rolls back its local mutation. Existing error text and retry controls remain.

Account → App Settings → **Haptic Feedback** controls Gatherory's additional
haptics. Guests have the same switch in their account screen. It defaults on and
is stored locally under `app.haptics.enabled`; it is a device preference, not a
role, account entitlement or notification permission. English and Spanish labels
include a short explanation. Turning it off does not override the operating
system's own feedback for native controls.

The app does not layer haptics on native picker/toggle changes or system
context-menu/share-sheet presentation. Loading, restored state and background
sync do not become success notifications. Custom event-rail feedback follows
direct scrolling/scrubbing, not a passive selection reset. Re-selecting an
unchanged custom choice stays quiet. Decision swipes receive a light impact
rather than the heavier success pattern used for an important completion.

`DesignSystem/Feedback/AppHaptics.swift` owns the semantic mapping, preference
check and foreground gate. `AppHaptics.play(_:)` is called from UI action paths;
`View.appHaptic(_:trigger:condition:)` observes an explicit trigger without an
initial callback. Existing sensory feedback was routed through this shared path
so the switch covers both old and new app-generated feedback. UIKit generators
provide native platform behavior; there is no custom engine, audio, timer or
analytics added. Unsupported hardware retains the visual interaction.

`AppHapticPlayer` and its injected foreground-check and emitter closures are
explicitly `@MainActor`. Keep that isolation on both stored callback types and
initializer parameters: UIKit application state and feedback generators must
remain on the main actor, including when default callbacks are supplied.

## Outcome boundaries

Local domain edits retain their existing persistence behavior; a haptic does not
promise that cloud sync completed. To-dos emit success only after their existing
archive/outbox save succeeds, and roll back plus show an error on failure.
Online-only actions emit feedback from acknowledged state changes and retain
their existing principal/generation guards. Reusing an accepted invitation to
recover destination loading does not repeat the join-success haptic. Native
sharing controls keep their own system feedback and completion semantics.

The implementation follows the Apple design skill's `playing-haptics.md` →
**Best practices** (consistent, brief, optional and restrained feedback) and
`feedback.md` → **Best practices** (accessible visual confirmation alongside
haptics). References: [Playing haptics](https://developer.apple.com/design/human-interface-guidelines/playing-haptics)
and [Feedback](https://developer.apple.com/design/human-interface-guidelines/feedback).

## Device acceptance

Non-UI tests can verify policy and successful compilation, but cannot assess the
physical strength or timing of the Taptic Engine. On a physical iPhone:

1. Change tabs/filters and swipe through decisions. Expect short feedback per
   changed choice, none from cancelled drags, passive loads or repeated choices.
2. Add/edit an idea or event, complete/undo/take a to-do, reserve a registry item
   and transfer a budget allocation. Check that feedback matches the visible
   result, and that denied/no-op actions do not feel successful.
3. Join/review an invitation, change RSVP, send an Update and use blueprint
   save/install/link/Search controls. Try failed and retried requests plus an
   account switch during a request. Existing privacy/recovery behavior must hold.
4. Select and save album photos and confirm a permitted deletion. Canceling
   PhotoKit permission or a confirmation must not produce success feedback.
5. Turn Haptic Feedback off and repeat the custom actions in both account and
   guest mode. Re-enable it without restarting. Check foreground/background
   transitions, VoiceOver, Reduce Motion and devices without haptic hardware.

No UI tests, device installations, build uploads, commits or deployments are part
of this pass. See [testing verification](testing-verification.md) for results.
