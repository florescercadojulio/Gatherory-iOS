import Foundation
import SwiftData
import Testing
@testable import Gatherory

@MainActor
struct RemoteWorkspaceDeletionTests {
    @Test("A confirmed missing root removes its child scopes without touching another account or workspace")
    func missingRootPurgesOwnedHierarchy() async throws {
        let fixture = try makeFixture(owner: "delete-owner")
        try queueOfflineEdits(in: fixture)
        try seedChildSyncMetadata(in: fixture)
        try addOtherAccountCopies(for: fixture)

        let coordinator = makeCoordinator(fixture, pullBehavior: .scopeNotFound)
        let summary = try await coordinator.synchronize(scopeID: fixture.rootID)

        #expect(summary.scopeWasRevoked)
        #expect(Set(fixture.library.workspaces.map(\.mainEventID)) == [fixture.unrelatedID])

        let context = ModelContext(fixture.persistence.container)
        let records = try context.fetch(FetchDescriptor<WorkspaceRecord>())
        #expect(Set(records.filter { $0.ownerUserID == fixture.owner }.map(\.id)) == [fixture.unrelatedID])
        #expect(Set(records.filter { $0.ownerUserID == "other-account" }.map(\.id))
            == Set([fixture.rootID] + fixture.childIDs))

        let mutations = try context.fetch(FetchDescriptor<PendingMutation>())
        #expect(mutations.filter { $0.ownerUserID == fixture.owner }
            .allSatisfy { $0.scopeID == fixture.unrelatedID })
        #expect(mutations.contains { $0.ownerUserID == "other-account" && $0.scopeID == fixture.childIDs[0] })

        let versions = try context.fetch(FetchDescriptor<RemoteEntityVersionRecord>())
        #expect(!versions.contains { $0.ownerUserID == fixture.owner && $0.scopeID == fixture.childIDs[0] })
        #expect(versions.contains { $0.ownerUserID == "other-account" && $0.scopeID == fixture.childIDs[0] })

        let childCheckpoints = try context.fetch(FetchDescriptor<SyncCheckpoint>())
        #expect(!childCheckpoints.contains { $0.ownerUserID == fixture.owner && $0.scopeID == fixture.childIDs[0] })
        #expect(childCheckpoints.contains { $0.ownerUserID == "other-account" && $0.scopeID == fixture.childIDs[0] })
        #expect(try context.fetch(FetchDescriptor<PendingMediaTransfer>())
            .allSatisfy { $0.ownerUserID != fixture.owner || !fixture.childIDs.contains($0.scopeID) })
    }

    @Test("The workspace sync controller clears a root after the server confirms the scope is missing")
    func controllerClearsMissingRootScope() async throws {
        let fixture = try makeFixture(owner: "controller-delete-owner")
        let controller = WorkspaceCloudSyncController(
            persistence: fixture.persistence,
            library: fixture.library,
            baseURL: URL(string: "https://gatherory.example"),
            transport: DeletionTransport(
                pullBehavior: .scopeNotFound,
                missingScopeIDs: [fixture.rootID]
            ),
            usesRemoteAccountState: true
        )

        await controller.activate(userID: fixture.owner, seedData: false)

        #expect(controller.lastError == nil)
        #expect(!fixture.library.workspaces.contains { $0.mainEventID == fixture.rootID })
        #expect(fixture.childIDs.allSatisfy { id in
            !fixture.library.workspaces.contains { $0.mainEventID == id }
        })
        #expect(fixture.library.workspaces.contains { $0.mainEventID == fixture.unrelatedID })
    }

    @Test("A missing response cannot erase a root whose local create was never acknowledged")
    func controllerPreservesUnacknowledgedLocalRoot() async throws {
        let fixture = try makeFixture(owner: "local-only-delete-owner", serverVersion: 0)
        try makeRootOutboxCreate(in: fixture)
        try queueOfflineEdits(in: fixture)
        let originalCreateID = try #require(ModelContext(fixture.persistence.container)
            .fetch(FetchDescriptor<PendingMutation>())
            .first {
                $0.ownerUserID == fixture.owner && $0.scopeID == fixture.rootID
                    && $0.entityType == .workspace && $0.operation == .create
            }?.id)
        let controller = WorkspaceCloudSyncController(
            persistence: fixture.persistence,
            library: fixture.library,
            baseURL: URL(string: "https://gatherory.example"),
            transport: DeletionTransport(
                pullBehavior: .scopeNotFound,
                missingScopeIDs: [fixture.rootID],
                rejectedScopeIDs: [fixture.rootID]
            ),
            usesRemoteAccountState: true
        )

        await controller.activate(userID: fixture.owner, seedData: false)

        #expect(fixture.library.workspaces.contains { $0.mainEventID == fixture.rootID })
        #expect(fixture.childIDs.allSatisfy { childID in
            fixture.library.workspaces.contains { $0.mainEventID == childID }
        })
        let mutations = try ModelContext(fixture.persistence.container)
            .fetch(FetchDescriptor<PendingMutation>())
        #expect(mutations.contains {
            $0.id == originalCreateID && $0.ownerUserID == fixture.owner
                && $0.scopeID == fixture.rootID && $0.state == .requiresAttention
                && $0.lastFailureCode == "SYNC_SCOPE_NOT_FOUND"
        })
    }

    @Test("Rejected child edits cannot recreate an acknowledged root that the server deleted")
    func controllerDeletesAcknowledgedRootInsteadOfRepairingIt() async throws {
        let fixture = try makeFixture(owner: "acknowledged-delete-owner", serverVersion: 1)
        let root = try #require(fixture.library.workspaces.first { $0.mainEventID == fixture.rootID })
        root.timeline[0].title += " local child edit"
        try fixture.persistence.saveChanges(in: fixture.library)
        let rootChildMutation = try #require(ModelContext(fixture.persistence.container)
            .fetch(FetchDescriptor<PendingMutation>())
            .first {
                $0.ownerUserID == fixture.owner && $0.scopeID == fixture.rootID
                    && $0.entityType == .event && $0.operation == .update
            })

        let controller = WorkspaceCloudSyncController(
            persistence: fixture.persistence,
            library: fixture.library,
            baseURL: URL(string: "https://gatherory.example"),
            transport: DeletionTransport(
                pullBehavior: .scopeNotFound,
                missingScopeIDs: [fixture.rootID],
                rejectedScopeIDs: [fixture.rootID]
            ),
            usesRemoteAccountState: true
        )

        await controller.activate(userID: fixture.owner, seedData: false)

        #expect(!fixture.library.workspaces.contains { $0.mainEventID == fixture.rootID })
        #expect(fixture.childIDs.allSatisfy { childID in
            !fixture.library.workspaces.contains { $0.mainEventID == childID }
        })
        let mutations = try ModelContext(fixture.persistence.container)
            .fetch(FetchDescriptor<PendingMutation>())
        #expect(!mutations.contains { $0.id == rootChildMutation.id })
        #expect(!mutations.contains {
            $0.ownerUserID == fixture.owner && $0.scopeID == fixture.rootID
                && $0.entityType == .workspace && $0.operation == .create
        })
    }

    @Test("A root event tombstone removes the main workspace and all cached child scopes")
    func rootEventTombstonePurgesHierarchy() async throws {
        let fixture = try makeFixture(owner: "tombstone-owner")
        try queueOfflineEdits(in: fixture)
        try seedChildSyncMetadata(in: fixture)
        let page = SyncPullPage(changes: [RemoteChangeEnvelope(
            id: UUID(),
            scopeID: fixture.rootID,
            entityType: .event,
            entityID: fixture.rootID,
            operation: .delete,
            payload: Data(),
            serverVersion: 2,
            occurredAt: .now
        )], nextCursor: "root-delete", hasMore: false)
        let applier = WorkspaceRemoteChangeApplier(
            persistence: fixture.persistence,
            library: fixture.library
        )

        try await applier.apply(page, to: fixture.rootID)

        #expect(!fixture.library.workspaces.contains { $0.mainEventID == fixture.rootID })
        #expect(fixture.childIDs.allSatisfy { id in
            !fixture.library.workspaces.contains { $0.mainEventID == id }
        })
        #expect(fixture.library.workspaces.contains { $0.mainEventID == fixture.unrelatedID })
        let context = ModelContext(fixture.persistence.container)
        #expect(try context.fetch(FetchDescriptor<WorkspaceRecord>())
            .filter { $0.ownerUserID == fixture.owner }
            .allSatisfy { $0.id == fixture.unrelatedID })
        #expect(try context.fetch(FetchDescriptor<PendingMutation>())
            .filter { $0.ownerUserID == fixture.owner }
            .allSatisfy { $0.scopeID == fixture.unrelatedID })
        #expect(try fixture.persistence.currentCursor(for: fixture.rootID) == "root-delete")
    }

    @Test("A child tombstone removes only its child projection and queued work")
    func childEventTombstoneKeepsRootAndSibling() async throws {
        let fixture = try makeFixture(owner: "child-delete-owner")
        try queueOfflineEdits(in: fixture)
        try seedChildSyncMetadata(in: fixture)
        let deletedChildID = fixture.childIDs[0]
        let survivingChildID = fixture.childIDs[1]
        let page = SyncPullPage(changes: [RemoteChangeEnvelope(
            id: UUID(),
            scopeID: fixture.rootID,
            entityType: .event,
            entityID: deletedChildID,
            operation: .delete,
            payload: Data(),
            serverVersion: 2,
            occurredAt: .now
        )], nextCursor: "child-delete", hasMore: false)

        try fixture.persistence.applyRemotePage(page, scopeID: fixture.rootID, to: fixture.library)

        let root = try #require(fixture.library.workspaces.first { $0.mainEventID == fixture.rootID })
        #expect(root.timeline.map(\.id) == [survivingChildID])
        #expect(!fixture.library.workspaces.contains { $0.mainEventID == deletedChildID })
        #expect(fixture.library.workspaces.contains { $0.mainEventID == survivingChildID })
        let mutations = try ModelContext(fixture.persistence.container)
            .fetch(FetchDescriptor<PendingMutation>())
        #expect(!mutations.contains { $0.ownerUserID == fixture.owner && $0.scopeID == deletedChildID })
        #expect(mutations.contains { $0.ownerUserID == fixture.owner && $0.scopeID == survivingChildID })
        #expect(mutations.contains { $0.ownerUserID == fixture.owner && $0.scopeID == fixture.unrelatedID })
        let checkpoints = try ModelContext(fixture.persistence.container).fetch(FetchDescriptor<SyncCheckpoint>())
        #expect(!checkpoints.contains { $0.ownerUserID == fixture.owner && $0.scopeID == deletedChildID })
        #expect(checkpoints.contains { $0.ownerUserID == fixture.owner && $0.scopeID == survivingChildID })
    }

    @Test("Empty bootstrap, empty pull, and transient pull failures preserve cached offline work")
    func absenceAndTransientFailuresDoNotDelete() async throws {
        let fixture = try makeFixture(owner: "offline-owner")
        try queueOfflineEdits(in: fixture)
        try seedChildSyncMetadata(in: fixture)
        try fixture.persistence.applyBootstrap([], to: fixture.library)
        try fixture.persistence.applyRemotePage(
            SyncPullPage(changes: [], nextCursor: "empty-page", hasMore: false),
            scopeID: fixture.rootID,
            to: fixture.library
        )

        for behavior in [DeletionPullBehavior.unauthorized, .networkUnavailable, .temporaryServerFailure] {
            let coordinator = makeCoordinator(fixture, pullBehavior: behavior)
            do {
                _ = try await coordinator.synchronize(scopeID: fixture.rootID)
                Issue.record("A transient pull should fail without being treated as a deletion.")
            } catch {
                // The cached graph and its unrelated queued work must survive the failure.
            }
            #expect(fixture.library.workspaces.contains { $0.mainEventID == fixture.rootID })
            #expect(fixture.childIDs.allSatisfy { childID in
                fixture.library.workspaces.contains { $0.mainEventID == childID }
            })
            let mutations = try ModelContext(fixture.persistence.container)
                .fetch(FetchDescriptor<PendingMutation>())
            #expect(fixture.childIDs.allSatisfy { childID in
                mutations.contains { $0.ownerUserID == fixture.owner && $0.scopeID == childID }
            })
        }
    }

    private struct Fixture {
        let owner: String
        let persistence: WorkspacePersistenceController
        let library: WorkspaceLibrary
        let rootID: UUID
        let childIDs: [UUID]
        let unrelatedID: UUID
    }

    private enum DeletionPullBehavior: Sendable {
        case empty
        case scopeNotFound
        case unauthorized
        case networkUnavailable
        case temporaryServerFailure
    }

    private struct DeletionTransport: WorkspaceSnapshotTransport {
        let pullBehavior: DeletionPullBehavior
        var missingScopeIDs: Set<UUID> = []
        var rejectedScopeIDs: Set<UUID> = []

        func bootstrap() async throws -> SyncBootstrapResponse {
            SyncBootstrapResponse(account: nil, snapshots: [])
        }

        func push(_ mutations: [PendingMutationSnapshot]) async throws -> SyncPushResponse {
            SyncPushResponse(results: mutations.map {
                SyncPushResult(
                    mutationID: $0.id,
                    disposition: rejectedScopeIDs.contains($0.scopeID) ? .rejected : .applied,
                    serverVersion: nil,
                    failureCode: rejectedScopeIDs.contains($0.scopeID) ? "SYNC_SCOPE_NOT_FOUND" : nil
                )
            })
        }

        func pull(scopeID: UUID, after cursor: String?) async throws -> SyncPullPage {
            switch pullBehavior {
            case .empty:
                return SyncPullPage(changes: [], nextCursor: cursor, hasMore: false)
            case .scopeNotFound:
                guard missingScopeIDs.isEmpty || missingScopeIDs.contains(scopeID) else {
                    return SyncPullPage(changes: [], nextCursor: cursor, hasMore: false)
                }
                throw CloudSyncFailure.server("SYNC_SCOPE_NOT_FOUND")
            case .unauthorized:
                throw CloudSyncFailure.invalidSession
            case .networkUnavailable:
                throw URLError(.notConnectedToInternet)
            case .temporaryServerFailure:
                throw CloudSyncFailure.server("TEMPORARY_FAILURE")
            }
        }
    }

    private func makeFixture(owner: String, serverVersion: Int = 1) throws -> Fixture {
        let persistence = try WorkspacePersistenceController(isStoredInMemoryOnly: true)
        let library = persistence.restoreLibrary(seedData: false, ownerUserID: owner)
        let start = Date(timeIntervalSinceReferenceDate: 900_000_000)
        let root = PlanningWorkspace.newWorkspace(
            title: "Remote root",
            startsAt: start,
            eventLocation: nil,
            imageData: nil
        )
        let childEvents = [
            TimelineItem(
                title: "First child", category: .ceremony, scheduledAt: start,
                participantIDs: [], parentEventID: root.mainEventID
            ),
            TimelineItem(
                title: "Second child", category: .reception, scheduledAt: start.addingTimeInterval(3_600),
                participantIDs: [], parentEventID: root.mainEventID
            )
        ]
        root.timeline = childEvents
        let childWorkspaces = childEvents.map { child in
            PlanningWorkspace(
                mainEventID: child.id,
                isScopedEvent: true,
                title: child.title,
                mainEventStartsAt: child.scheduledAt,
                venueName: "",
                location: "",
                planningMode: .openToIdeas,
                members: root.members,
                mainEventParticipantIDs: child.participantIDs,
                ideas: [],
                timeline: [],
                registry: []
            )
        }
        let unrelated = PlanningWorkspace.newWorkspace(
            title: "Unrelated workspace",
            startsAt: start.addingTimeInterval(86_400),
            eventLocation: nil,
            imageData: nil
        )
        let codec = WorkspaceArchiveCodec()
        let snapshots = try ([root] + childWorkspaces + [unrelated]).map { workspace in
            RemoteWorkspaceSnapshot(
                scopeID: workspace.mainEventID,
                payload: try codec.encode(WorkspaceArchiveV1(workspace: workspace)),
                serverVersion: serverVersion,
                updatedAt: .now
            )
        }
        try persistence.applyBootstrap(snapshots, to: library)
        return Fixture(
            owner: owner,
            persistence: persistence,
            library: library,
            rootID: root.mainEventID,
            childIDs: childEvents.map(\.id),
            unrelatedID: unrelated.mainEventID
        )
    }

    private func queueOfflineEdits(in fixture: Fixture) throws {
        for workspace in fixture.library.workspaces {
            if workspace.mainEventID == fixture.rootID
                || fixture.childIDs.contains(workspace.mainEventID)
                || workspace.mainEventID == fixture.unrelatedID {
                workspace.title += " pending edit"
            }
        }
        try fixture.persistence.saveChanges(in: fixture.library)
    }

    private func makeRootOutboxCreate(in fixture: Fixture) throws {
        let context = ModelContext(fixture.persistence.container)
        let rootRecord = try #require(context.fetch(FetchDescriptor<WorkspaceRecord>())
            .first { $0.ownerUserID == fixture.owner && $0.id == fixture.rootID })
        context.delete(rootRecord)
        try context.save()
        try fixture.persistence.saveChanges(in: fixture.library)
        let verificationContext = ModelContext(fixture.persistence.container)
        let rootCreate = try #require(verificationContext.fetch(FetchDescriptor<PendingMutation>())
            .first {
                $0.ownerUserID == fixture.owner && $0.scopeID == fixture.rootID
                    && $0.entityType == .workspace
            })
        #expect(rootCreate.operation == .create)
    }

    private func addOtherAccountCopies(for fixture: Fixture) throws {
        let context = ModelContext(fixture.persistence.container)
        let activeRecords = try context.fetch(FetchDescriptor<WorkspaceRecord>())
            .filter { $0.ownerUserID == fixture.owner && ($0.id == fixture.rootID || fixture.childIDs.contains($0.id)) }
        for record in activeRecords {
            context.insert(WorkspaceRecord(
                id: record.id,
                payload: record.payload,
                sortOrder: record.sortOrder,
                updatedAt: record.updatedAt,
                ownerUserID: "other-account",
                serverVersion: record.serverVersion
            ))
        }
        context.insert(PendingMutation(
            scopeID: fixture.childIDs[0],
            entityType: .event,
            entityID: fixture.childIDs[0],
            operation: .update,
            payload: Data([0x01]),
            ownerUserID: "other-account"
        ))
        context.insert(RemoteEntityVersionRecord(
            scopeID: fixture.childIDs[0],
            entityType: .event,
            entityID: fixture.childIDs[0],
            serverVersion: 4,
            ownerUserID: "other-account"
        ))
        context.insert(SyncCheckpoint(
            scopeID: fixture.childIDs[0], cursor: "other-account-cursor", ownerUserID: "other-account"
        ))
        context.insert(AppliedSyncEnvelope(
            id: UUID(), scopeID: fixture.childIDs[0], ownerUserID: "other-account"
        ))
        try context.save()
    }

    private func seedChildSyncMetadata(in fixture: Fixture) throws {
        let context = ModelContext(fixture.persistence.container)
        for childID in fixture.childIDs {
            context.insert(SyncCheckpoint(
                scopeID: childID,
                cursor: "cached-\(childID.uuidString)",
                ownerUserID: fixture.owner
            ))
            context.insert(AppliedSyncEnvelope(
                id: UUID(), scopeID: childID, ownerUserID: fixture.owner
            ))
            context.insert(RemoteEntityVersionRecord(
                scopeID: childID,
                entityType: .event,
                entityID: childID,
                serverVersion: 3,
                ownerUserID: fixture.owner
            ))
            context.insert(PendingMediaTransfer(
                scopeID: childID,
                entityID: UUID(),
                localFileURL: FileManager.default.temporaryDirectory
                    .appending(path: "missing-delete-test-\(fixture.owner)-\(childID.uuidString)"),
                contentType: "image/jpeg",
                ownerUserID: fixture.owner
            ))
        }
        try context.save()
    }

    private func makeCoordinator(
        _ fixture: Fixture,
        pullBehavior: DeletionPullBehavior
    ) -> OfflineSyncCoordinator {
        OfflineSyncCoordinator(
            store: SwiftDataSyncStore(modelContainer: fixture.persistence.container),
            transport: DeletionTransport(
                pullBehavior: pullBehavior,
                missingScopeIDs: [fixture.rootID]
            ),
            remoteApplier: WorkspaceRemoteChangeApplier(
                persistence: fixture.persistence,
                library: fixture.library
            ),
            ownerUserID: fixture.owner
        )
    }
}
