import Foundation
import Testing
@testable import Gatherory

@MainActor
struct SessionRestorationTests {
    @Test("An unavailable session check keeps guest data and allows a validated retry")
    func unavailableRestorationCanRetry() async throws {
        let client = RestorationTestClient()
        client.restoreFailure = AuthenticationFailure.networkUnavailable
        let profiles = MemoryLocalGuestProfileStore()
        let credentials = MemoryLocalGuestCredentialStore()
        let profile = LocalGuestProfile(displayName: "Morgan")
        try profiles.save(profile)
        let proof = try credentials.loadOrCreateToken(profileID: profile.id)
        let authentication = makeSession(client: client, profiles: profiles, credentials: credentials)

        await authentication.restoreSession()

        #expect(authentication.currentUser == nil)
        #expect(authentication.isSessionRestorationUnavailable)
        #expect(authentication.sessionRestorationFailure as? AuthenticationFailure == .networkUnavailable)
        #expect(!authentication.isProcessing)
        #expect(authentication.localGuestProfile == profile)
        #expect(profiles.profile == profile)
        #expect(try credentials.loadOrCreateToken(profileID: profile.id) == proof)

        client.restoreFailure = nil
        await authentication.restoreSession()

        #expect(authentication.currentUser == RestorationTestClient.account)
        #expect(!authentication.isSessionRestorationUnavailable)
        #expect(authentication.sessionRestorationFailure == nil)
        #expect(authentication.hasPendingGuestImport)
        #expect(profiles.profile == profile)
        #expect(try credentials.loadOrCreateToken(profileID: profile.id) == proof)
        #expect(client.restoreCalls == 2)
    }

    @Test("A confirmed expired or absent session resolves an earlier unavailable check", arguments: [false, true])
    func confirmedSignOutClearsRecovery(expired: Bool) async {
        let client = RestorationTestClient()
        client.restoreFailure = AuthenticationFailure.serviceUnavailable
        let authentication = makeSession(client: client)
        await authentication.restoreSession()
        #expect(authentication.isSessionRestorationUnavailable)

        client.restoreFailure = expired ? AuthenticationFailure.invalidSession : nil
        client.restoredAccount = nil
        await authentication.restoreSession()

        #expect(authentication.currentUser == nil)
        #expect(!authentication.isSessionRestorationUnavailable)
        #expect(authentication.sessionRestorationFailure == nil)
        #expect(!authentication.isProcessing)
    }

    @Test("Secure-storage restoration errors remain distinguishable from sign-out")
    func storageFailureStaysUnavailable() async {
        let client = RestorationTestClient()
        client.restoreFailure = CocoaError(.fileReadNoPermission)
        let authentication = makeSession(client: client)

        await authentication.restoreSession()

        #expect(authentication.currentUser == nil)
        #expect(authentication.isSessionRestorationUnavailable)
        #expect((authentication.sessionRestorationFailure as? CocoaError)?.code == .fileReadNoPermission)
    }

    @Test("Failed deliberate sign-in preserves restoration recovery and the guest profile")
    func failedSignInPreservesRecovery() async throws {
        let client = RestorationTestClient()
        client.restoreFailure = AuthenticationFailure.networkUnavailable
        client.signInFailure = .invalidCredentials
        let profiles = MemoryLocalGuestProfileStore()
        let profile = LocalGuestProfile(displayName: "Morgan")
        try profiles.save(profile)
        let authentication = makeSession(client: client, profiles: profiles)
        await authentication.restoreSession()

        await #expect(throws: AuthenticationFailure.invalidCredentials) {
            try await authentication.signIn(email: "morgan@example.com", password: "wrong")
        }

        #expect(authentication.currentUser == nil)
        #expect(authentication.isSessionRestorationUnavailable)
        #expect(authentication.localGuestProfile == profile)
        #expect(profiles.profile == profile)
        #expect(!authentication.isProcessing)
    }

    @Test("Successful authentication actions clear an earlier restoration failure", arguments: [
        "password", "apple", "google", "register", "verification"
    ])
    func deliberateAuthenticationClearsRecovery(action: String) async throws {
        let client = RestorationTestClient()
        client.restoreFailure = AuthenticationFailure.networkUnavailable
        client.requiresVerification = action == "verification"
        let authentication = makeSession(client: client)
        await authentication.restoreSession()
        #expect(authentication.isSessionRestorationUnavailable)

        switch action {
        case "password":
            try await authentication.signIn(email: "morgan@example.com", password: "password")
        case "apple":
            try await authentication.signInWithApple(AppleIdentity(
                identityToken: "test-token", authorizationCode: "test-code", nonce: "test-nonce",
                email: nil, givenName: nil, familyName: nil
            ), requestingSignUp: false)
        case "google":
            try await authentication.signInWithGoogle(
                identityToken: "test-token", nonce: "test-nonce", requestingSignUp: false
            )
        default:
            try await authentication.register(displayName: "Morgan", email: "morgan@example.com", password: "password")
        }

        #expect(!authentication.isSessionRestorationUnavailable)
        #expect(authentication.sessionRestorationFailure == nil)
        #expect(authentication.isAuthenticated == (action != "verification"))
        #expect(!authentication.isProcessing)
    }

    private func makeSession(
        client: RestorationTestClient,
        profiles: MemoryLocalGuestProfileStore? = nil,
        credentials: MemoryLocalGuestCredentialStore? = nil
    ) -> AuthenticationSession {
        AuthenticationSession(
            environment: .production, skipsAuthentication: false, client: client,
            guestProfileStore: profiles ?? MemoryLocalGuestProfileStore(),
            guestCredentialStore: credentials ?? MemoryLocalGuestCredentialStore()
        )
    }
}

@MainActor
private final class RestorationTestClient: AuthenticationClient {
    static let account = UserAccount(
        id: "restoration-account", email: "morgan@example.com", displayName: "Morgan",
        role: .member, authenticationProvider: .password,
        createdAt: Date(timeIntervalSinceReferenceDate: 900_000_000)
    )

    var restoredAccount: UserAccount? = RestorationTestClient.account
    var restoreFailure: (any Error)?
    var signInFailure: AuthenticationFailure?
    var requiresVerification = false
    private(set) var restoreCalls = 0

    func restoreSession() async throws -> UserAccount? {
        restoreCalls += 1
        if let restoreFailure { throw restoreFailure }
        return restoredAccount
    }

    func signIn(email: String, password: String) async throws -> UserAccount {
        if let signInFailure { throw signInFailure }
        return Self.account
    }

    func register(displayName: String, email: String, password: String) async throws -> RegistrationOutcome {
        requiresVerification ? .verificationRequired(email: email) : .authenticated(Self.account)
    }

    func signInWithApple(_ identity: AppleIdentity, requestingSignUp: Bool) async throws -> UserAccount { Self.account }
    func signInWithGoogle(identityToken: String, nonce: String, requestingSignUp: Bool) async throws -> UserAccount { Self.account }
    func deleteAccount() async throws {}
    func signOut() async {}
}
