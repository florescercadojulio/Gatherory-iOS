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

Existing anonymous/local data must not be silently assigned to the first
person who signs in. Present an explicit import/claim choice, or leave that data
in a separate local-only scope.

## Native session transport

Gatherory uses Better Auth bearer sessions for the native client. The iOS
client accepts the session token from Better Auth's `set-auth-token` response
header or documented JSON token field, stores it in Keychain, and sends it as
`Authorization: Bearer <token>`. It is never stored in `UserDefaults` or
SwiftData. The app uses an ephemeral, cookieless `URLSession`, so web cookies
cannot accidentally become the native authentication boundary.

Do not infer authentication from a locally cached profile. The server session
is authoritative. On launch, restore the credential, validate it with Better
Auth, and only then open that user's data scope. When offline, the UI may show
the last validated user and their local data, but must clearly preserve the
same user boundary and must not accept a different account until online
validation completes.

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
outbox entries, checkpoints, inbox receipts, and pending media files.

Sign out clears the credential and closes the active user data scope. It must
not delete server data or make another account's locally cached data visible.

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

