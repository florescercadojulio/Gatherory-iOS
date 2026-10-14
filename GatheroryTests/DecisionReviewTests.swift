import SwiftData
import Testing
@testable import Gatherory
import Foundation

@MainActor
struct DecisionReviewTests {
    private func account(_ id: String) -> UserAccount {
        UserAccount(id: id, email: "\(id)@example.test", displayName: id, role: .planner,
                    authenticationProvider: .password, createdAt: .now)
    }

    private func workspace() -> PlanningWorkspace {
        let workspace = PlanningWorkspace.newWorkspace(title: "Review", startsAt: .now.addingTimeInterval(86400),
            eventLocation: nil, imageData: nil, owner: account("host"))
        workspace.configureViewer(account("host"))
        return workspace
    }

    @Test("Review queues use the current account's response, not shared status or a teammate's response",
          arguments: [DecisionChoice.maybe, .pass])
    func personalQueue(choice: DecisionChoice) throws {
        let filter = DecisionQueueFilter(restoring: choice)
        let workspace = workspace()
        let personal = PlanningIdea(title: "My maybe", note: "", category: .flowers, submittedBy: "Host")
        let shared = PlanningIdea(title: "Shared status", note: "", category: .decor, submittedBy: "Host",
                                  status: choice == .maybe ? .maybe : .passed)
        let teammate = PlanningIdea(title: "Their maybe", note: "", category: .food, submittedBy: "Host")
        for idea in [personal, shared, teammate] { workspace.addIdea(idea) }
        workspace.decide(choice, on: personal)
        workspace.ideaResponses.append(IdeaResponse(ideaID: teammate.id, userID: "teammate", choice: choice))
        #expect(workspace.decisionQueue(for: nil, filter: filter).map(\.id) == [personal.id])
        let unansweredIDs = choice == .maybe ? [shared.id, teammate.id] : [teammate.id]
        #expect(Set(workspace.decisionQueue.map(\.id)) == Set(unansweredIDs))
        workspace.configureViewer(account("other-account"))
        #expect(workspace.decisionQueue(for: nil, filter: filter).isEmpty)
    }

    @Test("Keeping a response advances a finite review pass without changing the stored response",
          arguments: [DecisionChoice.maybe, .pass])
    func finiteReviewAndUndo(choice: DecisionChoice) throws {
        let filter = DecisionQueueFilter(restoring: choice)
        let workspace = workspace()
        let first = PlanningIdea(title: "First", note: "", category: .decor, submittedBy: "Host")
        let second = PlanningIdea(title: "Second", note: "", category: .flowers, submittedBy: "Host")
        for idea in [first, second] {
            workspace.addIdea(idea)
            workspace.decide(choice, on: idea)
        }
        var session = DecisionDeckSession()
        session.selectFilter(filter)
        let reviewOrder = session.queue(in: workspace)
        #expect(reviewOrder.count == 2)
        for idea in reviewOrder {
            #expect(session.queue(in: workspace).first?.id == idea.id)
            workspace.decide(choice, on: idea)
            session.recordDecision(on: idea.id)
            #expect(workspace.response(on: idea) == choice)
        }
        #expect(session.queue(in: workspace).isEmpty)
        #expect(workspace.decisionQueue(for: nil, filter: filter).count == 2)
        let undoneID = try #require(workspace.undoLastDecision())
        session.undoDecision(on: undoneID)
        #expect(session.queue(in: workspace).map(\.id) == [undoneID])
        session.restartReview()
        #expect(session.queue(in: workspace).map(\.id) == reviewOrder.map(\.id))
    }

    @Test("Revisiting responses can change queues, and undo restores the original response and filter",
          arguments: [DecisionChoice.maybe, .pass])
    func resolveAndUndo(original: DecisionChoice) throws {
        let filter = DecisionQueueFilter(restoring: original)
        let workspace = workspace()
        let idea = PlanningIdea(title: "Dinner", note: "", category: .food, submittedBy: "Host")
        workspace.addIdea(idea)
        workspace.decide(original, on: idea)
        for choice in [DecisionChoice.love, original == .maybe ? .pass : .maybe] {
            workspace.decide(choice, on: idea)
            #expect(workspace.decisionQueue(for: nil, filter: filter).isEmpty)
            if choice != .love {
                #expect(workspace.decisionQueue(for: nil, filter: DecisionQueueFilter(restoring: choice)).map(\.id) == [idea.id])
            }
            #expect(workspace.decisionQueue.isEmpty)
            #expect(workspace.undoLastDecision() == idea.id)
            #expect(workspace.response(on: idea) == original)
            #expect(DecisionQueueFilter(restoring: workspace.response(on: idea)) == filter)
            #expect(workspace.decisionQueue(for: nil, filter: filter).map(\.id) == [idea.id])
        }
        #expect(workspace.ideas.first?.status == .new)
    }

    @Test("Review queues respect event filters and remove closed ideas",
          arguments: [DecisionChoice.maybe, .pass])
    func eventAndLifecycleFilters(choice: DecisionChoice) throws {
        let filter = DecisionQueueFilter(restoring: choice)
        let workspace = workspace()
        let hostID = try #require(workspace.members.first?.id)
        let child = TimelineItem(title: "Reception", category: .reception, scheduledAt: .now,
            participantIDs: [hostID], parentEventID: workspace.mainEventID)
        workspace.addTimelineItem(child)
        let rootIdea = PlanningIdea(title: "Root", note: "", category: .decor, submittedBy: "Host")
        let childIdea = PlanningIdea(eventID: child.id, title: "Child", note: "", category: .decor, submittedBy: "Host")
        for idea in [rootIdea, childIdea] {
            workspace.addIdea(idea)
            workspace.decide(choice, on: idea)
        }
        #expect(workspace.decisionQueue(for: child.id, filter: filter).map(\.id) == [childIdea.id])
        #expect(workspace.decisionQueue(for: workspace.mainEventID, filter: filter).map(\.id) == [rootIdea.id])
        workspace.updateIdea(rootIdea, status: .chosen)
        workspace.setEventStatus(.cancelled, for: child)
        #expect(workspace.decisionQueue(for: nil, filter: filter).isEmpty)
        #expect(workspace.ideaResponses.count == 2)
    }

    @Test("Review survives offline restore and changes only the independent response mutation",
          arguments: [DecisionChoice.maybe, .pass])
    func offlineRestoreAndOutbox(choice: DecisionChoice) throws {
        let filter = DecisionQueueFilter(restoring: choice)
        let persistence = try WorkspacePersistenceController(isStoredInMemoryOnly: true)
        let library = persistence.restoreLibrary(seedData: false, ownerUserID: "host")
        library.configureViewer(account("host"))
        let workspace = workspace()
        let idea = PlanningIdea(title: "Flowers", note: "", category: .flowers, submittedBy: "Host")
        workspace.addIdea(idea)
        library.add(workspace)
        workspace.decide(choice, on: idea)
        try persistence.saveChanges(in: library)
        let before = try ModelContext(persistence.container).fetch(FetchDescriptor<PendingMutation>())
        let workspacePayload = try #require(before.first { $0.entityType == .workspace }).payload
        let responseID = try #require(before.first { $0.entityType == .ideaResponse }).id
        let restored = persistence.restoreLibrary(seedData: false, ownerUserID: "host")
        restored.configureViewer(account("host"))
        let cached = try #require(restored.workspaces.first)
        #expect(cached.decisionQueue(for: nil, filter: filter).map(\.id) == [idea.id])
        cached.decide(.love, on: idea)
        try persistence.saveChanges(in: restored)
        let after = try ModelContext(persistence.container).fetch(FetchDescriptor<PendingMutation>())
        #expect(after.count == before.count)
        #expect(after.first { $0.entityType == .workspace }?.payload == workspacePayload)
        let response = try #require(after.first { $0.entityType == .ideaResponse })
        #expect(response.id == responseID)
        #expect(try JSONDecoder().decode(IdeaResponse.self, from: response.payload).choice == .love)
    }

    @Test("Scoped collaborators review only while their exact-event access allows responses",
          arguments: [DecisionChoice.maybe, .pass])
    func scopedPermissions(choice: DecisionChoice) throws {
        let filter = DecisionQueueFilter(restoring: choice)
        for permission in [PlanningPermission.manage, .contribute, .viewOnly] {
            let idea = PlanningIdea(title: "Dinner", note: "", category: .food, submittedBy: "Host")
            let member = WorkspaceMember(userID: "viewer", name: "Viewer",
                participantRole: .collaborator, initials: "V", planningPermission: permission)
            let workspace = PlanningWorkspace(isScopedEvent: true, title: "Dinner",
                mainEventStartsAt: .now.addingTimeInterval(86400), venueName: "", location: "",
                planningMode: .openToIdeas, members: [member], ideas: [idea], timeline: [],
                ideaResponses: [IdeaResponse(ideaID: idea.id, userID: "viewer", choice: choice)],
                registry: [])
            workspace.configureViewer(account("viewer"))
            #expect(workspace.decisionQueue(for: nil, filter: filter).count == (permission == .viewOnly ? 0 : 1))
            workspace.decide(.love, on: idea)
            #expect(workspace.response(on: idea) == (permission == .viewOnly ? choice : .love))
        }
    }

    @Test("Switching review filters starts a fresh pass without changing responses")
    func switchReviewFilters() {
        let workspace = workspace()
        let maybe = PlanningIdea(title: "Maybe", note: "", category: .decor, submittedBy: "Host")
        let pass = PlanningIdea(title: "Pass", note: "", category: .flowers, submittedBy: "Host")
        workspace.addIdea(maybe)
        workspace.addIdea(pass)
        workspace.decide(.maybe, on: maybe)
        workspace.decide(.pass, on: pass)
        let responses = workspace.ideaResponses
        var session = DecisionDeckSession()
        session.selectFilter(.maybes)
        session.recordDecision(on: maybe.id)
        #expect(session.queue(in: workspace).isEmpty)
        session.selectFilter(.passes)
        #expect(session.queue(in: workspace).map(\.id) == [pass.id])
        session.recordDecision(on: pass.id)
        #expect(session.queue(in: workspace).isEmpty)
        session.selectFilter(.maybes)
        #expect(session.queue(in: workspace).map(\.id) == [maybe.id])
        #expect(workspace.ideaResponses == responses)
        #expect(DecisionQueueFilter(restoring: nil) == .unanswered)
    }
}
