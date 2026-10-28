# Offline entry, remote deletion and photo picker recovery

## Changes

- A root event deletion now removes its native workspace and cached child
  projections. Previously the entity merger searched only the timeline for a
  root ID, leaving the main event fields untouched. Workspace tombstones now
  clean up the same child projections.
- An explicit server missing-scope response can remove a previously synced
  root hierarchy. Pending creates and never-acknowledged offline plans are
  preserved. Repair cannot recreate a known deleted root from rejected child
  edits. Empty bootstrap, generic auth errors and transport failures preserve
  local work; a child tombstone keeps its parent and siblings.
- Account startup restores an exact token-matched profile from Keychain and
  opens that account's SwiftData archives and guest invitation cache before
  awaiting session validation or sync bootstrap. Remote validation continues
  separately with a bounded request. Retry remains available; saved edits keep
  their outbox identities across relaunch.
- The main-event image source uses explicit native Photos presentation from
  the source sheet's navigation host. The Photos control no longer owns its
  presentation from inside a Form row. Cancel returns to image choices;
  choosing an image retains the existing import/preparation pipeline.

Three Luna agents handled deletion, account entry and Photos presentation;
integration additionally covers cache-only guest invitation activation. No
server changes, schema migrations or dependency installation are required.

## Boundaries

The local profile is a previously validated account snapshot bound to the
current credential; it does not grant server permissions. Sign-out, confirmed
session expiry and account deletion clear it. A first launch after upgrading
an older build needs a successful online validation once to create this cache;
the app never infers an identity from arbitrary saved records. Content and
images must already have been downloaded to be available offline.

Guests retain their view-only invitation projections. Cached account content
does not bypass guest handover, account deletion cleanup or pending invitation
authentication. Nothing was deployed, uploaded to TestFlight or reset in a
database, and no dev server was started by this work.

## Verification

Final executed checks and acceptance limits are recorded in
`docs/testing-verification.md` under Offline entry, deletion and Photos recovery.
