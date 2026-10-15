# Gatherory App Store release and review handoff

This document is the release owner’s checklist and the source for Gatherory’s
App Review notes. Do not commit real review credentials here. Enter them only
in App Store Connect and keep the canonical copy in the team password manager.

Apple expects a complete build, live backend services, working links, and an
active demo account or an approved fully featured demo mode for apps that need
sign-in. See [App Review Guideline 2.1](https://developer.apple.com/app-store/review/guidelines/#performance),
[Providing information for a complete review](https://developer.apple.com/help/app-review/before-submitting-for-review/complete-review),
and [Apple’s App Review overview](https://developer.apple.com/app-store/review/).

## Source compatibility baseline — October 15, 2026

The current source targets iOS/iPadOS 26 or later for iPhone and iPad. Music
selection and audio-session APIs introduced in iOS 27 have guarded iOS 26
fallbacks. See [compatibility verification](testing-verification.md#ios-26-compatibility--october-15-2026)
for the build/test evidence and outstanding iOS 26 runtime checks.

This does not change the already-uploaded version 1.0 (3), which was built with
an iOS 27 minimum. Distributing iOS 26 support requires a new, incremented build;
no replacement TestFlight upload is part of this source change.

## Latest TestFlight verification — October 14, 2026

- Version **1.0 (3)** was archived, successfully uploaded, processed, and submitted
  to TestFlight beta review for the existing External Friends & Family group.
  App Store Connect confirmed **Waiting for Review**. Build 2 was withdrawn
  with the release owner's approval and remains available as Ready to Submit;
  it was not expired or deleted. Build 3 includes updated testing notes and
  automatic tester notification after approval.
- The complete `GatheroryTests` unit suite passed: 337 tests / 404 parameterized
  test runs. UI tests were excluded. English/Spanish localization coverage passed.
- The bootstrap preflight now checks the remote payload schema version before
  decoding it. Its regression verifies the specific unsupported-version error;
  save and remote-merge transaction boundaries are unchanged.
- The archived app uses the production authentication origin, disables
  development seeding and login bypasses, and retains the existing Release
  telemetry setting. Sign in with Apple and WeatherKit entitlements are present.
- Unauthenticated production bootstrap/pull GET requests and push POST requests
  returned HTTP 401. This is a route/authentication check, not a replacement for
  the signed-in device walkthrough below.

This is a TestFlight upload, not a public App Store submission. The checklist
below includes earlier verification gaps; recheck its dated entries against
current production/device evidence before a public release.

## Submission blockers

Do not submit the current Release build until every blocking item is resolved.

| Status | Item | Current state | Release requirement |
| --- | --- | --- | --- |
| **Blocking** | Reviewer access | The production web app and Apple web sign-in have been exercised, but no dedicated App Review account is recorded yet. | Supply a non-expiring verified review account and keep its backend available throughout review. Follow [`auth-integration.md`](auth-integration.md). |
| **Blocking** | Production sync origin | The web app and `/api/auth/*` are live, but an unsigned request to each deployed `/api/sync/bootstrap`, `/api/sync/pull`, and `/api/sync/push` route returned HTTP 404 on October 11, 2026. The local web-app source contains these routes. | Deploy the current web-app revision and production migrations. Confirm the sync routes return HTTP 401 without a bearer token, then exercise them from the archived iOS build. |
| **Verify before submission** | Sign in with Apple | Native identity-token exchange and the server bundle-audience setting are implemented, and QA has exercised the Apple flow successfully. | Verify the distribution profile contains Sign in with Apple and repeat the flow using the archived Release build. |
| **Verify before submission** | Google sign-in | Native Google ID-token exchange is implemented, and QA has exercised the Google flow successfully. | Repeat the flow using the archived Release build and production OAuth configuration. |
| **Verify before submission** | Account data isolation | SwiftData workspace records and sync envelopes are scoped by the canonical Better Auth user ID. Signing out closes the active scope. | On a physical device, switch between two production accounts and verify neither account can see the other's cached or server data. |
| **Verify before submission** | Account deletion | Better Auth deletion, web/iOS controls, shared-workspace transfer, server media cleanup, and local SwiftData/Keychain cleanup are implemented. | Apply the checked-in database migration in production, then delete a disposable production account from the archived build and confirm its private data, R2 objects, sessions, and local cache are gone. See [Guideline 5.1.1(v)](https://developer.apple.com/help/app-review/guideline-reference/5-1-1-account-deletion). |
| **Blocking if collaboration is advertised** | Cross-device sync | Authenticated native entities are synchronized through PostgreSQL with idempotent mutation receipts, an ordered change cursor, canonical-table materialization, and organization membership authorization. Separate S3 media transfer is not yet complete. | Verify two-account collaboration and owner sync on physical devices. Do not advertise cross-device photo sync until media transfer is connected and tested. |
| **Verified** | Legal and support URLs | Privacy, Terms, and Support URLs have been verified manually. | Recheck all three from a signed-out browser immediately before submission and keep the privacy answers accurate. See [Manage app privacy](https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy). |
| **Blocking for weather** | WeatherKit provisioning | The entitlement is in the project; profile/account configuration must still match. | Enable WeatherKit for the production App ID and regenerate the distribution profile. Test a forecast in the archived build. |
| Required | Export compliance | Not declared in the project. | Answer App Store Connect’s encryption questions. Add `ITSAppUsesNonExemptEncryption` only after confirming the correct answer. See [Apple’s encryption documentation guidance](https://developer.apple.com/help/app-store-connect/manage-app-information/determine-and-upload-app-encryption-documentation). |
| Required | App privacy | Not verifiable from code alone. | Declare every data type collected by Gatherory and its integrated providers, including authentication, photos, location, diagnostics, and user content as applicable. |
| Required | Age rating | Not verifiable from code alone. | Complete the current age-rating questionnaire in App Store Connect. |

## Review account contract

The production identity source is Better Auth in `gatherory-web-app`. The iOS
bridge, stable user-ID rules, provider flow, and deletion requirements are
defined in [`auth-integration.md`](auth-integration.md).

Create a dedicated production account with these properties:

- It does not expire during review and does not require an employee to approve
  a login.
- It does not require SMS, email, passkey, or other second-factor interaction.
- It opens directly into a clearly labeled, populated review workspace. The
  workspace includes a main event, sub-events, people, ideas, decisions,
  budget data, a shared playlist, and image-backed content so reviewers can
  inspect the product without first creating setup data.
- It can create and edit workspaces, events, ideas, costs, participants, and
  shared-album entries.
- If different roles expose different behavior, provide credentials for every
  role in the App Review Notes field.
- Its backend environment and any required feature flags remain available for
  the entire review period.

Enter the following values in App Store Connect’s **App Review Information**:

```text
Sign-in required: Yes
Username: [REVIEW ACCOUNT EMAIL]
Password: [REVIEW ACCOUNT PASSWORD]
Additional role credentials: [NONE, OR LIST EACH ROLE]
```

## Reviewer walkthrough

Run this exact walkthrough against the archived Release build before copying it
into App Store Connect.

1. Launch Gatherory and sign in with the review account.
2. Open the preloaded review workspace. Home shows the main event and provides
   access to its invitation-style details.
3. Add a sub-event from Home or Timeline. Add a location to exercise MapKit and,
   when the date is inside WeatherKit’s forecast range, weather.
4. In Ideas, add an attire or food idea. In Decide, approve it and confirm the
   decision is reflected in the correct event context.
5. In Manage → Budget, verify event costs and the Workspace Budget rollup. Add costs through the existing event editor.
6. Open an event’s shared album and add a photo if Photos access is available.
   Photo persistence is currently local; do not use this step to claim cross-device
   media sync until the S3 transfer path is connected.
7. Return to the workspace browser, background or terminate the app, relaunch,
   and confirm the workspace, events, ideas, costs, and image remain.

Permission prompts are contextual:

- Location appears only when **Use Current Location** is selected.
- Photos or Camera appears only when adding an image.
- Apple Music appears only when configuring music.
- Image Playground appears only on supported devices when explicitly selected.

Weather depends on the event having coordinates, network availability,
WeatherKit provisioning, and the date being within the available forecast
range. An unavailable forecast must not prevent the rest of the event from
being reviewed.

## App Review Notes template

Replace every bracketed value before submitting.

```text
Gatherory is an event-planning workspace for hosts, collaborators, and guests.
The review account opens directly into a populated wedding workspace so that
all core flows are available immediately. The reviewed build lets people create
a main event, organize direct sub-events, collect and decide on ideas, manage
participants, track budgets and costs, and attach event photos.

Review account
Email: [REVIEW ACCOUNT EMAIL]
Password: [REVIEW ACCOUNT PASSWORD]
[ADD OTHER ROLE CREDENTIALS OR DELETE THIS LINE]

Suggested review path
1. Sign in and open [REVIEW WORKSPACE NAME].
2. Open the main event on Home to view its invitation-style details.
3. Add or edit a sub-event from Home/Timeline.
4. Add an idea, then approve it in Decide.
5. Open Manage → Budget to review event spending; use the existing event editor to add a cost.
6. Background and relaunch the app to confirm local persistence.

First-run guidance
On a clean installation, brief contextual primers appear as reviewers visit
the relevant planning areas. These primers do not block access to the
preloaded review workspace.

External Apple services
- MapKit and Core Location: event locations and optional current location.
- WeatherKit: event forecasts when coordinates and forecast range permit.
- MusicKit: optional Apple Music search after user authorization.
- Photos/Camera/Image Playground: optional event and idea artwork.

The app remains usable when weather or optional media services are unavailable.
No special hardware is required.

Devices and OS versions tested
[LIST PHYSICAL DEVICES AND EXACT OS VERSIONS]

Regional differences
[NONE, OR DESCRIBE THEM]

Support contact
[NAME, EMAIL, PHONE]
```

## Persistence release verification

The app uses a versioned SwiftData schema. A `WorkspaceRecord` contains the
versioned workspace archive and its server version, while pending offline
mutations, sync checkpoints, inbox receipts, and media-transfer records share
the same `ModelContainer`. Records and envelopes carry the canonical Better
Auth owner ID, and a workspace archive change plus its coalesced outbox mutation
are committed in one save.

The foreground sync controller authenticates with the Keychain-backed Better
Auth bearer session, pushes idempotent mutations, and pulls ordered PostgreSQL
changes by cursor. The server enforces organization membership, record scope,
and optimistic base versions, then materializes accepted native entities into
the canonical product tables. Cover and shared-album bytes still travel inside
the compatibility archive; separate S3 media transfer is not connected yet.

Automated coverage must include:

- Workspace round-trip through an in-memory store.
- Multiple edits coalescing into one pending create/update mutation.
- A real SQLite store being closed and reopened at the same URL.
- Workspace deletion surviving a reopen while retaining its pending sync
  tombstone.
- Restoration of stable IDs, image data, location, and Decimal budget values.
- Account-scoped restoration and isolation between different owner IDs.
- Applying a remote bootstrap snapshot to the correct local account scope.
- The complete domain test suite.

Run the unit suite without parallel workers:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild test \
  -project Gatherory.xcodeproj \
  -scheme Gatherory \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=27.0' \
  -only-testing:GatheroryTests \
  -parallel-testing-enabled NO \
  -jobs 1 \
  CODE_SIGNING_ALLOWED=NO
```

Before every release candidate, also perform these device tests:

- Clean install → create data → background → relaunch.
- Edit each major record type → immediately background → relaunch.
- Add a photo → relaunch → verify the photo.
- Enable Airplane Mode → create and edit data → relaunch offline.
- Return online → verify local data is unchanged and the pending outbox is
  delivered exactly once from the user’s point of view.
- Sign into the same owner account on a second device → verify the workspace
  arrives, then edit it on each device and confirm the server-version conflict
  path preserves the unsent local edit instead of silently overwriting it.
- Sign out and sign into a different account → verify the previous account's
  cached workspaces are not visible.
- Install the new TestFlight build over the previous TestFlight build and
  verify its existing workspace. Do not validate migrations only with a clean
  install.
- Exercise low-storage and denied-permission behavior without losing existing
  workspace data.

## App Store Connect preflight

- Select the intended build and confirm version/build numbers.
- Complete description, keywords, screenshots, category, age rating, content
  rights, pricing, and availability.
- Verify Privacy Policy and Support URLs from a signed-out browser.
- Complete App Privacy and export-compliance answers.
- Confirm all agreements are accepted and the distribution profile contains
  every shipped capability.
- Add current reviewer credentials, review notes, and contact information.
- Keep backend services and the review account active until the submission is
  fully approved.
- Submit through App Store Connect using Apple’s current
  [submission workflow](https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/submit-an-app).
