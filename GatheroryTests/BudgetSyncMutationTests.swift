import Foundation
import SwiftData
import Testing
@testable import Gatherory

@MainActor
struct BudgetSyncMutationTests {
#if DEBUG
    @Test("The conflict UI fixture keeps a known shared vector and local full-vector intent")
    func conflictFixtureHasExpectedVectors() throws {
        let persistence = try WorkspacePersistenceController(isStoredInMemoryOnly: true)
        let owner = DevelopmentAccountFixtures.planner
        let library = persistence.restoreLibrary(seedData: false, ownerUserID: owner.id)
        try BudgetConflictUITestFixtures.install(persistence: persistence, library: library, owner: owner)

        let workspace = try #require(library.workspaces.first)
        let childID = try #require(workspace.timeline.first?.id)
        #expect(workspace.title == "Local event title")
        #expect(workspace.mainEventBudgetCap == 700)
        #expect(workspace.timeline.first?.budgetCap == 300)
        let context = ModelContext(persistence.container)
        let record = try #require(context.fetch(FetchDescriptor<WorkspaceRecord>()).first)
        let archive = try WorkspaceArchiveCodec().decode(WorkspaceArchiveV1.self, from: record.payload)
        let shared = try JSONDecoder().decode(
            ReplaceBudgetMutationPayload.self,
            from: #require(archive.remoteBudgetSnapshotData)
        )
        #expect(shared.allocations.first { $0.eventID == archive.mainEventID }?.amountCents == 60_000)
        #expect(shared.allocations.first { $0.eventID == childID }?.amountCents == 40_000)
        let pending = try #require(context.fetch(FetchDescriptor<PendingMutation>()).first {
            $0.entityType == .budgetTransfer
        })
        #expect(pending.state == .requiresAttention)
        #expect(pending.lastFailureCode == "budget_version_conflict")
    }
#endif

    @Test("Authoritative budget vectors apply explicit nil allocations")
    func authoritativeVectorCanDisableAllocation() throws {
        let workspace = PlanningWorkspace.newWorkspace(
            title: "Nullable budget", startsAt: .now, eventLocation: nil, imageData: nil, budgetCap: 100
        )
        workspace.addTimelineItem(TimelineItem(
            title: "Optional", category: .other, scheduledAt: .now,
            participantIDs: [], parentEventID: workspace.mainEventID, budgetCap: .zero
        ))
        var archive = WorkspaceArchiveV1(workspace: workspace)
        let childID = try #require(archive.timeline.first?.id)
        let nilAllocationPayload = ReplaceBudgetMutationPayload(
            expectedBudgetVersion: 1,
            workspaceCapCents: 10_000,
            allocations: [
                BudgetAllocationMutationValue(eventID: archive.mainEventID, amountCents: 10_000),
                BudgetAllocationMutationValue(eventID: childID, amountCents: nil)
            ]
        )
        let json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(nilAllocationPayload)) as? [String: Any])
        let allocationRows = try #require(json["allocations"] as? [[String: Any]])
        #expect(allocationRows.last?["amountCents"] is NSNull)
        try archive.apply(nilAllocationPayload)
        #expect(archive.timeline.first?.budgetCap == nil)
    }

    @Test("Budget and expense sync keep money as exact JSON numbers and preserve native expense categories")
    func budgetAndExpenseWireValuesAreJSONNumbers() throws {
        let workspace = PlanningWorkspace.newWorkspace(
            title: "Money wire format", startsAt: .now, eventLocation: nil, imageData: nil,
            budgetCap: Decimal(string: "1234.56")!
        )
        let expense = EventExpense(
            eventID: workspace.mainEventID, title: "Dinner", amount: Decimal(string: "123.45")!,
            category: .foodAndDrink, status: .paid
        )
        workspace.replaceExpenses([expense], forEventID: workspace.mainEventID)
        let archive = WorkspaceArchiveV1(workspace: workspace)

        let budget = try archive.budgetMutationPayload(expectedBudgetVersion: 0)
        #expect(budget.workspaceCapCents == 123_456)
        let budgetJSON = try #require(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(budget)) as? [String: Any]
        )
        #expect(budgetJSON["workspaceCapCents"] as? Int == 123_456)
        #expect(!(budgetJSON["workspaceCapCents"] is String))

        let expenseKey = WorkspaceSyncEntityKey(type: .expense, id: expense.id)
        let expensePayload = try #require(archive.syncEntities(using: WorkspaceArchiveCodec())[expenseKey])
        let expenseJSON = try #require(
            JSONSerialization.jsonObject(with: expensePayload) as? [String: Any]
        )
        #expect(expenseJSON["amount"] as? Double == 123.45)
        #expect(!(expenseJSON["amount"] is String))
        #expect(expenseJSON["category"] as? String == "foodAndDrink")
        #expect(expenseJSON["status"] as? String == "paid")
    }

    @Test("Budget sync rejects sub-cent precision instead of rounding")
    func budgetSyncRejectsSubCentPrecision() throws {
        let workspace = PlanningWorkspace.newWorkspace(
            title: "Fractional cent", startsAt: .now, eventLocation: nil, imageData: nil,
            budgetCap: Decimal(string: "10.001")!
        )
        let archive = WorkspaceArchiveV1(workspace: workspace)
        #expect(throws: BudgetSyncMutationError.self) {
            try archive.budgetMutationPayload(expectedBudgetVersion: 0)
        }
    }

    @Test("Discarding against an older shared vector clears a newer child allocation but keeps the child")
    func olderVectorDiscardsUnfundedChildAllocation() async throws {
        let persistence = try WorkspacePersistenceController(isStoredInMemoryOnly: true)
        let owner = "budget-manager"
        let library = persistence.restoreLibrary(seedData: false, ownerUserID: owner)
        let workspace = PlanningWorkspace.newWorkspace(
            title: "Shared event", startsAt: .now, eventLocation: nil, imageData: nil, budgetCap: 1_000
        )
        workspace.addTimelineItem(TimelineItem(
            title: "Existing child", category: .other, scheduledAt: .now,
            participantIDs: [], parentEventID: workspace.mainEventID, budgetCap: .zero
        ))
        let sharedArchive = WorkspaceArchiveV1(workspace: workspace)
        let existingChildID = try #require(sharedArchive.timeline.first?.id)
        let sharedVector = ReplaceBudgetMutationPayload(
            expectedBudgetVersion: 2,
            workspaceCapCents: 100_000,
            allocations: [
                BudgetAllocationMutationValue(eventID: sharedArchive.mainEventID, amountCents: 60_000),
                BudgetAllocationMutationValue(eventID: existingChildID, amountCents: 40_000)
            ]
        )
        let codec = WorkspaceArchiveCodec()
        try persistence.applyBootstrap(
            [RemoteWorkspaceSnapshot(
                scopeID: sharedArchive.mainEventID, payload: try codec.encode(sharedArchive),
                serverVersion: 4, updatedAt: .now
            )],
            entities: [RemoteEntitySnapshot(
                scopeID: sharedArchive.mainEventID, entityType: .budgetTransfer,
                entityID: sharedArchive.mainEventID, payload: try JSONEncoder().encode(sharedVector),
                serverVersion: 2, updatedAt: .now
            )],
            to: library
        )

        let local = try #require(library.workspaces.first)
        local.title = "Preserved local title"
        local.addTimelineItem(TimelineItem(
            title: "New child stays", category: .other, scheduledAt: .now,
            participantIDs: [], parentEventID: local.mainEventID, budgetCap: .zero
        ))
        let newChildID = try #require(local.timeline.first(where: { $0.title == "New child stays" })?.id)
        #expect(local.transferBudget(300, from: .main, to: .subevent(newChildID)))
        #expect(local.timeline.first(where: { $0.id == newChildID })?.budgetCap == 300)
        try persistence.saveChanges(in: library)
        let context = ModelContext(persistence.container)
        let pendingBudget = try #require(context.fetch(FetchDescriptor<PendingMutation>())
            .first { $0.entityType == .budgetTransfer })
        pendingBudget.state = .requiresAttention
        pendingBudget.lastFailureCode = "budget_version_conflict"
        try context.save()

        var serverArchive = try codec.decode(
            WorkspaceArchiveV1.self,
            from: try #require(context.fetch(FetchDescriptor<WorkspaceRecord>()).first?.payload)
        )
        serverArchive.mainEventBudgetCap = 600
        let newChildIndex = try #require(serverArchive.timeline.firstIndex { $0.id == newChildID })
        serverArchive.timeline[newChildIndex].budgetCap = nil
        try persistence.applyRemotePage(
            SyncPullPage(changes: [
                RemoteChangeEnvelope(
                    id: UUID(), scopeID: sharedArchive.mainEventID, entityType: .workspace,
                    entityID: sharedArchive.mainEventID, operation: .update,
                    payload: try codec.encode(serverArchive), serverVersion: 5, occurredAt: .now
                ),
                RemoteChangeEnvelope(
                    id: UUID(), scopeID: sharedArchive.mainEventID, entityType: .budgetTransfer,
                    entityID: sharedArchive.mainEventID, operation: .update,
                    payload: try JSONEncoder().encode(sharedVector), serverVersion: 2, occurredAt: .now
                )
            ], nextCursor: "older-budget-vector", hasMore: false),
            scopeID: sharedArchive.mainEventID,
            to: library
        )
        #expect(library.workspaces.first?.timeline.first(where: { $0.id == newChildID })?.budgetCap == 300)
        #expect(try persistence.discardPendingBudgetIntent(scopeID: sharedArchive.mainEventID, from: library))
        let restored = try #require(library.workspaces.first)
        #expect(restored.title == "Preserved local title")
        #expect(restored.timeline.first(where: { $0.id == newChildID })?.title == "New child stays")
        #expect(restored.timeline.first(where: { $0.id == newChildID })?.budgetCap == nil)
        #expect(restored.mainEventBudgetCap == 600)
    }

    @Test("One allocation edit stages a full versioned budget vector and keeps budget fields out of ordinary writes")
    func budgetEditIsOneAtomicMutation() async throws {
        let persistence = try WorkspacePersistenceController(isStoredInMemoryOnly: true)
        let library = persistence.restoreLibrary(seedData: false, ownerUserID: "budget-manager")
        let workspace = PlanningWorkspace.newWorkspace(
            title: "Atomic budget", startsAt: .now, eventLocation: nil, imageData: nil, budgetCap: 1_000
        )
        workspace.addTimelineItem(TimelineItem(
            title: "Dinner", category: .other, scheduledAt: .now,
            participantIDs: [], parentEventID: workspace.mainEventID, budgetCap: .zero
        ))
        let archive = WorkspaceArchiveV1(workspace: workspace)
        let childID = try #require(archive.timeline.first?.id)
        let codec = WorkspaceArchiveCodec()
        try persistence.applyBootstrap(
            [RemoteWorkspaceSnapshot(
                scopeID: archive.mainEventID,
                payload: try codec.encode(archive),
                serverVersion: 4,
                updatedAt: .now
            )],
            entities: [RemoteEntitySnapshot(
                scopeID: archive.mainEventID,
                entityType: .budgetTransfer,
                entityID: archive.mainEventID,
                payload: try JSONEncoder().encode(
                    archive.budgetMutationPayload(expectedBudgetVersion: 9)
                ),
                serverVersion: 9,
                updatedAt: .now
            )],
            to: library
        )

        let restored = try #require(library.workspaces.first)
        #expect(restored.transferBudget(300, from: .main, to: .subevent(childID)))
        restored.title = "Content edit beside the allocation"
        try persistence.saveChanges(in: library)

        let context = ModelContext(persistence.container)
        let queued = try context.fetch(FetchDescriptor<PendingMutation>())
            .filter { $0.ownerUserID == "budget-manager" }
        let budgetMutation = try #require(queued.first { $0.entityType == .budgetTransfer })
        let command = try JSONDecoder().decode(ReplaceBudgetMutationPayload.self, from: budgetMutation.payload)
        #expect(command.operation == "replace_budget")
        #expect(command.expectedBudgetVersion == 9)
        #expect(command.workspaceCapCents == 100_000)
        #expect(command.allocations == [
            BudgetAllocationMutationValue(eventID: archive.mainEventID, amountCents: 70_000),
            BudgetAllocationMutationValue(eventID: childID, amountCents: 30_000)
        ])
        #expect(queued.filter { $0.entityType == .budgetTransfer }.count == 1)
        #expect(budgetMutation.baseVersion == 9)

        let workspaceMutation = try #require(queued.first { $0.entityType == .workspace })
        let syncedArchive = try JSONSerialization.jsonObject(with: workspaceMutation.payload) as? [String: Any]
        #expect(syncedArchive?["title"] as? String == "Content edit beside the allocation")
        #expect(syncedArchive?["workspaceBudgetCap"] == nil)
        #expect(syncedArchive?["mainEventBudgetCap"] == nil)
        let syncedTimeline = syncedArchive?["timeline"] as? [[String: Any]]
        #expect(syncedTimeline?.first?["budgetCap"] == nil)
        #expect(!queued.contains { $0.entityType == .event && $0.entityID == childID })

        let stored = try #require(context.fetch(FetchDescriptor<WorkspaceRecord>())
            .first { $0.ownerUserID == "budget-manager" })
        let localArchive = try codec.decode(WorkspaceArchiveV1.self, from: stored.payload)
        #expect(localArchive.title == "Content edit beside the allocation")
        #expect(localArchive.mainEventBudgetCap == 700)
        #expect(localArchive.timeline.first?.budgetCap == 300)

        let store = SwiftDataSyncStore(modelContainer: persistence.container)
        try await store.requireAttention([budgetMutation.id], failureCode: "budget_version_conflict")
        var competingArchive = archive
        competingArchive.title = "Content edit beside the allocation"
        competingArchive.mainEventBudgetCap = 600
        competingArchive.timeline[0].budgetCap = 400
        let remoteBudget = ReplaceBudgetMutationPayload(
            expectedBudgetVersion: 10,
            workspaceCapCents: 100_000,
            allocations: [
                BudgetAllocationMutationValue(eventID: archive.mainEventID, amountCents: 60_000),
                BudgetAllocationMutationValue(eventID: childID, amountCents: 40_000)
            ]
        )
        try persistence.applyRemotePage(
            SyncPullPage(changes: [
                RemoteChangeEnvelope(
                    id: UUID(), scopeID: archive.mainEventID, entityType: .workspace,
                    entityID: archive.mainEventID, operation: .update,
                    payload: try codec.encode(competingArchive), serverVersion: 5, occurredAt: .now
                ),
                RemoteChangeEnvelope(
                    id: UUID(), scopeID: archive.mainEventID, entityType: .budgetTransfer,
                    entityID: archive.mainEventID, operation: .update,
                    payload: try JSONEncoder().encode(remoteBudget), serverVersion: 10, occurredAt: .now
                )
            ], nextCursor: "budget-conflict", hasMore: false),
            scopeID: archive.mainEventID,
            to: library
        )
        let recoveredWorkspace = try #require(library.workspaces.first)
        #expect(recoveredWorkspace.mainEventBudgetCap == 700)
        #expect(recoveredWorkspace.timeline.first?.budgetCap == 300)
        let savedBudgetVersion = try RemoteEntityVersionRecord.version(
            in: ModelContext(persistence.container), scopeID: archive.mainEventID,
            entityType: .budgetTransfer, entityID: archive.mainEventID,
            ownerUserID: "budget-manager"
        )
        #expect(savedBudgetVersion == 10)
        let retainedCommand = try #require(ModelContext(persistence.container)
            .fetch(FetchDescriptor<PendingMutation>()).first { $0.id == budgetMutation.id })
        #expect(retainedCommand.state == .requiresAttention)
        #expect(try JSONDecoder().decode(ReplaceBudgetMutationPayload.self, from: retainedCommand.payload) == command)
        #expect(try persistence.pendingBudgetSyncAttentionFailureCode() == "budget_version_conflict")
        #expect(try persistence.pendingBudgetSyncConflictScopeIDs() == [archive.mainEventID])
        #expect(try persistence.canDiscardPendingBudgetIntent(scopeID: archive.mainEventID))
        #expect(recoveredWorkspace.transferBudget(10, from: .main, to: .subevent(childID)))
        try persistence.saveChanges(in: library)
        let blockedCommands = try ModelContext(persistence.container)
            .fetch(FetchDescriptor<PendingMutation>())
            .filter { $0.entityType == .budgetTransfer }
        #expect(blockedCommands.count == 2)
        #expect(blockedCommands.allSatisfy { $0.state == .requiresAttention })
        #expect(blockedCommands.contains { $0.lastFailureCode == "budget_conflict_review_required" })
        #expect(try persistence.discardPendingBudgetIntent(scopeID: archive.mainEventID, from: library))
        let discardedWorkspace = try #require(library.workspaces.first)
        #expect(discardedWorkspace.mainEventBudgetCap == 600)
        #expect(discardedWorkspace.timeline.first?.budgetCap == 400)
        #expect(discardedWorkspace.title == "Content edit beside the allocation")
        let remainingMutations = try ModelContext(persistence.container).fetch(FetchDescriptor<PendingMutation>())
        #expect(!remainingMutations.contains { $0.id == budgetMutation.id })
    }

    @Test("A budget retry retains the same complete command and a conflict retains its whole intent")
    func retryAndConflictPreserveBudgetCommand() async throws {
        let persistence = try WorkspacePersistenceController(isStoredInMemoryOnly: true)
        let scopeID = UUID()
        let payload = try JSONEncoder().encode(ReplaceBudgetMutationPayload(
            expectedBudgetVersion: 3,
            workspaceCapCents: nil,
            allocations: [
                BudgetAllocationMutationValue(eventID: scopeID, amountCents: 70_000),
                BudgetAllocationMutationValue(eventID: UUID(), amountCents: 30_000)
            ]
        ))
        let encoded = try #require(JSONSerialization.jsonObject(with: payload) as? [String: Any])
        #expect(encoded["workspaceCapCents"] is NSNull)
        let context = ModelContext(persistence.container)
        let mutation = PendingMutation(
            scopeID: scopeID, entityType: .budgetTransfer, entityID: scopeID,
            operation: .update, payload: payload, baseVersion: 3, ownerUserID: "budget-manager"
        )
        context.insert(mutation)
        try context.save()
        let originalID = mutation.id

        let store = SwiftDataSyncStore(modelContainer: persistence.container)
        let firstClaim = try await store.claimReadyMutations(
            scopeID: scopeID, ownerUserID: "budget-manager", limit: 10,
            at: .now, leaseDuration: 60
        )
        #expect(firstClaim.map(\.id) == [originalID])
        #expect(firstClaim.first?.payload == payload)
        try await store.retry([originalID], failureCode: "transport_failure", at: .now,
                              policy: SyncRetryPolicy(initialDelay: 0, maximumDelay: 0))
        let retryClaim = try await store.claimReadyMutations(
            scopeID: scopeID, ownerUserID: "budget-manager", limit: 10,
            at: .now, leaseDuration: 60
        )
        #expect(retryClaim.map(\.id) == [originalID])
        #expect(retryClaim.first?.payload == payload)

        try await store.requireAttention([originalID], failureCode: "budget_version_conflict")
        let preserved = try ModelContext(persistence.container).fetch(FetchDescriptor<PendingMutation>())
            .first { $0.id == originalID }
        #expect(preserved?.state == .requiresAttention)
        #expect(preserved?.lastFailureCode == "budget_version_conflict")
        #expect(preserved?.payload == payload)
        #expect(try JSONDecoder().decode(ReplaceBudgetMutationPayload.self, from: #require(preserved).payload)
            .allocations.count == 2)
        #expect(try await store.claimReadyMutations(
            scopeID: scopeID, ownerUserID: "budget-manager", limit: 10,
            at: .now, leaseDuration: 60
        ).isEmpty)
    }

    @Test("Only an acknowledged budget command advances its next local command")
    func budgetAcknowledgmentAdvancesVersion() async throws {
        let persistence = try WorkspacePersistenceController(isStoredInMemoryOnly: true)
        let owner = "budget-manager"
        let scopeID = UUID()
        let childID = UUID()
        let context = ModelContext(persistence.container)
        let firstPayload = try JSONEncoder().encode(ReplaceBudgetMutationPayload(
            expectedBudgetVersion: 3,
            workspaceCapCents: 100_000,
            allocations: [
                BudgetAllocationMutationValue(eventID: scopeID, amountCents: 70_000),
                BudgetAllocationMutationValue(eventID: childID, amountCents: 30_000)
            ]
        ))
        let first = PendingMutation(
            scopeID: scopeID, entityType: .budgetTransfer, entityID: scopeID,
            operation: .update, payload: firstPayload, baseVersion: 3, ownerUserID: owner
        )
        first.state = .sending
        let following = PendingMutation(
            scopeID: scopeID, entityType: .budgetTransfer, entityID: scopeID,
            operation: .update, payload: firstPayload, baseVersion: 3, ownerUserID: owner
        )
        context.insert(first)
        context.insert(following)
        context.insert(WorkspaceRecord(
            id: scopeID, payload: Data(), sortOrder: 0, ownerUserID: owner, serverVersion: 7
        ))
        try context.save()

        let store = SwiftDataSyncStore(modelContainer: persistence.container)
        try await store.acknowledge([SyncPushResult(
            mutationID: first.id,
            disposition: .applied,
            serverVersion: 4,
            failureCode: nil,
            workspaceServerVersion: 8
        )])

        let verification = ModelContext(persistence.container)
        let remaining = try #require(verification.fetch(FetchDescriptor<PendingMutation>())
            .first { $0.id == following.id })
        let rebased = try JSONDecoder().decode(ReplaceBudgetMutationPayload.self, from: remaining.payload)
        #expect(rebased.expectedBudgetVersion == 4)
        #expect(remaining.baseVersion == 4)
        #expect(try RemoteEntityVersionRecord.version(
            in: verification, scopeID: scopeID, entityType: .budgetTransfer,
            entityID: scopeID, ownerUserID: owner
        ) == 4)
        #expect(try verification.fetch(FetchDescriptor<WorkspaceRecord>()).first?.serverVersion == 8)
        #expect(try verification.fetch(FetchDescriptor<PendingMutation>()).map(\.id) == [following.id])
    }

    @Test("A retried idempotency key stays immutable and later budget intent waits for conflict review")
    func retryKeyIsImmutableAndFollowUpIsBlocked() async throws {
        let persistence = try WorkspacePersistenceController(isStoredInMemoryOnly: true)
        let scopeID = UUID()
        let childID = UUID()
        let owner = "budget-manager"
        let oldPayload = try JSONEncoder().encode(ReplaceBudgetMutationPayload(
            expectedBudgetVersion: 3,
            workspaceCapCents: 100_000,
            allocations: [
                BudgetAllocationMutationValue(eventID: scopeID, amountCents: 70_000),
                BudgetAllocationMutationValue(eventID: childID, amountCents: 30_000)
            ]
        ))
        let newPayload = try JSONEncoder().encode(ReplaceBudgetMutationPayload(
            expectedBudgetVersion: 3,
            workspaceCapCents: 100_000,
            allocations: [
                BudgetAllocationMutationValue(eventID: scopeID, amountCents: 60_000),
                BudgetAllocationMutationValue(eventID: childID, amountCents: 40_000)
            ]
        ))
        let context = ModelContext(persistence.container)
        let attempted = PendingMutation(
            scopeID: scopeID, entityType: .budgetTransfer, entityID: scopeID,
            operation: .update, payload: oldPayload, baseVersion: 3, ownerUserID: owner
        )
        attempted.attemptCount = 1
        attempted.lastFailureCode = "transport_failure"
        context.insert(attempted)
        try context.save()

        let writer = WorkspaceOutboxWriter(context: context, codec: WorkspaceArchiveCodec(), ownerUserID: owner)
        writer.coalesceMutation(
            scopeID: scopeID, entityType: .budgetTransfer, entityID: scopeID,
            payload: newPayload, operation: .update, baseVersion: 3,
            pendingMutations: [attempted]
        )
        try context.save()
        let queued = try context.fetch(FetchDescriptor<PendingMutation>())
            .filter { $0.entityType == .budgetTransfer }
        #expect(queued.count == 2)
        #expect(queued.contains { $0.id == attempted.id && $0.payload == oldPayload })
        let laterIntent = try #require(queued.first { $0.id != attempted.id })
        #expect(try JSONDecoder().decode(ReplaceBudgetMutationPayload.self, from: laterIntent.payload)
            .allocations[0].amountCents == 60_000)

        let store = SwiftDataSyncStore(modelContainer: persistence.container)
        try await store.requireAttention([attempted.id], failureCode: "budget_version_conflict")
        let retained = try ModelContext(persistence.container).fetch(FetchDescriptor<PendingMutation>())
            .filter { $0.entityType == .budgetTransfer }
        #expect(retained.allSatisfy { $0.state == .requiresAttention })
        #expect(retained.contains { $0.id == laterIntent.id && $0.lastFailureCode == "budget_conflict_review_required" })
        #expect(try await store.claimReadyMutations(
            scopeID: scopeID, ownerUserID: owner, limit: 10,
            at: .now, leaseDuration: 60
        ).isEmpty)
    }

    @Test("Mutation claims preserve content, child deletion, budget replacement, and root deletion phases")
    func deletionDependenciesSurviveBatchLimitsAndRetries() async throws {
        let persistence = try WorkspacePersistenceController(isStoredInMemoryOnly: true)
        let scopeID = UUID()
        let childID = UUID()
        let owner = "budget-manager"
        let context = ModelContext(persistence.container)
        let expense = PendingMutation(
            scopeID: scopeID, entityType: .expense, entityID: UUID(), operation: .update,
            payload: Data([1]), ownerUserID: owner
        )
        let childDelete = PendingMutation(
            scopeID: scopeID, entityType: .event, entityID: childID, operation: .delete,
            payload: Data(), ownerUserID: owner
        )
        let budget = PendingMutation(
            scopeID: scopeID, entityType: .budgetTransfer, entityID: scopeID, operation: .update,
            payload: Data([2]), ownerUserID: owner
        )
        let rootDelete = PendingMutation(
            scopeID: scopeID, entityType: .workspace, entityID: scopeID, operation: .delete,
            payload: Data(), ownerUserID: owner
        )
        for mutation in [rootDelete, budget, childDelete, expense] { context.insert(mutation) }
        try context.save()
        let store = SwiftDataSyncStore(modelContainer: persistence.container)

        let contentClaim = try await store.claimReadyMutations(
            scopeID: scopeID, ownerUserID: owner, limit: 1, at: .now, leaseDuration: 60
        )
        #expect(contentClaim.map(\.id) == [expense.id])
        // A leased earlier phase blocks later phases, even if the batch limit was one.
        #expect(try await store.claimReadyMutations(
            scopeID: scopeID, ownerUserID: owner, limit: 10, at: .now, leaseDuration: 60
        ).isEmpty)
        try await store.acknowledge([SyncPushResult(
            mutationID: expense.id, disposition: .applied, serverVersion: 1, failureCode: nil
        )])

        let deletionClaim = try await store.claimReadyMutations(
            scopeID: scopeID, ownerUserID: owner, limit: 1, at: .now, leaseDuration: 60
        )
        #expect(deletionClaim.map(\.id) == [childDelete.id])
        try await store.retry([childDelete.id], failureCode: "temporary", at: .now,
                              policy: SyncRetryPolicy(initialDelay: 60, maximumDelay: 60))
        // The child tombstone retry must be resolved before the vector can omit it.
        #expect(try await store.claimReadyMutations(
            scopeID: scopeID, ownerUserID: owner, limit: 10, at: .now, leaseDuration: 60
        ).isEmpty)
        try await store.acknowledge([SyncPushResult(
            mutationID: childDelete.id, disposition: .applied, serverVersion: 1, failureCode: nil
        )])

        let budgetClaim = try await store.claimReadyMutations(
            scopeID: scopeID, ownerUserID: owner, limit: 1, at: .now, leaseDuration: 60
        )
        #expect(budgetClaim.map(\.id) == [budget.id])
        try await store.acknowledge([SyncPushResult(
            mutationID: budget.id, disposition: .applied, serverVersion: 1, failureCode: nil
        )])
        let rootClaim = try await store.claimReadyMutations(
            scopeID: scopeID, ownerUserID: owner, limit: 1, at: .now, leaseDuration: 60
        )
        #expect(rootClaim.map(\.id) == [rootDelete.id])
    }

    @Test("Ready dependency phases remain in one push batch")
    func readyPhasesShareBatch() async throws {
        let persistence = try WorkspacePersistenceController(isStoredInMemoryOnly: true)
        let scopeID = UUID()
        let context = ModelContext(persistence.container)
        let mutations = [
            PendingMutation(scopeID: scopeID, entityType: .expense, entityID: UUID(),
                            operation: .update, payload: Data([1]), ownerUserID: "owner"),
            PendingMutation(scopeID: scopeID, entityType: .event, entityID: UUID(),
                            operation: .delete, payload: Data(), ownerUserID: "owner"),
            PendingMutation(scopeID: scopeID, entityType: .budgetTransfer, entityID: scopeID,
                            operation: .update, payload: Data([2]), ownerUserID: "owner"),
            PendingMutation(scopeID: scopeID, entityType: .workspace, entityID: scopeID,
                            operation: .delete, payload: Data(), ownerUserID: "owner")
        ]
        for mutation in mutations { context.insert(mutation) }
        try context.save()

        let claimed = try await SwiftDataSyncStore(modelContainer: persistence.container)
            .claimReadyMutations(scopeID: scopeID, ownerUserID: "owner", limit: 10,
                                 at: .now, leaseDuration: 60)
        #expect(claimed.map(\.id) == mutations.map(\.id))
    }

    @Test("A local child deletion queues its tombstone before the replacement vector")
    func childDeletionStagesTombstoneAndCompleteRemainingVector() throws {
        let persistence = try WorkspacePersistenceController(isStoredInMemoryOnly: true)
        let context = ModelContext(persistence.container)
        let owner = "budget-manager"
        let workspace = PlanningWorkspace.newWorkspace(
            title: "Delete one child", startsAt: .now, eventLocation: nil, imageData: nil, budgetCap: 1_000
        )
        workspace.addTimelineItem(TimelineItem(
            title: "Funded child", category: .other, scheduledAt: .now,
            participantIDs: [], parentEventID: workspace.mainEventID, budgetCap: 100
        ))
        let previous = WorkspaceArchiveV1(workspace: workspace)
        let childID = try #require(previous.timeline.first?.id)
        var current = previous
        current.timeline.removeAll { $0.id == childID }
        let writer = WorkspaceOutboxWriter(
            context: context, codec: WorkspaceArchiveCodec(), ownerUserID: owner
        )
        try writer.coalesceEntityMutations(
            scopeID: previous.mainEventID, previousArchive: previous, archive: current,
            pendingMutations: []
        )
        try context.save()

        let mutations = try context.fetch(FetchDescriptor<PendingMutation>())
        let tombstone = try #require(mutations.first { $0.entityType == .event && $0.entityID == childID })
        let vectorMutation = try #require(mutations.first { $0.entityType == .budgetTransfer })
        #expect(tombstone.operation == .delete)
        let vector = try JSONDecoder().decode(ReplaceBudgetMutationPayload.self, from: vectorMutation.payload)
        #expect(!vector.allocations.contains { $0.eventID == childID })
        #expect(vector.allocations.contains { $0.eventID == previous.mainEventID })
    }

    @Test("Creating an unbudgeted child does not require a budget command")
    func unbudgetedChildDoesNotChangeBudgetVector() throws {
        let persistence = try WorkspacePersistenceController(isStoredInMemoryOnly: true)
        let context = ModelContext(persistence.container)
        let workspace = PlanningWorkspace.newWorkspace(
            title: "Unbudgeted child", startsAt: .now, eventLocation: nil, imageData: nil
        )
        let previous = WorkspaceArchiveV1(workspace: workspace)
        var current = previous
        current.timeline.append(TimelineItem(
            title: "No allocation", category: .other, scheduledAt: .now,
            participantIDs: [], parentEventID: previous.mainEventID, budgetCap: nil
        ))
        #expect(!current.hasBudgetChanges(comparedTo: previous))

        try WorkspaceOutboxWriter(
            context: context, codec: WorkspaceArchiveCodec(), ownerUserID: "owner"
        ).coalesceEntityMutations(
            scopeID: previous.mainEventID, previousArchive: previous, archive: current,
            pendingMutations: []
        )
        #expect(try context.fetch(FetchDescriptor<PendingMutation>())
            .allSatisfy { $0.entityType != .budgetTransfer })
    }

    @Test("Deleting a root workspace removes conflicted budget intents before its tombstone")
    func rootDeletionClearsBudgetAttention() throws {
        let persistence = try WorkspacePersistenceController(isStoredInMemoryOnly: true)
        let context = ModelContext(persistence.container)
        let scopeID = UUID()
        let owner = "budget-manager"
        let budget = PendingMutation(
            scopeID: scopeID, entityType: .budgetTransfer, entityID: scopeID, operation: .update,
            payload: Data([1]), ownerUserID: owner
        )
        budget.state = .requiresAttention
        budget.lastFailureCode = "budget_version_conflict"
        let childMutation = PendingMutation(
            scopeID: scopeID, entityType: .event, entityID: UUID(), operation: .update,
            payload: Data([2]), ownerUserID: owner
        )
        childMutation.state = .requiresAttention
        childMutation.lastFailureCode = "EVENT_VERSION_CONFLICT"
        context.insert(budget)
        context.insert(childMutation)
        try context.save()

        let writer = WorkspaceOutboxWriter(
            context: context, codec: WorkspaceArchiveCodec(), ownerUserID: owner
        )
        writer.coalesceDeletion(scopeID: scopeID, baseVersion: 4, pendingMutations: [budget])
        try context.save()
        let mutations = try context.fetch(FetchDescriptor<PendingMutation>())
        #expect(mutations.count == 1)
        #expect(mutations.first?.entityType == .workspace)
        #expect(mutations.first?.operation == .delete)
    }
}
