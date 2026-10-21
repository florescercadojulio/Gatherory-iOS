# Gatherory authentication integration contract

This document records the authentication contract shared by the iOS app,
`gatherory-web-app`, and the public landing site. It is intentionally free of
credentials and provider secrets.

## Existing foundation

`gatherory-web-app` is the source of truth for identity. It already configures
Better Auth with PostgreSQL and Drizzle and mounts the handler at
`/api/auth/*`. Its current server supports:

- email and password accounts with required email verification;
- password reset, email OTP, and magic-link email delivery;
- Google and Apple providers when their environment credentials are present;
- sessions, accounts, verification records, organizations, memberships,
  invitations, and organization teams.

The public site is `https://gatherory.com`. Its privacy policy, Terms, and
Support URLs have been verified manually for the release handoff.

The application/authentication origin is `https://app.gatherory.com`. The web
app is deployed and Apple web sign-in has been verified manually. The archived
iOS build still needs an end-to-end production-origin check before submission.

## Stable identity

The Better Auth `user.id` string is the canonical Gatherory user ID. Native
code must not create a second UUID identity for a signed-in account.

Every remotely synchronized workspace needs an immutable `ownerUserID`, and
membership should be represented by the backend organization/member records.
Local SwiftData rows should be queried through the authenticated account scope
so signing out or switching accounts cannot expose another account's data.

Legacy unowned local data must not be silently assigned to the first person
who signs in. The explicitly chosen device guest path below uses its own
namespace and a retry-safe handover when the guest signs in to save their plans.

## Device guest mode — October 20, 2026

Implemented locally for the V1 candidate; server migration/deployment and physical
device acceptance remain pending. **Continue as Guest** asks for a recognizable
name and creates a separate `LocalGuestProfile`, never a `UserAccount` or Better
Auth anonymous session. Guests can plan locally and attend public guest-role
invitations. Sharing owned events and blueprint account controls require sign-in.

`DeviceLocalGuestProfileStore` holds the non-secret name/UUID in an app-private
file. A separate device-only Keychain proof authenticates only `/api/guest/*`.
It is never a Better Auth bearer. The native transport uses a cookieless ephemeral
session and rejects cross-origin/credential-bearing redirects; HTTPS is required
except for loopback development.

Signing in to save flushes guest edits before replacing the account session.
Account bootstrap precedes additive local import. A durable target-account
receipt and retained source prevent replacement, duplicate imports and cross-account
retry. Local Decide response IDs/authorship are rebuilt for the real account.
The server then claims exact-event guest attendance using both independent
credentials and a verified account. Existing account RSVP/roles and explicit
leave decisions win. No planner/organization membership is granted by the claim.
Only after successful local import and server claim does native cleanup remove
the source/profile/proof. An interrupted handover stays bound to that account;
the old guest source cannot continue being edited and diverge from its imported
copy. An unreadable profile can be retried without replacing its identity.

**Leave Guest Mode** warns about losing device-only plans and cached invitations,
and offers Sign In to Save, explicit Remove from This Device, or cancellation.
It does not silently revoke attendance or remove the host's history. Normal
signed-in sign-out retains its existing draft/recovery behavior.

V1 invitation wording is **Attend as Guest** for public guest invitations and
**Sign In to Help Plan** for collaborator invitations that permit editing.
View-only invitations use **Sign In to View Plans**. Host sharing explains
those boundaries and email-bound invitations still require the invited account.
Guest sign-in explains that guest information will be kept. The native preview
uses the real bearer only after sign-in to resolve private invitations and
existing membership; guest previews remain unauthenticated. An existing attendee
is not promoted to a planner by signing in or opening a forwarded planning link.

Private/email-bound and planner invitations continue to require real sign-in.
Invited-event caches remain projections, separate from locally owned plans and
planner synchronization. Offline RSVP is not shown as sent without acknowledgement.
See the web repository's
[guest handoff](../../../gatherory-web-app/docs/roadmaps/v1-guest-release-candidate-roadmap/01-device-guest-mode.md)
for the API contract and remaining acceptance checks. Browser guest RSVP remains
outside this native slice.

## Native session transport

Gatherory uses Better Auth bearer sessions for the native client. The iOS
client accepts the session token from Better Auth's `set-auth-token` response
header or documented JSON token field, stores it in Keychain, and sends it as
`Authorization: Bearer <token>`. It is never stored in `UserDefaults` or
SwiftData. The app uses an ephemeral, cookieless `URLSession`, so web cookies
cannot accidentally become the native authentication boundary.

Do not infer authentication from a locally cached profile. The server session
is authoritative. On launch, restore the credential, validate it with Better
Auth, and only then open that user's data scope. A network or secure-storage
failure shows retryable restoration recovery while retaining the credential
and isolated archives. Confirmed expiry/absence shows authentication. This
implementation does not manufacture offline authentication from a cached
profile. An already prepared account continues using its existing offline
data and outbox behavior.

## Entry routing and preparation — October 20, 2026

`AuthenticationFlowChain` is a pure Chain of Responsibility: each ordered
handler either selects a destination or passes to the next handler. Screen
routing is separate from `SessionPreparationCoordinator`, which owns the
observable `idle` / `preparing` / `ready` / `recovery` phases. Preparation
captures a typed account/guest identity and checks its generation, current
identity, and cancellation after suspension. Old A → B → A completions cannot
publish readiness or clean up another session's retained guest source.

`LiveSessionPreparationServices` connects the existing persistence, sync,
guest claim, invitation, and notification boundaries. `SessionLifecycleActions`
installs the common save-before-authentication and exit hooks. The launch view
renders destinations and supplies user actions. New checks belong in a routing
handler; new asynchronous preparation belongs in the coordinator/services.
Routing handlers must not perform network requests, delete data, or grant
permissions.

Onboarding uses the active account's onboarding state and positive account cache;
the device-global completion flag no longer selects the next screen. The
session-only QA override is tied to the active identity. Guest handover persists
its exact target account after import and attendance claim succeed. Relaunch can
finish local cleanup for that account without recreating or reusing a removed
guest proof. Explicit guest removal persists its discard marker before cleanup,
so relaunch resumes its recovery gate if archive/cache cleanup already
succeeded. Wrong-account preparation and guest editing stay blocked until the
matching cleanup completes.

The regression suites cover restoration retry/expiry, provider save gates,
guest source/proof retention, preparation ordering, cancellation, account round
trips, and real in-memory persistence through the installed lifecycle hooks.
No automated UI tests are included. See the shared
[mobile lifecycle design](../../../gatherory-web-app/docs/architecture/mobile-session-lifecycle.md)
for the state/retention table and remaining physical-device checks.

## Sign-in flows

### Email and password

- Sign in through Better Auth's email endpoint.
- Sign up through the email endpoint and preserve the existing required-email-
  verification behavior.
- Surface verification and password-reset flows instead of mapping every
  server response to “invalid password.”

### Sign in with Apple

- Add the Sign in with Apple capability to the iOS App ID, entitlements, and
  distribution profile.
- Use `ASAuthorizationAppleIDCredential` on device and send the returned
  identity token to Better Auth's social sign-in endpoint.
- Configure Better Auth with the native bundle identifier
  `com.guide-systems.gatherory` as an accepted Apple audience in addition to
  the web Services ID where applicable.
- Capture Apple's name and relay email on the first authorization. Apple may
  not return them on later authorizations.
- Use a production Apple client secret with an established rotation process;
  do not embed it in the app.

### Google

- Use Google's native iOS authorization flow to obtain an ID token.
- Send the ID token to Better Auth's social sign-in endpoint. Provider client
  secrets remain on the server.
- Register the production iOS bundle identifier and URL scheme in the Google
  provider configuration.

## Account lifecycle

Better Auth hard deletion is enabled. The web account page and authenticated
iOS Account view both require an explicit destructive confirmation and call the
same Better Auth endpoint. Better Auth requires a fresh session; an older
session is asked to sign in again instead of weakening that protection.

Before deleting the Better Auth user, the server deletes sole-owner workspaces,
transfers a collaborative workspace to its oldest remaining member, removes
the departing user's uploaded media from R2, and relies on foreign-key actions
to remove participation, decisions, commitments, sessions, and provider
accounts. Historical content retained for collaborators clears its author ID.
The iOS client then clears the Keychain token and purges SwiftData workspaces,
outbox entries, checkpoints, inbox receipts, and pending media files for that
exact account ID. Other account caches, device guest sources/proofs, and legacy
unowned records remain isolated and intact.

### Retryable device cleanup after deletion — October 20, 2026

Account deletion writes an account-scoped local cleanup intent before the
remote request, suspends/joins sync without uploading queued changes, then
records the server's confirmation. `AccountDeletionCleanupCoordinator` keeps
that record until every local cleanup and final journal removal succeed.
`AccountDeletionLocalCleanup` attempts independent stores even when another
store fails. `AccountView` no longer decides which mutable active namespace
to purge or sequences cache removal itself.

Confirmed cleanup retries on launch before credential restoration, planning
scope activation, guest import, link routing, or notification binding. It
never calls the account-deletion endpoint again, restores an account, or
uploads removed data. Failures show **Finishing Device Cleanup** with Retry.
Unreadable journals stay blocked rather than being replaced. An unavailable
real SwiftData store cannot be reported clean by an ephemeral fallback.

Explicit server rejection retains the account and device records. A lost
response or an app interruption before confirmation leaves `awaitingConfirmation`;
it does not authorize automatic data removal. That rare state offers a separate
explicit **Remove from This Device** confirmation. Its durable
`deviceRemovalConfirmed` phase authorizes local cleanup only and never claims
the server account was deleted or repeats the remote request.

Cleanup covers exact-owner SwiftData entities and media transfer files,
invitation cache, image safety preferences, saved blueprint drafts, installation
intents, used/personal library caches, hidden/collection/recent preferences,
share-link Keychain credentials, onboarding and notification preferences, and
the deleted session credential. Media removal failures retain transfer rows
for retry, and a file referenced by another namespace stays in place. The
device notification installation secret/revision is retained for future safe
detach/rebind operations. A retry for an inactive deleted account does not clear
the active account's graph or credential.

The cleanup journal contains only the captured canonical account ID and phase;
it uses a protected atomic app-private file. Account/provider secrets, bearer
tokens, and event content are never written to it. The live bootstrap uses the
disk journal; test/fixture sessions use an isolated memory journal unless one
is injected explicitly.

Sign out clears the credential and closes the active user data scope. It must
not delete server data or make another account's locally cached data visible.

### Non-UI lifecycle regression coverage

`AuthenticationLifecycleTests` uses injected in-memory profile/credential stores
and an authentication client to exercise retention across session restoration,
authentication, and sign-out. An unsuccessful restoration leaves the guest
profile and attendance proof available for retry. A restored account with guest
data waits for import before acquiring its notification principal. Failed final
sync retains both the account session and guest import source; a successful
sign-out retains unfinished guest data for recovery.

The same suite checks that email sign-in, registration, Apple, and Google all
save guest edits before calling the authentication client. A failed save blocks
each entry point without changing the guest identity or contacting sign-in.
`GuestAuthenticationTests` separately covers explicit guest removal and durable
import completion, while `OfflineSyncTests` covers account-scoped workspace and
outbox retention. These tests do not replace physical-device checks for provider
callbacks, process termination during import, or Keychain/file access failures.

## Backend-to-local data sequence

Use this order when real-user sync work begins:

1. Deploy and health-check the production Better Auth origin.
2. Enable the Better Auth bearer plugin and native Apple bundle audience.
3. Configure the iOS environment URL and Keychain-backed native session client.
4. Use the canonical Better Auth string ID in the iOS account model.
5. Add `ownerUserID` and account scope to the versioned SwiftData schema, with
   migration tests.
6. Open the local store only after the session resolves to a user scope.
7. Add the authenticated user/workspace identifiers to every outbox envelope.
8. Connect sync transport, keeping idempotency and tombstone semantics already
   established by the local outbox.
9. Test sign-out, account switching, offline relaunch, token expiry, password
   reset, provider revocation, deletion, and TestFlight upgrade paths.

Steps 2–8 and account deletion are implemented in source. The production web
app is deployed, and email, Apple, and Google authentication have been
exercised by QA. Debug defaults to production-like account behavior against
`https://dev.gatherory.com`, supports a temporary `-AuthenticationBaseURL`
launch override, and Release points to `https://app.gatherory.com`. Email/password registration,
sign-in, session restoration, sign-out, and native provider token exchange all
use the Better Auth client. The native data-sync contract now authorizes
workspace access through Better Auth organization membership and
transactionally materializes native entities into the normalized product
tables. End-to-end collaboration still requires a two-account release test,
and separate S3 media transfer remains follow-up work.

Debug now sets `SIMULATE_PRODUCTION_FLOW = YES` by default. Use the
`-DisableProductionFlowSimulation` launch argument only for deliberate fixture
or UI work. Production-flow simulation forces real accounts, disables fixture
authentication and development seeding, and resolves first-run onboarding from
the authenticated user's web-app database record while preserving Debug's
configurable `AUTH_BASE_URL`. `-AlwaysShowOnboarding` remains an explicit UI/QA
override even when production-flow simulation is enabled. The
Release build always uses production behavior directly; it never reads this
simulation switch.

The account's server-owned `hasCompletedOnboarding` field is authoritative in
production-like flows. Native bootstrap returns it with the user's workspace
snapshots. iOS waits for that authenticated response before choosing onboarding
or the workspace browser, caches only a positive result per user for offline
relaunch, and never uses the old device-global onboarding preference to decide
another account's state. Creating a workspace through either web or native sync
sets the account field. Existing accounts with a main event or a native
workspace snapshot are backfilled by the database migration.

## Production and App Review checklist

- `https://app.gatherory.com` resolves and its auth health check succeeds.
- Email delivery uses a verified production sender.
- Apple and Google production credentials and callback URLs are configured.
- Privacy, Terms, and Support URLs return successful responses when signed out.
- The iOS Release build contains only working sign-in methods.
- A dedicated, email/password App Review account is verified and does not
  require an employee-controlled OTP or second factor.
- Account deletion works end to end from inside the app.
- App Review credentials are stored only in App Store Connect and the team's
  password manager, never in this repository.

## References

- [Better Auth bearer sessions](https://better-auth.com/docs/plugins/bearer)
- [Better Auth Apple provider](https://better-auth.com/docs/authentication/apple)
- [Better Auth users and accounts](https://better-auth.com/docs/concepts/users-accounts)
- [Better Auth session management](https://better-auth.com/docs/concepts/session-management)
- [Apple account-deletion requirement](https://developer.apple.com/help/app-review/guideline-reference/5-1-1-account-deletion)

