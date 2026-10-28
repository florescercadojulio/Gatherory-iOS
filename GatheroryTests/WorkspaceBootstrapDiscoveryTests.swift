import Foundation
import SwiftData
import Testing
@testable import Gatherory

@MainActor
struct WorkspaceBootstrapDiscoveryTests {
    @Test("Manual and foreground sync discover new roots without replacing known planner data")
    func discoversNewRootAndPreservesExistingWork() async throws {
        let persistence = try WorkspacePersistenceController(isStoredInMemoryOnly: true)
        let library = persistence.restoreLibrary(seedData: false)
        let accountID = UUID().uuidString
        defer { UserDefaults.standard.removeObject(forKey: "accountOnboardingComplete.\(accountID)") }

        let knownClean = makeWorkspace("Initial clean workspace")
        let knownPending = makeWorkspace("Initial pending workspace")
        let newRoot = makeWorkspace("Discovered workspace", childTitle: "Discovered child")
        let initialResponse = try response([knownClean, knownPending])
        let discoveryResponse = try response([
            makeWorkspace("Stale server version of clean workspace", id: knownClean.mainEventID),
            makeWorkspace("Stale server version of pending workspace", id: knownPending.mainEventID),
            newRoot
        ])
        let transport = BootstrapDiscoveryTransport(responses: [
            initialResponse,
            discoveryResponse,
            discoveryResponse
        ])
        let sync = WorkspaceCloudSyncController(
            persistence: persistence,
            library: library,
            baseURL: URL(string: "https://example.invalid")!,
            transport: transport,
            usesRemoteAccountState: true
        )

        await sync.activate(userID: accountID, seedData: false)
        #expect(Set(library.workspaces.map(\.mainEventID)) == [knownClean.mainEventID, knownPending.mainEventID])

        let cleanWorkspace = try #require(library.workspaces.first { $0.mainEventID == knownClean.mainEventID })
        let pendingWorkspace = try #require(library.workspaces.first { $0.mainEventID == knownPending.mainEventID })
        pendingWorkspace.title = "Saved local title with pending mutation"
        try persistence.saveChanges(in: library)
        cleanWorkspace.title = "In-memory local title"
        transport.failPush = true

        await sync.synchronize(trigger: .manual)

        #expect(transport.bootstrapCount == 2)
        #expect(sync.accountOnboardingState == .complete)
        #expect(library.workspaces.count == 3)
        #expect(cleanWorkspace.title == "In-memory local title")
        #expect(pendingWorkspace.title == "Saved local title with pending mutation")
        #expect(try persistence.pendingScopeIDs().contains(knownPending.mainEventID))
        let discovered = try #require(library.workspaces.first { $0.mainEventID == newRoot.mainEventID })
        #expect(discovered.timeline.count == 1)
        #expect(discovered.timeline.first?.title == "Discovered child")

        transport.failPush = false
        await sync.synchronize(trigger: .appBecameActive)

        #expect(transport.bootstrapCount == 3)
        #expect(library.workspaces.count == 3)
        #expect(library.workspaces.filter { $0.mainEventID == newRoot.mainEventID }.count == 1)
        #expect(discovered.timeline.count == 1)
        #expect(discovered.timeline.first?.title == "Discovered child")
        // A failed push is retried with backoff. The discovery pass must not
        // discard that queued local mutation even after the app becomes active.
        #expect(try persistence.pendingScopeIDs().contains(knownPending.mainEventID))
    }

    @Test("A bootstrap response from a previous account cannot import scopes after an account switch")
    func staleDiscoveryIsDiscardedAfterAccountSwitch() async throws {
        let persistence = try WorkspacePersistenceController(isStoredInMemoryOnly: true)
        let library = persistence.restoreLibrary(seedData: false)
        let accountA = UUID().uuidString
        let accountB = UUID().uuidString
        defer {
            UserDefaults.standard.removeObject(forKey: "accountOnboardingComplete.\(accountA)")
            UserDefaults.standard.removeObject(forKey: "accountOnboardingComplete.\(accountB)")
        }

        let accountAWorkspace = makeWorkspace("Account A workspace")
        let lateAccountAWorkspace = makeWorkspace("Late Account A workspace")
        let accountBWorkspace = makeWorkspace("Account B workspace")
        let transport = BootstrapDiscoveryTransport(responses: [
            try response([accountAWorkspace]),
            try response([accountAWorkspace, lateAccountAWorkspace]),
            try response([accountBWorkspace])
        ])
        let sync = WorkspaceCloudSyncController(
            persistence: persistence,
            library: library,
            baseURL: URL(string: "https://example.invalid")!,
            transport: transport,
            usesRemoteAccountState: true
        )

        await sync.activate(userID: accountA, seedData: false)
        transport.holdNextBootstrap = true
        let discovery = Task { await sync.synchronize(trigger: .manual) }
        for _ in 0..<100 where !transport.isWaitingForBootstrap { await Task.yield() }
        #expect(transport.isWaitingForBootstrap)

        let accountSwitch = Task { await sync.activate(userID: accountB, seedData: false) }
        await Task.yield()
        transport.releaseHeldBootstrap()
        await discovery.value
        await accountSwitch.value

        #expect(persistence.activeUserID == accountB)
        #expect(library.workspaces.map(\.mainEventID) == [accountBWorkspace.mainEventID])
        let records = try ModelContext(persistence.container).fetch(FetchDescriptor<WorkspaceRecord>())
        #expect(!records.contains { $0.ownerUserID == accountA && $0.id == lateAccountAWorkspace.mainEventID })
        #expect(records.contains { $0.ownerUserID == accountB && $0.id == accountBWorkspace.mainEventID })
    }

    private func makeWorkspace(_ title: String, id: UUID? = nil, childTitle: String? = nil) -> PlanningWorkspace {
        let workspace = PlanningWorkspace(
            mainEventID: id ?? UUID(),
            title: title,
            mainEventStartsAt: Date(timeIntervalSinceReferenceDate: 900_000_000),
            venueName: "",
            location: "",
            planningMode: .openToIdeas,
            members: [],
            mainEventParticipantIDs: [],
            ideas: [],
            timeline: [],
            registry: []
        )
        if let childTitle {
            workspace.timeline = [TimelineItem(
                title: childTitle,
                category: .other,
                purpose: .eventExperience,
                scheduledAt: Date(timeIntervalSinceReferenceDate: 900_000_100),
                location: "",
                participantIDs: [],
                parentEventID: workspace.mainEventID
            )]
        }
        return workspace
    }

    private func response(_ workspaces: [PlanningWorkspace]) throws -> SyncBootstrapResponse {
        let codec = WorkspaceArchiveCodec()
        let snapshots = try workspaces.map { workspace in
            RemoteWorkspaceSnapshot(
                scopeID: workspace.mainEventID,
                payload: try codec.encode(WorkspaceArchiveV1(workspace: workspace)),
                serverVersion: 1,
                updatedAt: Date(timeIntervalSinceReferenceDate: 900_000_000)
            )
        }
        return SyncBootstrapResponse(account: nil, snapshots: snapshots)
    }
}

@MainActor
private final class BootstrapDiscoveryTransport: WorkspaceSnapshotTransport {
    private let responses: [SyncBootstrapResponse]
    private var nextResponseIndex = 0
    private var heldResponseContinuation: CheckedContinuation<SyncBootstrapResponse, Never>?
    private var heldResponse: SyncBootstrapResponse?
    private(set) var bootstrapCount = 0
    private(set) var isWaitingForBootstrap = false
    var holdNextBootstrap = false
    var failPush = false

    init(responses: [SyncBootstrapResponse]) {
        self.responses = responses
    }

    func bootstrap() async throws -> SyncBootstrapResponse {
        let response = responses[min(nextResponseIndex, responses.count - 1)]
        nextResponseIndex += 1
        bootstrapCount += 1
        if holdNextBootstrap {
            holdNextBootstrap = false
            isWaitingForBootstrap = true
            heldResponse = response
            return await withCheckedContinuation { heldResponseContinuation = $0 }
        }
        return response
    }

    func releaseHeldBootstrap() {
        guard let response = heldResponse,
              let continuation = heldResponseContinuation else { return }
        isWaitingForBootstrap = false
        heldResponse = nil
        heldResponseContinuation = nil
        continuation.resume(returning: response)
    }

    func push(_ mutations: [PendingMutationSnapshot]) async throws -> SyncPushResponse {
        if failPush { throw URLError(.notConnectedToInternet) }
        return SyncPushResponse(results: mutations.map {
            SyncPushResult(mutationID: $0.id, disposition: .applied, serverVersion: 2, failureCode: nil)
        })
    }

    func pull(scopeID: UUID, after cursor: String?) async throws -> SyncPullPage {
        SyncPullPage(changes: [], nextCursor: cursor, hasMore: false)
    }
}
