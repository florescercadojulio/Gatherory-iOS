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
}
