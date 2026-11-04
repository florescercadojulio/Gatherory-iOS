import Foundation
import Testing
@testable import Gatherory

/// Domain-command simulations for team budgeting. These tests deliberately
/// exercise model commands directly; view visibility is covered elsewhere.
@MainActor
struct TeamBudgetAuditTests {
    @Test("A contributor cannot resize the shared cap through the root editor command path")
    func contributorRootCapPolicyMismatch() throws {
        let contributor = WorkspaceMember(
            userID: "actor", name: "Contributor", participantRole: .collaborator,
            initials: "C", planningPermission: .contribute
        )
        let workspace = makeWorkspace(cap: 100, actor: contributor)
        #expect(workspace.canManageMainEvent)
        #expect(!workspace.canManageBudgets)
        #expect(!BudgetAllocationPermissionPolicy.canEditAllocation(in: workspace, for: .main))
        let accepted = workspace.updateWorkspaceBudgetCap(150)
        #expect(!accepted && workspace.workspaceBudgetCap == 100)

        let requestedChild = TimelineItem(
            title: "Contributor child", category: .other, scheduledAt: .now,
            participantIDs: [contributor.id], parentEventID: workspace.mainEventID, budgetCap: 40
        )
        workspace.addTimelineItem(requestedChild)
        let storedChild = try #require(workspace.timeline.first)
        #expect(storedChild.budgetCap == nil)
        var editedChild = storedChild
        editedChild.budgetCap = 60
        workspace.updateTimelineItem(editedChild)
        #expect(workspace.timeline.first?.budgetCap == nil)
        #expect(workspace.allocatedBudgetTotal == 100)
    }

    @Test("Unapproved alternatives already contribute to the displayed cost forecast")
    func alternativeEstimatesAreNotPaidOrCommitted() {
        let workspace = makeWorkspace(cap: 100)
        for (title, cost) in [("Catering option A", Decimal(60)), ("Catering option B", Decimal(70))] {
            workspace.addIdea(PlanningIdea(
                title: title, note: "", category: .food, submittedBy: "Planner",
                estimatedCost: cost
            ))
        }
        #expect(workspace.costTotal(status: .paid) == 0)
        #expect(workspace.costTotal(status: .committed) == 0)
        #expect(workspace.costTotal(status: .estimated) == 130)
        #expect(workspace.workspaceBudgetRemaining == -30)
    }

    @Test("Host, manager, contributor, view-only member, and guest cross budget and schedule boundaries")
    func roleBoundaries() throws {
        for (role, permission, mayManage, mayContribute) in [
            (WorkspaceRole.host, PlanningPermission.manage, true, true),
            (.collaborator, .manage, true, true),
            (.collaborator, .contribute, false, true),
            (.collaborator, .viewOnly, false, false),
            (.guest, .viewOnly, false, false)
        ] {
            let actor = WorkspaceMember(
                userID: "actor", name: "Actor", participantRole: role,
                initials: "A", planningPermission: permission
            )
            let proposal = eventIdea()
            let workspace = makeWorkspace(cap: 100, actor: actor, ideas: [proposal])
            let stored = try #require(workspace.ideas.first)

            #expect(workspace.canManageEventIdeaScheduling(stored) == mayManage)
            #expect(workspace.canScheduleEventIdea(stored) == mayManage)
            #expect(workspace.canRespond(to: stored) == mayContribute)

            let child = TimelineItem(
                title: "Side event", category: .other, scheduledAt: .now,
                participantIDs: [actor.id], parentEventID: workspace.mainEventID,
                budgetCap: 0
            )
            workspace.addTimelineItem(child)
            let actualChild = try #require(workspace.timeline.first)
            #expect(BudgetAllocationPermissionPolicy.canEditAllocation(in: workspace, for: .main) == mayManage)
            #expect(BudgetAllocationPermissionPolicy.canEditAllocation(
                in: workspace, for: .subevent(actualChild.id)
            ) == mayManage)
        }
    }

    @Test("Global cap allocates from pool then main, blocks overspend, and keeps zero allocations explicit")
    func globalAndChildAllocation() throws {
        let workspace = makeWorkspace(cap: 100)
        let child = TimelineItem(
            title: "Dinner", category: .reception, scheduledAt: .now,
            participantIDs: [], parentEventID: workspace.mainEventID, budgetCap: 0
        )
        workspace.addTimelineItem(child)
        let storedChild = try #require(workspace.timeline.first)
        #expect(workspace.mainEventBudgetCap == 100)
        #expect(workspace.freeBudgetPool == 0)
        #expect(!workspace.allocateInitialBudget(0, to: storedChild.id))
        #expect(workspace.allocateInitialBudget(80, to: storedChild.id))
        #expect(workspace.budgetCap(for: .main) == 20)
        #expect(workspace.budgetCap(for: .subevent(storedChild.id)) == 80)
        #expect(!workspace.allocateInitialBudget(21, to: storedChild.id))
        #expect(!workspace.transferBudget(-1, from: .main, to: .subevent(storedChild.id)))
        #expect(workspace.allocatedBudgetTotal == 100)
        #expect(workspace.updateWorkspaceBudgetCap(0) == false)
        #expect(workspace.updateWorkspaceBudgetCap(nil))
        #expect(workspace.mainEventBudgetCap == nil)
        #expect(workspace.timeline.first?.budgetCap == nil)
    }

    @Test("Managers can opt a child into budgeting while direct allocation edits do not resize it")
    func managerChildBudgetOptIn() throws {
        let workspace = makeWorkspace(cap: 100)
        #expect(!workspace.canManageBudgets(for: .idea(UUID())))
        #expect(!workspace.canManageBudgets(for: .subevent(UUID())))
        let child = TimelineItem(
            title: "New child", category: .other, scheduledAt: .now,
            participantIDs: [], parentEventID: workspace.mainEventID, budgetCap: nil
        )
        workspace.addTimelineItem(child)
        let stored = try #require(workspace.timeline.first)
        #expect(stored.budgetCap == nil)
        var optIn = stored
        optIn.budgetCap = 45
        workspace.updateTimelineItem(optIn)
        #expect(workspace.timeline.first?.budgetCap == 0)
        var attemptedResize = try #require(workspace.timeline.first)
        attemptedResize.budgetCap = 90
        workspace.updateTimelineItem(attemptedResize)
        #expect(workspace.timeline.first?.budgetCap == 0)
        #expect(workspace.allocatedBudgetTotal == 100)
        var archivedChild = try #require(workspace.timeline.first)
        archivedChild.status = .archived
        workspace.updateTimelineItem(archivedChild)
        #expect(!workspace.canManageBudgets(for: .subevent(archivedChild.id)))
    }

    @Test("Idea estimate is one ledger row, commitment follows approval, decline releases, and unscheduling releases event allocation")
    func ideaLifecycleAndNoDoubleCounting() throws {
        let proposal = eventIdea(cost: 30, date: nil, budget: 25)
        let workspace = makeWorkspace(cap: 100, ideas: [proposal])
        #expect(workspace.eventExpenses.count == 1)
        #expect(workspace.workspaceCostTotal == 30)
        #expect(workspace.eventExpenses[0].status == .estimated)

        let stored = try #require(workspace.ideas.first)
        let request = try #require(workspace.makeScheduleRequest(for: stored))
        var config = try #require(stored.eventConfiguration)
        config.proposedDate = .now.addingTimeInterval(86_400)
        let childID = try #require(workspace.confirmScheduleEventIdea(request, configuration: config))
        #expect(workspace.eventExpenses.count == 1)
        #expect(workspace.eventExpenses[0].eventID == childID)
        #expect(workspace.eventExpenses[0].status == .committed)
        #expect(workspace.budgetCap(for: .subevent(childID)) == 25)
        #expect(workspace.workspaceBudgetRemaining == 70)

        workspace.updateIdea(stored, status: .passed)
        #expect(workspace.eventExpenses.isEmpty)
        #expect(workspace.workspaceCostTotal == 0)
        #expect(workspace.timeline.isEmpty)
    }

    @Test("Paid bookkeeping survives linked idea note edits and archival")
    func paidExpenseSurvivesIdeaEdit() throws {
        let idea = PlanningIdea(
            title: "Catering", note: "", category: .food, submittedBy: "Host",
            estimatedCost: 40, status: .chosen
        )
        let workspace = makeWorkspace(ideas: [idea])
        var expense = try #require(workspace.eventExpenses.first)
        expense.status = .paid
        workspace.replaceExpenses([expense], forEventID: expense.eventID)
        var edited = try #require(workspace.ideas.first)
        edited.note = "Updated catering details"
        workspace.updateIdea(edited)

        let reconciled = try #require(workspace.eventExpenses.first)
        #expect(reconciled.status == .paid)
        #expect(reconciled.amount == 40)
        #expect(workspace.eventExpenses.count == 1)

        edited = try #require(workspace.ideas.first)
        edited.estimatedCost = 75
        workspace.updateIdea(edited)
        #expect(workspace.eventExpenses.first?.amount == 40)
        #expect(workspace.costTotal(status: .committed) == 0)

        var paidAgain = reconciled
        paidAgain.status = .paid
        workspace.replaceExpenses([paidAgain], forEventID: paidAgain.eventID)
        let currentIdea = try #require(workspace.ideas.first)
        workspace.updateIdea(currentIdea, status: .archived)
        #expect(workspace.costTotal(status: .paid) == 40)
        #expect(workspace.eventExpenses.count == 1)
    }

    @Test("Disabling the workspace cap requires authority for every allocated child")
    func capDisableRequiresChildBudgetAuthority() throws {
        let workspace = makeWorkspace(cap: 100)
        let child = TimelineItem(
            title: "Archived child", category: .other, scheduledAt: .now,
            participantIDs: [], parentEventID: workspace.mainEventID, budgetCap: 0
        )
        workspace.addTimelineItem(child)
        let childID = try #require(workspace.timeline.first?.id)
        #expect(workspace.transferBudget(20, from: .main, to: .subevent(childID)))
        var archivedChild = try #require(workspace.timeline.first)
        archivedChild.status = .archived
        workspace.updateTimelineItem(archivedChild)

        #expect(!workspace.canManageBudgets(for: .subevent(childID)))
        #expect(!workspace.updateWorkspaceBudgetCap(nil))
        #expect(workspace.workspaceBudgetCap == 100)
        #expect(workspace.budgetCap(for: .subevent(childID)) == 20)
    }

    @Test("Hosts-only schedule rejects a funded manager excluded from the child before mutation")
    func hostsOnlyScheduleRejectsExcludedBudgetManager() throws {
        let manager = WorkspaceMember(
            userID: "manager", name: "Manager", participantRole: .collaborator,
            initials: "M", planningPermission: .manage
        )
        let host = WorkspaceMember(
            userID: "host", name: "Host", participantRole: .host,
            initials: "H", planningPermission: .manage
        )
        let idea = eventIdea(cost: 40, date: .now.addingTimeInterval(86_400), budget: 25)
        var hostOnlyConfiguration = try #require(idea.eventConfiguration)
        hostOnlyConfiguration.audience = .hostsOnly
        var hostOnlyIdea = idea
        hostOnlyIdea.configuration = .event(hostOnlyConfiguration)
        let mainID = UUID()
        let workspace = PlanningWorkspace(
            mainEventID: mainID,
            title: "Hosts-only funding",
            mainEventStartsAt: .now,
            venueName: "",
            location: "",
            planningMode: .openToIdeas,
            members: [manager, host],
            eventParticipations: [
                EventParticipation(eventID: mainID, memberID: manager.id, role: .collaborator,
                                  planningPermission: .manage, attendance: .invited, invitationStatus: .active),
                EventParticipation(eventID: mainID, memberID: host.id, role: .host,
                                  planningPermission: .manage, attendance: .invited, invitationStatus: .active)
            ],
            ideas: [hostOnlyIdea],
            timeline: [],
            workspaceBudgetCap: 100,
            registry: []
        )
        workspace.configureViewer(UserAccount(
            id: "manager", email: "manager@example.test", displayName: "Manager",
            role: .planner, authenticationProvider: .password, createdAt: .now
        ))
        let storedIdea = try #require(workspace.ideas.first)
        let request = try #require(workspace.makeScheduleRequest(for: storedIdea))
        let configuration = try #require(storedIdea.eventConfiguration)

        #expect(workspace.confirmScheduleEventIdea(request, configuration: configuration) == nil)
        #expect(workspace.ideas == [storedIdea])
        #expect(workspace.timeline.isEmpty)
        #expect(workspace.workspaceBudgetCap == 100)
        #expect(workspace.mainEventBudgetCap == 100)
        #expect(workspace.eventExpenses.isEmpty)
    }

    @Test("Unscheduling a linked child preserves its paid expense and source identity")
    func paidExpenseSurvivesUnscheduling() throws {
        var idea = eventIdea(cost: 40, date: .now.addingTimeInterval(86_400), budget: 20)
        idea.status = .chosen
        let workspace = makeWorkspace(cap: 100, ideas: [idea])
        var expense = try #require(workspace.eventExpenses.first)
        let childID = try #require(workspace.timeline.first?.id)
        expense.eventID = childID
        expense.status = .paid
        workspace.replaceExpenses([expense], forEventID: childID)
        #expect(workspace.costTotal(for: .subevent(childID)) == 40)
        let storedIdea = try #require(workspace.ideas.first)
        workspace.updateIdea(storedIdea, status: .passed)
        #expect(workspace.timeline.isEmpty)
        #expect(workspace.costTotal(status: .paid) == 40)
        #expect(workspace.eventExpenses.first?.eventID == workspace.mainEventID)
        #expect(workspace.eventExpenses.first?.sourceIdeaID == idea.id)
    }

    @Test("Deleting a child detaches a paid child-local idea expense before rehoming")
    func paidChildLocalIdeaExpenseRehomesWithoutDanglingSource() throws {
        let workspace = makeWorkspace(cap: 100)
        let child = TimelineItem(
            title: "Dinner", category: .other, scheduledAt: .now,
            participantIDs: [], parentEventID: workspace.mainEventID, budgetCap: nil
        )
        workspace.addTimelineItem(child)
        let storedChild = try #require(workspace.timeline.first)
        let idea = PlanningIdea(
            eventID: storedChild.id, title: "Child catering", note: "", category: .food, submittedBy: "Actor",
            estimatedCost: 35
        )
        workspace.addIdea(idea)
        var expense = try #require(workspace.eventExpenses.first)
        #expect(expense.eventID == storedChild.id)
        #expect(expense.sourceIdeaID == idea.id)
        expense.status = .paid
        workspace.replaceExpenses([expense], forEventID: storedChild.id)

        workspace.deleteTimelineItem(storedChild)

        let retained = try #require(workspace.eventExpenses.first)
        #expect(retained.status == .paid)
        #expect(retained.amount == 35)
        #expect(retained.eventID == workspace.mainEventID)
        #expect(retained.sourceIdeaID == nil)
        #expect(workspace.ideas.isEmpty)
    }

    @Test("Scheduling rejects an event whose requested budget exceeds the workspace cap")
    func oversizedScheduledEventBudget() throws {
        let date = Date.now.addingTimeInterval(86_400)
        let proposal = eventIdea(date: date, budget: 150)
        let workspace = makeWorkspace(cap: 100, ideas: [proposal])
        let stored = try #require(workspace.ideas.first)

        let request = try #require(workspace.makeScheduleRequest(for: stored))
        let configuration = try #require(stored.eventConfiguration)
        let scheduledID = workspace.confirmScheduleEventIdea(request, configuration: configuration)
        let scheduled = workspace.timeline.first { $0.linkedIdeaID == proposal.id }

        #expect(scheduledID == nil)
        #expect(scheduled == nil)
        #expect(workspace.ideas.first == stored)
        #expect(workspace.allocatedBudgetTotal <= workspace.workspaceBudgetCap!)
        #expect(workspace.workspaceBudgetCap == 100)
    }

    @Test("Expense rows have one owning event; replacement normalizes ownership and cross-event cost splitting is unsupported")
    func expenseOwnershipAndNegativeValues() throws {
        let workspace = makeWorkspace(cap: 100)
        let mainID = workspace.mainEventID
        let childID = UUID()
        let expense = EventExpense(eventID: childID, title: "Shared venue", amount: 20)
        workspace.replaceExpenses([expense], forEventID: mainID)
        #expect(workspace.eventExpenses.count == 1)
        #expect(workspace.eventExpenses[0].eventID == mainID)
        #expect(workspace.costTotal(for: .main) == 20)
        #expect(workspace.costTotal(for: .subevent(childID)) == 0)

        let negative = EventExpense(eventID: mainID, title: "Credit", amount: -10)
        workspace.replaceExpenses([negative], forEventID: mainID)
        #expect(workspace.workspaceCostTotal == 20)
        #expect(workspace.eventExpenses.count == 1)
        #expect(workspace.eventExpenses.first?.title == "Shared venue")
    }

    @Test("Legacy raw archive merge does not guarantee budget conservation without a command")
    func invariantNotGuaranteedWithoutCommand() throws {
        let workspace = makeWorkspace(cap: 1_000)
        let firstManager = try #require(workspace.members.first)
        let secondManager = WorkspaceMember(
            userID: "manager-b", name: "Second manager", participantRole: .collaborator,
            initials: "B", planningPermission: .manage
        )
        workspace.members.append(secondManager)
        workspace.mainEventParticipantIDs.append(secondManager.id)
        #expect(workspace.transferBudget(200, from: .event(.main), to: .freePool))
        let firstChild = TimelineItem(
            title: "First", category: .other, scheduledAt: .now,
            participantIDs: [firstManager.id, secondManager.id], parentEventID: workspace.mainEventID, budgetCap: 0
        )
        let secondChild = TimelineItem(
            title: "Second", category: .other, scheduledAt: .now,
            participantIDs: [firstManager.id, secondManager.id], parentEventID: workspace.mainEventID, budgetCap: 0
        )
        workspace.addTimelineItem(firstChild)
        workspace.addTimelineItem(secondChild)
        let baseline = WorkspaceArchiveV1(workspace: workspace)
        let offlineA = baseline.makeWorkspace()
        let offlineB = baseline.makeWorkspace()
        offlineA.configureViewer(UserAccount(
            id: "actor", email: "actor@example.test", displayName: "First manager",
            role: .planner, authenticationProvider: .password, createdAt: .now
        ))
        offlineB.configureViewer(UserAccount(
            id: "manager-b", email: "manager-b@example.test", displayName: "Second manager",
            role: .planner, authenticationProvider: .password, createdAt: .now
        ))
        let childA = try #require(offlineA.timeline.first { $0.id == firstChild.id })
        let childB = try #require(offlineB.timeline.first { $0.id == secondChild.id })
        #expect(BudgetAllocationPermissionPolicy.canEditAllocation(in: offlineA, for: .subevent(childA.id)))
        #expect(BudgetAllocationPermissionPolicy.canEditAllocation(in: offlineB, for: .subevent(childB.id)))
        #expect(offlineA.transferBudget(150, from: .freePool, to: .event(.subevent(childA.id))))
        #expect(offlineB.transferBudget(150, from: .freePool, to: .event(.subevent(childB.id))))

        let codec = WorkspaceArchiveCodec()
        var merged = baseline
        let updatedA = try #require(offlineA.timeline.first { $0.id == childA.id })
        let updatedB = try #require(offlineB.timeline.first { $0.id == childB.id })
        try merged.applyEntity(
            type: .event, id: updatedA.id, operation: .update,
            payload: codec.encode(updatedA), codec: codec
        )
        try merged.applyEntity(
            type: .event, id: updatedB.id, operation: .update,
            payload: codec.encode(updatedB), codec: codec
        )
        let mergedWorkspace = merged.makeWorkspace()

        // This characterizes the legacy raw entity merge path only. Production
        // command acceptance is covered by the budget sync mutation tests.
        #expect(mergedWorkspace.allocatedBudgetTotal == 1_100)
    }

    @Test("Idea account transfer is rejected before changing an event balance")
    func invalidDestinationTransferIsAtomic() {
        let workspace = makeWorkspace(cap: 100)
        let accepted = workspace.transferBudget(10, from: .main, to: .idea(UUID()))

        #expect(!accepted)
        #expect(workspace.budgetCap(for: .main) == 100)
    }

    private func makeWorkspace(
        cap: Decimal? = nil,
        actor: WorkspaceMember? = nil,
        ideas: [PlanningIdea] = []
    ) -> PlanningWorkspace {
        let member = actor ?? WorkspaceMember(
            userID: "actor", name: "Actor", participantRole: .host,
            initials: "A", planningPermission: .manage
        )
        let mainID = UUID()
        let workspace = PlanningWorkspace(
            mainEventID: mainID, title: "Team budget audit", mainEventStartsAt: .now,
            venueName: "", location: "", planningMode: .openToIdeas,
            members: [member],
            eventParticipations: [EventParticipation(
                eventID: mainID, memberID: member.id,
                role: member.participantRole, planningPermission: member.planningPermission,
                attendance: .invited, invitationStatus: .active
            )],
            ideas: [], timeline: [], workspaceBudgetCap: cap, registry: []
        )
        for idea in ideas { workspace.addIdea(idea) }
        workspace.configureViewer(UserAccount(
            id: "actor", email: "actor@example.test", displayName: "Actor",
            role: .planner, authenticationProvider: .password, createdAt: .now
        ))
        return workspace
    }

    private func eventIdea(cost: Decimal? = nil, date: Date? = nil, budget: Decimal? = nil) -> PlanningIdea {
        PlanningIdea(
            title: "Reception", note: "Dinner", category: .event,
            submittedBy: "Actor", estimatedCost: cost,
            configuration: .event(EventIdeaConfiguration(
                category: .reception, purpose: .eventExperience,
                proposedBudget: budget, proposedDate: date, location: nil
            ))
        )
    }
}
