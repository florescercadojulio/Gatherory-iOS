import Foundation
import Observation
import PostHog

enum AuthenticationFailure: LocalizedError, Equatable {
    case invalidCredentials
    case invalidRegistration
    case accountAlreadyExists
    case providerUnavailable
    case emailNotVerified
    case invalidSession
    case reauthenticationRequired
    case networkUnavailable
    case serviceUnavailable
    case invalidServerResponse
    case guestDataUnavailable
    case server(message: String?)

    var errorDescription: String? {
        switch self {
        case .invalidCredentials:
            "The email or password is incorrect."
        case .invalidRegistration:
            "Enter a name, a valid email address, and a password with at least eight characters."
        case .accountAlreadyExists:
            "An account with this email address already exists."
        case .providerUnavailable:
            "This sign-in provider isn’t available right now."
        case .emailNotVerified:
            "Verify your email address, then try signing in again."
        case .invalidSession:
            "Your session has expired. Sign in again to continue."
        case .reauthenticationRequired:
            "For security, sign out and sign in again before deleting your account."
        case .networkUnavailable:
            "Gatherory couldn’t reach the sign-in service. Check your connection and try again."
        case .serviceUnavailable:
            "The sign-in service is temporarily unavailable. Try again in a moment."
        case .invalidServerResponse:
            "Gatherory received an unexpected response from the sign-in service."
        case .guestDataUnavailable:
            GuestCopy.storageFailed
        case .server(let message):
            message ?? "Gatherory couldn’t complete the sign-in request."
        }
    }
}

@Observable
@MainActor
final class AuthenticationSession {
    private(set) var currentUser: UserAccount? {
        didSet { if oldValue?.id != currentUser?.id { principalGeneration &+= 1 } }
    }
    private(set) var localGuestProfile: LocalGuestProfile? {
        didSet { if oldValue?.id != localGuestProfile?.id { principalGeneration &+= 1 } }
    }
    /// Invalidates identity-bound requests even across a rapid A → B → A switch.
    private(set) var principalGeneration: UInt64 = 0
    private(set) var isGuestSignInRequested = false
    private(set) var guestStorageFailed = false
    private(set) var guestDiscardNeedsAttention = false
    @ObservationIgnored var prepareForGuestAuthentication: (() throws -> Void)?
    @ObservationIgnored var prepareForGuestDiscard: ((LocalGuestProfile) async throws -> Void)?
    @ObservationIgnored private let guestProfileStore: any LocalGuestProfileStore
    @ObservationIgnored private let guestCredentialStore: any LocalGuestCredentialStore
    private(set) var developmentAccounts: [UserAccount]
    private(set) var isProcessing = false
    private(set) var isSigningOut = false {
        didSet { if isSigningOut && !oldValue { principalGeneration &+= 1 } }
    }
    var signOutNeedsAttention = false
    var accountDeletionNeedsAttention = false
    @ObservationIgnored var prepareForSignOut: ((Bool) async throws -> Void)?
    @ObservationIgnored var prepareForAccountDeletion: ((String) async throws -> Void)?
    @ObservationIgnored var resumeAfterFailedAccountDeletion: ((UserAccount) async -> Void)?
    let deletionCleanup: AccountDeletionCleanupCoordinator
    private(set) var registrationNotice: String?
    /// A failed network or secure-storage check is not evidence of sign-out.
    /// Keep entry behind recovery until a retry validates the saved session.
    private(set) var sessionRestorationFailure: (any Error)?

    var isSessionRestorationUnavailable: Bool { sessionRestorationFailure != nil }

    let environment: AppRuntimeConfiguration.Environment

    private var developmentPasswords: [String: String]
    private let client: (any AuthenticationClient)?
    @ObservationIgnored private let removeSavedShareLinks: (@MainActor (String) -> Void)?

    var isAuthenticated: Bool {
        currentUser != nil
    }

    var isGuestMode: Bool { currentUser == nil && localGuestProfile != nil }
    var hasPendingGuestImport: Bool { currentUser != nil && localGuestProfile != nil }

    /// A guest handover must finish before this installation can receive
    /// notifications for the account. Display names never identify a recipient.
    var notificationPrincipal: NotificationPrincipal? {
        guard !deletionCleanup.blocksEntry, !hasPendingGuestImport, !guestDiscardNeedsAttention, !isSessionRestorationUnavailable else { return nil }
        if let currentUser { return .account(id: currentUser.id) }
        return localGuestProfile.map { .guest(id: $0.id) }
    }

    func continueAsGuest(displayName: String) throws {
        guard !deletionCleanup.blocksEntry, !isProcessing, !isAuthenticated, !guestStorageFailed else {
            throw AuthenticationFailure.guestDataUnavailable
        }
        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.unicodeScalars.count <= 80 else {
            throw LocalGuestProfileStoreError.invalidProfile
        }
        let profile = LocalGuestProfile(id: localGuestProfile?.id ?? UUID(), displayName: name)
        try guestProfileStore.save(profile)
        localGuestProfile = profile
        isGuestSignInRequested = false
        registrationNotice = nil
    }

    func retryGuestProfileLoading() {
        guard guestStorageFailed, !isProcessing, !isAuthenticated else { return }
        do {
            localGuestProfile = try guestProfileStore.load()
            guestStorageFailed = false
        } catch { guestStorageFailed = true }
    }

    func requestGuestSignIn() { isGuestSignInRequested = true }
    func cancelGuestSignIn() { isGuestSignInRequested = false }

    /// Called only after workspace import and event-grant claiming are durable.
    func completeGuestImport() throws {
        guard !deletionCleanup.blocksEntry else { throw AuthenticationFailure.guestDataUnavailable }
        guard isAuthenticated, let profile = localGuestProfile else { return }
        try guestProfileStore.remove()
        localGuestProfile = nil
        isGuestSignInRequested = false
        guestDiscardNeedsAttention = false
        try? guestCredentialStore.removeSecret(profileID: profile.id)
    }

    /// The caller must first show the explicit device-data-loss confirmation.
    func discardGuestSession() async throws {
        guard !deletionCleanup.blocksEntry, !isProcessing, currentUser == nil, let profile = localGuestProfile,
              let prepareForGuestDiscard else { throw AuthenticationFailure.guestDataUnavailable }
        // Teardown may already have removed guest archives before profile removal
        // fails. Keep entry in recovery until an explicit retry finishes cleanup.
        guestDiscardNeedsAttention = true
        isProcessing = true
        defer { isProcessing = false }
        try await prepareForGuestDiscard(profile)
        try guestProfileStore.remove()
        localGuestProfile = nil
        isGuestSignInRequested = false
        try? guestCredentialStore.removeSecret(profileID: profile.id)
        guestDiscardNeedsAttention = false
    }

    init(
        environment: AppRuntimeConfiguration.Environment,
        skipsAuthentication: Bool,
        client: (any AuthenticationClient)? = nil,
        removeSavedShareLinks: (@MainActor (String) -> Void)? = nil,
        guestProfileStore: (any LocalGuestProfileStore)? = nil,
        guestCredentialStore: (any LocalGuestCredentialStore)? = nil,
        deletionCleanup: AccountDeletionCleanupCoordinator? = nil
    ) {
        self.environment = environment
        self.client = client
        self.removeSavedShareLinks = removeSavedShareLinks
        if let deletionCleanup {
            self.deletionCleanup = deletionCleanup
        } else {
            let fixtureCleanup = AccountDeletionCleanupCoordinator(journal: MemoryAccountDeletionCleanupJournal())
            fixtureCleanup.removeLocalData = { _ in }
            self.deletionCleanup = fixtureCleanup
        }
        let profileStore = guestProfileStore ?? DeviceLocalGuestProfileStore()
        self.guestProfileStore = profileStore
        self.guestCredentialStore = guestCredentialStore ?? KeychainLocalGuestCredentialStore()
        do { localGuestProfile = try profileStore.load() }
        catch { guestStorageFailed = true }

        if environment == .development {
            let planner = DevelopmentAccountFixtures.planner
            developmentAccounts = [planner]
            developmentPasswords = [
                planner.email.lowercased(): DevelopmentAccountFixtures.plannerPassword
            ]
            currentUser = skipsAuthentication ? planner : nil
        } else {
            developmentAccounts = []
            developmentPasswords = [:]
            currentUser = nil
        }

        if let currentUser {
            identify(currentUser)
        }
    }

    static func bootstrap() -> AuthenticationSession {
        let client = AppRuntimeConfiguration.authenticationBaseURL.map {
            BetterAuthClient(baseURL: $0)
        }
        return AuthenticationSession(
            environment: AppRuntimeConfiguration.environment,
            skipsAuthentication: AppRuntimeConfiguration.skipsAuthentication,
            client: client,
            deletionCleanup: AccountDeletionCleanupCoordinator(journal: DeviceAccountDeletionCleanupJournal())
        )
    }

    func restoreSession() async {
        guard !deletionCleanup.blocksEntry, !isProcessing, currentUser == nil, let client else { return }

        isProcessing = true
        defer { isProcessing = false }

        do {
            currentUser = try await client.restoreSession()
            sessionRestorationFailure = nil
            if let currentUser {
                identify(currentUser)
            } else {
                PostHogSDK.shared.reset()
            }
        } catch AuthenticationFailure.invalidSession {
            // Clients may report expiry directly; Better Auth normally returns nil.
            sessionRestorationFailure = nil
            currentUser = nil
            PostHogSDK.shared.reset()
        } catch {
            // Preserve the distinction between a confirmed sign-out and an
            // unavailable check without manufacturing an authenticated state.
            sessionRestorationFailure = error
            currentUser = nil
            PostHogSDK.shared.reset()
        }
    }

    func signIn(email: String, password: String) async throws {
        guard !deletionCleanup.blocksEntry, !isProcessing else { throw AuthenticationFailure.serviceUnavailable }
        try prepareForGuestAuthentication?()
        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        registrationNotice = nil

        if let client {
            isProcessing = true
            defer { isProcessing = false }
            let account = try await client.signIn(email: normalizedEmail, password: password)
            currentUser = account
            sessionRestorationFailure = nil
            identify(account)
            return
        }

        guard
            let account = developmentAccounts.first(where: { $0.email.lowercased() == normalizedEmail }),
            developmentPasswords[normalizedEmail] == password
        else {
            throw AuthenticationFailure.invalidCredentials
        }

        currentUser = account
        sessionRestorationFailure = nil
        identify(account)
    }

    func clearRegistrationNotice() {
        registrationNotice = nil
    }

    func register(displayName: String, email: String, password: String) async throws {
        guard !deletionCleanup.blocksEntry, !isProcessing else { throw AuthenticationFailure.serviceUnavailable }
        try prepareForGuestAuthentication?()
        let normalizedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        guard
            !normalizedName.isEmpty,
            normalizedEmail.contains("@"),
            password.count >= 8
        else {
            throw AuthenticationFailure.invalidRegistration
        }

        registrationNotice = nil

        if let client {
            isProcessing = true
            defer { isProcessing = false }

            switch try await client.register(
                displayName: normalizedName,
                email: normalizedEmail,
                password: password
            ) {
            case .authenticated(let account):
                currentUser = account
                sessionRestorationFailure = nil
                identify(account)
            case .verificationRequired(let email):
                currentUser = nil
                sessionRestorationFailure = nil
                registrationNotice = "Check \(email) for a verification link, then sign in."
            }
            return
        }

        guard environment == .development else {
            throw AuthenticationFailure.serviceUnavailable
        }

        guard !developmentAccounts.contains(where: { $0.email.lowercased() == normalizedEmail }) else {
            throw AuthenticationFailure.accountAlreadyExists
        }

        let account = UserAccount(
            id: UUID().uuidString,
            email: normalizedEmail,
            displayName: normalizedName,
            role: .member,
            authenticationProvider: .password,
            createdAt: .now
        )
        developmentAccounts.append(account)
        developmentPasswords[normalizedEmail] = password
        currentUser = account
        sessionRestorationFailure = nil
        identify(account)
    }

    func signIn(using provider: AuthenticationProvider) async throws {
        guard !deletionCleanup.blocksEntry, !isProcessing else { throw AuthenticationFailure.serviceUnavailable }
        try prepareForGuestAuthentication?()
        registrationNotice = nil
        guard environment == .development, client == nil else {
            throw AuthenticationFailure.providerUnavailable
        }

        var planner = DevelopmentAccountFixtures.planner
        planner.authenticationProvider = provider
        currentUser = planner
        sessionRestorationFailure = nil
        identify(planner)
    }

    func signInWithApple(
        _ identity: AppleIdentity,
        requestingSignUp: Bool
    ) async throws {
        guard !deletionCleanup.blocksEntry, !isProcessing else { throw AuthenticationFailure.serviceUnavailable }
        registrationNotice = nil

        guard let client else {
            try await signIn(using: .apple)
            return
        }

        try prepareForGuestAuthentication?()
        isProcessing = true
        defer { isProcessing = false }
        let account = try await client.signInWithApple(
            identity,
            requestingSignUp: requestingSignUp
        )
        currentUser = account
        sessionRestorationFailure = nil
        identify(account)
    }

    func signInWithGoogle(
        identityToken: String,
        nonce: String,
        requestingSignUp: Bool
    ) async throws {
        guard !deletionCleanup.blocksEntry, !isProcessing else { throw AuthenticationFailure.serviceUnavailable }
        registrationNotice = nil

        guard let client else {
            try await signIn(using: .google)
            return
        }

        try prepareForGuestAuthentication?()
        isProcessing = true
        defer { isProcessing = false }
        let account = try await client.signInWithGoogle(
            identityToken: identityToken,
            nonce: nonce,
            requestingSignUp: requestingSignUp
        )
        currentUser = account
        sessionRestorationFailure = nil
        identify(account)
    }

    @discardableResult
    func updateProfile(displayName: String) -> Bool {
        let normalizedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedName.isEmpty, var account = currentUser else { return false }

        account.displayName = normalizedName
        currentUser = account

        if let index = developmentAccounts.firstIndex(where: { $0.id == account.id }) {
            developmentAccounts[index] = account
        }
        return true
    }

    @discardableResult
    func signOut(keepingPendingChanges: Bool = false) async -> Bool {
        guard !deletionCleanup.blocksEntry, !isProcessing, !isSigningOut else { return false }
        isSigningOut = true
        isProcessing = true
        signOutNeedsAttention = false
        defer { isSigningOut = false; isProcessing = false }
        do {
            // Keep the bearer alive until the final outbox and media sync.
            try await prepareForSignOut?(keepingPendingChanges)
        } catch {
            SyncDiagnostics.record("sign_out_sync_failed", error: error)
            signOutNeedsAttention = true
            return false
        }
        await client?.signOut()
        PostHogSDK.shared.reset()
        currentUser = nil
        registrationNotice = nil
        return true
    }

    func deleteAccount() async throws {
        guard !isProcessing, !deletionCleanup.blocksEntry else { throw AuthenticationFailure.serviceUnavailable }
        guard let account = currentUser else {
            throw AuthenticationFailure.invalidSession
        }

        isProcessing = true
        defer { isProcessing = false }
        accountDeletionNeedsAttention = false
        try deletionCleanup.begin(accountID: account.id)
        var sentRemoteRequest = false
        do {
            try await prepareForAccountDeletion?(account.id)
            try Task.checkCancellation()
            if let client {
                sentRemoteRequest = true
                try await client.deleteAccount()
            } else {
                developmentAccounts.removeAll { $0.id == account.id }
                developmentPasswords.removeValue(forKey: account.email.lowercased())
            }
        } catch {
            // A transport failure after sending can mean the server deleted
            // the account but its acknowledgement was lost. Keep that intent
            // for explicit device-only resolution; never repeat remote delete.
            let rejected: Bool
            switch error as? AuthenticationFailure {
            case .reauthenticationRequired, .invalidSession, .invalidCredentials, .emailNotVerified,
                 .invalidRegistration, .accountAlreadyExists, .providerUnavailable:
                rejected = true
            default: rejected = false
            }
            if !sentRemoteRequest || rejected { deletionCleanup.cancelUnconfirmedRequest() }
            accountDeletionNeedsAttention = !deletionCleanup.blocksEntry
            await resumeAfterFailedAccountDeletion?(account)
            throw error
        }
        deletionCleanup.confirmRemoteDeletion()
        // The account must be deleted remotely before its local sharing
        // credentials are removed. Normal sign-out keeps them account scoped.
        removeSavedShareLinks?(account.id)
        PostHogSDK.shared.reset()
        currentUser = nil
        registrationNotice = nil
        sessionRestorationFailure = nil
        await deletionCleanup.retry()
    }

    /// Clears only the matching in-memory identity while an explicit device
    /// cleanup is in progress. This never calls the remote deletion endpoint.
    func clearAccountForDeviceCleanup(accountID: String) {
        guard currentUser?.id == accountID else { return }
        currentUser = nil
        registrationNotice = nil
        sessionRestorationFailure = nil
        PostHogSDK.shared.reset()
    }

    private func identify(_ account: UserAccount) {
        PostHogSDK.shared.identify(
            account.id,
            userProperties: [
                "email": account.email,
                "name": account.displayName,
                "role": account.role.rawValue,
                "authentication_provider": account.authenticationProvider.rawValue
            ]
        )
    }
}
