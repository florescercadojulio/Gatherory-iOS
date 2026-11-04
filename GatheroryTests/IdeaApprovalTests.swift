import Foundation
import Testing
@testable import Gatherory

@MainActor
struct IdeaApprovalTests {
    @Test("Liked follows the current viewer's personal response and excludes archived ideas")
    func likedIsPersonalAndViewerBound() throws {
        let host = member("host", role: .host, permission: .manage)
        let collaborator = member("collaborator", role: .collaborator, permission: .contribute)
        let loved = PlanningIdea(title: "Loved", note: "", category: .decor, submittedBy: "Host")
        let archived = PlanningIdea(title: "Archived", note: "", category: .decor, submittedBy: "Host", status: .archived)
        let shortlisted = PlanningIdea(title: "Shortlisted", note: "", category: .decor, submittedBy: "Host", status: .shortlisted)
        let workspace = makeWorkspace(members: [host, collaborator], ideas: [loved, archived, shortlisted], responses: [
            IdeaResponse(ideaID: loved.id, userID: "host", choice: .love),
            IdeaResponse(ideaID: loved.id, userID: "collaborator", choice: .pass),
            IdeaResponse(ideaID: archived.id, userID: "host", choice: .love),
            IdeaResponse(ideaID: shortlisted.id, userID: "host", choice: .maybe)
        ])

        workspace.configureViewer(account("host"))
        #expect(IdeaFilter.liked.includes(loved, response: workspace.response(on: loved)))
        #expect(!IdeaFilter.liked.includes(archived, response: workspace.response(on: archived)))
        #expect(!IdeaFilter.liked.includes(shortlisted, response: workspace.response(on: shortlisted)))
        workspace.configureViewer(account("collaborator"))
        #expect(!IdeaFilter.liked.includes(loved, response: workspace.response(on: loved)))

        workspace.decide(.love, on: loved)
        #expect(IdeaFilter.liked.includes(loved, response: workspace.response(on: loved)))
        workspace.decide(.pass, on: loved)
        #expect(!IdeaFilter.liked.includes(loved, response: workspace.response(on: loved)))
    }

    @Test("Approving a non-event idea commits only after confirmation and retries safely")
    func approvalConfirmationIsIdempotentAndPreservesOtherIdeas() throws {
        let host = member("host", role: .host, permission: .manage)
        let contributor = member("contributor", role: .collaborator, permission: .contribute)
        let target = PlanningIdea(title: "Dinner", note: "", category: .food, submittedBy: "Host", estimatedCost: 45)
        let other = PlanningIdea(title: "Flowers", note: "", category: .decor, submittedBy: "Host")
        let workspace = makeWorkspace(members: [host, contributor], ideas: [target, other], budget: 100)
        workspace.configureViewer(account("contributor"))
        let parentTitle = workspace.title
        let parentStatus = workspace.mainEventStatus
        let storedTarget = try #require(workspace.ideas.first { $0.id == target.id })
        let storedOther = try #require(workspace.ideas.first { $0.id == other.id })
        let request = try #require(workspace.makeIdeaApprovalRequest(for: storedTarget))

        #expect(workspace.canApproveIdea(storedTarget))
        #expect(workspace.ideas.first { $0.id == target.id }?.status == .new)
        #expect(workspace.eventExpenses.isEmpty)
        #expect(workspace.timeline.isEmpty)
        #expect(workspace.confirmIdeaApproval(request))
        #expect(workspace.ideas.first { $0.id == target.id }?.status == .chosen)
        #expect(workspace.ideas.first { $0.id == other.id } == storedOther)
        #expect(workspace.eventExpenses.count == 1)
        #expect(workspace.eventExpenses.first?.sourceIdeaID == target.id)
        #expect(workspace.eventExpenses.first?.status == .committed)
        #expect(workspace.eventExpenses.first?.amount == 45)
        #expect(workspace.timeline.isEmpty, "Approving a non-event idea should not create or publish a child event.")
        #expect(workspace.title == parentTitle)
        #expect(workspace.mainEventStatus == parentStatus)
        let expenseID = try #require(workspace.eventExpenses.first?.id)

        #expect(workspace.confirmIdeaApproval(request), "An exact retry should succeed idempotently.")
        #expect(workspace.eventExpenses.count == 1)
        #expect(workspace.eventExpenses.first?.id == expenseID)
    }

    @Test("A changed target, removed target, or lost permission invalidates an approval request")
    func staleApprovalRequestsAreRejected() throws {
        let host = member("host", role: .host, permission: .manage)
        let contributor = member("contributor", role: .collaborator, permission: .contribute)

        let edited = PlanningIdea(title: "Dinner", note: "", category: .food, submittedBy: "Host")
        let editedWorkspace = makeWorkspace(members: [host, contributor], ideas: [edited])
        editedWorkspace.configureViewer(account("contributor"))
        let editedSnapshot = try #require(editedWorkspace.ideas.first)
        let editedRequest = try #require(editedWorkspace.makeIdeaApprovalRequest(for: editedSnapshot))
        var changed = editedSnapshot
        changed.note = "Changed after confirmation opened"
        editedWorkspace.updateIdea(changed)
        #expect(!editedWorkspace.confirmIdeaApproval(editedRequest))
        #expect(editedWorkspace.ideas.first?.status == .new)

        let removedParent = TimelineItem(
            title: "Removed parent", category: .reception, scheduledAt: .now,
            location: "", participantIDs: [host.id, contributor.id]
        )
        let removed = PlanningIdea(eventID: removedParent.id, title: "Removed", note: "", category: .food, submittedBy: "Host")
        let removedWorkspace = makeWorkspace(members: [host, contributor], ideas: [removed], timeline: [removedParent])
        removedWorkspace.configureViewer(account("contributor"))
        let removedSnapshot = try #require(removedWorkspace.ideas.first)
        let removedRequest = try #require(removedWorkspace.makeIdeaApprovalRequest(for: removedSnapshot))
        removedWorkspace.deleteTimelineItem(removedParent)
        #expect(!removedWorkspace.confirmIdeaApproval(removedRequest))
        #expect(removedWorkspace.eventExpenses.isEmpty)

        let permissionIdea = PlanningIdea(title: "Permission", note: "", category: .food, submittedBy: "Host")
        let permissionWorkspace = makeWorkspace(members: [host, contributor], ideas: [permissionIdea])
        permissionWorkspace.configureViewer(account("contributor"))
        let permissionSnapshot = try #require(permissionWorkspace.ideas.first)
        let permissionRequest = try #require(permissionWorkspace.makeIdeaApprovalRequest(for: permissionSnapshot))
        #expect(permissionWorkspace.updateParticipant(
            contributor.id, role: .collaborator, planningPermission: .viewOnly, in: .main
        ))
        #expect(!permissionWorkspace.canApproveIdea(permissionSnapshot))
        #expect(!permissionWorkspace.confirmIdeaApproval(permissionRequest))
        #expect(permissionWorkspace.ideas.first?.status == .new)
        #expect(permissionWorkspace.eventExpenses.isEmpty)

        let accountIdea = PlanningIdea(title: "Account", note: "", category: .food, submittedBy: "Host")
        let accountWorkspace = makeWorkspace(members: [host, contributor], ideas: [accountIdea])
        accountWorkspace.configureViewer(account("contributor"))
        let accountSnapshot = try #require(accountWorkspace.ideas.first)
        let accountRequest = try #require(accountWorkspace.makeIdeaApprovalRequest(for: accountSnapshot))
        accountWorkspace.configureViewer(account("host"))
        #expect(!accountWorkspace.confirmIdeaApproval(accountRequest))
        #expect(accountWorkspace.ideas.first?.status == .new)
        #expect(accountWorkspace.eventExpenses.isEmpty)
    }

    @Test("Approving an idea in a draft child keeps that exact parent draft unchanged")
    func approvalDoesNotApproveOrScheduleDraftParent() throws {
        let host = member("host", role: .host, permission: .manage)
        let contributor = member("contributor", role: .collaborator, permission: .contribute)
        let childID = UUID()
        let child = TimelineItem(
            id: childID, title: "Draft Reception", category: .reception,
            scheduledAt: .now.addingTimeInterval(86_400), location: "",
            participantIDs: [host.id, contributor.id], status: .draft
        )
        let target = PlanningIdea(
            eventID: childID, title: "Dinner", note: "", category: .food,
            submittedBy: "Host", estimatedCost: 45, invitationVisibility: .planningOnly
        )
        let unrelated = PlanningIdea(title: "Root flowers", note: "", category: .flowers, submittedBy: "Host")
        let workspace = makeWorkspace(members: [host, contributor], ideas: [target, unrelated], timeline: [child], budget: 100)
        workspace.configureViewer(account("contributor"))
        let storedTarget = try #require(workspace.ideas.first { $0.id == target.id })
        let storedUnrelated = try #require(workspace.ideas.first { $0.id == unrelated.id })
        let originalChild = try #require(workspace.timeline.first { $0.id == childID })
        let request = try #require(workspace.makeIdeaApprovalRequest(for: storedTarget))

        #expect(request.parentEventID == childID)
        #expect(request.parentEventName == "Draft Reception")
        #expect(request.parentStatus == .subevent(.draft))
        #expect(workspace.confirmIdeaApproval(request))
        #expect(workspace.ideas.first { $0.id == target.id }?.status == .chosen)
        #expect(workspace.ideas.first { $0.id == unrelated.id } == storedUnrelated)
        #expect(workspace.timeline == [originalChild])
        #expect(workspace.timeline.first?.status == .draft)
        #expect(workspace.timeline.first?.title == "Draft Reception")
        #expect(workspace.timeline.first?.linkedIdeaID == nil)
        #expect(HomeEventsOverviewProjection(workspace: workspace).childEvents.contains { $0.id == childID },
                "Dated draft events can already be visible to authorized planners.")
        #expect(workspace.invitationIdeas(for: .subevent(childID)).isEmpty,
                "Approval must not publish an idea marked for planning only.")
        let expense = try #require(workspace.eventExpenses.first { $0.sourceIdeaID == target.id })
        #expect(expense.eventID == childID)
        #expect(expense.status == .committed)
        #expect(workspace.makeScheduleRequest(for: storedTarget) == nil,
                "Approving a non-event idea must not produce an event schedule request.")
    }

    @Test("Missing parents and event ideas cannot enter non-event approval")
    func missingParentAndEventIdeasAreNotApprovalTargets() throws {
        let host = member("host", role: .host, permission: .manage)
        let missingParentID = UUID()
        let orphan = PlanningIdea(
            eventID: missingParentID, title: "Orphan dinner", note: "", category: .food, submittedBy: "Host"
        )
        let eventIdea = PlanningIdea(
            title: "Reception proposal", note: "", category: .event, submittedBy: "Host",
            configuration: .event(EventIdeaConfiguration(category: .reception, purpose: .planning, proposedDate: nil, location: nil))
        )
        let workspace = makeWorkspace(members: [host], ideas: [orphan, eventIdea])
        workspace.configureViewer(account("host"))

        let storedOrphan = try #require(workspace.ideas.first { $0.id == orphan.id })
        let storedEvent = try #require(workspace.ideas.first { $0.id == eventIdea.id })
        #expect(workspace.makeIdeaApprovalRequest(for: storedOrphan) == nil,
                "A missing parent ID must not fall back to the root event.")
        #expect(workspace.makeIdeaApprovalRequest(for: storedEvent) == nil,
                "An event IDEA is scheduled through its existing event scheduling flow.")
        #expect(workspace.timeline.isEmpty,
                "An unapproved event idea is a proposal, not a real timeline target.")
        let eventProposalStatus = workspace.ideas.first { $0.id == eventIdea.id }?.status
        #expect(eventProposalStatus == IdeaStatus.new)
    }

    @Test("Parent removal, rename, and lifecycle changes invalidate an open approval request")
    func changedParentInvalidatesApprovalRequest() throws {
        let host = member("host", role: .host, permission: .manage)
        let contributor = member("contributor", role: .collaborator, permission: .contribute)

        for change in ["remove", "rename", "status"] {
            let childID = UUID()
            let child = TimelineItem(
                id: childID, title: "Reception", category: .reception,
                scheduledAt: .now.addingTimeInterval(86_400), location: "",
                participantIDs: [host.id, contributor.id], status: .draft
            )
            let target = PlanningIdea(
                eventID: childID, title: "Dinner", note: "", category: .food,
                submittedBy: "Host", estimatedCost: 45
            )
            let workspace = makeWorkspace(members: [host, contributor], ideas: [target], timeline: [child])
            workspace.configureViewer(account("contributor"))
            let storedTarget = try #require(workspace.ideas.first)
            let request = try #require(workspace.makeIdeaApprovalRequest(for: storedTarget))

            switch change {
            case "remove":
                workspace.timeline.removeAll { $0.id == childID }
            case "rename":
                workspace.timeline[0].title = "Renamed Reception"
            default:
                workspace.timeline[0].status = .approved
            }

            #expect(!workspace.confirmIdeaApproval(request), "Parent change \(change) must stale the request.")
            #expect(workspace.ideas.first { $0.id == target.id } == storedTarget)
            #expect(workspace.eventExpenses.isEmpty)
        }
    }

    @Test("Guests, view-only and invited collaborators, and ineligible ideas cannot be approved")
    func initialApprovalDenials() throws {
        let host = member("host", role: .host, permission: .manage)
        let candidate = PlanningIdea(title: "Dinner", note: "", category: .food, submittedBy: "Host")
        let actors = [
            member("guest", role: .guest, permission: .viewOnly),
            member("reader", role: .collaborator, permission: .viewOnly),
            member("invited", role: .collaborator, permission: .contribute, invitation: .invited)
        ]
        for actor in actors {
            let workspace = makeWorkspace(members: [host, actor], ideas: [candidate])
            workspace.configureViewer(account(actor.userID!))
            let stored = try #require(workspace.ideas.first)
            #expect(!workspace.canApproveIdea(stored))
            #expect(workspace.makeIdeaApprovalRequest(for: stored) == nil)
        }

        let ineligibleIdeas = [
            PlanningIdea(title: "Event", note: "", category: .event, submittedBy: "Host"),
            PlanningIdea(title: "Playlist", note: "", category: .music, submittedBy: "Host"),
            PlanningIdea(title: "Already chosen", note: "", category: .food, submittedBy: "Host", status: .chosen),
            PlanningIdea(title: "Archived", note: "", category: .food, submittedBy: "Host", status: .archived),
            PlanningIdea(title: "Passed", note: "", category: .food, submittedBy: "Host", status: .passed)
        ]
        let workspace = makeWorkspace(members: [host], ideas: ineligibleIdeas)
        workspace.configureViewer(account("host"))
        for idea in ineligibleIdeas {
            let stored = try #require(workspace.ideas.first { $0.id == idea.id })
            #expect(!workspace.canApproveIdea(stored), "\(stored.title) should not be an approval target.")
            #expect(workspace.makeIdeaApprovalRequest(for: stored) == nil)
        }
        #expect(workspace.timeline.isEmpty)
        #expect(workspace.eventExpenses.isEmpty)
    }

    private func makeWorkspace(
        members: [WorkspaceMember], ideas: [PlanningIdea], timeline: [TimelineItem] = [],
        responses: [IdeaResponse] = [], budget: Decimal = 250
    ) -> PlanningWorkspace {
        PlanningWorkspace(title: "Approval test", mainEventStartsAt: .now, venueName: "", location: "",
            planningMode: .openToIdeas, members: members, ideas: ideas, timeline: timeline,
            workspaceBudgetCap: budget, ideaResponses: responses, registry: [])
    }

    private func member(
        _ id: String, role: WorkspaceRole, permission: PlanningPermission,
        invitation: CollaborationInvitationStatus = .active
    ) -> WorkspaceMember {
        WorkspaceMember(userID: id, name: id, participantRole: role,
            initials: String(id.prefix(1)).uppercased(), planningPermission: permission,
            invitationStatus: invitation)
    }

    private func account(_ id: String) -> UserAccount {
        UserAccount(id: id, email: "\(id)@example.test", displayName: id, role: .planner,
            authenticationProvider: .password, createdAt: .now)
    }
}
