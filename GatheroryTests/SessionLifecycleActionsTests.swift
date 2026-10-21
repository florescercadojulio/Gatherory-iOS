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
        #expect(fixture.authentication.localGuestProfile == fixture.profile)
        #expect(fixture.profiles.profile == fixture.profile)
        #expect(fixture.credentials.tokens[fixture.profile.id] == fixture.proof)
        #expect(fixture.authentication.notificationPrincipal == nil)
        #expect(fixture.notifications.activePrincipal == nil)
        #expect(fixture.persistence.activeUserID == nil)
        #expect(fixture.library.workspaces.isEmpty)
        #expect(try fixture.savedRecords().isEmpty)

        await #expect(throws: AuthenticationFailure.guestDataUnavailable) {
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
    private(set) var signInCalls = 0
    func restoreSession() async throws -> UserAccount? { nil }
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
