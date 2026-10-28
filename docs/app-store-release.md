# Gatherory App Store release and review handoff

The later [release readiness audit](release-readiness-audit-2026-10-23.md)
found and corrected an invitation-preview timezone issue, broken Home lifecycle
shortcuts and the primer's upward practice gesture. It also improves safe sync
failure diagnostics. These native/backend working-tree changes are newer than
build 6 and require a new build plus the compatible backend deployment. The
audit records current checks and remaining live-device acceptance separately
from the uploaded build history below.

## TestFlight build 6 — October 23, 2026

Version **1.0 (6)** was signed for Guide Systems LLC (`LW97NHT3JA`) and
successfully uploaded to Gatherory's existing App Store Connect app
(`6820635528`) at **8:27 PM America/Detroit**. Xcode completed with
`EXPORT SUCCEEDED`; after processing, App Store Connect lists build 6 as
**Testing**, expiring in 90 days, with both existing Friends & Family and
External Friends & Family groups attached (four invitees). The detail confirms
both groups. What to Test notes were saved, export compliance completed, and
Submit for Review completed with automatic tester notification enabled. The
overall status is Testing; no separate external review approval was observed.
See [build 6 detail](https://appstoreconnect.apple.com/teams/56187352-94ba-429f-82d1-35f22508a99b/apps/6820635528/testflight/ios/d4faf37c-8300-40f5-8c8d-fb6a2374fb0a).

The archive contains native HEAD `19833ddc93734b00cfe3a660f0e66f576e4a0118`
(`Next release`) plus the build-number increment from 5 to 6. This includes the
[beta date/contrast fixes](../../../gatherory-web-app/docs/release/beta-feedback-2026-10-23.md)
and [main invitation tap editing/sharing](event-invitation-cards.md#main-event-sharing-and-tap-editing--october-23-2026).
Share sits beside native Back; authorized main-event planners can tap title,
date and location to open focused native edit sheets. Guests/view-only attendees
stay read-only. These native changes require no server/schema changes; this
upload does not establish the separate browser beta-gate deployment status.

The submitted distribution signature and provisioning profile both verify
`aps-environment=production`, `get-task-allow=false` and the exact Gatherory
bundle/team. The archived app targets iOS 26.0 and uses
`https://app.gatherory.com`; push, consent-gated production ads and PostHog are
enabled. Development seeding, sign-in bypass and forced onboarding are disabled.

For this build, App Store Connect's encryption question was answered **None of
the algorithms mentioned above**: Gatherory's app code uses Apple OS networking
for HTTPS, Apple Keychain for credentials and SHA-256 hashes, with no app-level
cipher implementation found. No encryption declaration key was added to the
project. Reassess this answer when the app's encryption usage changes.

The pre-upload checks include the passing 1,023-test native unit suite
(1,157 executions), all five focused invitation UI methods passing across the
final run/rerun, normal Light/Dark visual review, Release simulator build and
1,700-string English/Spanish localization check. The device archive passed.
See [invitation verification](event-invitation-cards.md#main-event-sharing-and-tap-editing--october-23-2026)
for evidence and the combined-bundle/UI-rerun distinction. Live sign-in,
invitation delivery, cross-device date sync and physical-device push remain
beta acceptance checks.

The upload completed with the same two non-blocking vendor dSYM warnings
for `GoogleMobileAds.framework` and `UserMessagingPlatform.framework`. Their
internal stack traces may be less detailed. The existing App Intents metadata
warning also remains; no SDK version was changed.

Archive: `~/Library/Developer/Xcode/Archives/2026-10-23/Gatherory 1.0 (6).xcarchive`.
Logs, testing notes and verified distribution settings:
`/tmp/gatherory-testflight-1.0-6-*`. No database reset, backend deployment,
Git commit/push or public App Store release was performed for this upload.

## TestFlight build 5 — October 23, 2026

Version **1.0 (5)** was signed for Guide Systems LLC (`LW97NHT3JA`) and
successfully uploaded to Gatherory's existing App Store Connect app
(`6820635528`) at **2:09 PM America/Detroit**. The upload command completed
with `EXPORT SUCCEEDED`. After processing, App Store Connect lists build 5 as
**Testing**, expiring in 90 days, and shows it assigned to both existing
Friends & Family and External Friends & Family groups. External Friends & Family
has four invitees; the internal group has none. The build detail confirms both
groups are attached. Submit for Review completed with automatic tester
notification enabled. The overall build status is **Testing**; no separate
external review approval was observed. The saved What to Test notes cover Explore
search/discovery, Yours/Saved/Liked, Use and retry, push, ads, light/dark
appearance, feedback and PostHog. See the [App Store Connect build detail](https://appstoreconnect.apple.com/teams/56187352-94ba-429f-82d1-35f22508a99b/apps/6820635528/testflight/ios/26074dbf-5cb8-4c14-86f7-583d1e1cbe50).

The archived source is native HEAD `9190bc3da97a57bcf7bc8a3794a287edbfa0e70f`
plus the current working-tree changes and build-number increment. Existing
uncommitted work was included without a Git commit/push. Version remains 1.0;
the app and test targets now use build 5.

The submitted, distribution-signed app and its store provisioning profile were
both verified with `aps-environment=production`, `get-task-allow=false` and the
exact Gatherory bundle/team. Release enables opt-in push, consent-gated
production Explore ads and existing PostHog telemetry. It targets iOS 26.0,
uses `https://app.gatherory.com`, bundles the matching Firebase config and
disables development seeding, sign-in bypass and forced onboarding. Firebase's
production APNs key is configured; actual TestFlight delivery remains a device
acceptance check.

The complete native non-UI suite passed **1,016 tests / 1,150 executions** with
zero failures/skips/runtime warnings, and localization passed for **1,695
English/Spanish strings**. See [build verification](testing-verification.md#testflight-build-5-verification--october-23-2026).

Apple accepted the binary with two non-blocking symbol-upload warnings:
the vendor `GoogleMobileAds.framework` and `UserMessagingPlatform.framework`
dSYMs are missing. Stack traces inside those two SDKs may be less detailed;
this did not reject the build. No SDK version was changed to address this.
App archive compilation also emitted the existing App Intents metadata warning.

Archive: `~/Library/Developer/Xcode/Archives/2026-10-23/Gatherory 1.0 (5).xcarchive`.
Logs and verified distribution settings: `/tmp/gatherory-testflight-1.0-5-*`.
No production database reset, backend deployment or public App Store release
was performed as part of this upload.

## Beta configuration decision — October 23, 2026

The release owner chose a fresh database and beta-based acceptance/feedback.
The owner will perform the reset; this configuration change does not reset,
seed or deploy anything. Recreate the current schema, publish the intended
Blueprint catalog, and deploy the compatible backend. Resetting removes the
need to preserve old rows, but does not remove the schema/server requirement.

Release now enables `FCM_NOTIFICATIONS_ENABLED=YES` and
`EXPLORE_ADS_ENABLED=YES`. `EXPLORE_ADS_TEST_MODE=NO` retains Gatherory's
production native ad unit. Existing UMP consent and notification opt-in remain
required. Debug retains Google's sample ad unit and development APNs.
`POSTHOG_ENABLED=YES` remains unchanged. Recommendation measurement remains
separate from PostHog. The October 28 native source automatically enables its
account-bound server setting after acknowledgement, with no Account toggle;
signals still require valid public exposure context and server eligibility.
This source change has not been uploaded by the current work.

Production APNs setup was completed in Safari on October 23 for
`gatherory-e4d8b` / `com.guide-systems.gatherory`, with the release owner's
explicit upload confirmation. Apple lists the existing key `KL2Y639363` as
**Sandbox & Production**, despite its “Gatherory Push Development” name. Its
existing `.p8` was reused in Firebase's production slot; Firebase now lists both
development and production entries with team `LW97NHT3JA`. No new key was
created or revoked, and no private key contents were added to source or logs.
Apple's exact Gatherory App ID also has Push Notifications enabled.

Build 4, uploaded before this configuration, had FCM disabled. The later build 5
distribution signature and provisioning profile both verify the production APNs
entitlement; actual TestFlight push delivery remains a device acceptance check.
Current server code
uses [one best-effort attempt after saving](../../../gatherory-web-app/docs/roadmaps/notifications-roadmap/04-best-effort-delivery.md);
the retry scheduler remains disabled. Production server credentials and actual
delivery have not been verified by this configuration change.

The last AdMob inspection (October 22) showed Gatherory Requires review.
Enabling the local flag does not establish app approval, ad fill or revenue.
See [advertising setup](explore-advertising.md) for provider/device checks and
[Google's test-ad guidance](https://developers.google.com/admob/ios/test-ads)
for testing interactions without live advertising traffic.

The release owner reports the previous invalid-frame warning is resolved.
Remaining user journeys will be evaluated through the beta; this is not a claim
that all production/device checks passed. This configuration change did not
upload a build; the subsequent build 5 upload and current processing status are
recorded above. Verification for this change is recorded in
[testing verification](testing-verification.md).

## AdMob pre-release setup — October 22, 2026

The AdMob account is approved, but Gatherory still Requires review and has no
public store listing linked. European/US privacy messages and publisher website
files are prepared; production IDs are configured behind disabled Release ads.
Debug uses Gatherory's app ID with Google's native test unit for consent testing.
See [advertising setup and acceptance gates](explore-advertising.md) before changing
Release enablement or submitting privacy/age-rating answers. This setup did not
upload a native build, submit App Store answers or establish device ad acceptance.

## Current mobile V1 checkpoint — October 21, 2026

Use the [guest and invitation audit](../../../gatherory-web-app/docs/release/mobile-v1-guest-invitation-audit.md)
for the current source/recovery changes, non-UI evidence, and outstanding
release gates. Guest mode, announcements, native media transfer, reusable QR
invitations, and CSV exports have advanced beyond the older build notes below.
No deployment, App Store Connect inspection, Release archive, or device
acceptance is implied by those local implementations.

Historical sync-route failures, media-transfer deferrals, reviewer-account
status, and dated TestFlight review states below must be revalidated against
the intended backend and candidate build. They are not a current defect list.

This document is the release owner’s checklist and the source for Gatherory’s
App Review notes. Do not commit real review credentials here. Enter them only
in App Store Connect and keep the canonical copy in the team password manager.

Apple expects a complete build, live backend services, working links, and an
active demo account or an approved fully featured demo mode for apps that need
sign-in. See [App Review Guideline 2.1](https://developer.apple.com/app-store/review/guidelines/#performance),
[Providing information for a complete review](https://developer.apple.com/help/app-review/before-submitting-for-review/complete-review),
and [Apple’s App Review overview](https://developer.apple.com/app-store/review/).

## TestFlight build 4 — October 21, 2026

- Version **1.0 (4)** was archived from source commit `c766f14c` plus the build
  number increment, signed for Guide Systems LLC (`LW97NHT3JA`), and uploaded
  successfully to the existing Gatherory App Store Connect app. Apple accepted
  the package for processing at 12:36 PM America/Detroit. App Store Connect was
  then verified in the release owner's Safari session: build 4 shows **Testing**
  for both existing Friends & Family and External Friends & Family groups.
  Testing notes cover guest/account handover, shared to-dos, update audiences,
  reusable QR invitations, CSV exports, offline edits, and account isolation.
  Automatic tester notification remains enabled.
- The archive targets iOS 26.0, uses `https://app.gatherory.com`, and disables
  development seeding and sign-in bypass. Existing Release telemetry is retained.
  **FCM remains disabled in Release**, so this candidate does not test push
  notifications. Production APNs/FCM enablement remains a separate release gate.
- All **892 non-UI tests across 126 suites** passed. UI tests were excluded.
  Localization checks passed for 1,500 English/Spanish strings; deployment-target
  checks passed for all app and test configurations.
- The archive is retained outside the repository in Xcode's local Archives
  directory. Build/upload/test logs are in `/tmp/gatherory-testflight-1.0-4-*`.
  No backend deployment, database migration, Git commit, or public App Store
  submission was performed. Physical-device and backend rollout checks from the
  linked audit remain outstanding.

## Historical source compatibility baseline — October 15, 2026

The current source targets iOS/iPadOS 26 or later for iPhone and iPad. Music
selection and audio-session APIs introduced in iOS 27 have guarded iOS 26
fallbacks. See [compatibility verification](testing-verification.md#ios-26-compatibility--october-15-2026)
for the build/test evidence and outstanding iOS 26 runtime checks.

This does not change the already-uploaded version 1.0 (3), which was built with
an iOS 27 minimum. Distributing iOS 26 support requires a new, incremented build;
no replacement TestFlight upload is part of this source change.

## Historical TestFlight verification — October 14, 2026

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

## Historical submission checklist — revalidation required

Revalidate these dated items alongside the current checkpoint before submission.
Do not treat an old verified item as current evidence, or an old missing-source
item as proof that the current code lacks that feature.

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
| Required | Export compliance | Answered for build 6 in App Store Connect; no declaration key in the project. | Reassess when encryption usage changes. Add `ITSAppUsesNonExemptEncryption` only after confirming the correct answer. See [Apple’s encryption documentation guidance](https://developer.apple.com/help/app-store-connect/manage-app-information/determine-and-upload-app-encryption-documentation). |
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
