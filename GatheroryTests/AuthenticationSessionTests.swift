import Foundation
import Testing
@testable import Gatherory

struct AuthenticationSessionTests {
    @Test("Production sign in keeps the Better Auth user identifier")
    @MainActor
    func remoteSignInUsesCanonicalUserID() async throws {
        let client = StubAuthenticationClient()
        let authentication = AuthenticationSession(
            environment: .production,
            skipsAuthentication: false,
            client: client
        )

        try await authentication.signIn(email: "julio@example.com", password: "password")

        #expect(authentication.currentUser?.id == StubAuthenticationClient.user.id)
        #expect(authentication.currentUser?.email == "julio@example.com")
        #expect(!authentication.isProcessing)
    }

    @Test("Registration waits for required email verification")
    @MainActor
    func registrationRequiresVerification() async throws {
        let client = StubAuthenticationClient(registrationRequiresVerification: true)
        let authentication = AuthenticationSession(
            environment: .production,
            skipsAuthentication: false,
            client: client
        )

        try await authentication.register(
            displayName: "Julio Flores",
            email: "julio@example.com",
            password: "password"
        )

        #expect(authentication.currentUser == nil)
        #expect(authentication.registrationNotice?.contains("julio@example.com") == true)
        #expect(!authentication.isProcessing)

        authentication.clearRegistrationNotice()
        #expect(authentication.registrationNotice == nil)
    }

    @Test("A valid stored server session restores the user")
    @MainActor
    func restoresRemoteSession() async {
        let authentication = AuthenticationSession(
            environment: .production,
            skipsAuthentication: false,
            client: StubAuthenticationClient()
        )

        await authentication.restoreSession()

        #expect(authentication.currentUser?.id == StubAuthenticationClient.user.id)
    }

    @Test("Google identity token sign in uses the remote client")
    @MainActor
    func googleIdentityTokenUsesRemoteClient() async throws {
        let client = StubAuthenticationClient()
        let authentication = AuthenticationSession(
            environment: .production,
            skipsAuthentication: false,
            client: client
        )

        try await authentication.signInWithGoogle(
            identityToken: "google-id-token",
            nonce: "google-nonce",
            requestingSignUp: false
        )

        #expect(authentication.currentUser?.authenticationProvider == .google)
        #expect(client.lastGoogleIdentityToken == "google-id-token")
        #expect(client.lastGoogleNonce == "google-nonce")
    }

    @Test("Deleting a remote account clears the authenticated session")
    @MainActor
    func deletingRemoteAccountClearsSession() async throws {
        let client = StubAuthenticationClient()
        let authentication = AuthenticationSession(
            environment: .production,
            skipsAuthentication: false,
            client: client
        )

        await authentication.restoreSession()
        try await authentication.deleteAccount()

        #expect(authentication.currentUser == nil)
        #expect(client.didRequestAccountDeletion)
        #expect(!authentication.isProcessing)
    }
}

@MainActor
private final class StubAuthenticationClient: AuthenticationClient {
    static let user = UserAccount(
        id: "better-auth-user-123",
        email: "julio@example.com",
        displayName: "Julio Flores",
        role: .member,
        authenticationProvider: .password,
        createdAt: Date(timeIntervalSinceReferenceDate: 900_000_000)
    )

    private let registrationRequiresVerification: Bool
    private(set) var didRequestAccountDeletion = false
    private(set) var lastGoogleIdentityToken: String?
    private(set) var lastGoogleNonce: String?

    init(registrationRequiresVerification: Bool = false) {
        self.registrationRequiresVerification = registrationRequiresVerification
    }

    func restoreSession() async throws -> UserAccount? {
        Self.user
    }

    func signIn(email: String, password: String) async throws -> UserAccount {
        Self.user
    }

    func register(
        displayName: String,
        email: String,
        password: String
    ) async throws -> RegistrationOutcome {
        if registrationRequiresVerification {
            return .verificationRequired(email: email)
        }
        return .authenticated(Self.user)
    }

    func signInWithApple(
        _ identity: AppleIdentity,
        requestingSignUp: Bool
    ) async throws -> UserAccount {
        var user = Self.user
        user.authenticationProvider = .apple
        return user
    }

    func signInWithGoogle(
        identityToken: String,
        nonce: String,
        requestingSignUp: Bool
    ) async throws -> UserAccount {
        lastGoogleIdentityToken = identityToken
        lastGoogleNonce = nonce
        var user = Self.user
        user.authenticationProvider = .google
        return user
    }

    func deleteAccount() async throws {
        didRequestAccountDeletion = true
    }

    func signOut() async {}
}
