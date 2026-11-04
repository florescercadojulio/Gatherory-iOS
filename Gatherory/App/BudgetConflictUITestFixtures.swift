#if DEBUG
import Foundation
import SwiftData

private enum BudgetConflictUITestFixtureError: Error {
    case workspaceUnavailable
    case budgetMutationUnavailable
}

/// Synthetic, ephemeral account data for the Account budget-conflict UI test.
@MainActor
enum BudgetConflictUITestFixtures {
    static var isEnabled: Bool {
        let arguments = ProcessInfo.processInfo.arguments
        return arguments.contains("-BudgetConflictUITest")
            && arguments.contains("-UseEphemeralDataStore")
    }

    static func install(
        persistence: WorkspacePersistenceController,
        library: WorkspaceLibrary,
        owner: UserAccount
    ) throws {
        let sharedWorkspace = PlanningWorkspace.newWorkspace(
            title: "Shared Budget Title",
            startsAt: .now,
            eventLocation: nil,
            imageData: nil,
            budgetCap: 1_000,
            owner: owner
        )
        sharedWorkspace.addTimelineItem(TimelineItem(
            title: "Dinner",
            category: .other,
            scheduledAt: sharedWorkspace.mainEventStartsAt,
            participantIDs: [],
            parentEventID: sharedWorkspace.mainEventID,
            budgetCap: .zero
        ))
        guard let initialChildID = sharedWorkspace.timeline.first?.id,
              sharedWorkspace.allocateInitialBudget(400, to: initialChildID) else {
            throw BudgetConflictUITestFixtureError.workspaceUnavailable
        }
        let sharedArchive = WorkspaceArchiveV1(workspace: sharedWorkspace)
        let sharedBudget = try sharedArchive.budgetMutationPayload(expectedBudgetVersion: 1)
        let codec = WorkspaceArchiveCodec()
        try persistence.applyBootstrap(
            [RemoteWorkspaceSnapshot(
                scopeID: sharedArchive.mainEventID,
                payload: try codec.encode(sharedArchive),
                serverVersion: 4,
                updatedAt: .now
            )],
            entities: [RemoteEntitySnapshot(
                scopeID: sharedArchive.mainEventID,
                entityType: .budgetTransfer,
                entityID: sharedArchive.mainEventID,
                payload: try JSONEncoder().encode(sharedBudget),
                serverVersion: 1,
                updatedAt: .now
            )],
            to: library
        )

        guard let workspace = library.workspaces.first else {
            throw BudgetConflictUITestFixtureError.workspaceUnavailable
        }
        workspace.title = "Local event title"
        guard let childID = workspace.timeline.first?.id,
              workspace.transferBudget(100, from: .subevent(childID), to: .main) else {
            throw BudgetConflictUITestFixtureError.workspaceUnavailable
        }
        try persistence.saveChanges(in: library)

        let context = ModelContext(persistence.container)
        let pending = try context.fetch(FetchDescriptor<PendingMutation>())
            .filter { $0.ownerUserID == owner.id && $0.entityType == .budgetTransfer }
        guard !pending.isEmpty else { throw BudgetConflictUITestFixtureError.budgetMutationUnavailable }
        for mutation in pending {
            mutation.state = .requiresAttention
            mutation.lastFailureCode = "budget_version_conflict"
        }
        try context.save()
    }
}
#endif
