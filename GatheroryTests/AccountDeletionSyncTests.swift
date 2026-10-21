import Foundation
import SwiftData
import Testing
@testable import Gatherory

@MainActor
struct AccountDeletionSyncTests {
    @Test("Deletion suspension and deactivation never deliver queued edits; only explicit purge removes them")
    func deletionStopsDeliveryAndRetainsOutbox() async throws {
        let (persistence, library, sync, transport) = try makeFixture()
        let accountID = "delete-sync-\(UUID().uuidString)"
        await sync.activate(userID: accountID, seedData: false)
        let workspace = addWorkspace(to: library, title: "Queued before deletion")
        try persistence.saveChanges(in: library)
        let mutationIDs = try pendingIDs(persistence, ownerID: accountID)
        #expect(!mutationIDs.isEmpty)
        let bootstrapCount = transport.bootstrapCount

        await sync.suspendForAccountDeletion(accountID: accountID)
        await sync.synchronize()
        await sync.refreshCollaboration()
        await sync.refreshCollaboration(passively: true)
        sync.schedule(trigger: .mutationCreated)
        // This passes the ordinary scheduled-delivery debounce, proving a
        // queued or newly scheduled task cannot start delivery while suspended.
        try await Task.sleep(for: .milliseconds(750))
        #expect(transport.bootstrapCount == bootstrapCount)
        #expect(transport.pushCount == 0)
        #expect(transport.pullCount == 0)
        #expect(try pendingIDs(persistence, ownerID: accountID) == mutationIDs)
        #expect(library.workspaces.first === workspace)

        await sync.deactivateDeletedAccount(accountID: accountID)
        await sync.synchronize()
        await sync.refreshCollaboration()
        sync.schedule(trigger: .appBecameActive)
        #expect(transport.bootstrapCount == bootstrapCount)
        #expect(transport.pushCount == 0)
        #expect(transport.pullCount == 0)
        #expect(persistence.activeUserID == nil)
        #expect(library.workspaces.isEmpty)
        #expect(try pendingIDs(persistence, ownerID: accountID) == mutationIDs)
        #expect(try ModelContext(persistence.container).fetch(FetchDescriptor<WorkspaceRecord>())
            .contains { $0.ownerUserID == accountID && $0.id == workspace.mainEventID })

        try persistence.purgeLocalData(accountID: accountID, from: library)
        #expect(try pendingIDs(persistence, ownerID: accountID).isEmpty)
        #expect(try ModelContext(persistence.container).fetch(FetchDescriptor<WorkspaceRecord>()).isEmpty)
    }

    @Test("A failed deletion resumes delivery only for the suspended account")
    func failedDeletionResumesSync() async throws {
        let (persistence, library, sync, transport) = try makeFixture()
        let accountID = "resume-sync-\(UUID().uuidString)"
        await sync.activate(userID: accountID, seedData: false)
        _ = addWorkspace(to: library, title: "Retry after server failure")
        try persistence.saveChanges(in: library)
        let mutationIDs = try pendingIDs(persistence, ownerID: accountID)
        await sync.suspendForAccountDeletion(accountID: accountID)

        sync.resumeAfterFailedAccountDeletion(accountID: "different-account")
        await sync.synchronize()
        #expect(transport.pushCount == 0)
        #expect(try pendingIDs(persistence, ownerID: accountID) == mutationIDs)

        sync.resumeAfterFailedAccountDeletion(accountID: accountID)
        await sync.synchronize()
        #expect(transport.pushCount > 0)
        #expect(Set(transport.pushedMutations.map(\.id)) == mutationIDs)
        #expect(try pendingIDs(persistence, ownerID: accountID).isEmpty)
        #expect(persistence.activeUserID == accountID)
        #expect(library.workspaces.count == 1)
        await sync.deactivateDeletedAccount(accountID: accountID)
    }

    @Test("Device-only cleanup allows a later explicit sign-in to the existing account to sync again")
    func localOnlyRemovalDoesNotPermanentlySuspendExistingAccount() async throws {
        let (persistence, library, sync, transport) = try makeFixture()
        let accountID = "local-cleanup-signin-\(UUID().uuidString)"
        await sync.activate(userID: accountID, seedData: false)
        _ = addWorkspace(to: library, title: "Device-only edit to remove")
        try persistence.saveChanges(in: library)
        let discardedMutationIDs = try pendingIDs(persistence, ownerID: accountID)
        #expect(!discardedMutationIDs.isEmpty)

        // An ambiguous remote result can lead to explicitly removing only the
        // device copy. Quiescing that session must end when it is deactivated.
        await sync.suspendForAccountDeletion(accountID: accountID)
        await sync.deactivateDeletedAccount(accountID: accountID)
        try persistence.purgeLocalData(accountID: accountID, from: library)
        #expect(transport.pushCount == 0)
        #expect(try pendingIDs(persistence, ownerID: accountID).isEmpty)

        let serverWorkspace = PlanningWorkspace.newWorkspace(title: "Existing server plan", startsAt: .now,
            eventLocation: nil, imageData: nil)
        transport.bootstrapSnapshots = [RemoteWorkspaceSnapshot(scopeID: serverWorkspace.mainEventID,
            payload: try WorkspaceArchiveCodec().encode(WorkspaceArchiveV1(workspace: serverWorkspace)),
            serverVersion: 1, updatedAt: .now)]
        await sync.activate(userID: accountID, seedData: false)
        #expect(transport.bootstrapCount == 2)
        #expect(persistence.activeUserID == accountID)
        let restored = try #require(library.workspaces.first)
        #expect(restored.mainEventID == serverWorkspace.mainEventID)
        restored.title = "New edit after explicit sign-in"
        try persistence.saveChanges(in: library)
        let newMutationIDs = try pendingIDs(persistence, ownerID: accountID)
        #expect(!newMutationIDs.isEmpty)
        #expect(newMutationIDs.isDisjoint(with: discardedMutationIDs))

        await sync.synchronize()
        #expect(transport.pushCount > 0)
        #expect(Set(transport.pushedMutations.map(\.id)) == newMutationIDs)
        #expect(transport.pushedMutations.allSatisfy { $0.scopeID == serverWorkspace.mainEventID })
        #expect(try pendingIDs(persistence, ownerID: accountID).isEmpty)
        await sync.deactivateDeletedAccount(accountID: accountID)
    }

    @Test("Quiescing an inactive deleted account leaves the active account's graph and delivery intact")
    func inactiveAccountDoesNotSuspendCurrentAccount() async throws {
        let (persistence, library, sync, transport) = try makeFixture()
        let deletedAccountID = "inactive-delete-\(UUID().uuidString)"
        let activeAccountID = "active-keep-\(UUID().uuidString)"
        await sync.activate(userID: deletedAccountID, seedData: false)
        _ = addWorkspace(to: library, title: "Deleted account pending")
        try persistence.saveChanges(in: library)
        let deletedMutationIDs = try pendingIDs(persistence, ownerID: deletedAccountID)
        await sync.deactivateDeletedAccount(accountID: deletedAccountID)

        await sync.activate(userID: activeAccountID, seedData: false)
        let currentWorkspace = addWorkspace(to: library, title: "Current account pending")
        try persistence.saveChanges(in: library)
        let currentMutationIDs = try pendingIDs(persistence, ownerID: activeAccountID)
        let generation = persistence.activeUserGeneration
        await sync.suspendForAccountDeletion(accountID: deletedAccountID)
        await sync.deactivateDeletedAccount(accountID: deletedAccountID)
        #expect(persistence.activeUserID == activeAccountID)
        #expect(persistence.activeUserGeneration == generation)
        #expect(library.workspaces.first === currentWorkspace)

        await sync.synchronize()
        #expect(transport.pushCount > 0)
        #expect(Set(transport.pushedMutations.map(\.id)) == currentMutationIDs)
        #expect(transport.pushedMutations.allSatisfy { $0.scopeID == currentWorkspace.mainEventID })
        #expect(try pendingIDs(persistence, ownerID: activeAccountID).isEmpty)
        #expect(try pendingIDs(persistence, ownerID: deletedAccountID) == deletedMutationIDs)
        #expect(library.workspaces.first === currentWorkspace)
        await sync.deactivateDeletedAccount(accountID: activeAccountID)
    }

    @Test("Suspension joins an in-flight bootstrap and rejects its late response")
    func suspensionWaitsForCancelledBootstrap() async throws {
        let (persistence, library, sync, transport) = try makeFixture()
        let accountID = "inflight-delete-\(UUID().uuidString)"
        let remote = PlanningWorkspace.newWorkspace(title: "Late remote response", startsAt: .now,
            eventLocation: nil, imageData: nil)
        transport.bootstrapSnapshots = [RemoteWorkspaceSnapshot(scopeID: remote.mainEventID,
            payload: try WorkspaceArchiveCodec().encode(WorkspaceArchiveV1(workspace: remote)),
            serverVersion: 1, updatedAt: .now)]
        transport.holdBootstrap = true
        let activation = Task { await sync.activate(userID: accountID, seedData: false) }
        for _ in 0..<1_000 {
            if transport.releaseBootstrap != nil { break }
            await Task.yield()
        }
        let release = try #require(transport.releaseBootstrap)
        var suspensionCompleted = false
        let suspension = Task {
            await sync.suspendForAccountDeletion(accountID: accountID)
            suspensionCompleted = true
        }
        for _ in 0..<10 { await Task.yield() }
        #expect(!suspensionCompleted)
        transport.releaseBootstrap = nil
        release.resume()
        await activation.value
        await suspension.value
        #expect(suspensionCompleted)
        #expect(transport.bootstrapCount == 1)
        #expect(transport.pushCount == 0)
        #expect(transport.pullCount == 0)
        #expect(library.workspaces.isEmpty)
        #expect(try ModelContext(persistence.container).fetch(FetchDescriptor<WorkspaceRecord>()).isEmpty)
        await sync.deactivateDeletedAccount(accountID: accountID)
    }

    private func makeFixture() throws -> (
        WorkspacePersistenceController, WorkspaceLibrary, WorkspaceCloudSyncController, AccountDeletionSyncTransport
    ) {
        let persistence = try WorkspacePersistenceController(isStoredInMemoryOnly: true)
        let library = persistence.restoreLibrary(seedData: false)
        let transport = AccountDeletionSyncTransport()
        let sync = WorkspaceCloudSyncController(persistence: persistence, library: library,
            baseURL: URL(string: "https://example.invalid")!, transport: transport, usesRemoteAccountState: true)
        return (persistence, library, sync, transport)
    }

    private func addWorkspace(to library: WorkspaceLibrary, title: String) -> PlanningWorkspace {
        let workspace = PlanningWorkspace.newWorkspace(title: title, startsAt: .now,
            eventLocation: nil, imageData: nil)
        library.add(workspace)
        return workspace
    }

    private func pendingIDs(_ persistence: WorkspacePersistenceController, ownerID: String) throws -> Set<UUID> {
        Set(try ModelContext(persistence.container).fetch(FetchDescriptor<PendingMutation>())
            .filter { $0.ownerUserID == ownerID }.map(\.id))
    }
}

@MainActor
private final class AccountDeletionSyncTransport: WorkspaceSnapshotTransport {
    private(set) var bootstrapCount = 0
    private(set) var pushCount = 0
    private(set) var pullCount = 0
    private(set) var pushedMutations: [PendingMutationSnapshot] = []
    var bootstrapSnapshots: [RemoteWorkspaceSnapshot] = []
    var holdBootstrap = false
    var releaseBootstrap: CheckedContinuation<Void, Never>?

    func bootstrap() async -> SyncBootstrapResponse {
        bootstrapCount += 1
        if holdBootstrap {
            holdBootstrap = false
            await withCheckedContinuation { releaseBootstrap = $0 }
        }
        return .init(account: nil, snapshots: bootstrapSnapshots)
    }

    func push(_ mutations: [PendingMutationSnapshot]) -> SyncPushResponse {
        pushCount += 1
        pushedMutations.append(contentsOf: mutations)
        return .init(results: mutations.map {
            .init(mutationID: $0.id, disposition: .applied, serverVersion: 1, failureCode: nil)
        })
    }

    func pull(scopeID: UUID, after cursor: String?) -> SyncPullPage {
        pullCount += 1
        return .init(changes: [], nextCursor: cursor, hasMore: false)
    }
}
