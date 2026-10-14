import Foundation
import Testing
@testable import Gatherory

struct WorkspaceBudgetRulesTests {
    @Test("Currency normalization keeps the existing length-only validation")
    func currencyNormalization() {
        #expect(WorkspaceBudgetRules.normalizedCurrencyCode("  eur\n") == "EUR")
        #expect(WorkspaceBudgetRules.normalizedCurrencyCode("xy") == "USD")
        #expect(WorkspaceBudgetRules.normalizedCurrencyCode("") == "USD")
        #expect(WorkspaceBudgetRules.normalizedCurrencyCode("123") == "123")
    }

    @Test("Initial allocations preserve explicit legacy values and clamp only the inferred remainder")
    func initialAllocation() {
        #expect(WorkspaceBudgetRules.initialMainAllocation(
            explicitAllocation: nil, workspaceCap: 100, childAllocations: [25, nil, 15]
        ) == 60)
        #expect(WorkspaceBudgetRules.initialMainAllocation(
            explicitAllocation: nil, workspaceCap: 10, childAllocations: [25]
        ) == .zero)
        #expect(WorkspaceBudgetRules.initialMainAllocation(
            explicitAllocation: nil, workspaceCap: nil, childAllocations: [25]
        ) == nil)
        #expect(WorkspaceBudgetRules.initialMainAllocation(
            explicitAllocation: -5, workspaceCap: nil, childAllocations: [25]
        ) == -5)
        #expect(WorkspaceBudgetRules.initialMainAllocation(
            explicitAllocation: 120, workspaceCap: 100, childAllocations: [25]
        ) == 120)
    }

    @Test("Allocation totals use Decimal precision and overspending remains visible")
    func decimalTotalsAndRemainders() {
        let tenth = Decimal(1) / 10
        let total = WorkspaceBudgetRules.allocatedTotal(
            mainAllocation: tenth, childAllocations: [nil, tenth, tenth]
        )
        #expect(total == Decimal(3) / 10)
        #expect(WorkspaceBudgetRules.freePool(workspaceCap: 1, allocatedTotal: total) == Decimal(7) / 10)
        #expect(WorkspaceBudgetRules.freePool(workspaceCap: tenth, allocatedTotal: total) == .zero)
        #expect(WorkspaceBudgetRules.freePool(workspaceCap: nil, allocatedTotal: total) == .zero)
        #expect(WorkspaceBudgetRules.remaining(cap: tenth, cost: total) == -Decimal(2) / 10)
        #expect(WorkspaceBudgetRules.remaining(cap: nil, cost: total) == nil)
    }

    @Test("Cap changes distinguish disabling, starting, resizing, and rejection")
    func capChanges() {
        #expect(WorkspaceBudgetRules.capChange(to: nil, currentCap: nil, allocatedTotal: 100) == .disable)
        #expect(WorkspaceBudgetRules.capChange(to: 0, currentCap: nil, allocatedTotal: 100) == .start(0))
        #expect(WorkspaceBudgetRules.capChange(to: -1, currentCap: nil, allocatedTotal: 0) == nil)
        #expect(WorkspaceBudgetRules.capChange(to: 99, currentCap: 150, allocatedTotal: 100) == nil)
        #expect(WorkspaceBudgetRules.capChange(to: 100, currentCap: 150, allocatedTotal: 100) == .resize(100))
        #expect(WorkspaceBudgetRules.capChange(to: 150, currentCap: 150, allocatedTotal: 100) == .resize(150))
        #expect(WorkspaceBudgetRules.capChange(to: 200, currentCap: 150, allocatedTotal: 100) == .resize(200))
    }

    @Test("Child editors only change participation in budgeting")
    func childAllocation() {
        #expect(WorkspaceBudgetRules.childAllocation(
            workspaceCap: nil, previousAllocation: 25, requestedAllocation: 50
        ) == nil)
        #expect(WorkspaceBudgetRules.childAllocation(
            workspaceCap: 100, previousAllocation: 25, requestedAllocation: nil
        ) == nil)
        #expect(WorkspaceBudgetRules.childAllocation(
            workspaceCap: 100, previousAllocation: nil, requestedAllocation: nil
        ) == nil)
        #expect(WorkspaceBudgetRules.childAllocation(
            workspaceCap: 100, previousAllocation: nil, requestedAllocation: 50
        ) == .zero)
        #expect(WorkspaceBudgetRules.childAllocation(
            workspaceCap: 100, previousAllocation: 25, requestedAllocation: 50
        ) == 25)
    }

    @Test("Initial funding consumes the pool first and validates all funds before either transfer")
    func initialFunding() {
        #expect(WorkspaceBudgetRules.initialFunding(amount: 30, freePool: 10, mainAllocation: 20)
            == .init(poolContribution: 10, mainContribution: 20))
        #expect(WorkspaceBudgetRules.initialFunding(amount: 30, freePool: 50, mainAllocation: nil)
            == .init(poolContribution: 30, mainContribution: 0))
        #expect(WorkspaceBudgetRules.initialFunding(amount: 30, freePool: 0, mainAllocation: 30)
            == .init(poolContribution: 0, mainContribution: 30))
        #expect(WorkspaceBudgetRules.initialFunding(amount: 31, freePool: 10, mainAllocation: 20) == nil)
        #expect(WorkspaceBudgetRules.initialFunding(amount: 30, freePool: 10, mainAllocation: nil) == nil)
        for amount: Decimal? in [nil, 0, -1] {
            #expect(WorkspaceBudgetRules.initialFunding(amount: amount, freePool: 50, mainAllocation: 50) == nil)
        }
    }

    @Test("Transfers require enabled balances and positive affordable amounts")
    func transferValidation() {
        let amount = Decimal(3) / 10
        #expect(WorkspaceBudgetRules.transfer(amount: amount, sourceBalance: amount, destinationBalance: 0)
            == .init(sourceBalance: 0, destinationBalance: amount))
        #expect(WorkspaceBudgetRules.transfer(amount: 1, sourceBalance: nil, destinationBalance: 0) == nil)
        #expect(WorkspaceBudgetRules.transfer(amount: 1, sourceBalance: 10, destinationBalance: nil) == nil)
        for amount: Decimal in [-1, 0, 11] {
            #expect(WorkspaceBudgetRules.transfer(amount: amount, sourceBalance: 10, destinationBalance: 0) == nil)
        }
    }
}

@MainActor
struct WorkspaceBudgetFacadeParityTests {
    @Test("Initialization derives the main allocation before removing legacy undated linked events")
    func initializationOrder() {
        let idea = PlanningIdea(
            title: "Dinner", note: "", category: .event, submittedBy: "Host", status: .chosen,
            configuration: .event(EventIdeaConfiguration(
                category: .reception, purpose: .eventExperience, proposedDate: nil, location: nil
            ))
        )
        let child = TimelineItem(
            title: "Dinner", category: .reception, scheduledAt: .now,
            participantIDs: [], linkedIdeaID: idea.id, budgetCap: 25
        )
        let workspace = makeWorkspace(timeline: [child], ideas: [idea], currencyCode: " eur\n")

        #expect(workspace.currencyCode == "EUR")
        #expect(workspace.timeline.isEmpty)
        #expect(workspace.mainEventBudgetCap == 75)
        #expect(workspace.freeBudgetPool == 25)
    }

    @Test("Cap resizing preserves allocations and disabling clears every event")
    func capLifecycle() {
        let workspace = makeWorkspace()
        let child = addBudgetedChild(to: workspace)
        #expect(workspace.allocateInitialBudget(25, to: child.id))
        #expect(workspace.updateWorkspaceBudgetCap(120))
        #expect(workspace.mainEventBudgetCap == 75)
        #expect(workspace.budgetCap(for: .subevent(child.id)) == 25)
        #expect(workspace.freeBudgetPool == 20)
        #expect(workspace.updateWorkspaceBudgetCap(100))
        #expect(!workspace.updateWorkspaceBudgetCap(99))
        #expect(workspace.workspaceBudgetCap == 100)
        #expect(workspace.updateWorkspaceBudgetCap(nil))
        #expect(workspace.workspaceBudgetCap == nil)
        #expect(workspace.mainEventBudgetCap == nil)
        #expect(workspace.timeline.allSatisfy { $0.budgetCap == nil })
        #expect(workspace.budgetBalance(for: .freePool) == nil)
        #expect(!workspace.setEventRequiresBudget(true, eventID: child.id))
        #expect(workspace.updateWorkspaceBudgetCap(80))
        #expect(workspace.mainEventBudgetCap == 80)
        #expect(workspace.budgetCap(for: .subevent(child.id)) == nil)
    }

    @Test("Failed initial funding does not consume an available pool contribution")
    func initialFundingIsPrevalidated() {
        let workspace = makeWorkspace()
        let child = addBudgetedChild(to: workspace)
        #expect(workspace.transferBudget(20, from: .event(.main), to: .freePool))
        #expect(!workspace.allocateInitialBudget(101, to: child.id))
        #expect(workspace.freeBudgetPool == 20)
        #expect(workspace.mainEventBudgetCap == 80)
        #expect(workspace.budgetCap(for: .subevent(child.id)) == 0)
        #expect(workspace.allocateInitialBudget(30, to: child.id))
        #expect(workspace.freeBudgetPool == 0)
        #expect(workspace.mainEventBudgetCap == 70)
        #expect(workspace.budgetCap(for: .subevent(child.id)) == 30)
        #expect(workspace.workspaceBudgetCap == 100)
    }

    @Test("Transfers reject identical, missing, idea, and opted-out accounts")
    func invalidAccountsAreNoOps() {
        let workspace = makeWorkspace()
        let child = addBudgetedChild(to: workspace)
        let invalidAccounts: [BudgetAccount] = [
            .event(.main), .event(.idea(UUID())), .event(.subevent(UUID()))
        ]
        for account in invalidAccounts {
            #expect(!workspace.transferBudget(1, from: .event(.main), to: account))
        }
        #expect(!workspace.transferBudget(1, from: .freePool, to: .freePool))
        #expect(workspace.setEventRequiresBudget(false, eventID: child.id))
        #expect(!workspace.transferBudget(1, from: .main, to: .subevent(child.id)))
        #expect(!workspace.allocateInitialBudget(1, to: child.id))
        #expect(!workspace.setEventRequiresBudget(true, eventID: UUID()))
        #expect(workspace.mainEventBudgetCap == 100)
        #expect(workspace.freeBudgetPool == 0)
        #expect(workspace.workspaceBudgetCap == 100)
    }

    @Test("Child edits retain allocation and hierarchy validation while allowing opt-out")
    func childEditing() {
        let workspace = makeWorkspace()
        var child = addBudgetedChild(to: workspace)
        #expect(workspace.budgetCap(for: .subevent(child.id)) == 0)
        #expect(workspace.allocateInitialBudget(25, to: child.id))
        child.budgetCap = 90
        workspace.updateTimelineItem(child)
        #expect(workspace.budgetCap(for: .subevent(child.id)) == 25)
        child.parentEventID = UUID()
        child.budgetCap = nil
        workspace.updateTimelineItem(child)
        #expect(workspace.budgetCap(for: .subevent(child.id)) == 25)
        child.parentEventID = workspace.mainEventID
        workspace.updateTimelineItem(child)
        #expect(workspace.budgetCap(for: .subevent(child.id)) == nil)
        #expect(workspace.freeBudgetPool == 25)
        child.budgetCap = 50
        workspace.updateTimelineItem(child)
        #expect(workspace.budgetCap(for: .subevent(child.id)) == 0)
        #expect(workspace.mainEventBudgetCap == 75)
    }

    @Test("Scheduled idea funding and expense reconciliation retain their distinct amounts and identity")
    func linkedEventAndExpenseCoordination() throws {
        let workspace = makeWorkspace()
        let idea = PlanningIdea(
            title: "Dinner", note: "", category: .event, submittedBy: "Host",
            estimatedCost: 40, status: .chosen,
            configuration: .event(EventIdeaConfiguration(
                category: .reception, purpose: .eventExperience,
                proposedBudget: 30, proposedDate: .now, location: nil
            ))
        )
        workspace.addIdea(idea)
        let child = try #require(workspace.timeline.first { $0.linkedIdeaID == idea.id })
        let expense = try #require(workspace.eventExpenses.first)
        #expect(child.budgetCap == 30)
        #expect(expense.eventID == child.id)
        #expect(expense.amount == 40)
        #expect(expense.status == .committed)
        #expect(workspace.budgetRemaining(for: .subevent(child.id)) == -10)
        var edited = idea
        edited.estimatedCost = 45
        workspace.updateIdea(edited)
        #expect(workspace.eventExpenses.count == 1)
        #expect(workspace.eventExpenses.first?.id == expense.id)
        #expect(workspace.eventExpenses.first?.amount == 45)
        #expect(workspace.budgetCap(for: .subevent(child.id)) == 30)
        #expect(workspace.mainEventBudgetCap == 70)
        #expect(workspace.workspaceBudgetRemaining == 55)
    }

    private func makeWorkspace(
        timeline: [TimelineItem] = [],
        ideas: [PlanningIdea] = [],
        currencyCode: String = "USD"
    ) -> PlanningWorkspace {
        PlanningWorkspace(
            title: "Budget rules", mainEventStartsAt: .now, venueName: "", location: "",
            planningMode: .openToIdeas, members: [], ideas: ideas, timeline: timeline,
            workspaceBudgetCap: 100, currencyCode: currencyCode, registry: []
        )
    }

    private func addBudgetedChild(to workspace: PlanningWorkspace) -> TimelineItem {
        let child = TimelineItem(
            title: "Dinner", category: .reception, scheduledAt: .now,
            participantIDs: [], parentEventID: workspace.mainEventID, budgetCap: 90
        )
        workspace.addTimelineItem(child)
        return child
    }
}
