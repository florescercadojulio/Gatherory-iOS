import Foundation
import SwiftData
import Testing
@testable import Gatherory

@MainActor
struct OfflineAccountRestorationTests {
    private static let account = UserAccount(
        id: "offline-account-a",
        email: "morgan@example.com",
        displayName: "Morgan",
        role: .member,
        authenticationProvider: .password,
        createdAt: Date(timeIntervalSinceReferenceDate: 900_000_000)
    )

    @Test("A token-matched cached account opens locally while network validation continues")
    func transientRestoreUsesCachedAccountLocally() async {
        let client = OfflineRestoreAuthenticationClient(cachedAccount: Self.account)
        client.restoreFailure = AuthenticationFailure.networkUnavailable
        let authentication = makeSession(client)

        await authentication.restoreSession()

        #expect(authentication.currentUser == Self.account)
        #expect(authentication.isOfflineAccountSession)
        #expect(authentication.isSessionRestorationUnavailable)
        #expect(authentication.notificationPrincipal == nil)
        #expect(client.cacheReadCount == 1)

        await authentication.revalidateOfflineSession()
        #expect(authentication.currentUser == Self.account)
        #expect(authentication.isOfflineAccountSession)
        #expect(authentication.isSessionRestorationUnavailable)
    }

    @Test("Without a token-matched profile, offline restore remains in retry recovery")
    func unavailableRestoreWithoutCachedProfileStaysInRecovery() async {
        let client = OfflineRestoreAuthenticationClient(cachedAccount: nil)
        client.restoreFailure = AuthenticationFailure.networkUnavailable
        let authentication = makeSession(client)

        await authentication.restoreSession()

        #expect(authentication.currentUser == nil)
        #expect(!authentication.isOfflineAccountSession)
        #expect(authentication.isSessionRestorationUnavailable)
        #expect(client.cacheReadCount == 2)
    }

    @Test("Explicit sign out clears the offline identity and account cache")
    func explicitSignOutClearsOfflineIdentity() async {
        let client = OfflineRestoreAuthenticationClient(cachedAccount: Self.account)
        client.restoreFailure = AuthenticationFailure.networkUnavailable
        let authentication = makeSession(client)
        await authentication.restoreSession()
        var keepsPendingChanges = false
        authentication.prepareForSignOut = { keepsPendingChanges = $0 }

        #expect(await authentication.signOut())
        #expect(keepsPendingChanges)
        #expect(authentication.currentUser == nil)
        #expect(!authentication.isOfflineAccountSession)
        #expect(client.clearCacheCount == 1)
    }

    @Test("A cold offline relaunch restores only the saved account archive and keeps queued mutation IDs")
    func diskRelaunchRestoresAccountArchiveAndOutbox() async throws {
        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("gatherory-offline-\(UUID().uuidString).sqlite")
        defer {
            try? FileManager.default.removeItem(at: storeURL)
            try? FileManager.default.removeItem(atPath: storeURL.path + "-shm")
            try? FileManager.default.removeItem(atPath: storeURL.path + "-wal")
        }

        let originalMutationIDs = try seedAccountArchives(at: storeURL)
        let client = OfflineRestoreAuthenticationClient(cachedAccount: Self.account)
        client.restoreFailure = AuthenticationFailure.networkUnavailable
        let authentication = makeSession(client)
        await authentication.restoreSession()
        #expect(authentication.isOfflineAccountSession)
        #expect(authentication.currentUser?.id == Self.account.id)

        let editedIDs = try await hydrateAndEditOfflineAccount(
            at: storeURL,
            originalMutationIDs: originalMutationIDs
        )
        let relaunchedPersistence = try WorkspacePersistenceController(storeURL: storeURL)
        let relaunchedLibrary = WorkspaceLibrary()
        relaunchedPersistence.activate(userID: Self.account.id, in: relaunchedLibrary)
        #expect(relaunchedLibrary.workspaces.map(\.eventMessage) == ["Saved without a connection"])
        #expect(try pendingMutationIDs(in: relaunchedPersistence, ownerUserID: Self.account.id) == editedIDs)

        let destination = AuthenticationFlowChain.default.destination(for: AuthenticationFlowContext(
            isAuthenticated: true,
            preparedIdentityMatches: false,
            hasLocalAccountLibraryReady: true,
            usesRemoteAccountState: true,
            accountOnboardingState: .unavailable,
            isOfflineAccountSession: true
        ))
        #expect(destination == .app)

        let recoveringDestination = AuthenticationFlowChain.default.destination(for: AuthenticationFlowContext(
            isAuthenticated: true,
            hasLocalAccountLibraryReady: true,
            usesRemoteAccountState: true,
            accountOnboardingState: .unavailable,
            accountPreparationFailed: true
        ))
        #expect(recoveringDestination == .app)
    }

    @Test("An online retry that confirms expiry clears offline identity and cached account")
    func confirmedExpiryLeavesOfflineScope() async {
        let client = OfflineRestoreAuthenticationClient(cachedAccount: Self.account)
        client.restoreFailure = AuthenticationFailure.networkUnavailable
        let authentication = makeSession(client)
        await authentication.restoreSession()
        #expect(authentication.isOfflineAccountSession)

        client.restoreFailure = AuthenticationFailure.invalidSession
        await authentication.retrySessionRestoration()

        #expect(authentication.currentUser == nil)
        #expect(!authentication.isOfflineAccountSession)
        #expect(!authentication.isSessionRestorationUnavailable)
        #expect(client.clearCacheCount == 1)
    }

    @Test("The cached account profile is bound to the exact bearer token")
    func accountCacheRejectsDifferentToken() throws {
        let tokenStore = MemorySessionTokenStore(token: "token-a")
        let cache = MemoryValidatedAccountCache()
        let client = BetterAuthClient(
            baseURL: URL(string: "https://app.gatherory.com")!,
            tokenStore: tokenStore,
            accountCache: cache
        )
        try client.cacheValidatedAccount(Self.account)
        #expect(try client.cachedAccountForOfflineRestoration() == Self.account)

        tokenStore.token = "token-b"
        #expect(try client.cachedAccountForOfflineRestoration() == nil)
    }

    @Test("Keychain account cache survives client recreation and remains token scoped")
    func keychainAccountCacheUsesTokenScopedNamespace() throws {
        let bundleIdentifier = "com.gatherory.offline-cache-tests.\(UUID().uuidString)"
        let writer = KeychainValidatedAccountCache(bundleIdentifier: bundleIdentifier)
        let reader = KeychainValidatedAccountCache(bundleIdentifier: bundleIdentifier)
        defer { reader.clear() }

        try writer.save(Self.account, matching: "cached-token")
        #expect(try reader.account(matching: "cached-token") == Self.account)
        #expect(try reader.account(matching: "different-token") == nil)

        reader.clear()
        #expect(try writer.account(matching: "cached-token") == nil)
    }

    private func hydrateAndEditOfflineAccount(
        at storeURL: URL,
        originalMutationIDs: Set<UUID>
    ) async throws -> Set<UUID> {
        let persistence = try WorkspacePersistenceController(storeURL: storeURL)
        let library = WorkspaceLibrary()
        let transport = SuspendedSnapshotTransport()
        let cloudSync = WorkspaceCloudSyncController(
            persistence: persistence,
            library: library,
            baseURL: URL(string: "https://app.gatherory.com"),
            transport: transport,
            usesRemoteAccountState: true
        )
        let activation = Task {
            await cloudSync.activate(userID: Self.account.id, seedData: false)
        }
        await transport.waitForBootstrapStart()

        #expect(library.workspaces.map(\.title) == ["Account A offline edit"])
        #expect(library.workspaces.allSatisfy { $0.members.contains(where: { $0.userID == Self.account.id }) })
        #expect(cloudSync.accountOnboardingState == .resolving)

        let destination = AuthenticationFlowChain.default.destination(for: AuthenticationFlowContext(
            isAuthenticated: true,
            preparedIdentityMatches: false,
            hasLocalAccountLibraryReady: true,
            usesRemoteAccountState: true,
            accountOnboardingState: cloudSync.accountOnboardingState,
            isOfflineAccountSession: true
        ))
        #expect(destination == .app)

        transport.failBootstrap()
        await activation.value
        #expect(cloudSync.accountOnboardingState == .complete)

        let persistedIDs = try pendingMutationIDs(in: persistence, ownerUserID: Self.account.id)
        #expect(!persistedIDs.isEmpty)
        #expect(persistedIDs == originalMutationIDs)

        let editedWorkspace = try #require(library.workspaces.first)
        editedWorkspace.eventMessage = "Saved without a connection"
        persistence.onPendingMutations = nil
        try persistence.saveChanges(in: library)
        let editedIDs = try pendingMutationIDs(in: persistence, ownerUserID: Self.account.id)
        #expect(editedIDs == persistedIDs)
        return editedIDs
    }

    private func makeSession(_ client: OfflineRestoreAuthenticationClient) -> AuthenticationSession {
        AuthenticationSession(
            environment: .production,
            skipsAuthentication: false,
            client: client,
            guestProfileStore: MemoryLocalGuestProfileStore(),
            guestCredentialStore: MemoryLocalGuestCredentialStore()
        )
    }

    private func seedAccountArchives(at storeURL: URL) throws -> Set<UUID> {
        let persistence = try WorkspacePersistenceController(storeURL: storeURL)
        let accountB = UserAccount(
            id: "offline-account-b",
            email: "casey@example.com",
            displayName: "Casey",
            role: .member,
            authenticationProvider: .password,
            createdAt: Date(timeIntervalSinceReferenceDate: 900_000_100)
        )

        var accountAMutationIDs = Set<UUID>()
        for (account, title) in [(Self.account, "Account A offline edit"), (accountB, "Account B private archive")] {
            let library = WorkspaceLibrary()
            persistence.activate(userID: account.id, in: library)
            let workspace = PlanningWorkspace.newWorkspace(
                title: title,
                startsAt: .now,
                eventLocation: nil,
                imageData: nil,
                owner: account
            )
            library.add(workspace)
            try persistence.saveChanges(in: library)
            if account.id == Self.account.id {
                accountAMutationIDs = try pendingMutationIDs(in: persistence, ownerUserID: account.id)
            }
        }
        return accountAMutationIDs
    }

    private func pendingMutationIDs(
        in persistence: WorkspacePersistenceController,
        ownerUserID: String
    ) throws -> Set<UUID> {
        Set(try persistence.container.mainContext.fetch(FetchDescriptor<PendingMutation>())
            .filter { $0.ownerUserID == ownerUserID }
            .map(\.id))
    }
}

private final class OfflineRestoreAuthenticationClient: AuthenticationClient, @unchecked Sendable {
    private let cachedAccount: UserAccount?
    private let lock = NSLock()
    private var failure: AuthenticationFailure?
    private var cacheReads = 0
    private var cacheClears = 0

    init(cachedAccount: UserAccount?) {
        self.cachedAccount = cachedAccount
    }

    var restoreFailure: AuthenticationFailure? {
        get { lock.withLock { failure } }
        set { lock.withLock { failure = newValue } }
    }
    var cacheReadCount: Int { lock.withLock { cacheReads } }
    var clearCacheCount: Int { lock.withLock { cacheClears } }

    func restoreSession() async throws -> UserAccount? {
        if let failure = lock.withLock({ failure }) { throw failure }
        return cachedAccount
    }

    func cachedAccountForOfflineRestoration() throws -> UserAccount? {
        lock.withLock { cacheReads += 1 }
        return cachedAccount
    }

    func clearCachedAccount() {
        lock.withLock { cacheClears += 1 }
    }

    func signIn(email: String, password: String) async throws -> UserAccount { cachedAccount! }
    func register(displayName: String, email: String, password: String) async throws -> RegistrationOutcome {
        .authenticated(cachedAccount!)
    }
    func signInWithApple(_ identity: AppleIdentity, requestingSignUp: Bool) async throws -> UserAccount { cachedAccount! }
    func signInWithGoogle(identityToken: String, nonce: String, requestingSignUp: Bool) async throws -> UserAccount { cachedAccount! }
    func deleteAccount() async throws {}
    func signOut() async {}
}

private final class MemorySessionTokenStore: SessionTokenStore, @unchecked Sendable {
    private let lock = NSLock()
    private var storedToken: String?

    init(token: String?) { storedToken = token }
    var token: String? {
        get { lock.withLock { storedToken } }
        set { lock.withLock { storedToken = newValue } }
    }
    func read() throws -> String? { token }
    func save(_ token: String) throws { self.token = token }
    func delete() { token = nil }
}

private final class MemoryValidatedAccountCache: ValidatedAccountCache, @unchecked Sendable {
    private let lock = NSLock()
    private var savedAccount: UserAccount?
    private var token: String?

    func account(matching token: String) throws -> UserAccount? {
        lock.withLock { self.token == token ? savedAccount : nil }
    }

    func save(_ account: UserAccount, matching token: String) throws {
        lock.withLock {
            savedAccount = account
            self.token = token
        }
    }

    func clear() {
        lock.withLock {
            savedAccount = nil
            token = nil
        }
    }
}

@MainActor
private final class SuspendedSnapshotTransport: WorkspaceSnapshotTransport {
    private var bootstrapContinuation: CheckedContinuation<SyncBootstrapResponse, any Error>?
    private var hasStartedBootstrap = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []

    func bootstrap() async throws -> SyncBootstrapResponse {
        try await withCheckedThrowingContinuation { continuation in
            bootstrapContinuation = continuation
            hasStartedBootstrap = true
            startWaiters.forEach { $0.resume() }
            startWaiters.removeAll()
        }
    }

    func waitForBootstrapStart() async {
        if hasStartedBootstrap { return }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func failBootstrap() {
        bootstrapContinuation?.resume(throwing: AuthenticationFailure.networkUnavailable)
        bootstrapContinuation = nil
    }

    func push(_ mutations: [PendingMutationSnapshot]) async throws -> SyncPushResponse {
        throw AuthenticationFailure.networkUnavailable
    }

    func pull(scopeID: UUID, after cursor: String?) async throws -> SyncPullPage {
        throw AuthenticationFailure.networkUnavailable
    }
}
