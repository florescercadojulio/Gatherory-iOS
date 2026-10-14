import Foundation
import Testing
@testable import Gatherory

struct IdeaBudgetTests {
    @Test("A cost-bearing idea creates one estimated ledger entry")
    func addingIdeaUpdatesBudget() throws {
        let workspace = makeWorkspace()
        let idea = makeIdea(cost: 50)

        workspace.addIdea(idea)

        let expense = try #require(workspace.eventExpenses.first)
        #expect(workspace.eventExpenses.count == 1)
        #expect(expense.sourceIdeaID == idea.id)
        #expect(expense.amount == 50)
        #expect(expense.status == .estimated)
        #expect(workspace.workspaceCostTotal == 50)
        #expect(workspace.workspaceBudgetRemaining == 50)
    }

    @Test("Approving and editing an idea updates its existing ledger entry")
    func approvingIdeaCommitsWithoutDuplicatingCost() throws {
        let workspace = makeWorkspace()
        let idea = makeIdea(cost: 50)
        workspace.addIdea(idea)
        let originalExpenseID = try #require(workspace.eventExpenses.first?.id)

        workspace.updateIdea(idea, status: .chosen)
        var editedIdea = try #require(workspace.ideas.first { $0.id == idea.id })
        editedIdea.estimatedCost = 65
        workspace.updateIdea(editedIdea)

        let expense = try #require(workspace.eventExpenses.first)
        #expect(workspace.eventExpenses.count == 1)
        #expect(expense.id == originalExpenseID)
        #expect(expense.amount == 65)
        #expect(expense.status == .committed)
        #expect(workspace.workspaceBudgetRemaining == 35)
    }

    @Test("Archiving an idea releases its estimated budget")
    func archivingIdeaReleasesBudget() {
        let workspace = makeWorkspace()
        let idea = makeIdea(cost: 50)
        workspace.addIdea(idea)

        workspace.updateIdea(idea, status: .archived)

        #expect(workspace.eventExpenses.isEmpty)
        #expect(workspace.workspaceCostTotal == .zero)
        #expect(workspace.workspaceBudgetRemaining == 100)
    }

    @Test("Personal responses and undo do not alter the shared budget")
    func undoRestoresBudgetImpact() {
        let workspace = makeWorkspace()
        let idea = makeIdea(cost: 50)
        workspace.addIdea(idea)

        workspace.decide(.pass, on: idea)
        #expect(workspace.workspaceCostTotal == 50)

        workspace.undoLastDecision()
        #expect(workspace.workspaceCostTotal == 50)
    }

    @Test("A new event receives its requested allocation from the main event")
    func newEventReceivesInitialBudget() throws {
        let workspace = makeWorkspace()
        let event = TimelineItem(
            title: "Venue Visit",
            category: .venue,
            scheduledAt: .now,
            participantIDs: workspace.mainEventParticipantIDs,
            parentEventID: workspace.mainEventID,
            budgetCap: .zero
        )

        workspace.addTimelineItem(event)
        let allocated = workspace.allocateInitialBudget(25, to: event.id)

        #expect(allocated)
        #expect(workspace.budgetCap(for: .subevent(event.id)) == 25)
        #expect(workspace.budgetCap(for: .main) == 75)
        #expect(workspace.allocatedBudgetTotal == 100)
    }

    @Test("Approving an event idea preserves its budget and attire")
    func approvedEventIdeaCarriesPlanningDetails() throws {
        let workspace = makeWorkspace()
        let idea = PlanningIdea(
            title: "Reception",
            note: "Dinner and dancing",
            category: .event,
            submittedBy: "You",
            status: .chosen,
            configuration: .event(
                EventIdeaConfiguration(
                    category: .reception,
                    purpose: .eventExperience,
                    proposedBudget: 30,
                    proposedDate: .now,
                    location: nil,
                    attireStyle: .cocktail,
                    attireGuidance: "Blue encouraged"
                )
            )
        )

        workspace.addIdea(idea)
        let event = try #require(workspace.timeline.first { $0.linkedIdeaID == idea.id })

        #expect(event.budgetCap == 30)
        #expect(event.dressCode == "Cocktail · Blue encouraged")
        #expect(workspace.budgetCap(for: .main) == 70)
    }

    private func makeWorkspace() -> PlanningWorkspace {
        PlanningWorkspace.newWorkspace(
            title: "Budget test",
            startsAt: .now,
            eventLocation: nil,
            imageData: nil,
            budgetCap: 100
        )
    }

    private func makeIdea(cost: Decimal) -> PlanningIdea {
        PlanningIdea(
            title: "Dinner",
            note: "",
            category: .food,
            submittedBy: "You",
            estimatedCost: cost
        )
    }
}
