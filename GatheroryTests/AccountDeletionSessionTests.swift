import Foundation
import Testing
@testable import Gatherory

@MainActor
struct AccountDeletionSessionTests {
    @Test("A failed initial journal write prevents freezing and remote deletion")
    func beginFailureStopsRemoteRequest() async throws {
        let fixture = AccountDeletionSessionFixture()
        await fixture.authentication.restoreSession()
        fixture.journal.failAllSaves = true
        fixture.authentication.prepareForAccountDeletion = { _ in fixture.client.events.append("freeze") }

        await #expect(throws: AccountDeletionTestFailure.write) { try await fixture.authentication.deleteAccount() }

        #expect(fixture.client.deleteCalls == 0)
        #expect(fixture.client.events.isEmpty)
        #expect(fixture.authentication.currentUser == AccountDeletionSessionClient.user)
        #expect(fixture.journal.record == nil)
        #expect(!fixture.authentication.isProcessing)
    }

    @Test("An explicitly rejected deletion restores the retained account without removing local data")
    func remoteFailureRetainsAccountAndData() async throws {
        let fixture = AccountDeletionSessionFixture()
        await fixture.authentication.restoreSession()
        fixture.client.deleteFailure = .reauthenticationRequired
        var hasLocalData = true
        fixture.coordinator.removeLocalData = { _ in hasLocalData = false }
        fixture.authentication.prepareForAccountDeletion = { accountID in
            #expect(accountID == AccountDeletionSessionClient.user.id)
            fixture.client.events.append("freeze")
        }
        fixture.authentication.resumeAfterFailedAccountDeletion = { account in
            #expect(account == AccountDeletionSessionClient.user)
            fixture.client.events.append("resume")
        }

        await #expect(throws: AuthenticationFailure.reauthenticationRequired) { try await fixture.authentication.deleteAccount() }

        #expect(fixture.client.events == ["freeze", "remote", "resume"])
        #expect(fixture.client.deleteCalls == 1)
        #expect(fixture.authentication.currentUser == AccountDeletionSessionClient.user)
        #expect(hasLocalData)
        #expect(fixture.journal.record == nil)
        #expect(!fixture.coordinator.blocksEntry)
        #expect(!fixture.authentication.isProcessing)
    }

    @Test("A lost remote response retains the intent and data until explicit device-only removal")
    func ambiguousNetworkFailureRequiresExplicitDeviceRemoval() async throws {
        let fixture = AccountDeletionSessionFixture()
        await fixture.authentication.restoreSession()
        fixture.client.deleteFailure = .networkUnavailable
        var hasLocalData = true
        var cleanupAccounts: [String] = []
        fixture.coordinator.removeLocalData = { accountID in
            #expect(fixture.journal.record?.phase == .deviceRemovalConfirmed)
            fixture.authentication.clearAccountForDeviceCleanup(accountID: accountID)
            cleanupAccounts.append(accountID)
            hasLocalData = false
        }

        await #expect(throws: AuthenticationFailure.networkUnavailable) { try await fixture.authentication.deleteAccount() }
        #expect(fixture.authentication.currentUser == AccountDeletionSessionClient.user)
        #expect(fixture.authentication.notificationPrincipal == nil)
        #expect(fixture.coordinator.needsConfirmation)
        #expect(fixture.coordinator.blocksEntry)
        #expect(fixture.journal.record?.phase == .awaitingConfirmation)
        #expect(hasLocalData)
        await fixture.coordinator.retry()
        #expect(cleanupAccounts.isEmpty)
        #expect(fixture.client.deleteCalls == 1)
        await #expect(throws: AuthenticationFailure.serviceUnavailable) { try await fixture.authentication.deleteAccount() }

        let relaunchedCoordinator = AccountDeletionCleanupCoordinator(journal: fixture.journal)
        let relaunched = fixture.makeSession(cleanup: relaunchedCoordinator)
        await assertEntryBlocked(relaunched)
        await relaunchedCoordinator.retry()
        #expect(hasLocalData)
        #expect(cleanupAccounts.isEmpty)
        #expect(fixture.client.deleteCalls == 1)

        await fixture.coordinator.confirmDeviceRemoval()
        #expect(cleanupAccounts == [AccountDeletionSessionClient.user.id])
        #expect(!hasLocalData)
        #expect(fixture.authentication.currentUser == nil)
        #expect(fixture.client.deleteCalls == 1)
        #expect(fixture.client.signOutCalls == 0)
        #expect(fixture.journal.record == nil)
        #expect(!fixture.coordinator.blocksEntry)
    }

    @Test("Freezing fails before remote deletion and resumes the retained account")
    func freezeFailureStopsRemoteRequest() async throws {
        let fixture = AccountDeletionSessionFixture()
        await fixture.authentication.restoreSession()
        fixture.authentication.prepareForAccountDeletion = { _ in throw AccountDeletionTestFailure.freeze }
        fixture.authentication.resumeAfterFailedAccountDeletion = { _ in fixture.client.events.append("resume") }

        await #expect(throws: AccountDeletionTestFailure.freeze) { try await fixture.authentication.deleteAccount() }

        #expect(fixture.client.deleteCalls == 0)
        #expect(fixture.client.events == ["resume"])
        #expect(fixture.authentication.currentUser == AccountDeletionSessionClient.user)
        #expect(fixture.journal.record == nil)
    }

    @Test("Acknowledged deletion freezes first, clears authentication and retries cleanup without remote calls")
    func confirmedCleanupFailureBlocksEveryEntryUntilLocalRetry() async throws {
        let fixture = AccountDeletionSessionFixture()
        await fixture.authentication.restoreSession()
        fixture.authentication.prepareForAccountDeletion = { accountID in
            #expect(accountID == AccountDeletionSessionClient.user.id)
            #expect(fixture.journal.record?.phase == .awaitingConfirmation)
            #expect(fixture.authentication.currentUser != nil)
            fixture.client.events.append("freeze")
        }
        fixture.client.beforeDelete = {
            #expect(fixture.client.events == ["freeze"])
            #expect(fixture.journal.record?.phase == .awaitingConfirmation)
        }
        var cleanupAccounts: [String] = []
        fixture.coordinator.removeLocalData = { accountID in
            #expect(fixture.journal.record?.phase == .confirmed)
            #expect(fixture.authentication.currentUser == nil)
            cleanupAccounts.append(accountID)
            fixture.client.events.append("cleanup")
            throw AccountDeletionTestFailure.cleanup
        }

        try await fixture.authentication.deleteAccount()

        #expect(fixture.client.events == ["freeze", "remote", "cleanup"])
        #expect(fixture.client.deleteCalls == 1)
        #expect(fixture.authentication.currentUser == nil)
        #expect(fixture.authentication.notificationPrincipal == nil)
        #expect(fixture.coordinator.blocksEntry)
        #expect(!fixture.authentication.isProcessing)
        #expect(fixture.journal.record?.phase == .confirmed)
        let restoreCalls = fixture.client.restoreCalls
        await assertEntryBlocked(fixture.authentication)
        #expect(fixture.client.restoreCalls == restoreCalls)
        #expect(fixture.client.signInCalls == 0)
        #expect(fixture.client.registrationCalls == 0)
        #expect(fixture.client.appleCalls == 0)
        #expect(fixture.client.googleCalls == 0)
        #expect(fixture.profiles.profile == nil)

        // Relaunch uses the same durable identity without restoring auth or
        // repeating account deletion while device cleanup remains pending.
        let relaunchedCoordinator = AccountDeletionCleanupCoordinator(journal: fixture.journal)
        let relaunched = fixture.makeSession(cleanup: relaunchedCoordinator)
        await relaunched.restoreSession()
        #expect(fixture.client.restoreCalls == restoreCalls)
        relaunchedCoordinator.removeLocalData = { cleanupAccounts.append($0) }
        await relaunchedCoordinator.retry()
        #expect(cleanupAccounts == [AccountDeletionSessionClient.user.id, AccountDeletionSessionClient.user.id])
        #expect(fixture.client.deleteCalls == 1)
        #expect(fixture.client.signOutCalls == 0)
        #expect(fixture.journal.record == nil)
        #expect(!relaunchedCoordinator.blocksEntry)
        #expect(relaunched.currentUser == nil)
    }

    @Test("An interrupted request blocks restored sessions and providers without remote deletion")
    func awaitingConfirmationBlocksEntry() async throws {
        let fixture = AccountDeletionSessionFixture()
        try fixture.coordinator.begin(accountID: AccountDeletionSessionClient.user.id)
        let relaunchedCoordinator = AccountDeletionCleanupCoordinator(journal: fixture.journal)
        let authentication = fixture.makeSession(cleanup: relaunchedCoordinator)
        await assertEntryBlocked(authentication)
        await relaunchedCoordinator.retry()
        #expect(fixture.client.restoreCalls == 0)
        #expect(fixture.client.deleteCalls == 0)
        #expect(fixture.client.signInCalls == 0)
        #expect(fixture.client.registrationCalls == 0)
        #expect(fixture.client.appleCalls == 0)
        #expect(fixture.client.googleCalls == 0)
        #expect(relaunchedCoordinator.needsConfirmation)
        #expect(fixture.journal.record?.phase == .awaitingConfirmation)
    }

    private func assertEntryBlocked(_ authentication: AuthenticationSession) async {
        await authentication.restoreSession()
        await #expect(throws: AuthenticationFailure.serviceUnavailable) {
            try await authentication.signIn(email: "new@example.com", password: "local-test-password")
        }
        await #expect(throws: AuthenticationFailure.serviceUnavailable) {
            try await authentication.register(displayName: "New", email: "new@example.com", password: "local-test-password")
        }
        for requestingSignUp in [false, true] {
            await #expect(throws: AuthenticationFailure.serviceUnavailable) {
                try await authentication.signInWithApple(
                    AppleIdentity(identityToken: "test", authorizationCode: "test", nonce: "test",
                                  email: nil, givenName: nil, familyName: nil),
                    requestingSignUp: requestingSignUp
                )
            }
            await #expect(throws: AuthenticationFailure.serviceUnavailable) {
                try await authentication.signInWithGoogle(identityToken: "test", nonce: "test", requestingSignUp: requestingSignUp)
            }
        }
        for provider in [AuthenticationProvider.password, .apple, .google] {
            await #expect(throws: AuthenticationFailure.serviceUnavailable) { try await authentication.signIn(using: provider) }
        }
        #expect(throws: AuthenticationFailure.guestDataUnavailable) { try authentication.continueAsGuest(displayName: "Guest") }
        #expect(authentication.currentUser == nil)
        #expect(authentication.localGuestProfile == nil)
    }
}

@MainActor
private final class AccountDeletionSessionFixture {
    let journal = AccountDeletionTestJournal()
    let client = AccountDeletionSessionClient()
    let profiles = MemoryLocalGuestProfileStore()
    let credentials = MemoryLocalGuestCredentialStore()
    let coordinator: AccountDeletionCleanupCoordinator
    lazy var authentication = makeSession(cleanup: coordinator)

    init() {
        coordinator = AccountDeletionCleanupCoordinator(journal: journal)
    }

    func makeSession(cleanup: AccountDeletionCleanupCoordinator) -> AuthenticationSession {
        AuthenticationSession(environment: .production, skipsAuthentication: false, client: client,
                              guestProfileStore: profiles, guestCredentialStore: credentials, deletionCleanup: cleanup)
    }
}

@MainActor
private final class AccountDeletionSessionClient: AuthenticationClient {
    static let user = UserAccount(id: "account-deletion-session", email: "deletion@example.com", displayName: "Morgan",
                                  role: .member, authenticationProvider: .password, createdAt: .distantPast)
    var deleteFailure: AuthenticationFailure?
    var beforeDelete: (() -> Void)?
    var events: [String] = []
    private(set) var restoreCalls = 0
    private(set) var deleteCalls = 0
    private(set) var signOutCalls = 0
    private(set) var signInCalls = 0
    private(set) var registrationCalls = 0
    private(set) var appleCalls = 0
    private(set) var googleCalls = 0

    func restoreSession() async throws -> UserAccount? { restoreCalls += 1; return Self.user }
    func signIn(email: String, password: String) async throws -> UserAccount { signInCalls += 1; return Self.user }
    func register(displayName: String, email: String, password: String) async throws -> RegistrationOutcome {
        registrationCalls += 1
        return .authenticated(Self.user)
    }
    func signInWithApple(_ identity: AppleIdentity, requestingSignUp: Bool) async throws -> UserAccount {
        appleCalls += 1
        return Self.user
    }
    func signInWithGoogle(identityToken: String, nonce: String, requestingSignUp: Bool) async throws -> UserAccount {
        googleCalls += 1
        return Self.user
    }
    func deleteAccount() async throws {
        beforeDelete?()
        deleteCalls += 1
        events.append("remote")
        if let deleteFailure { throw deleteFailure }
    }
    func signOut() async { signOutCalls += 1 }
}
