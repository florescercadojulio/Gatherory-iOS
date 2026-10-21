# Mobile collaboration notifications (local proof of concept)

FCM transports assignment, exact-event change, and explicit announcement notifications. Better Auth and
device guest proofs remain Gatherory's identity system. No Firebase Auth,
personal reminder scheduling, browser push, or analytics integration is added.

## Explicit announcements

The iPhone event Home, Manage and invitation open the same **Updates** screen.
One composer has a **To** segmented selector: **All**, **Planning**, **Guests**.
It defaults to Planning when available, and every message displays its audience.
Hosts with exact-event manage permission can choose all three; collaborators
with manage/contribute can send only to Planning. View-only planners and guests
cannot send. Planning messages are private to hosts/collaborators. Guests
messages are visible to guests and overseeing hosts, but only guest roles receive
their alerts. All messages are visible to both groups. Server history filtering
and dispatch revalidation enforce this policy; it is not a client-only filter.
Completed, finished, cancelled and archived events cannot send.

Sending requires a connection, a message of up to 750 Unicode characters and an
explicit Send. Earlier planning notes remain private history within this same
screen, using their original persistence and sync records. They are never
converted, resent or disclosed to invitation projections. Device-local guest
planning retains its private Planning-only Save path through the original note
store, with device-only/no-notification help; it does not call announcement APIs.

`Features/Announcements` owns the cookieless account/guest transport, memory-only
list/draft, generation-guarded controller and native composer. Failed explicit
sends reuse the same request ID for the same message and audience while this screen remains open, including after
composer dismissal. Closing the Updates screen or terminating the app does not
persist its draft. Refresh, ordinary sync and reconnection never send messages.
Changing the message or audience explicitly starts a different request. New
server announcement content never enters offline planning archives or blueprints.

The server commits the message and notification intents together, then the
existing dispatcher delivers generic localized push text. A tap refreshes event
access before fetching the authorized Updates list. Payload text never supplies
the message. The sender receives no self-notification; recipients need their
existing per-identity consent and valid installation. A server acknowledgement
means the update was saved, not that a phone displayed its push.

See the server [announcement handoff](../../../gatherory-web-app/docs/roadmaps/notifications-roadmap/02-event-announcements.md)
for the additive migration, API envelopes, exact permissions, tests and remaining
physical-device checks. Neither repository has been deployed for this slice.
The approved existing device test established sign-in and basic push delivery;
announcement foreground/background/tap behavior still needs its own acceptance.

The original feature defaults were off in Debug and Release. The October 20
device setup below enables Debug locally; Release remains off. The account's
**Event and Task Notifications** setting and the guest's event-update setting ask for system
permission only after an explicit choice. The old inert `planningNotifications`
preference does not count as consent. Opt-in is scoped to the current identity
on this device; a guest's choice is not transferred automatically on sign-in.

The app uses only the FirebaseMessaging product, pinned to Firebase Apple SDK
12.19.2. Firebase 13 currently conflicts with this app's Google Sign-In 9.x
package dependencies. Keep the compatible pin until both can be upgraded and
verified together. SwiftPM may resolve other Firebase targets, but the app does
not link Firebase Analytics or Firebase Auth.

The pinned SDK deprecates token retrieval in favor of Firebase Installation ID
registration. These are different delivery targets: `register(completion:)`
requires `FirebaseMessagingInstallationIdEnabled=YES` and does not return an FCM
registration token. The current server sends `message.token`, so the app retains
token mode. `FirebaseTokenCompatibility` isolates the one intentional legacy call
with a narrowly scoped Objective-C deprecation suppression; Swift callers share
the same token provider. Other compiler warnings remain enabled. Folder
synchronization includes the adapter, and Debug/Release xcconfigs specify its
bridging header. Migrating to Installation ID targeting remains separate work;
do not substitute an Installation ID into the server's token field.

Compatibility verification on October 20: the app and test target build with no
`token(completion:)` deprecation diagnostics; the focused notification controller
and navigation run passes **12 non-UI tests in 2 suites**. Localization checks
still pass for **1,432 English/Spanish strings**. Log:
`/tmp/gatherory-fcm-token-compatibility-20261020.log`. No UI tests, live push send,
commit, deployment or package-version change was made for this repair.

## Test configuration

Enable `FCM_NOTIFICATIONS_ENABLED=YES` only in an intended test build, add a real
Firebase `GoogleService-Info.plist` matching this target's bundle identifier,
enable Push Notifications provisioning, and configure the APNs key in Firebase.
The build settings provide development/production APS environment values; those
values alone do not provision Apple push. The local SDK plist is now downloaded
and ignored by Git; server credentials remain outside the native app and Git.
Firebase Messaging auto-init starts disabled; explicit consent
enables registration.

Registering `/api/notifications/installations` uses either the current account
bearer or device guest headers, never both. A separate device-only Keychain
installation ID/secret and persistent revision protect rebindings and detach.
Disable, sign-out, or guest removal sends an installation-proof detach before
identity cleanup. A retained pending-detach marker allows recovery after a crash
or failed request. Offline logout cannot recall a push already submitted to APNs.

Push text is generic. Foreground alerts validate the active recipient and
refresh canonical state. Taps refresh through the current account/guest transport
and open only an accessible exact event; assignment taps additionally require
the unfinished task to remain assigned to the current planner, then open that
event's To-dos. Failed refresh does not navigate using an old cached permission.
No payload URL is opened and no push writes planning data.

See the server repository's
[FCM proof-of-concept guide](../../../gatherory-web-app/docs/roadmaps/notifications-roadmap/01-fcm-proof-of-concept.md)
for service boundaries, migration and dispatcher setup, and the shared device
acceptance checks. Server dispatch is manual in this slice; enabling the client
setting alone does not schedule delivery.

## Acceptance still needed

Test on physical devices with valid credentials: permission denial/re-enable,
foreground/background/terminated launch, token refresh/reinstall, sandbox and
production APNs profiles, Spanish/English text, account switching during delayed
requests, offline logout, guest-to-account claim, task reassignment/completion,
and event access removal. Confirm the push opens the correct event/To-dos without
revealing parent/sibling plans. Simulator and mocked non-UI tests do not prove
APNs/FCM delivery. No UI tests, build upload or deployment are authorized here.

## Device setup progress — October 20, 2026

- Firebase CLI/plugin authenticated; user selected the existing **Gatherory**
  project `gatherory-e4d8b` (project number `221925876535`).
- Registered iOS app `1:221925876535:ios:3968ff28092ee855d3f0b2`, bundle ID
  `com.guide-systems.gatherory`. Xcode's Apple team is `LW97NHT3JA`.
- Retrieved SDK configuration through the Firebase plugin into
  `Gatherory/GoogleService-Info.plist`. Folder synchronization includes the
  resource; `git check-ignore` confirms it is not tracked. Existing Google
  Sign-In client settings were retained.
- Debug enables FCM and uses development APNs. Release keeps FCM disabled.
  App xcconfigs now include inherited linker flags plus `-ObjC`; the existing
  exact Firebase 12.19.2 package pin and project targets are preserved.
- Debug simulator build passed. The built app's configuration was verified as
  `gatherory-e4d8b` and `FCM_NOTIFICATIONS_ENABLED=YES`. Evidence:
  `/tmp/gatherory-firebase-config-build-verified-20261020.log`.
- Repaired the app target's missing `FirebaseMessaging` package-product
  dependency. The existing Frameworks entry and Firebase 12.19.2 pin were
  retained. Pinned package resolution and a generic iOS Debug build with signing
  disabled passed; this build does not prove device provisioning or delivery.
  Evidence: `/tmp/gatherory-fcm-package-resolution-20261020.log` and
  `/tmp/gatherory-fcm-device-build-repair-20261020.log`.
- User uploaded development APNs key `KL2Y639363`, Apple team `LW97NHT3JA`;
  Firebase settings visibly confirm it. Production APNs remains unconfigured.
- Server credentials are configured in the server repo's ignored `.env.local`;
  Google accepted the Messaging-scope OAuth exchange. The temporary Gatherory-only
  key-creation exception was restored to inherited enforcement after download.
- Verified the Debug HTTPS origin reaches the notification registration route.
  The server's configured local PostgreSQL database now has both notification
  migrations applied, without a reset or seed.
- Still pending: Apple Push Notifications provisioning for this bundle ID,
  physical-device registration and actual phone delivery. No Firebase Auth,
  database or Hosting service was initialized.
  No deployment, build upload, commit or push occurred.

Next user step: run the Debug app on the iPhone, enable its notification setting
and allow the iOS prompt. Use another signed-in planner to assign a to-do to the
iPhone user or change an existing shared event's time/location, let sync finish,
then manually dispatch from the configured local server as described in the
server guide. Verify foreground/background/tap behavior. A development APNs key
is for this Debug test, not a claim that Release/production APNs is configured.
