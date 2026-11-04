import Foundation
import Testing
@testable import Gatherory

@MainActor
struct CoreGatheringSimulationTests {
    @Test("Host and collaborator plan, decide, approve, schedule, budget, and coordinate a gathering")
    func coreGatheringLifecycle() throws {
        let host = WorkspaceMember(
            userID: "host", name: "Host", participantRole: .host, initials: "H",
            planningPermission: .manage
        )
        let collaborator = WorkspaceMember(
            userID: "collaborator", name: "Collaborator", participantRole: .collaborator,
            initials: "C", planningPermission: .contribute
        )
        let viewer = WorkspaceMember(
            userID: "viewer", name: "Viewer", participantRole: .collaborator,
            initials: "V", planningPermission: .viewOnly
        )
        let guest = WorkspaceMember(
            userID: "guest", name: "Guest", participantRole: .guest, initials: "G"
        )
        let workspace = PlanningWorkspace(
            title: "Friends", mainEventStartsAt: .now.addingTimeInterval(86_400),
            venueName: "", location: "", planningMode: .openToIdeas,
            members: [host, collaborator, viewer, guest], ideas: [], timeline: [],
            workspaceBudgetCap: 250, registry: []
        )

        // Create/edit the root event and add a direct child event.
        workspace.configureViewer(account("host"))
        let mainStart = Date.now.addingTimeInterval(172_800)
        workspace.updateMainEvent(
            title: "Friendsgiving", status: .ongoing, startsAt: mainStart, endsAt: nil,
            isAllDay: true, timeZoneIdentifier: "America/Detroit", eventLocation: nil,
            imageData: nil, dressCode: "Cozy", message: "Bring a dish."
        )
        #expect(workspace.title == "Friendsgiving")
        #expect(workspace.mainEventStatus == .ongoing)
        let reception = TimelineItem(
            title: "Dinner", category: .reception,
            scheduledAt: mainStart.addingTimeInterval(3_600), location: "Dining room",
            participantIDs: [], parentEventID: workspace.mainEventID
        )
        workspace.addTimelineItem(reception)
        let child = try #require(workspace.timeline.first { $0.id == reception.id })
        #expect(child.parentEventID == workspace.mainEventID)
        #expect(Set(child.participantIDs) == Set(workspace.mainEventParticipantIDs))
        var editedChild = child
        editedChild.title = "Thanksgiving dinner"
        workspace.updateTimelineItem(editedChild)
        #expect(workspace.timeline.first { $0.id == child.id }?.title == "Thanksgiving dinner")
        workspace.configureViewer(account("collaborator"))
        workspace.updateMainEvent(
            title: "Collaborator edit", status: .ongoing, startsAt: mainStart, endsAt: nil,
            isAllDay: true, timeZoneIdentifier: "America/Detroit", eventLocation: nil,
            imageData: nil, dressCode: "Cozy", message: "Bring a dish."
        )
        #expect(workspace.title == "Collaborator edit")

        // A contributor's decision stays personal; approval turns a non-event
        // proposal into a committed expense without publishing a subevent.
        let meal = PlanningIdea(
            eventID: child.id, title: "Catered meal", note: "Vegetarian option",
            category: .food, submittedBy: "Collaborator", estimatedCost: 45
        )
        workspace.configureViewer(account("host"))
        workspace.addIdea(meal)
        let storedMeal = try #require(workspace.ideas.first { $0.id == meal.id })
        workspace.configureViewer(account("host"))
        workspace.decide(.love, on: storedMeal)
        #expect(workspace.response(on: storedMeal) == .love)
        workspace.configureViewer(account("collaborator"))
        workspace.decide(.maybe, on: storedMeal)
        #expect(workspace.response(on: storedMeal) == .maybe)
        #expect(workspace.teamResponseSummary(for: storedMeal) == .init(love: 1, maybe: 1))

        // The host enables a cap and funds the child. The contributor then
        // confirms the approval request against that exact child event.
        workspace.configureViewer(account("host"))
        #expect(workspace.updateWorkspaceBudgetCap(250))
        #expect(workspace.setEventRequiresBudget(true, eventID: child.id))
        #expect(workspace.allocateInitialBudget(80, to: child.id))
        #expect(workspace.budgetCap(for: .subevent(child.id)) == 80)
        workspace.configureViewer(account("collaborator"))
        let mealApproval = try #require(workspace.makeIdeaApprovalRequest(for: storedMeal))
        #expect(workspace.confirmIdeaApproval(mealApproval))
        #expect(workspace.ideas.first { $0.id == meal.id }?.status == .chosen)
        #expect(workspace.timeline.count == 1, "Approving an ordinary idea must not create a child event.")
        let expense = try #require(workspace.eventExpenses.first { $0.sourceIdeaID == meal.id })
        #expect(expense.eventID == child.id)
        #expect(expense.amount == 45)
        #expect(expense.status == .committed)

        // Event ideas use the host-only schedule confirmation flow.
        let activityDate = mainStart.addingTimeInterval(7_200)
        let activity = PlanningIdea(
            title: "Board games", note: "After dinner", category: .event,
            submittedBy: "Collaborator",
            configuration: .event(EventIdeaConfiguration(
                category: .other, purpose: .eventExperience,
                proposedDate: activityDate, location: EventLocation(address: "Living room")
            ))
        )
        workspace.addIdea(activity)
        let storedActivity = try #require(workspace.ideas.first { $0.id == activity.id })
        workspace.decide(.love, on: storedActivity)
        #expect(workspace.teamResponseSummary(for: storedActivity).love == 1)
        #expect(workspace.makeScheduleRequest(for: storedActivity) == nil)
        workspace.configureViewer(account("host"))
        let scheduleRequest = try #require(workspace.makeScheduleRequest(for: storedActivity))
        let scheduleConfiguration = try #require(storedActivity.eventConfiguration)
        let scheduledID = try #require(workspace.confirmScheduleEventIdea(
            scheduleRequest, configuration: scheduleConfiguration
        ))
        let scheduled = try #require(workspace.timeline.first { $0.id == scheduledID })
        #expect(scheduled.linkedIdeaID == activity.id)
        #expect(scheduled.parentEventID == workspace.mainEventID)
        #expect(scheduled.scheduledAt == activityDate)
        #expect(workspace.ideas.first { $0.id == activity.id }?.status == .chosen)

        // Contributors can coordinate tasks and notes on an event they can
        // plan, while guests and view-only members cannot make planning writes.
        workspace.configureViewer(account("collaborator"))
        let todo = try #require(workspace.addTodo(title: "  Set the table  ", to: .subevent(child.id)))
        #expect(todo.eventID == child.id)
        #expect(todo.title == "Set the table")
        #expect(workspace.sendNote("  I'll bring dessert.  ", to: .subevent(child.id))?.body == "I'll bring dessert.")
        workspace.configureViewer(account("viewer"))
        #expect(workspace.addTodo(title: "Change table", to: .subevent(child.id)) == nil)
        #expect(workspace.sendNote("I will help.", to: .subevent(child.id)) == nil)
        #expect(workspace.updateWorkspaceBudgetCap(300) == false)
        #expect(workspace.makeScheduleRequest(for: storedActivity) == nil)
        workspace.configureViewer(account("guest"))
        #expect(workspace.addTodo(title: "Guest task", to: .subevent(child.id)) == nil)
        #expect(workspace.sendNote("Guest planning note", to: .subevent(child.id)) == nil)
        #expect(!EventManagementAccess.canOpen(reference: .main, in: workspace))
    }

    private func account(_ id: String) -> UserAccount {
        UserAccount(
            id: id, email: "\(id)@example.test", displayName: id, role: .planner,
            authenticationProvider: .password, createdAt: .now
        )
    }
}
