# Spanish screenshot polish

October 22, 2026. Local source and simulator work only; no App Store Connect
changes, uploads, submission, release, deployment, or database reset.

## Changes

- Home resolves generated attendance counts, countdowns, event purpose labels,
  and status badges through the English/Spanish string catalog. Event and idea
  status/filter titles also use localized copy rather than plain English values.
- The native invitation localizes its attendee heading, attendance/invited
  summaries, and the timeline's “Other” category, including labels that are
  visible farther down the wider iPad layout.
- Ideas resolves contributor bylines, singular/plural song counts, the scope
  picker, and the shared-playlist label through the catalog on card, detail,
  and editor surfaces. Playlist card metadata can wrap to two lines.
- The compact Manage guest legend uses a Dynamic Type-aware caption and chooses
  two columns only when the labels fit at their natural width. Otherwise it
  uses four full-width rows with unrestricted wrapping. The complete
  accessibility summary is retained.
- The DEBUG birthday fixture accepts an explicit locale, translates its sample
  content for Spanish previews, and includes three fictional playlist tracks.
  Those tracks have a local fixture provider and no playable/external URLs.
  Real people’s authored content is not translated by these changes. The
  fixture's existing ephemeral-store/authentication gates remain unchanged.
- Event lifecycle is unchanged. The sample event remains a draft and is labeled
  “Borrador” in Spanish; its state is not altered to hide the badge in marketing.

## Validation

- `bash scripts/verify-localizations.sh`: 1,577 catalog strings verified for
  English and Spanish. The existing non-literal-key extraction warning remains.
- Focused simulator tests: 13 passed in `SpanishGeneratedCopyTests`,
  `BirthdayMarketingFixturesTests`, and `LayoutDimensionTests` on iPhone 18 Pro,
  iOS 27.0. This checks compiled Spanish resources, fixture isolation/archive
  behavior, and layout geometry; screenshot review checks actual text fitting.
- Test result bundle:
  `/tmp/gatherory-spanish-capture-build/Logs/Test/Test-Gatherory-RSVP-Spanish-2026-10-22.xcresult`.

## Capture handoff

Current screenshots, source fingerprints, and visual review live in
`../../../gatherory-landing/docs/app-store-release/`. These are simulator previews
of an isolated snapshot at `/tmp/gatherory-spanish-capture-source`, not evidence
that the changes are in TestFlight build 4 or a selected App Store candidate.
Concurrent advertising/Explore work temporarily prevented the shared project
from building. The snapshot linked its existing SDK products to the app target
and made two mechanical compile fixes, leaving those unrelated shared files
untouched. The exact temporary changes are recorded in
`../../../gatherory-landing/docs/app-store-release/capture-build-notes.txt`.
The native checkout already contained
unrelated changes; they were preserved, and no native commit was created by
this task.

The twenty local JPEGs cover Home, Ideas, Decide, Manage, and the child-event
RSVP invitation in English and Spanish on iPhone and 13-inch iPad. The Spanish
iPhone Manage framing preserves the full budget and RSVP legend, but its
floating event selector partially covers the task due date. The iPad version
shows that date in full. No screenshot pixels were retouched to hide this limit.
