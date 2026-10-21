import Foundation
import SwiftData
import Testing
@testable import Gatherory

@MainActor
struct AccountDeletionLocalCleanupTests {
    private enum CleanupFailure: Error, Equatable { case artifact, credential }

    @Test("A failed account artifact does not skip later cleanup or disturb the active account, and retry succeeds")
    func artifactFailureContinuesAndRetries() async throws {
        let fixture = try await makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let generation = fixture.persistence.activeUserGeneration
        let pendingIDs = try pendingMutationIDs(fixture.persistence, ownerID: fixture.accountB)
        #expect(!pendingIDs.isEmpty)
        #expect(fixture.persistence.hasUnsavedLocalChanges)
        var shouldFail = true
        var visited: [String] = []
        var credentialRemovals = 0
        let cleanup = fixture.cleanup(removeSessionCredential: { credentialRemovals += 1 }, artifacts: [
            { accountID in
                visited.append("first:\(accountID)")
                if shouldFail { throw CleanupFailure.artifact }
            },
            { visited.append("second:\($0)") }
        ])

        await #expect(throws: CleanupFailure.artifact) {
            try await cleanup.remove(accountID: fixture.accountA, canRemoveSessionCredential: false)
        }
        #expect(visited == ["first:\(fixture.accountA)", "second:\(fixture.accountA)"])
        #expect(credentialRemovals == 0)
        try assertDeletedAndRetained(fixture, generation: generation, pendingIDs: pendingIDs)

        shouldFail = false
        try await cleanup.remove(accountID: fixture.accountA, canRemoveSessionCredential: false)
        #expect(visited == ["first:\(fixture.accountA)", "second:\(fixture.accountA)",
            "first:\(fixture.accountA)", "second:\(fixture.accountA)"])
        #expect(credentialRemovals == 0)
        try assertDeletedAndRetained(fixture, generation: generation, pendingIDs: pendingIDs)

        // The retained account's scheduled edit still belongs to its original namespace.
        try fixture.persistence.saveChanges(in: fixture.library)
        let record = try #require(ModelContext(fixture.persistence.container)
            .fetch(FetchDescriptor<WorkspaceRecord>()).first { $0.ownerUserID == fixture.accountB })
        #expect(try WorkspaceArchiveCodec().decode(WorkspaceArchiveV1.self, from: record.payload).title == "Pending B edit")
    }

    @Test("Session credential deletion failure still finishes other cleanup and supports retry")
    func credentialFailureContinuesAndRetries() async throws {
        let fixture = try await makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let generation = fixture.persistence.activeUserGeneration
        let pendingIDs = try pendingMutationIDs(fixture.persistence, ownerID: fixture.accountB)
        var shouldFail = true
        var credentialRemovals = 0
        var artifactAccounts: [String] = []
        let cleanup = fixture.cleanup(removeSessionCredential: {
            credentialRemovals += 1
            if shouldFail { throw CleanupFailure.credential }
        }, artifacts: [{ artifactAccounts.append($0) }])

        await #expect(throws: CleanupFailure.credential) {
            try await cleanup.remove(accountID: fixture.accountA, canRemoveSessionCredential: true)
        }
        #expect(artifactAccounts == [fixture.accountA])
        #expect(credentialRemovals == 1)
        try assertDeletedAndRetained(fixture, generation: generation, pendingIDs: pendingIDs)

        shouldFail = false
        try await cleanup.remove(accountID: fixture.accountA, canRemoveSessionCredential: true)
        #expect(artifactAccounts == [fixture.accountA, fixture.accountA])
        #expect(credentialRemovals == 2)
        try assertDeletedAndRetained(fixture, generation: generation, pendingIDs: pendingIDs)
        try fixture.persistence.saveChanges(in: fixture.library)
    }

    private func assertDeletedAndRetained(_ fixture: Fixture, generation: UUID, pendingIDs: Set<UUID>) throws {
        let context = ModelContext(fixture.persistence.container)
        let records = try context.fetch(FetchDescriptor<WorkspaceRecord>())
        #expect(records.map(\.ownerUserID) == [fixture.accountB])
        #expect(try pendingMutationIDs(fixture.persistence, ownerID: fixture.accountA).isEmpty)
        #expect(try pendingMutationIDs(fixture.persistence, ownerID: fixture.accountB) == pendingIDs)
        #expect(fixture.persistence.activeUserID == fixture.accountB)
        #expect(fixture.persistence.activeUserGeneration == generation)
        #expect(fixture.library.workspaces.count == 1)
        #expect(fixture.library.workspaces.first === fixture.workspaceB)
        #expect(fixture.workspaceB.title == "Pending B edit")
        #expect(fixture.persistence.hasUnsavedLocalChanges)
        #expect(fixture.defaults.object(forKey: "accountOnboardingComplete.\(fixture.accountA)") == nil)
        #expect(fixture.defaults.bool(forKey: "accountOnboardingComplete.\(fixture.accountB)"))
        #expect(fixture.defaults.object(forKey: "notifications.enabled.user:\(fixture.accountA)") == nil)
        #expect(fixture.defaults.bool(forKey: "notifications.enabled.user:\(fixture.accountB)"))
        #expect(fixture.defaults.object(forKey: "hiddenImages.\(fixture.accountA)") == nil)
        #expect(fixture.defaults.stringArray(forKey: "hiddenImages.\(fixture.accountB)") == [fixture.hiddenB.uuidString])
        #expect(fixture.imageSafety.accountID == fixture.accountB)
        #expect(fixture.imageSafety.hiddenIDs == [fixture.hiddenB])
        #expect(fixture.notifications.activePrincipal == .account(id: fixture.accountB))
        #expect(fixture.defaults.string(forKey: "unrelated.preference") == "keep")
    }

    private func pendingMutationIDs(_ persistence: WorkspacePersistenceController, ownerID: String) throws -> Set<UUID> {
        Set(try ModelContext(persistence.container).fetch(FetchDescriptor<PendingMutation>())
            .filter { $0.ownerUserID == ownerID }.map(\.id))
    }

    private func makeFixture() async throws -> Fixture {
        let accountA = "cleanup-delete-\(UUID().uuidString)"
        let accountB = "cleanup-keep-\(UUID().uuidString)"
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let defaults = LocalCleanupMemoryDefaults()
        for account in [accountA, accountB] {
            defaults.set(true, forKey: "accountOnboardingComplete.\(account)")
            defaults.set(true, forKey: "notifications.enabled.user:\(account)")
        }
        let hiddenB = UUID()
        defaults.set([UUID().uuidString], forKey: "hiddenImages.\(accountA)")
        defaults.set([hiddenB.uuidString], forKey: "hiddenImages.\(accountB)")
        defaults.set("keep", forKey: "unrelated.preference")
        let persistence = try WorkspacePersistenceController(isStoredInMemoryOnly: true)
        let library = persistence.restoreLibrary(seedData: false, ownerUserID: accountA)
        library.add(PlanningWorkspace.newWorkspace(title: "Delete A", startsAt: .now,
            eventLocation: nil, imageData: nil))
        try persistence.saveChanges(in: library)
        let sync = WorkspaceCloudSyncController(persistence: persistence, library: library,
            baseURL: nil, usesRemoteAccountState: false)
        await sync.activate(userID: accountB, seedData: false)
        let workspaceB = PlanningWorkspace.newWorkspace(title: "Keep B", startsAt: .now,
            eventLocation: nil, imageData: nil)
        library.add(workspaceB)
        try persistence.saveChanges(in: library)
        persistence.startObserving(library)
        workspaceB.title = "Observation warmup"
        for _ in 0..<10 { await Task.yield() }
        try persistence.saveChanges(in: library)
        workspaceB.title = "Pending B edit"
        for _ in 0..<100 {
            if persistence.hasUnsavedLocalChanges { break }
            await Task.yield()
        }
        let invitations = GuestInvitationStore(baseURL: nil, cacheDirectory: directory)
        let notifications = NotificationController(baseURL: nil, configured: false,
            installationStore: LocalCleanupInstallationStore(),
            guestCredentials: MemoryLocalGuestCredentialStore(), accountTokenStore: LocalCleanupSessionTokenStore(),
            tokenProvider: LocalCleanupNotificationTokenProvider(), preferences: defaults)
        await notifications.activate(identity: .account(id: accountB))
        let imageSafety = ImageSafetyStore(defaults: defaults)
        imageSafety.configure(accountID: accountB)
        return Fixture(accountA: accountA, accountB: accountB, directory: directory, defaults: defaults,
            persistence: persistence, library: library, sync: sync, invitations: invitations,
            notifications: notifications, imageSafety: imageSafety, workspaceB: workspaceB, hiddenB: hiddenB)
    }

    @MainActor private struct Fixture {
        let accountA: String
        let accountB: String
        let directory: URL
        let defaults: UserDefaults
        let persistence: WorkspacePersistenceController
        let library: WorkspaceLibrary
        let sync: WorkspaceCloudSyncController
        let invitations: GuestInvitationStore
        let notifications: NotificationController
        let imageSafety: ImageSafetyStore
        let workspaceB: PlanningWorkspace
        let hiddenB: UUID

        func cleanup(removeSessionCredential: @escaping () throws -> Void,
            artifacts: [(String) throws -> Void]) -> AccountDeletionLocalCleanup {
            AccountDeletionLocalCleanup(library: library, persistence: persistence, cloudSync: sync,
                guestInvitations: invitations, notifications: notifications, imageSafety: imageSafety,
                defaults: defaults, removeSessionCredential: removeSessionCredential, artifactCleanupSteps: artifacts)
        }
    }
}

private final class LocalCleanupMemoryDefaults: UserDefaults, @unchecked Sendable {
    private var values: [String: Any] = [:]
    override func set(_ value: Any?, forKey defaultName: String) { values[defaultName] = value }
    override func removeObject(forKey defaultName: String) { values.removeValue(forKey: defaultName) }
    override func object(forKey defaultName: String) -> Any? { values[defaultName] }
    override func bool(forKey defaultName: String) -> Bool { values[defaultName] as? Bool ?? false }
    override func string(forKey defaultName: String) -> String? { values[defaultName] as? String }
    override func stringArray(forKey defaultName: String) -> [String]? { values[defaultName] as? [String] }
}

@MainActor private final class LocalCleanupInstallationStore: NotificationInstallationStoring {
    private var value = NotificationInstallation(secret: LocalGuestCredentialToken.make())
    func loadIfExists() -> NotificationInstallation? { value }
    func loadOrCreate() -> NotificationInstallation { value }
    func nextRevision(minimum: Int) -> NotificationInstallation {
        value.revision = max(value.revision + 1, minimum)
        return value
    }
    func markMayBeBound() { value.mayBeBound = true }
    func markDetached() { value.mayBeBound = false }
}

private struct LocalCleanupSessionTokenStore: SessionTokenStore {
    func read() -> String? { nil }
    func save(_ token: String) {}
    func delete() {}
}

@MainActor private struct LocalCleanupNotificationTokenProvider: NotificationTokenProviding {
    func currentToken() async throws -> String? { nil }
    func setAutoInitEnabled(_ enabled: Bool) {}
}
