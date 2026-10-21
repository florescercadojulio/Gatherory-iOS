import Foundation
import Testing
@testable import Gatherory

@MainActor
struct ManageBudgetTests {
    @Test("Budget pill distinguishes unset, zero, remaining, and overspent allocations")
    func budgetPillMetrics() {
        let unset = ManageMetric.remaining(spent: 20, budget: nil, currencyCode: "USD")
        #expect(unset.value == "—")
        #expect(unset.label == String(localized: "No budget set"))
        #expect(!unset.isWarning)

        let remaining = ManageMetric.remaining(spent: 20, budget: 100, currencyCode: "EUR")
        #expect(remaining.value == Decimal(80).formatted(.currency(code: "EUR")))
        #expect(remaining.label == String(localized: "Remaining"))
        #expect(!remaining.isWarning)

        let zero = ManageMetric.remaining(spent: 0, budget: 0, currencyCode: "USD")
        #expect(zero.value == Decimal.zero.formatted(.currency(code: "USD")))
        #expect(zero.label == String(localized: "Remaining"))

        let over = ManageMetric.remaining(spent: 120, budget: 100, currencyCode: "USD")
        #expect(over.value == Decimal(20).formatted(.currency(code: "USD")))
        #expect(over.label == String(localized: "Over budget"))
        #expect(over.isWarning)
    }

    @Test("Missing reference projects the full root workspace overview")
    func rootOverviewContainsEveryLocalEvent() throws {
        let fixture = makeWorkspace()
        let projection = BudgetDestinationProjection.make(
            reference: nil,
            isScopedEvent: false,
            mainEventID: fixture.mainID,
            workspaceTitle: "Weekend",
            timeline: [fixture.child, fixture.sibling],
            expenses: fixture.expenses,
            workspaceBudgetCap: 500,
            mainEventBudgetCap: 300
        )

        #expect(projection.isValid)
        #expect(projection.isWorkspaceOverview)
        #expect(projection.title == "Event Budget")
        #expect(projection.displayedSpent == 175)
        #expect(Set(projection.expenses.map(\.id)) == Set(fixture.expenses.map(\.id)))
        #expect(projection.costSummaries.map(\.id).count == 3)
        #expect(projection.budgetSummaries.map(\.reference) == [
            .main, .subevent(fixture.child.id), .subevent(fixture.sibling.id)
        ])
    }

    @Test("Explicit child reference contains only that event's local budget and expenses")
    func selectedChildIsIsolatedFromRootAndSibling() throws {
        let fixture = makeWorkspace()
        let projection = BudgetDestinationProjection.make(
            reference: .subevent(fixture.child.id),
            isScopedEvent: false,
            mainEventID: fixture.mainID,
            workspaceTitle: "Weekend",
            timeline: [fixture.child, fixture.sibling],
            expenses: fixture.expenses,
            workspaceBudgetCap: 500,
            mainEventBudgetCap: 300
        )

        #expect(projection.isValid)
        #expect(!projection.isWorkspaceOverview)
        #expect(projection.title == "Dinner")
        #expect(projection.displayedBudgetCap == 120)
        #expect(projection.displayedSpent == 25)
        #expect(projection.expenses.map(\.id) == [fixture.childExpense.id])
        #expect(projection.budgetSummaries.map(\.reference) == [.subevent(fixture.child.id)])
    }

    @Test("Scoped root remains local and rejects workspace overview, sibling, idea, and unknown references")
    func scopedRootRejectsBroaderReferences() throws {
        let fixture = makeWorkspace()
        let scopedExpenses = fixture.expenses + [
            EventExpense(eventID: UUID(), title: "Anomalous sibling row", amount: 999)
        ]
        let local = BudgetDestinationProjection.make(
            reference: .main,
            isScopedEvent: true,
            mainEventID: fixture.child.id,
            workspaceTitle: "Dinner",
            timeline: [fixture.sibling],
            expenses: scopedExpenses,
            workspaceBudgetCap: 500,
            mainEventBudgetCap: 120
        )

        #expect(local.isValid)
        #expect(!local.isWorkspaceOverview)
        #expect(local.title == "Dinner")
        #expect(local.displayedBudgetCap == 120)
        #expect(local.expenses.map(\.id) == [fixture.childExpense.id])
        #expect(local.displayedSpent == 25)

        for reference in [EventReference.subevent(fixture.sibling.id), .idea(UUID()), .subevent(UUID())] {
            let rejected = BudgetDestinationProjection.make(
                reference: reference,
                isScopedEvent: true,
                mainEventID: fixture.child.id,
                workspaceTitle: "Dinner",
                timeline: [fixture.sibling],
                expenses: scopedExpenses,
                workspaceBudgetCap: 500,
                mainEventBudgetCap: 300
            )
            #expect(!rejected.isValid)
            #expect(rejected.expenses.isEmpty)
            #expect(rejected.displayedSpent == .zero)
            #expect(rejected.budgetSummaries.isEmpty)
        }

        let rejectedOverview = BudgetDestinationProjection.make(
            reference: nil,
            isScopedEvent: true,
            mainEventID: fixture.child.id,
            workspaceTitle: "Dinner",
            timeline: [fixture.sibling],
            expenses: scopedExpenses,
            workspaceBudgetCap: 500,
            mainEventBudgetCap: 300
        )
        #expect(!rejectedOverview.isValid)
        #expect(rejectedOverview.expenses.isEmpty)
    }

    @Test("Allocation requires unscoped root and exact target management permissions")
    func allocationPolicyRequiresRootAndTargetManager() {
        let childManagerOnly = makePermissionWorkspace(
            isScoped: false,
            mainPermission: .contribute,
            childPermission: .manage
        )
        #expect(!BudgetAllocationPermissionPolicy.canEditAllocation(in: childManagerOnly.workspace, for: .main))
        #expect(!BudgetAllocationPermissionPolicy.canEditAllocation(
            in: childManagerOnly.workspace,
            for: .subevent(childManagerOnly.child.id)
        ))

        let viewOnly = makePermissionWorkspace(
            isScoped: false,
            mainPermission: .viewOnly,
            childPermission: .manage
        )
        #expect(!BudgetAllocationPermissionPolicy.canEditAllocation(in: viewOnly.workspace, for: .main))

        let rootManagerOnly = makePermissionWorkspace(
            isScoped: false,
            mainPermission: .manage,
            childPermission: .contribute
        )
        #expect(BudgetAllocationPermissionPolicy.canEditAllocation(in: rootManagerOnly.workspace, for: .main))
        #expect(!BudgetAllocationPermissionPolicy.canEditAllocation(
            in: rootManagerOnly.workspace,
            for: .subevent(rootManagerOnly.child.id)
        ))

        let scopedManager = makePermissionWorkspace(
            isScoped: true,
            mainPermission: .manage,
            childPermission: .manage
        )
        #expect(scopedManager.workspace.canManageInvitations(for: .main))
        #expect(!BudgetAllocationPermissionPolicy.canEditAllocation(in: scopedManager.workspace, for: .main))
    }

    private func makeWorkspace() -> Fixture {
        let mainID = UUID()
        let child = TimelineItem(
            title: "Dinner", category: .reception, scheduledAt: .now,
            location: "", participantIDs: [], parentEventID: mainID, budgetCap: 120
        )
        let sibling = TimelineItem(
            title: "Brunch", category: .foodTasting, scheduledAt: .now.addingTimeInterval(3600),
            location: "", participantIDs: [], parentEventID: mainID, budgetCap: 80
        )
        let rootExpense = EventExpense(eventID: mainID, title: "Venue", amount: 100)
        let childExpense = EventExpense(eventID: child.id, title: "Dinner", amount: 25)
        let siblingExpense = EventExpense(eventID: sibling.id, title: "Brunch", amount: 50)
        return Fixture(
            mainID: mainID,
            child: child,
            sibling: sibling,
            expenses: [rootExpense, childExpense, siblingExpense],
            childExpense: childExpense
        )
    }

    private func makePermissionWorkspace(
        isScoped: Bool,
        mainPermission: PlanningPermission,
        childPermission: PlanningPermission
    ) -> (workspace: PlanningWorkspace, child: TimelineItem) {
        let mainID = UUID()
        let member = WorkspaceMember(
            userID: "budget-manager",
            name: "Planner",
            participantRole: .collaborator,
            initials: "P",
            planningPermission: mainPermission
        )
        let child = TimelineItem(
            title: "Dinner",
            category: .reception,
            scheduledAt: .now,
            location: "",
            participantIDs: [member.id],
            parentEventID: mainID,
            budgetCap: 100
        )
        let workspace = PlanningWorkspace(
            mainEventID: mainID,
            isScopedEvent: isScoped,
            title: "Weekend",
            mainEventStartsAt: .now,
            venueName: "",
            location: "",
            planningMode: .openToIdeas,
            members: [member],
            eventParticipations: [
                EventParticipation(
                    eventID: mainID,
                    memberID: member.id,
                    role: .collaborator,
                    planningPermission: mainPermission,
                    attendance: .invited,
                    invitationStatus: .active
                ),
                EventParticipation(
                    eventID: child.id,
                    memberID: member.id,
                    role: .collaborator,
                    planningPermission: childPermission,
                    attendance: .invited,
                    invitationStatus: .active
                )
            ],
            ideas: [],
            timeline: isScoped ? [] : [child],
            workspaceBudgetCap: 100,
            mainEventBudgetCap: 100,
            registry: []
        )
        workspace.configureViewer(UserAccount(
            id: "budget-manager",
            email: "planner@example.test",
            displayName: "Planner",
            role: .planner,
            authenticationProvider: .password,
            createdAt: .now
        ))
        return (workspace, child)
    }

    private struct Fixture {
        let mainID: UUID
        let child: TimelineItem
        let sibling: TimelineItem
        let expenses: [EventExpense]
        let childExpense: EventExpense
    }
}
