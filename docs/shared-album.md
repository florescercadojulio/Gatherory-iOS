# Event shared album

The shared album belongs to an event: Workspaces → Home → event card → Shared
Album. Its job is to let people revisit the event through the photos everyone
contributed and keep a few favorites in their own Photos library.

## Presentation

- The event card previews up to four photos. Each preview opens that exact photo;
  View Album opens the collage. Closing a photo returns to the collage, then
  closing the collage returns to the event.
- iPhone uses two masonry columns in either orientation. iPad uses the available
  window width to choose two to six columns, including narrow multitasking
  windows. The minimum ideal iPad card width is 190 points, with 12-point gaps.
- Photo metadata determines the card shape. Display ratios are bounded between
  0.65 and 1.5 to prevent extreme panoramas or portraits from dominating the
  collage. EXIF rotation and mirrored orientations are respected. The viewer
  always shows the complete image.
- Cards show the contributor's icon and a single-line name with tail truncation.
  Avatars resolve by account ID among the event's participants. Missing identity
  or profile artwork uses initials; names alone never establish an account match.
- Photography carries the personality. Navigation and actions use native SwiftUI
  controls and the existing semantic theme. The Ideas-style progressive image
  blur and a dark bottom scrim keep attribution legible. Reduced transparency
  uses an opaque attribution background and removes image blur.
- The viewer offers horizontal paging, position, contributor/date, pinch and
  double-tap zoom, Save Photo, and a photo actions menu. No editing, filters,
  collections, face recognition, or photo-management tools are introduced.

## Selection and saving

Select switches card taps to selection. A bottom bar offers Select All or
Deselect All and Save to Photos with a count. Save is unavailable with no
selection. Done exits selection and clears it. Hidden/deleted photo IDs are
pruned, and saving resolves selected IDs against the current visible gallery.
Cards and selection controls are disabled while a batch is saving.

`AlbumPhotoSaver` requests PhotoKit `.addOnly` access only after a nonempty,
explicit save. It validates every selected photo before asking for access and
submits original stored bytes in one PhotoKit change transaction. A failed or
invalid batch keeps the selection for explicit retry; no automatic retry can
create duplicate assets. Successful saving clears the selection and reports the
saved count. Denied access offers Open Settings. The app never requests full
photo-library read access for this feature. These are the images stored by
Gatherory, not a promise of the camera's original pre-upload files.

Upload, reporting, personal hiding, and deletion retain their existing
permission and persistence boundaries. Saving an already accessible photo does
not grant upload or planning access. Deletion remains limited to authorized
uploaders and requires confirmation. Viewer navigation reconciles live removals
without changing the target of an already requested deletion.

## Accessibility and performance

Names remain available in full to VoiceOver even when visually truncated.
Selection has a spoken Selected/Not selected value and a checkmark, so it does
not rely on color. Controls have at least 44-point touch targets. Dynamic Type
stacks footers when needed. VoiceOver exposes adjustable photo navigation and
named zoom actions; zoom animations respect Reduce Motion. Fixed UI and
permission strings are available in English and Spanish.

The collage uses lazy columns and orientation-correct display-sized ImageIO
thumbnails. Layout metadata is recomputed when photos or window dimensions
change, rather than on each selection toggle. The viewer releases decoded
images when their pages lose selection. Image loading follows selection inside
a stable page container, so navigation transitions cannot trigger reload loops. PhotoKit authorization and writes are
injected at the service boundary for deterministic tests.

## Tests

- `AlbumPresentationTests`: window sizing, invalid dimensions, encoded EXIF
  orientation, shortest-column placement, selection reconciliation, export order.
- `AlbumPhotoSaverTests`: add-only authorization, no eager permission request,
  original byte/order preservation, duplicate/concurrent submission guards,
  invalid data, denial, write failure/retry, localized permission configuration.
- `AlbumViewerStateTests`: initial selection, live refresh, nearest remaining
  photo, navigation bounds, deletion target capture and cleanup.
- `SharedAlbumUITests`: the real Home/event route, direct preview opening and
  dismissal, gallery/viewer/selection in light/dark/large text, ordinary empty
  album behavior, and screenshot attachments.
- Existing `SharedAlbumDeletionTests` cover authorization, event isolation,
  durable offline tombstones, and stored uploader identity.

UI tests use a DEBUG-only `-SeedSharedAlbumUITestPhotos` flag together with the
existing skip-authentication, ephemeral-store, and development-seed flags. The
four locally generated images never modify ordinary fixtures or account data.

Before release, check real-device permission grant/denial/Settings recovery,
actual Photos writes and zoom/swipe gestures on iOS 26, and iPad window resizing.
Mocked PhotoKit tests do not prove real library writes.
