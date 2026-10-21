import Foundation
import Testing
@testable import Gatherory

struct AuthenticationLifecycleTests {
    @Test("Session restore failures preserve the guest identity and proof for a later account handover")
    @MainActor
    func restorationRetainsPendingGuestData() async throws {
        let profile = LocalGuestProfile(displayName: "Morgan")
        let profiles = MemoryLocalGuestProfileStore()
        try profiles.save(profile)
        let credentials = MemoryLocalGuestCredentialStore()
        let proof = try credentials.loadOrCreateToken(profileID: profile.id)
        let client = LifecycleAuthenticationClient()
        client.restoreFailure = .networkUnavailable
        let auth = makeSession(client: client, profiles: profiles, credentials: credentials)

        await auth.restoreSession()

        #expect(auth.isGuestMode)
        #expect(!auth.isProcessing)
        #expect(auth.localGuestProfile == profile)
        #expect(profiles.profile == profile)
        #expect(credentials.tokens[profile.id] == proof)
        #expect(auth.notificationPrincipal == nil)

        client.restoreFailure = nil
        await auth.restoreSession()

        #expect(auth.currentUser?.id == LifecycleAuthenticationClient.user.id)
        #expect(auth.hasPendingGuestImport)
        #expect(auth.localGuestProfile == profile)
        #expect(profiles.profile == profile)
        #expect(credentials.tokens[profile.id] == proof)
        #expect(auth.notificationPrincipal == nil)
    }

    @Test("Signing out before guest import finishes retains its source and releases processing guards")
    @MainActor
    func signOutRetainsUnfinishedGuestImport() async throws {
        let profile = LocalGuestProfile(displayName: "Morgan")
        let profiles = MemoryLocalGuestProfileStore()
        try profiles.save(profile)
        let credentials = MemoryLocalGuestCredentialStore()
        let proof = try credentials.loadOrCreateToken(profileID: profile.id)
        let client = LifecycleAuthenticationClient()
        let auth = makeSession(client: client, profiles: profiles, credentials: credentials)
        await auth.restoreSession()
        auth.prepareForSignOut = { _ in throw AuthenticationFailure.networkUnavailable }

        #expect(await auth.signOut() == false)
        #expect(auth.currentUser?.id == LifecycleAuthenticationClient.user.id)
        #expect(auth.hasPendingGuestImport)
        #expect(auth.signOutNeedsAttention)
        #expect(!auth.isProcessing)
        #expect(!auth.isSigningOut)
        #expect(client.signOutCalls == 0)
        #expect(profiles.profile == profile)
        #expect(credentials.tokens[profile.id] == proof)
        #expect(auth.notificationPrincipal == nil)

        var retainedPendingChanges: Bool?
        auth.prepareForSignOut = { retainedPendingChanges = $0 }

        #expect(await auth.signOut(keepingPendingChanges: true))
        #expect(retainedPendingChanges == true)
        #expect(client.signOutCalls == 1)
        #expect(auth.currentUser == nil)
        #expect(!auth.signOutNeedsAttention)
        #expect(!auth.isProcessing)
        #expect(!auth.isSigningOut)
        #expect(auth.localGuestProfile == profile)
        #expect(profiles.profile == profile)
        #expect(credentials.tokens[profile.id] == proof)

        let relaunched = makeSession(client: client, profiles: profiles, credentials: credentials)
        await relaunched.restoreSession()
        #expect(relaunched.currentUser == nil)
        #expect(relaunched.localGuestProfile == profile)
        #expect(credentials.tokens[profile.id] == proof)
    }

    @Test("Guest removal stays in recovery after teardown or profile removal fails and retries cleanup")
    @MainActor
    func incompleteGuestRemovalRequiresRecovery() async throws {
        let profile = LocalGuestProfile(displayName: "Morgan")
        let profiles = MemoryLocalGuestProfileStore()
        try profiles.save(profile)
        let credentials = MemoryLocalGuestCredentialStore()
        let proof = try credentials.loadOrCreateToken(profileID: profile.id)
        let auth = makeSession(client: LifecycleAuthenticationClient(), profiles: profiles, credentials: credentials)
        var cleanupAttempts = 0
        var activeScope: String? = profile.storageID
        var hasGuestArchives = true
        auth.prepareForGuestDiscard = { requestedProfile in
            #expect(requestedProfile == profile)
            #expect(auth.guestDiscardNeedsAttention)
            cleanupAttempts += 1
            if cleanupAttempts == 1 { throw AuthenticationFailure.guestDataUnavailable }
            // Cleanup is idempotent: a retry must also work after these are gone.
            activeScope = nil
            hasGuestArchives = false
        }
        #expect(!auth.guestDiscardNeedsAttention)

        await #expect(throws: AuthenticationFailure.guestDataUnavailable) {
            try await auth.discardGuestSession()
        }
        #expect(auth.guestDiscardNeedsAttention)
        #expect(!auth.isProcessing)
        #expect(activeScope == profile.storageID)
        #expect(hasGuestArchives)
        #expect(auth.localGuestProfile == profile)

        profiles.failRemove = true
        await #expect(throws: CocoaError.self) { try await auth.discardGuestSession() }
        #expect(auth.guestDiscardNeedsAttention)
        #expect(!auth.isProcessing)
        #expect(activeScope == nil)
        #expect(!hasGuestArchives)
        #expect(auth.localGuestProfile == profile)
        #expect(profiles.profile == profile)
        #expect(credentials.tokens[profile.id] == proof)

        profiles.failRemove = false
        try await auth.discardGuestSession()

        #expect(cleanupAttempts == 3)
        #expect(!auth.guestDiscardNeedsAttention)
        #expect(!auth.isProcessing)
        #expect(auth.localGuestProfile == nil)
        #expect(profiles.profile == nil)
        #expect(credentials.tokens[profile.id] == nil)
        #expect(auth.notificationPrincipal == nil)
    }

    @Test("Every account entry point saves guest edits before contacting authentication", arguments: LifecycleEntryPoint.allCases)
    @MainActor
    func guestSavePrecedesAuthentication(entryPoint: LifecycleEntryPoint) async throws {
        let profile = LocalGuestProfile(displayName: "Morgan")
        let profiles = MemoryLocalGuestProfileStore()
        try profiles.save(profile)
        let credentials = MemoryLocalGuestCredentialStore()
        let proof = try credentials.loadOrCreateToken(profileID: profile.id)
        let client = LifecycleAuthenticationClient()
        let auth = makeSession(client: client, profiles: profiles, credentials: credentials)
        auth.prepareForGuestAuthentication = {
            client.events.append("save")
            throw AuthenticationFailure.guestDataUnavailable
        }

        await #expect(throws: AuthenticationFailure.guestDataUnavailable) {
            try await entryPoint.authenticate(auth)
        }
        #expect(client.events == ["save"])
        #expect(auth.currentUser == nil)
        #expect(auth.localGuestProfile == profile)
        #expect(!auth.isProcessing)
        #expect(profiles.profile == profile)
        #expect(credentials.tokens[profile.id] == proof)

        client.events.removeAll()
        auth.prepareForGuestAuthentication = { client.events.append("save") }
        try await entryPoint.authenticate(auth)

        #expect(client.events == ["save", entryPoint.rawValue])
        #expect(auth.currentUser?.id == LifecycleAuthenticationClient.user.id)
        #expect(auth.hasPendingGuestImport)
        #expect(profiles.profile == profile)
        #expect(credentials.tokens[profile.id] == proof)
        #expect(auth.notificationPrincipal == nil)
    }

    @MainActor
    private func makeSession(
        client: LifecycleAuthenticationClient,
        profiles: MemoryLocalGuestProfileStore,
        credentials: MemoryLocalGuestCredentialStore
    ) -> AuthenticationSession {
        AuthenticationSession(
            environment: .production,
            skipsAuthentication: false,
            client: client,
            guestProfileStore: profiles,
            guestCredentialStore: credentials
        )
    }
}

enum LifecycleEntryPoint: String, CaseIterable, Sendable {
    case email, registration, apple, google

    @MainActor
    func authenticate(_ auth: AuthenticationSession) async throws {
        switch self {
        case .email:
            try await auth.signIn(email: "morgan@example.com", password: "test-password")
        case .registration:
            try await auth.register(displayName: "Morgan", email: "morgan@example.com", password: "test-password")
        case .apple:
            try await auth.signInWithApple(
                AppleIdentity(identityToken: "test-identity", authorizationCode: "test-code", nonce: "test-nonce",
                              email: nil, givenName: nil, familyName: nil),
                requestingSignUp: false
            )
        case .google:
            try await auth.signInWithGoogle(identityToken: "test-identity", nonce: "test-nonce", requestingSignUp: false)
        }
    }
}

@MainActor
private final class LifecycleAuthenticationClient: AuthenticationClient {
    static let user = UserAccount(
        id: "lifecycle-account", email: "morgan@example.com", displayName: "Morgan",
        role: .member, authenticationProvider: .password, createdAt: .distantPast
    )
    var restoreFailure: AuthenticationFailure?
    var restoredUser: UserAccount? = LifecycleAuthenticationClient.user
    var events: [String] = []
    private(set) var signOutCalls = 0

    func restoreSession() async throws -> UserAccount? {
        if let restoreFailure { throw restoreFailure }
        return restoredUser
    }

    func signIn(email: String, password: String) async throws -> UserAccount {
        events.append("email")
        return Self.user
    }

    func register(displayName: String, email: String, password: String) async throws -> RegistrationOutcome {
        events.append("registration")
        return .authenticated(Self.user)
    }

    func signInWithApple(_ identity: AppleIdentity, requestingSignUp: Bool) async throws -> UserAccount {
        events.append("apple")
        return Self.user
    }

    func signInWithGoogle(identityToken: String, nonce: String, requestingSignUp: Bool) async throws -> UserAccount {
        events.append("google")
        return Self.user
    }

    func signOut() async {
        signOutCalls += 1
        restoredUser = nil
    }

    func deleteAccount() async throws {}
}
