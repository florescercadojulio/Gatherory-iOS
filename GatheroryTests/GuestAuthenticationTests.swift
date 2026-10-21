import Foundation
import Testing
@testable import Gatherory

struct GuestAuthenticationTests {
    @Test("Continue as guest restores a device identity without manufacturing an account")
    @MainActor
    func guestModeHasNoAuthenticatedUser() async throws {
        let stores = try makeStores()
        let auth = AuthenticationSession(
            environment: .production,
            skipsAuthentication: false,
            guestProfileStore: stores.profile,
            guestCredentialStore: stores.credentials
        )
        try auth.continueAsGuest(displayName: "  Morgan Lee  ")
        #expect(auth.currentUser == nil)
        #expect(!auth.isAuthenticated)
        #expect(auth.isGuestMode)
        #expect(auth.localGuestProfile?.displayName == "Morgan Lee")
        #expect(auth.notificationPrincipal == auth.localGuestProfile.map { .guest(id: $0.id) })
        #expect(stores.profile.profile == auth.localGuestProfile)

        let relaunched = AuthenticationSession(
            environment: .production,
            skipsAuthentication: false,
            guestProfileStore: stores.profile,
            guestCredentialStore: stores.credentials
        )
        await relaunched.restoreSession()
        #expect(relaunched.currentUser == nil)
        #expect(relaunched.isGuestMode)
        #expect(relaunched.localGuestProfile == auth.localGuestProfile)
    }

    @Test("Guest display names enforce Unicode-scalar limits and preserve an old profile on save failure")
    @MainActor
    func guestNameValidationAndSaveRollback() async throws {
        let stores = try makeStores()
        let original = LocalGuestProfile(displayName: "Morgan")
        try stores.profile.save(original)
        let auth = AuthenticationSession(
            environment: .production,
            skipsAuthentication: false,
            guestProfileStore: stores.profile,
            guestCredentialStore: stores.credentials
        )
        await #expect(throws: LocalGuestProfileStoreError.invalidProfile) {
            try auth.continueAsGuest(displayName: String(repeating: "🪻", count: 81))
        }
        await #expect(throws: LocalGuestProfileStoreError.invalidProfile) {
            try auth.continueAsGuest(displayName: " \n ")
        }
        stores.profile.failSave = true
        await #expect(throws: CocoaError.self) { try auth.continueAsGuest(displayName: "New name") }
        #expect(auth.localGuestProfile == original)
        #expect(stores.profile.profile == original)
    }

    @Test("An unreadable guest profile blocks replacement rather than creating a new identity")
    @MainActor
    func unreadableProfileDoesNotOverwriteGuestData() async throws {
        let stores = try makeStores()
        let original = LocalGuestProfile(displayName: "Morgan")
        try stores.profile.save(original)
        stores.profile.failLoad = true
        let auth = AuthenticationSession(
            environment: .production,
            skipsAuthentication: false,
            guestProfileStore: stores.profile,
            guestCredentialStore: stores.credentials
        )
        #expect(auth.guestStorageFailed)
        await #expect(throws: AuthenticationFailure.guestDataUnavailable) {
            try auth.continueAsGuest(displayName: "Different device guest")
        }
        #expect(stores.profile.profile == original)
        stores.profile.failLoad = false
        auth.retryGuestProfileLoading()
        #expect(!auth.guestStorageFailed)
        #expect(auth.localGuestProfile == original)
    }

    @Test("Failed sign in keeps the guest namespace and a successful sign in retains it for import")
    @MainActor
    func signInPreservesGuestUntilImportCompletes() async throws {
        let stores = try makeStores()
        let profile = LocalGuestProfile(displayName: "Morgan")
        try stores.profile.save(profile)
        let client = GuestAuthenticationTestClient()
        client.signInFailure = .invalidCredentials
        let auth = AuthenticationSession(
            environment: .production,
            skipsAuthentication: false,
            client: client,
            guestProfileStore: stores.profile,
            guestCredentialStore: stores.credentials
        )
        let proof = try stores.credentials.loadOrCreateToken(profileID: profile.id)

        await #expect(throws: AuthenticationFailure.invalidCredentials) {
            try await auth.signIn(email: "morgan@example.com", password: "wrong")
        }
        #expect(auth.currentUser == nil)
        #expect(auth.isGuestMode)
        #expect(stores.profile.profile == profile)
        #expect(try stores.credentials.loadOrCreateToken(profileID: profile.id) == proof)

        client.signInFailure = nil
        try await auth.signIn(email: "morgan@example.com", password: "password")
        #expect(auth.currentUser?.id == GuestAuthenticationTestClient.user.id)
        #expect(auth.hasPendingGuestImport)
        #expect(auth.localGuestProfile == profile)
        #expect(auth.notificationPrincipal == nil)

        stores.profile.failRemove = true
        await #expect(throws: CocoaError.self) { try auth.completeGuestImport() }
        #expect(auth.hasPendingGuestImport)
        #expect(stores.profile.profile == profile)
        #expect(try stores.credentials.loadOrCreateToken(profileID: profile.id) == proof)
        stores.profile.failRemove = false
        try auth.completeGuestImport()
        #expect(!auth.hasPendingGuestImport)
        #expect(auth.localGuestProfile == nil)
        #expect(stores.profile.profile == nil)
        #expect(stores.credentials.tokens[profile.id] == nil)
        #expect(auth.notificationPrincipal == .account(id: GuestAuthenticationTestClient.user.id))
    }

    @Test("A failed guest import hook blocks authentication while preserving local data")
    @MainActor
    func guestImportGateMustSucceedBeforeSignIn() async throws {
        let stores = try makeStores()
        let profile = LocalGuestProfile(displayName: "Morgan")
        try stores.profile.save(profile)
        let client = GuestAuthenticationTestClient()
        let auth = AuthenticationSession(
            environment: .production,
            skipsAuthentication: false,
            client: client,
            guestProfileStore: stores.profile,
            guestCredentialStore: stores.credentials
        )
        auth.prepareForGuestAuthentication = { throw AuthenticationFailure.guestDataUnavailable }
        await #expect(throws: AuthenticationFailure.guestDataUnavailable) {
            try await auth.signIn(email: "morgan@example.com", password: "password")
        }
        #expect(client.signInCalls == 0)
        #expect(auth.currentUser == nil)
        #expect(auth.localGuestProfile == profile)
    }

    @Test("Guest exit keeps local data when import or cleanup fails, and clears it only after cleanup")
    @MainActor
    func discardGuestRequiresSuccessfulLocalCleanup() async throws {
        let stores = try makeStores()
        let profile = LocalGuestProfile(displayName: "Morgan")
        try stores.profile.save(profile)
        let auth = AuthenticationSession(
            environment: .production,
            skipsAuthentication: false,
            guestProfileStore: stores.profile,
            guestCredentialStore: stores.credentials
        )
        let proof = try stores.credentials.loadOrCreateToken(profileID: profile.id)
        var discardCalls = 0
        auth.prepareForGuestDiscard = { _ in
            discardCalls += 1
            throw AuthenticationFailure.guestDataUnavailable
        }
        await #expect(throws: AuthenticationFailure.guestDataUnavailable) { try await auth.discardGuestSession() }
        #expect(discardCalls == 1)
        #expect(auth.localGuestProfile == profile)
        #expect(stores.profile.profile == profile)
        #expect(try stores.credentials.loadOrCreateToken(profileID: profile.id) == proof)

        stores.profile.failRemove = true
        auth.prepareForGuestDiscard = { _ in }
        await #expect(throws: CocoaError.self) { try await auth.discardGuestSession() }
        #expect(auth.localGuestProfile == profile)
        #expect(try stores.credentials.loadOrCreateToken(profileID: profile.id) == proof)

        stores.profile.failRemove = false
        try await auth.discardGuestSession()
        #expect(auth.localGuestProfile == nil)
        #expect(stores.profile.profile == nil)
        #expect(stores.credentials.tokens[profile.id] == nil)
    }

    @Test("Guest sign in prompt can be canceled without changing the local session")
    @MainActor
    func cancelGuestSignInPrompt() throws {
        let stores = try makeStores()
        let profile = LocalGuestProfile(displayName: "Morgan")
        try stores.profile.save(profile)
        let auth = AuthenticationSession(
            environment: .production,
            skipsAuthentication: false,
            guestProfileStore: stores.profile,
            guestCredentialStore: stores.credentials
        )
        auth.requestGuestSignIn()
        #expect(auth.isGuestSignInRequested)
        auth.cancelGuestSignIn()
        #expect(!auth.isGuestSignInRequested)
        #expect(auth.localGuestProfile == profile)
        #expect(auth.isGuestMode)
    }

    @Test("Planner invitation survives guest sign-in and stays pending until an accepted join")
    @MainActor
    func plannerInvitationRequiresExplicitAcceptedJoin() async throws {
        let stores = try makeStores()
        let profile = LocalGuestProfile(displayName: "Morgan")
        try stores.profile.save(profile)
        let client = GuestAuthenticationTestClient()
        let auth = AuthenticationSession(
            environment: .production,
            skipsAuthentication: false,
            client: client,
            guestProfileStore: stores.profile,
            guestCredentialStore: stores.credentials
        )
        let proof = try stores.credentials.loadOrCreateToken(profileID: profile.id)

        let domain = "guest-planner-invitation-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        let baseURL = try #require(URL(string: "https://dev.gatherory.com"))
        let router = InvitationRouter(baseURL: baseURL, defaults: defaults)
        let inviteToken = UUID()
        #expect(router.receive(URL(string: "https://dev.gatherory.com/join/\(inviteToken)")!))

        let preview = try JSONDecoder().decode(
            InvitationPreview.self,
            from: Data(#"{"requiresSignIn":true,"role":"collaborator","status":"pending","requiresApproval":true,"planningPermission":"view_only"}"#.utf8)
        )
        auth.requestGuestSignIn()
        #expect(auth.isGuestSignInRequested)
        #expect(router.pendingToken == inviteToken)
        auth.cancelGuestSignIn()
        #expect(!auth.isGuestSignInRequested)
        #expect(router.pendingToken == inviteToken)

        try await auth.signIn(email: "morgan@example.com", password: "password")

        #expect(auth.currentUser?.role == .member)
        #expect(auth.hasPendingGuestImport)
        #expect(auth.localGuestProfile == profile)
        #expect(try stores.credentials.loadOrCreateToken(profileID: profile.id) == proof)
        #expect(router.pendingToken == inviteToken)
        #expect(!router.didJoinThisSession)
        #expect(!preview.shouldOpenExistingEvent(isAuthenticated: auth.isAuthenticated))
        #expect(InvitationJoinProgress().acceptedResponse(for: auth.currentUser?.id) == nil)
    }

    @MainActor
    private func makeStores() throws -> (profile: GuestAuthProfileStore, credentials: MemoryLocalGuestCredentialStore) {
        (GuestAuthProfileStore(), MemoryLocalGuestCredentialStore())
    }
}

@MainActor
private final class GuestAuthProfileStore: LocalGuestProfileStore {
    private(set) var profile: LocalGuestProfile?
    var failLoad = false
    var failSave = false
    var failRemove = false
    func load() throws -> LocalGuestProfile? {
        if failLoad { throw CocoaError(.fileReadUnknown) }
        return profile
    }
    func save(_ profile: LocalGuestProfile) throws {
        if failSave { throw CocoaError(.fileWriteUnknown) }
        self.profile = profile
    }
    func remove() throws {
        if failRemove { throw CocoaError(.fileWriteUnknown) }
        profile = nil
    }
}

@MainActor
private final class GuestAuthenticationTestClient: AuthenticationClient {
    static let user = UserAccount(
        id: "guest-auth-test-user", email: "morgan@example.com", displayName: "Morgan",
        role: .member, authenticationProvider: .password, createdAt: .distantPast
    )
    var signInFailure: AuthenticationFailure?
    private(set) var signInCalls = 0
    func restoreSession() async throws -> UserAccount? { nil }
    func signIn(email: String, password: String) async throws -> UserAccount {
        signInCalls += 1
        if let signInFailure { throw signInFailure }
        return Self.user
    }
    func register(displayName: String, email: String, password: String) async throws -> RegistrationOutcome {
        .authenticated(Self.user)
    }
    func signInWithApple(_ identity: AppleIdentity, requestingSignUp: Bool) async throws -> UserAccount { Self.user }
    func signInWithGoogle(identityToken: String, nonce: String, requestingSignUp: Bool) async throws -> UserAccount { Self.user }
    func deleteAccount() async throws {}
    func signOut() async {}
}
