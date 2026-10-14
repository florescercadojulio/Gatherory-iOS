import Foundation
import SwiftData
import Testing
@testable import Gatherory

@MainActor
struct TeamDecisionTests {
    private func makeWorkspace() -> PlanningWorkspace {
        PlanningWorkspace(title: "Team", mainEventStartsAt: .now.addingTimeInterval(86400),
            venueName: "", location: "", planningMode: .openToIdeas,
            members: [
                WorkspaceMember(userID: "host", name: "Host", participantRole: .host, initials: "H", planningPermission: .manage),
                WorkspaceMember(userID: "collaborator", name: "Collaborator", participantRole: .collaborator, initials: "C"),
                WorkspaceMember(userID: "guest", name: "Guest", participantRole: .guest, initials: "G"),
                WorkspaceMember(userID: "reader", name: "Reader", participantRole: .collaborator, initials: "R", planningPermission: .viewOnly)
            ], ideas: [PlanningIdea(title: "Flowers", note: "", category: .decor, submittedBy: "Host")],
            timeline: [], registry: [])
    }
    private func account(_ id: String) -> UserAccount {
        UserAccount(id: id, email: "\(id)@example.test", displayName: id, role: .planner,
                    authenticationProvider: .password, createdAt: .now)
    }

    @Test("Each teammate has an independent queue, response, and undo history")
    func independentResponses() throws {
        let workspace = makeWorkspace()
        let idea = try #require(workspace.ideas.first)
        workspace.configureViewer(account("host"))
        workspace.decide(.love, on: idea)
        #expect(workspace.decisionQueue.isEmpty)
        #expect(workspace.ideas.first?.status == .new)
        #expect(workspace.teamResponseSummary(for: idea) == .init(love: 1, unanswered: 1))
        workspace.configureViewer(account("collaborator"))
        #expect(!workspace.canUndoDecision)
        #expect(workspace.decisionQueue.count == 1)
        workspace.decide(.pass, on: idea)
        #expect(workspace.teamResponseSummary(for: idea) == .init(love: 1, pass: 1))
        workspace.decide(.maybe, on: idea)
        #expect(workspace.teamResponseSummary(for: idea) == .init(love: 1, maybe: 1))
        #expect(workspace.ideaResponses.count == 2)
        workspace.undoLastDecision()
        #expect(workspace.response(on: idea) == .pass)
        workspace.undoLastDecision()
        #expect(workspace.decisionQueue.count == 1)
        #expect(workspace.teamResponseSummary(for: idea) == .init(love: 1, unanswered: 1))
    }

    @Test("Guests and read-only planners cannot respond or finalize")
    func permissions() throws {
        for id in ["guest", "reader"] {
            let workspace = makeWorkspace()
            workspace.configureViewer(account(id))
            let idea = try #require(workspace.ideas.first)
            workspace.decide(.love, on: idea)
            workspace.updateIdea(idea, status: .chosen)
            #expect(workspace.ideaResponses.isEmpty)
            #expect(workspace.ideas.first?.status == .new)
        }
    }

    @Test("Seed-style root and child bars count only that event's eligible planners")
    func eventScopedResponses() throws {
        let workspace = makeWorkspace()
        let rootIdea = try #require(workspace.ideas.first)
        let childPlanner = WorkspaceMember(userID: "child-planner", name: "Child planner",
            participantRole: .collaborator, initials: "CP", planningPermission: .contribute)
        workspace.members.append(childPlanner)
        let host = try #require(workspace.members.first { $0.userID == "host" })
        let child = TimelineItem(title: "Reception", category: .reception,
            scheduledAt: .now.addingTimeInterval(86400), participantIDs: [host.id, childPlanner.id],
            parentEventID: workspace.mainEventID)
        workspace.addTimelineItem(child)
        let childIdea = PlanningIdea(eventID: child.id, title: "Reception decor", note: "",
            category: .decor, submittedBy: "Host")
        workspace.addIdea(childIdea)
        workspace.ideaResponses = [
            IdeaResponse(ideaID: childIdea.id, userID: "collaborator", choice: .pass),
            IdeaResponse(ideaID: rootIdea.id, userID: "child-planner", choice: .pass)
        ]
        workspace.configureViewer(account("host"))
        workspace.decide(.love, on: rootIdea)
        workspace.decide(.maybe, on: childIdea)
        #expect(workspace.teamResponseSummary(for: rootIdea) == .init(love: 1, unanswered: 1))
        #expect(workspace.teamResponseSummary(for: childIdea) == .init(maybe: 1, unanswered: 1))

        let scoped = PlanningWorkspace(mainEventID: child.id, isScopedEvent: true,
            title: child.title, mainEventStartsAt: child.scheduledAt, venueName: "", location: "",
            planningMode: .openToIdeas, members: workspace.members,
            eventParticipations: workspace.eventParticipations,
            mainEventParticipantIDs: child.participantIDs, ideas: [childIdea], timeline: [],
            ideaResponses: workspace.ideaResponses, registry: [])
        scoped.configureViewer(account("child-planner"))
        #expect(scoped.teamResponseSummary(for: childIdea) == workspace.teamResponseSummary(for: childIdea))
        scoped.decide(.love, on: childIdea)
        #expect(scoped.teamResponseSummary(for: childIdea) == .init(love: 1, maybe: 1))

        workspace.undoLastDecision()
        #expect(workspace.teamResponseSummary(for: childIdea) == .init(unanswered: 2))
        #expect(workspace.teamResponseSummary(for: rootIdea) == .init(love: 1, unanswered: 1))

        // A planner who isn't on this event must neither vote nor count in its bar.
        workspace.configureViewer(account("collaborator"))
        #expect(!workspace.canRespond(to: childIdea))
        #expect(!workspace.decisionQueue.contains { $0.id == childIdea.id })
    }

    @Test("Even unanimous love needs explicit approval")
    func explicitApproval() throws {
        let workspace = makeWorkspace()
        let idea = try #require(workspace.ideas.first)
        for id in ["host", "collaborator"] {
            workspace.configureViewer(account(id))
            workspace.decide(.love, on: idea)
        }
        #expect(workspace.teamResponseSummary(for: idea) == .init(love: 2))
        #expect(workspace.ideas.first?.status == .new)
        workspace.updateIdea(idea, status: .chosen)
        let approved = try #require(workspace.ideas.first)
        #expect(approved.status == .chosen)
        #expect(!workspace.canRespond(to: approved))
        workspace.decide(.pass, on: approved)
        #expect(workspace.response(on: approved) == .love)
    }

    @Test("Responses persist separately without republishing the workspace or idea")
    func persistence() throws {
        let persistence = try WorkspacePersistenceController(isStoredInMemoryOnly: true)
        let library = persistence.restoreLibrary(seedData: false)
        let workspace = makeWorkspace()
        workspace.configureViewer(account("host"))
        library.add(workspace)
        try persistence.saveChanges(in: library)
        let context = ModelContext(persistence.container)
        let before = try context.fetch(FetchDescriptor<PendingMutation>())
        let count = before.count
        let rootPayload = try #require(before.first { $0.entityType == .workspace }).payload
        let idea = try #require(workspace.ideas.first)
        workspace.decide(.love, on: idea)
        try persistence.saveChanges(in: library)
        let mutations = try ModelContext(persistence.container).fetch(FetchDescriptor<PendingMutation>())
        #expect(mutations.count == count + 1)
        #expect(mutations.first { $0.entityType == .workspace }?.payload == rootPayload)
        let vote = try #require(mutations.first { $0.entityType == .ideaResponse })
        #expect(try JSONDecoder().decode(IdeaResponse.self, from: vote.payload).userID == "host")
        let restored = try #require(persistence.restoreLibrary(seedData: false).workspaces.first)
        restored.configureViewer(account("host"))
        #expect(restored.response(on: idea) == .love)
        #expect(restored.decisionQueue.isEmpty)
    }

    @Test("Response IDs are deterministic and distinct per account")
    func identity() throws {
        let ideaID = try #require(UUID(uuidString: "00000000-0000-4000-8000-000000000001"))
        let first = IdeaResponse.identifier(ideaID: ideaID, userID: "host")
        #expect(first == IdeaResponse.identifier(ideaID: ideaID, userID: "host"))
        #expect(first != IdeaResponse.identifier(ideaID: ideaID, userID: "collaborator"))
    }

    @Test("A synced late joiner expands existing bars and gets an independent queue")
    func lateJoinerRefreshesExistingResponses() throws {
        let persistence = try WorkspacePersistenceController(isStoredInMemoryOnly: true)
        let library = persistence.restoreLibrary(seedData: false)
        let workspace = makeWorkspace()
        let idea = try #require(workspace.ideas.first)
        for id in ["host", "collaborator"] {
            workspace.configureViewer(account(id))
            workspace.decide(.love, on: idea)
        }
        library.add(workspace)
        library.configureViewer(account("host"))
        try persistence.saveChanges(in: library)
        #expect(workspace.teamResponseSummary(for: idea) == .init(love: 2))

        let newcomer = WorkspaceMember(userID: "newcomer", name: "New Teammate",
            participantRole: .collaborator, initials: "NT")
        var participation = EventParticipation(eventID: workspace.mainEventID, memberID: newcomer.id,
            role: .collaborator, planningPermission: .contribute, attendance: .invited, invitationStatus: .active)
        func envelope<T: Encodable>(_ type: SyncEntityType, _ id: UUID, _ value: T) throws -> RemoteChangeEnvelope {
            RemoteChangeEnvelope(id: UUID(), scopeID: workspace.mainEventID, entityType: type,
                entityID: id, operation: .update, payload: try JSONEncoder().encode(value),
                serverVersion: 1, occurredAt: .now)
        }
        // The server publishes the person and event membership as separate entities.
        let joinChanges = try [envelope(.participant, newcomer.id, newcomer),
                              envelope(.eventParticipation, participation.id, participation)]
        try persistence.applyRemotePage(.init(changes: joinChanges, nextCursor: "2", hasMore: false),
            scopeID: workspace.mainEventID, to: library)
        let updated = try #require(library.selectedWorkspace)
        #expect(updated.teamResponseSummary(for: idea) == .init(love: 2, unanswered: 1))
        #expect(updated.decisionQueue.isEmpty) // Host has already responded.
        library.configureViewer(account("newcomer"))
        #expect(updated.decisionQueue.map(\.id) == [idea.id])

        let response = IdeaResponse(ideaID: idea.id, userID: "newcomer", choice: .maybe)
        try persistence.applyRemotePage(.init(changes: [try envelope(.ideaResponse, response.id, response)],
            nextCursor: "3", hasMore: false), scopeID: workspace.mainEventID, to: library)
        let voted = try #require(library.selectedWorkspace)
        #expect(voted.teamResponseSummary(for: idea) == .init(love: 2, maybe: 1))
        #expect(voted.decisionQueue.isEmpty)
        #expect(voted.ideas.first?.status == .new)

        // A role refresh also removes no-longer-eligible input from the denominator.
        participation.planningPermission = .viewOnly
        try persistence.applyRemotePage(.init(changes: [try envelope(.eventParticipation, participation.id, participation)],
            nextCursor: "4", hasMore: false), scopeID: workspace.mainEventID, to: library)
        #expect(library.selectedWorkspace?.teamResponseSummary(for: idea) == .init(love: 2))
    }

    @Test("An unchanged refresh preserves the live workspace and undo state")
    func unchangedRefreshPreservesLiveState() throws {
        let persistence = try WorkspacePersistenceController(isStoredInMemoryOnly: true)
        let library = persistence.restoreLibrary(seedData: false)
        let workspace = makeWorkspace()
        library.configureViewer(account("host"))
        library.add(workspace)
        workspace.decide(.love, on: try #require(workspace.ideas.first))
        try persistence.saveChanges(in: library)
        try persistence.applyRemotePage(.init(changes: [], nextCursor: "5", hasMore: false),
            scopeID: workspace.mainEventID, to: library)
        #expect(library.selectedWorkspace === workspace)
        #expect(workspace.canUndoDecision)
        #expect(try persistence.currentCursor(for: workspace.mainEventID) == "5")
    }

    @Test("Empty pulls advance the checkpoint without decoding stored artwork archives")
    func emptyRefreshDoesNotDecodeArchive() throws {
        let persistence = try WorkspacePersistenceController(isStoredInMemoryOnly: true)
        let library = persistence.restoreLibrary(seedData: false)
        let workspace = makeWorkspace()
        library.add(workspace)
        let context = ModelContext(persistence.container)
        // An intentionally opaque payload proves this path never decodes the
        // archive; it only needs the scope's checkpoint when nothing changed.
        let record = WorkspaceRecord(id: workspace.mainEventID,
            payload: Data("opaque archive".utf8), sortOrder: 0)
        context.insert(record)
        try context.save()
        try persistence.applyRemotePage(.init(changes: [], nextCursor: "9", hasMore: false),
            scopeID: workspace.mainEventID, to: library)
        #expect(library.selectedWorkspace === workspace)
        #expect(try persistence.currentCursor(for: workspace.mainEventID) == "9")
        #expect(record.payload == Data("opaque archive".utf8))
    }
}
