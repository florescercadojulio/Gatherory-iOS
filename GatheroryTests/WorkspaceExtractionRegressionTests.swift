import Foundation
import SwiftData
import Testing
@testable import Gatherory

/// Exercises the existing public facades, independently of the extracted helpers.
@MainActor
struct WorkspaceExtractionRegressionTests {
    @Test("Budget commands still debounce into a durable archive and stable outbox before notifying sync")
    func budgetEditsRemainObservedAndAtomic() async throws {
        let persistence = try WorkspacePersistenceController(isStoredInMemoryOnly: true)
        let library = persistence.restoreLibrary(seedData: false, ownerUserID: "budget-owner")
        let workspace = makeWorkspace()
        library.add(workspace)
        try persistence.saveChanges(in: library)
        let originalMutations = try mutations(in: persistence)
        let originalIDs = Set(originalMutations.map(\.id))
        let childID = try #require(workspace.timeline.first?.id)
        var notificationCount = 0
        defer { persistence.onPendingMutations = nil }
        persistence.onPendingMutations = {
            notificationCount += 1
            do {
                // An independent context must see BOTH writes by the time sync is notified.
                let context = ModelContext(persistence.container)
                let record = try #require(context.fetch(FetchDescriptor<WorkspaceRecord>()).first)
                let archive = try JSONDecoder().decode(WorkspaceArchiveV1.self, from: record.payload)
                #expect(archive.mainEventBudgetCap == 700)
                #expect(archive.timeline.first?.budgetCap == 300)
                let queued = try context.fetch(FetchDescriptor<PendingMutation>())
                #expect(Set(queued.map(\.id)) == originalIDs)
                #expect(queued.allSatisfy { $0.ownerUserID == "budget-owner" })
                let eventMutation = try #require(queued.first { $0.entityType == .event && $0.entityID == childID })
                let event = try JSONDecoder().decode(TimelineItem.self, from: eventMutation.payload)
                #expect(event.budgetCap == 300)
                let workspaceMutation = try #require(queued.first { $0.entityType == .workspace })
                let remote = try JSONDecoder().decode(WorkspaceArchiveV1.self, from: workspaceMutation.payload)
                #expect(remote.mainEventBudgetCap == 700)
                #expect(remote.timeline.first?.budgetCap == 300)
            } catch {
                Issue.record(error)
            }
        }
        persistence.startObserving(library)

        #expect(workspace.transferBudget(300, from: .main, to: .subevent(childID)))
        #expect(workspace.mainEventBudgetCap == 700) // UI-facing state changes synchronously.
        #expect(notificationCount == 0)
        try await waitUntil { notificationCount == 1 }
        #expect(!persistence.hasUnsavedLocalChanges)
        #expect(library.selectedWorkspace === workspace)

        // Presentation-only state must not create a save or an outgoing edit.
        workspace.selectEventContext(.subevent(childID))
        #expect(workspace.selectedEventReference == .subevent(childID))
        try await Task.sleep(for: .milliseconds(600))
        #expect(notificationCount == 1)
        #expect(Set(try mutations(in: persistence).map(\.id)) == originalIDs)
        #expect(persistence.lastError == nil)
    }

    @Test("Rejected budget operations leave the stored archive and queued mutation envelopes unchanged")
    func rejectedBudgetEditDoesNotWrite() throws {
        let persistence = try WorkspacePersistenceController(isStoredInMemoryOnly: true)
        let library = persistence.restoreLibrary(seedData: false, ownerUserID: "budget-owner")
        let workspace = makeWorkspace()
        library.add(workspace)
        try persistence.saveChanges(in: library)
        let beforeMutations = Set(try mutations(in: persistence))
        let beforeArchive = try storedPayload(in: persistence)
        let childID = try #require(workspace.timeline.first?.id)
        var notifications = 0
        persistence.onPendingMutations = { notifications += 1 }

        #expect(!workspace.transferBudget(1_001, from: .main, to: .subevent(childID)))
        #expect(!workspace.transferBudget(-1, from: .main, to: .subevent(childID)))
        #expect(!workspace.transferBudget(1, from: .main, to: .subevent(UUID())))
        #expect(!workspace.updateWorkspaceBudgetCap(999))
        try persistence.saveChanges(in: library)

        #expect(try storedPayload(in: persistence) == beforeArchive)
        #expect(Set(try mutations(in: persistence)) == beforeMutations)
        #expect(notifications == 0)
    }

    @Test("Remote archive application advances receipts and cursor without echoing; later local edits still save")
    func remoteApplicationDoesNotEchoOrBreakObservation() async throws {
        let persistence = try WorkspacePersistenceController(isStoredInMemoryOnly: true)
        let library = persistence.restoreLibrary(seedData: false, ownerUserID: "remote-owner")
        let workspace = makeWorkspace()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let timestamp = Date(timeIntervalSinceReferenceDate: 900_000_000)
        try persistence.applyBootstrap([
            RemoteWorkspaceSnapshot(scopeID: workspace.mainEventID,
                payload: encoder.encode(WorkspaceArchiveV1(workspace: workspace)),
                serverVersion: 1, updatedAt: timestamp)
        ], to: library)
        persistence.startObserving(library)
        var notifications = 0
        persistence.onPendingMutations = { notifications += 1 }
        workspace.title = "Remote title"
        let envelopeID = UUID()
        let page = SyncPullPage(changes: [
            RemoteChangeEnvelope(id: envelopeID, scopeID: workspace.mainEventID,
                entityType: .workspace, entityID: workspace.mainEventID, operation: .update,
                payload: try encoder.encode(WorkspaceArchiveV1(workspace: workspace)),
                serverVersion: 2, occurredAt: timestamp)
        ], nextCursor: "42", hasMore: false)

        try persistence.applyRemotePage(page, scopeID: workspace.mainEventID, to: library)
        try await Task.sleep(for: .milliseconds(600))
        #expect(notifications == 0)
        #expect(try mutations(in: persistence).isEmpty)
        let refreshed = try #require(library.workspaces.first)
        #expect(refreshed.title == "Remote title")
        let context = ModelContext(persistence.container)
        let record = try #require(context.fetch(FetchDescriptor<WorkspaceRecord>()).first)
        #expect(record.serverVersion == 2)
        #expect(record.ownerUserID == "remote-owner")
        #expect(try JSONDecoder().decode(WorkspaceArchiveV1.self, from: record.payload).title == "Remote title")
        let receipts = try context.fetch(FetchDescriptor<AppliedSyncEnvelope>())
        #expect(receipts.map(\.id) == [envelopeID])
        #expect(receipts.first?.ownerUserID == "remote-owner")
        let checkpoint = try #require(context.fetch(FetchDescriptor<SyncCheckpoint>()).first)
        #expect(checkpoint.cursor == "42")
        #expect(checkpoint.ownerUserID == "remote-owner")

        // Duplicate pages and empty refreshes must not replace the live graph.
        try persistence.applyRemotePage(page, scopeID: workspace.mainEventID, to: library)
        try persistence.applyRemotePage(SyncPullPage(changes: [], nextCursor: "43", hasMore: false),
                                        scopeID: workspace.mainEventID, to: library)
        #expect(library.workspaces.first === refreshed)
        #expect(try persistence.currentCursor(for: workspace.mainEventID) == "43")
        #expect(try mutations(in: persistence).isEmpty)

        #expect(refreshed.updateWorkspaceBudgetCap(1_200))
        try await waitUntil { notifications == 1 }
        let restored = persistence.restoreLibrary(seedData: false, ownerUserID: "remote-owner")
        #expect(restored.workspaces.first?.workspaceBudgetCap == 1_200)
        #expect(!persistence.hasUnsavedLocalChanges)
        #expect(try mutations(in: persistence).contains { $0.entityType == .workspace })
    }

    @Test("Scoped offline edits queue stable event entities and never workspace mutations")
    func scopedOfflineEditsUseEntityOutboxOnly() async throws {
        let persistence = try WorkspacePersistenceController(isStoredInMemoryOnly: true)
        let library = persistence.restoreLibrary(seedData: false, ownerUserID: "scoped-owner")
        persistence.startObserving(library)
        let workspace = makeWorkspace()
        workspace.isScopedEvent = true
        var archive = WorkspaceArchiveV1(workspace: workspace)
        var mainEvent = TimelineItem(
            id: workspace.mainEventID, title: workspace.title, category: .rehearsal,
            purpose: .planning, scheduledAt: workspace.mainEventStartsAt,
            schedulingState: .unscheduled, location: "", participantIDs: [],
            parentEventID: nil
        )
        mainEvent.linkedIdeaID = nil
        archive.scopedEvent = mainEvent
        try persistence.applyBootstrap([
            RemoteWorkspaceSnapshot(scopeID: archive.mainEventID,
                payload: try WorkspaceArchiveCodec().encode(archive), serverVersion: 1, updatedAt: .now)
        ], to: library)
        await Task.yield()
        let scoped = try #require(library.workspaces.first)
        var notifications = 0
        persistence.onPendingMutations = { notifications += 1 }

        scoped.title = "Offline title one"
        try persistence.saveChanges(in: library)
        #expect(notifications == 1)
        let first = try #require(try mutations(in: persistence).first)
        #expect(first.entityType == .event)
        #expect(first.entityID == scoped.mainEventID)
        #expect(first.scopeID == scoped.mainEventID)
        #expect(try mutations(in: persistence).allSatisfy { $0.entityType != .workspace })
        let firstPayload = try WorkspaceArchiveCodec().decode(TimelineItem.self, from: first.payload)
        #expect(firstPayload.title == "Offline title one")
        #expect(firstPayload.category == .rehearsal)
        #expect(firstPayload.schedulingState == .unscheduled)
        #expect(firstPayload.parentEventID == nil)
        #expect(firstPayload.linkedIdeaID == nil)

        scoped.title = "Offline title two"
        try persistence.saveChanges(in: library)
        #expect(notifications == 2)
        let coalesced = try #require(try mutations(in: persistence).first)
        #expect(coalesced.id == first.id)
        #expect(try WorkspaceArchiveCodec().decode(TimelineItem.self, from: coalesced.payload).title == "Offline title two")
    }

    @Test("Bootstrap omission retains offline scope work, but an authoritative delete clears it")
    func scopedRevocationBoundary() throws {
        let persistence = try WorkspacePersistenceController(isStoredInMemoryOnly: true)
        let library = persistence.restoreLibrary(seedData: false, ownerUserID: "scoped-owner")
        let workspace = makeWorkspace()
        workspace.isScopedEvent = true
        let archive = WorkspaceArchiveV1(workspace: workspace)
        try persistence.applyBootstrap([
            RemoteWorkspaceSnapshot(scopeID: archive.mainEventID,
                payload: try WorkspaceArchiveCodec().encode(archive), serverVersion: 1, updatedAt: .now)
        ], to: library)
        let scoped = try #require(library.workspaces.first)
        scoped.title = "Pending while offline"
        try persistence.saveChanges(in: library)
        #expect(try mutations(in: persistence).contains { $0.scopeID == scoped.mainEventID })

        try persistence.applyBootstrap([], to: library)
        #expect(library.workspaces.contains { $0.mainEventID == scoped.mainEventID })
        #expect(try mutations(in: persistence).contains { $0.scopeID == scoped.mainEventID })

        let deletion = RemoteChangeEnvelope(
            id: UUID(), scopeID: scoped.mainEventID, entityType: .workspace,
            entityID: scoped.mainEventID, operation: .delete, payload: Data(),
            serverVersion: 2, occurredAt: .now
        )
        try persistence.applyRemotePage(
            .init(changes: [deletion], nextCursor: "delete-high-water", hasMore: false),
            scopeID: scoped.mainEventID, to: library
        )
        #expect(!library.workspaces.contains { $0.mainEventID == scoped.mainEventID })
        #expect(try mutations(in: persistence).allSatisfy { $0.scopeID != scoped.mainEventID })
        #expect(try persistence.currentCursor(for: scoped.mainEventID) == "delete-high-water")
    }

    @Test("Authoritative root bootstrap removes stale scoped projections but preserves pending offline work")
    func authoritativeRootReconcilesScopedCache() throws {
        let persistence = try WorkspacePersistenceController(isStoredInMemoryOnly: true)
        let library = persistence.restoreLibrary(seedData: false, ownerUserID: "planner-owner")

        let root = makeWorkspace()
        let staleScoped = makeWorkspace()
        staleScoped.isScopedEvent = true
        let codec = WorkspaceArchiveCodec()
        let rootSnapshot = RemoteWorkspaceSnapshot(
            scopeID: root.mainEventID,
            payload: try codec.encode(WorkspaceArchiveV1(workspace: root)),
            serverVersion: 2,
            updatedAt: .now
        )
        let staleSnapshot = RemoteWorkspaceSnapshot(
            scopeID: staleScoped.mainEventID,
            payload: try codec.encode(WorkspaceArchiveV1(workspace: staleScoped)),
            serverVersion: 1,
            updatedAt: .now
        )

        try persistence.applyBootstrap([rootSnapshot, staleSnapshot], to: library)
        #expect(library.workspaces.count == 2)

        try persistence.applyBootstrap([rootSnapshot], to: library)
        #expect(library.workspaces.map(\.mainEventID) == [root.mainEventID])

        let pendingScoped = makeWorkspace()
        pendingScoped.isScopedEvent = true
        let pendingSnapshot = RemoteWorkspaceSnapshot(
            scopeID: pendingScoped.mainEventID,
            payload: try codec.encode(WorkspaceArchiveV1(workspace: pendingScoped)),
            serverVersion: 1,
            updatedAt: .now
        )
        try persistence.applyBootstrap([rootSnapshot, pendingSnapshot], to: library)
        let restoredPendingScoped = try #require(
            library.workspaces.first { $0.mainEventID == pendingScoped.mainEventID }
        )
        restoredPendingScoped.title = "Offline collaborator edit"
        try persistence.saveChanges(in: library)

        try persistence.applyBootstrap([rootSnapshot], to: library)
        #expect(library.workspaces.contains { $0.mainEventID == pendingScoped.mainEventID })
        #expect(try mutations(in: persistence).contains { $0.scopeID == pendingScoped.mainEventID })
    }

    @Test("Forbidden write cleanup is limited to a cached scoped event")
    func forbiddenScopedCleanup() throws {
        let persistence = try WorkspacePersistenceController(isStoredInMemoryOnly: true)
        let library = persistence.restoreLibrary(seedData: false, ownerUserID: "scoped-owner")
        let workspace = makeWorkspace()
        workspace.isScopedEvent = true
        let archive = WorkspaceArchiveV1(workspace: workspace)
        try persistence.applyBootstrap([
            RemoteWorkspaceSnapshot(scopeID: archive.mainEventID,
                payload: try WorkspaceArchiveCodec().encode(archive), serverVersion: 1, updatedAt: .now)
        ], to: library)
        let scoped = try #require(library.workspaces.first)
        scoped.title = "Queued edit"
        try persistence.saveChanges(in: library)

        #expect(try persistence.clearScopedWorkspaceAfterWriteForbidden(
            scopeID: scoped.mainEventID, from: library
        ))
        #expect(!library.workspaces.contains { $0.mainEventID == scoped.mainEventID })
        #expect(try mutations(in: persistence).allSatisfy { $0.scopeID != scoped.mainEventID })
    }

    private func makeWorkspace() -> PlanningWorkspace {
        let workspace = PlanningWorkspace.newWorkspace(
            title: "Budget regression", startsAt: Date(timeIntervalSinceReferenceDate: 900_000_000),
            eventLocation: nil, imageData: nil, budgetCap: 1_000
        )
        workspace.addTimelineItem(TimelineItem(
            title: "Dinner", category: .other,
            scheduledAt: workspace.mainEventStartsAt,
            participantIDs: [], parentEventID: workspace.mainEventID, budgetCap: .zero
        ))
        return workspace
    }

    private func mutations(in persistence: WorkspacePersistenceController) throws -> [PendingMutationSnapshot] {
        try ModelContext(persistence.container).fetch(FetchDescriptor<PendingMutation>()).map(PendingMutationSnapshot.init)
    }

    private func storedPayload(in persistence: WorkspacePersistenceController) throws -> Data {
        let records = try ModelContext(persistence.container).fetch(FetchDescriptor<WorkspaceRecord>())
        return try #require(records.first).payload
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(5))
        while !condition(), clock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(condition(), "The existing debounced save should complete within five seconds")
    }
}
