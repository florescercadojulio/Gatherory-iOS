# Core gathering media and offline follow-up — November 4, 2026

## Current results

The parent executed the Luna lane's test changes on Debug 1.0 (6), iPhone 18 Pro / iOS 27.0:

- `PhotoAttachmentPickerUITests.testMainEventPhotoPickerOpensCancelsAndReopensWithoutDiscardingDraft` **passed**, 107.695 s, in `gatherory-core-acceptance-final-ui-20261104.xcresult`. In Light and Dark, the editor retained an unsaved title while Photos opened/cancelled twice, returned to image choices, and returned to the same editor draft.
- `SharedAlbumUITests.testPreviewPhotoOpensViewerAndCloseReturnsThroughAlbumToEvent` **passed**, 29.366 s, in `gatherory-core-acceptance-followup-r2-20261104.xcresult`. A seeded preview opened the viewer, closed to the album, then returned to the same invitation.
- The focused model selection **passed 67 tests** across recovery, offline account restoration, media bookkeeping, management access, idea scheduling and sync. Those tests overlap the earlier core audit.
- The final combined native selection passed all 68 tests, including the real two-account dev sync acceptance; see the [completed release follow-up](core-gathering-release-followup-2026-11-04.md) for finalized evidence and exact service limits.

No new media product defect was demonstrated by these follow-up UI failures. Existing app authorization and native presentation code remain unchanged.

## Test corrections and failure evidence

The initial tests stopped at an old action-menu label. They now use generic XCUI descendant lookup for the invitation's stable `invitation.actions` identifier. That entry reached the editor and actual native Photos picker in the fresh run. Album navigation no longer depends on an unrelated permission-conditional editing menu.

The next Photos failure occurred only in Dark while the title's software keyboard still covered Change Image. The failure log showed the image button at y=721–961 and keyboard from y=546 through the bottom of the viewport; no tap on Change Image had occurred. The regression now uses the editor's existing keyboard-toolbar Done action, waits for the keyboard to disappear, then reaches Change Image. It preserves the unsaved title. This is test setup, not a new keyboard/picker implementation.

Failure teardown registers the app accessibility tree and screenshot and terminates the fixture. Console AX evidence was available in `gatherory-core-acceptance-followup-r2-20261104.log`; screenshot attachments were not exported under that run's diagnostic policy. The final assertions passed in both appearances.

## Persistence and recovery boundaries

`OfflineAccountRestorationTests.diskRelaunchRestoresAccountArchiveAndOutbox` edits during a failed bootstrap, reopens an on-disk store, and verifies the edited archive and stable queued mutation IDs. The fixture also seeds a second account archive. Media bookkeeping tests verify scoped transfer queries and durable retry state.

`CoreGatheringRecoveryTests` verifies that account restoration recovers interrupted `.uploading` rows while preserving transfer identity, local file, attempt count and another account's state. `WorkspacePersistenceController.restoreLibrary` invokes recovery before its worker starts. Routine staging still excludes active uploads, preventing duplicate live workers. This validates the product fix from the initial audit.

## Acceptance limits

The picker test verifies cancellation/reopening, not choosing a real library photo. Album navigation uses seeded images. Real R2 upload/download, library save permissions and interrupted physical-device media transfer remain signed-candidate/service acceptance. Offline disk recovery and account isolation are local SwiftData/failing-transport checks; the live dev simulation verifies vote/schedule reconnect separately, not two physical phones under airplane-mode transitions. No deployment or production account mutation occurred.
