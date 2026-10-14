import Foundation
import Testing
@testable import Gatherory

struct AuthenticationSessionTests {
    @Test("Failed session restoration leaves sign-in available and can be retried")
    @MainActor
    func failedRestoreCanRetry() async {
        let client = StubAuthenticationClient()
        client.restoreFailure = .networkUnavailable
        let authentication = AuthenticationSession(environment: .production, skipsAuthentication: false, client: client)

        await authentication.restoreSession()
        #expect(authentication.currentUser == nil)
        #expect(!authentication.isProcessing)

        client.restoreFailure = nil
        await authentication.restoreSession()
        #expect(authentication.currentUser?.id == StubAuthenticationClient.user.id)
        #expect(!authentication.isProcessing)
    }

    @Test("Failed sign-in never authenticates the account and releases the processing guard")
    @MainActor
    func failedSignInCanRetry() async throws {
        let client = StubAuthenticationClient()
        client.signInFailure = .invalidCredentials
        let authentication = AuthenticationSession(environment: .production, skipsAuthentication: false, client: client)

        await #expect(throws: AuthenticationFailure.invalidCredentials) {
            try await authentication.signIn(email: "julio@example.com", password: "wrong-password")
        }
        #expect(authentication.currentUser == nil)
        #expect(!authentication.isProcessing)

        client.signInFailure = nil
        try await authentication.signIn(email: "julio@example.com", password: "password")
        #expect(authentication.currentUser?.id == StubAuthenticationClient.user.id)
        #expect(!authentication.isProcessing)
    }

    @Test("Failed remote deletion preserves the account until the server acknowledges deletion")
    @MainActor
    func failedDeletionPreservesSession() async throws {
        let client = StubAuthenticationClient()
        client.deletionFailure = .reauthenticationRequired
        let authentication = AuthenticationSession(environment: .production, skipsAuthentication: false, client: client)
        await authentication.restoreSession()

        await #expect(throws: AuthenticationFailure.reauthenticationRequired) {
            try await authentication.deleteAccount()
        }
        #expect(client.didRequestAccountDeletion)
        #expect(authentication.currentUser?.id == StubAuthenticationClient.user.id)
        #expect(!authentication.isProcessing)

        client.deletionFailure = nil
        try await authentication.deleteAccount()
        #expect(authentication.currentUser == nil)
        #expect(!authentication.isProcessing)
    }

    @Test("Deleting without an authenticated account never calls the remote client")
    @MainActor
    func unauthenticatedDeletionIsRejected() async {
        let client = StubAuthenticationClient()
        let authentication = AuthenticationSession(environment: .production, skipsAuthentication: false, client: client)
        await #expect(throws: AuthenticationFailure.invalidSession) {
            try await authentication.deleteAccount()
        }
        #expect(!client.didRequestAccountDeletion)
        #expect(!authentication.isProcessing)
    }

    @Test("Sign out waits for sync and client teardown before clearing the account")
    @MainActor
    func signOutWaitsForSync() async throws {
        let client = StubAuthenticationClient()
        client.holdSignOut = true
        let authentication = AuthenticationSession(environment: .production, skipsAuthentication: false, client: client)
        await authentication.restoreSession()
        var finishSync: CheckedContinuation<Void, Never>?
        authentication.prepareForSignOut = { _ in
            await withCheckedContinuation { finishSync = $0 }
        }
        let task = Task { await authentication.signOut() }
        while finishSync == nil { await Task.yield() }
        #expect(authentication.isSigningOut)
        #expect(authentication.currentUser != nil)
        #expect(!client.didSignOut)
        #expect(await authentication.signOut() == false)
        await #expect(throws: AuthenticationFailure.serviceUnavailable) {
            try await authentication.signIn(email: "other@example.com", password: "password")
        }
        finishSync?.resume()
        while client.finishSignOut == nil { await Task.yield() }
        #expect(authentication.currentUser != nil)
        #expect(authentication.isSigningOut)
        client.finishSignOut?.resume()
        #expect(await task.value)
        #expect(client.didSignOut)
        #expect(authentication.currentUser == nil)
        #expect(!authentication.isProcessing)
    }

    @Test("Failed final sync leaves account signed in; explicit override retains pending changes")
    @MainActor
    func signOutSyncFailure() async {
        let client = StubAuthenticationClient()
        let authentication = AuthenticationSession(environment: .production, skipsAuthentication: false, client: client)
        await authentication.restoreSession()
        var requestedModes: [Bool] = []
        authentication.prepareForSignOut = { keepingPendingChanges in
            requestedModes.append(keepingPendingChanges)
            if !keepingPendingChanges { throw URLError(.notConnectedToInternet) }
        }
        #expect(await authentication.signOut() == false)
        #expect(authentication.signOutNeedsAttention)
        #expect(authentication.currentUser != nil)
        #expect(!client.didSignOut)
        #expect(await authentication.signOut(keepingPendingChanges: true))
        #expect(requestedModes == [false, true])
        #expect(authentication.currentUser == nil)
    }

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
    private(set) var didSignOut = false
    var holdSignOut = false
    var restoreFailure: AuthenticationFailure?
    var signInFailure: AuthenticationFailure?
    var deletionFailure: AuthenticationFailure?
    var finishSignOut: CheckedContinuation<Void, Never>?
    private(set) var lastGoogleIdentityToken: String?
    private(set) var lastGoogleNonce: String?

    init(registrationRequiresVerification: Bool = false) {
        self.registrationRequiresVerification = registrationRequiresVerification
    }

    func restoreSession() async throws -> UserAccount? {
        if let restoreFailure { throw restoreFailure }
        return Self.user
    }

    func signIn(email: String, password: String) async throws -> UserAccount {
        if let signInFailure { throw signInFailure }
        return Self.user
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
        if let deletionFailure { throw deletionFailure }
    }

    func signOut() async {
        if holdSignOut { await withCheckedContinuation { finishSignOut = $0 } }
        didSignOut = true
    }
}
