import Foundation
import SwiftData
import Testing
@testable import Gatherory

@MainActor
struct SessionLifecycleActionsTests {
    @Test("Installed guest removal hooks keep partially removed data behind recovery and allow cleanup retry")
    func incompleteGuestRemovalCannotReenterOrSignIn() async throws {
        let fixture = try LifecycleActionsFixture()
        defer { fixture.cleanup() }
        let workspace = fixture.addGuestPlan(title: "Guest dinner")
        try fixture.persistence.saveChanges(in: fixture.library)
        #expect(try fixture.savedRecords().map(\.id) == [workspace.mainEventID])
        await fixture.notifications.activate(identity: fixture.authentication.notificationPrincipal)
        #expect(fixture.notifications.activePrincipal == .guest(id: fixture.profile.id))
        fixture.profiles.failRemove = true

        await #expect(throws: CocoaError.self) { try await fixture.authentication.discardGuestSession() }

        #expect(fixture.authentication.guestDiscardNeedsAttention)
        #expect(fixture.authentication.localGuestProfile?.id == fixture.profile.id)
        #expect(fixture.authentication.localGuestProfile?.discardPending == true)
        #expect(fixture.profiles.profile?.discardPending == true)
        #expect(fixture.credentials.tokens[fixture.profile.id] == nil)
        #expect(fixture.authentication.notificationPrincipal == nil)
        #expect(fixture.notifications.activePrincipal == nil)
        #expect(fixture.persistence.activeUserID == nil)
        #expect(fixture.library.workspaces.isEmpty)
        #expect(try fixture.savedRecords().isEmpty)

        await #expect(throws: AuthenticationFailure.serviceUnavailable) {
            try await fixture.authentication.signIn(email: "morgan@example.com", password: "test-password")
        }
        #expect(fixture.client.signInCalls == 0)
        #expect(fixture.authentication.currentUser == nil)
        #expect(fixture.persistence.activeUserID == nil)
        #expect(try fixture.savedRecords().isEmpty)

        fixture.profiles.failRemove = false
        try await fixture.authentication.discardGuestSession()

        #expect(!fixture.authentication.guestDiscardNeedsAttention)
        #expect(fixture.authentication.localGuestProfile == nil)
        #expect(fixture.profiles.profile == nil)
        #expect(fixture.credentials.tokens[fixture.profile.id] == nil)
        #expect(fixture.authentication.notificationPrincipal == nil)
        #expect(fixture.persistence.activeUserID == nil)
        #expect(try fixture.savedRecords().isEmpty)
    }

    @Test("Installed sign-in hook saves a new guest plan before the authentication response")
    func guestPlanIsDurableBeforeAccountAuthentication() async throws {
        let fixture = try LifecycleActionsFixture()
        defer { fixture.cleanup() }
        let workspace = fixture.addGuestPlan(title: "Unsaved guest dinner")
        #expect(try fixture.savedRecords().isEmpty)
        var checkedDurableSaveBeforeResponse = false
        fixture.client.beforeSignInResponse = {
            let record = try #require(fixture.savedRecords().first)
            let archive = try WorkspaceArchiveCodec().decode(WorkspaceArchiveV1.self, from: record.payload)
            #expect(record.id == workspace.mainEventID)
            #expect(record.ownerUserID == fixture.profile.storageID)
            #expect(archive.title == "Unsaved guest dinner")
            #expect(fixture.authentication.currentUser == nil)
            #expect(fixture.persistence.activeUserID == fixture.profile.storageID)
            #expect(fixture.profiles.profile == fixture.profile)
            #expect(fixture.credentials.tokens[fixture.profile.id] == fixture.proof)
            let context = ModelContext(fixture.persistence.container)
            #expect(try context.fetch(FetchDescriptor<PendingMutation>()).isEmpty)
            checkedDurableSaveBeforeResponse = true
        }

        try await fixture.authentication.signIn(email: "morgan@example.com", password: "test-password")

        #expect(checkedDurableSaveBeforeResponse)
        #expect(fixture.client.signInCalls == 1)
        #expect(fixture.authentication.currentUser?.id == LifecycleActionsAuthenticationClient.user.id)
        #expect(fixture.authentication.hasPendingGuestImport)
        #expect(fixture.authentication.notificationPrincipal == nil)
        #expect(fixture.profiles.profile == fixture.profile)
        #expect(try fixture.savedRecords().count == 1)
    }

    @Test("A claimed guest handover retries cleanup without reimporting or regenerating its proof")
    func claimedGuestCleanupSkipsImportAndClaimAfterRelaunchBoundary() async throws {
        let fixture = try LifecycleActionsFixture()
        defer { fixture.cleanup() }
        let guestWorkspace = fixture.addGuestPlan(title: "Claimed guest plan")
        try fixture.persistence.saveChanges(in: fixture.library)
        try await fixture.authentication.signIn(email: "morgan@example.com", password: "test-password")
        let account = try #require(fixture.authentication.currentUser)
        await fixture.cloudSync.activate(userID: account.id, seedData: false)

        _ = try fixture.persistence.importLocalGuest(fixture.profile, into: account, in: fixture.library)
        try fixture.authentication.markGuestHandoverReadyForCleanup(
            profileID: fixture.profile.id,
            accountID: account.id
        )
        let importedCopy = try #require(fixture.library.workspaces.first { $0.mainEventID == guestWorkspace.mainEventID })
        fixture.library.remove(importedCopy)
        try fixture.persistence.saveChanges(in: fixture.library)
        #expect(try fixture.persistence.guestImportAccountID(fixture.profile) == account.id)

        var claimCalls = 0
        var services = LiveSessionPreparationServices(
            authentication: fixture.authentication,
            library: fixture.library,
            cloudSync: fixture.cloudSync,
            persistence: fixture.persistence,
            guestInvitations: fixture.guestInvitations,
            notifications: fixture.notifications,
            usesRemoteAccountState: true,
            seedsDevelopmentData: false,
            baseURL: nil,
            claimGuestAttendance: { _ in claimCalls += 1 }
        )
        let cleanupProfile = try #require(fixture.authentication.localGuestProfile)
        fixture.profiles.failRemove = true
        await #expect(throws: CocoaError.self) {
            try await services.transferGuest(cleanupProfile, into: account, validate: {})
        }

        #expect(claimCalls == 0)
        #expect(fixture.profiles.profile?.handoverCleanupAccountID == account.id)
        #expect(fixture.credentials.tokens[fixture.profile.id] == nil)
        #expect(try fixture.savedRecords().allSatisfy { $0.ownerUserID != fixture.profile.storageID })

        fixture.profiles.failRemove = false
        fixture.client.restoredUser = account
        let relaunched = AuthenticationSession(
            environment: .production,
            skipsAuthentication: false,
            client: fixture.client,
            guestProfileStore: fixture.profiles,
            guestCredentialStore: fixture.credentials
        )
        await relaunched.restoreSession()
        let relaunchedServices = LiveSessionPreparationServices(
            authentication: relaunched,
            library: fixture.library,
            cloudSync: fixture.cloudSync,
            persistence: fixture.persistence,
            guestInvitations: fixture.guestInvitations,
            notifications: fixture.notifications,
            usesRemoteAccountState: true,
            seedsDevelopmentData: false,
            baseURL: nil,
            claimGuestAttendance: { _ in claimCalls += 1 }
        )
        let relaunchedProfile = try #require(relaunched.localGuestProfile)
        try await relaunchedServices.transferGuest(relaunchedProfile, into: account, validate: {})
        #expect(claimCalls == 0)
        #expect(relaunched.localGuestProfile == nil)
        #expect(fixture.profiles.profile == nil)
        #expect(fixture.credentials.tokens[fixture.profile.id] == nil)
    }
}

@MainActor
private final class LifecycleActionsFixture {
    let profile = LocalGuestProfile(displayName: "Morgan")
    let profiles = MemoryLocalGuestProfileStore()
    let credentials = MemoryLocalGuestCredentialStore()
    let client = LifecycleActionsAuthenticationClient()
    let persistence: WorkspacePersistenceController
    let library: WorkspaceLibrary
    let cloudSync: WorkspaceCloudSyncController
    let authentication: AuthenticationSession
    let notifications: NotificationController
    let guestInvitations: GuestInvitationStore
    let proof: String
    private let defaultsDomain: String
    private let defaults: UserDefaults
    private let cacheDirectory: URL

    init() throws {
        defaultsDomain = "SessionLifecycleActionsTests-\(UUID())"
        defaults = try #require(UserDefaults(suiteName: defaultsDomain))
        cacheDirectory = FileManager.default.temporaryDirectory.appending(path: defaultsDomain)
        persistence = try WorkspacePersistenceController(isStoredInMemoryOnly: true)
        library = persistence.restoreLibrary(seedData: false)
        cloudSync = WorkspaceCloudSyncController(
            persistence: persistence, library: library, baseURL: nil, usesRemoteAccountState: false
        )
        try profiles.save(profile)
        authentication = AuthenticationSession(
            environment: .production, skipsAuthentication: false, client: client,
            guestProfileStore: profiles, guestCredentialStore: credentials
        )
        proof = try credentials.loadOrCreateToken(profileID: profile.id)
        try persistence.activateLocalGuest(profile, in: library)
        notifications = NotificationController(
            baseURL: nil, configured: false,
            installationStore: LifecycleActionsInstallationStore(),
            guestCredentials: credentials,
            tokenProvider: LifecycleActionsTokenProvider(),
            preferences: defaults
        )
        guestInvitations = GuestInvitationStore(baseURL: nil, cacheDirectory: cacheDirectory)
        SessionLifecycleActions(
            authentication: authentication, library: library, persistence: persistence,
            cloudSync: cloudSync, guestInvitations: guestInvitations, notifications: notifications
        ).install()
    }

    func addGuestPlan(title: String) -> PlanningWorkspace {
        let workspace = PlanningWorkspace.newLocalGuestWorkspace(
            title: title, startsAt: .now, eventLocation: nil, imageData: nil, guest: profile
        )
        library.add(workspace)
        return workspace
    }

    func savedRecords() throws -> [WorkspaceRecord] {
        try ModelContext(persistence.container).fetch(FetchDescriptor<WorkspaceRecord>())
    }

    func cleanup() {
        client.beforeSignInResponse = nil
        defaults.removePersistentDomain(forName: defaultsDomain)
        try? FileManager.default.removeItem(at: cacheDirectory)
    }
}

@MainActor
private final class LifecycleActionsAuthenticationClient: AuthenticationClient {
    static let user = UserAccount(
        id: "lifecycle-actions-account", email: "morgan@example.com", displayName: "Morgan",
        role: .member, authenticationProvider: .password, createdAt: .distantPast
    )
    var beforeSignInResponse: (() throws -> Void)?
    var restoredUser: UserAccount?
    private(set) var signInCalls = 0
    func restoreSession() async throws -> UserAccount? { restoredUser }
    func signIn(email: String, password: String) async throws -> UserAccount {
        signInCalls += 1
        try beforeSignInResponse?()
        return Self.user
    }
    func register(displayName: String, email: String, password: String) async throws -> RegistrationOutcome {
        .authenticated(Self.user)
    }
    func signInWithApple(_ identity: AppleIdentity, requestingSignUp: Bool) async throws -> UserAccount { Self.user }
    func signInWithGoogle(identityToken: String, nonce: String, requestingSignUp: Bool) async throws -> UserAccount { Self.user }
    func signOut() async {}
    func deleteAccount() async throws {}
}

@MainActor
private struct LifecycleActionsInstallationStore: NotificationInstallationStoring {
    func loadIfExists() throws -> NotificationInstallation? { nil }
    func loadOrCreate() throws -> NotificationInstallation { throw AuthenticationFailure.serviceUnavailable }
    func nextRevision(minimum: Int) throws -> NotificationInstallation { throw AuthenticationFailure.serviceUnavailable }
    func markMayBeBound() throws {}
    func markDetached() throws {}
}

@MainActor
private struct LifecycleActionsTokenProvider: NotificationTokenProviding {
    func currentToken() async throws -> String? { nil }
    func setAutoInitEnabled(_ enabled: Bool) {}
}
