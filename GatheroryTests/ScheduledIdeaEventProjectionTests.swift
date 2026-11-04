import Foundation
import Testing
@testable import Gatherory

@MainActor
struct ScheduledIdeaEventProjectionTests {
    @Test("Projection returns the unique visible direct child linked to an idea")
    func resolvesExactChild() {
        let host = WorkspaceMember(name: "Host", participantRole: .host, initials: "H")
        let idea = makeIdea()
        let rootID = UUID()
        let child = makeChild(ideaID: idea.id, parentID: rootID, participantIDs: [host.id])
        let workspace = makeWorkspace(idea: idea, child: child, rootID: rootID, members: [host])

        #expect(ScheduledIdeaEventProjection.resolve(ideaID: idea.id, in: workspace)?.id == child.id)
    }

    @Test("Projection rejects ambiguous, unrelated, archived, or unlinked children")
    func rejectsInvalidLinks() {
        let host = WorkspaceMember(name: "Host", participantRole: .host, initials: "H")
        let idea = makeIdea()
        let rootID = UUID()

        let wrongParent = makeChild(ideaID: idea.id, parentID: UUID(), participantIDs: [host.id])
        let wrongParentWorkspace = makeWorkspace(idea: idea, child: wrongParent, rootID: rootID, members: [host])
        wrongParentWorkspace.timeline[0].parentEventID = UUID()
        #expect(ScheduledIdeaEventProjection.resolve(ideaID: idea.id, in: wrongParentWorkspace) == nil)

        let archived = makeChild(ideaID: idea.id, parentID: rootID, participantIDs: [host.id], status: .archived)
        let archivedWorkspace = makeWorkspace(idea: idea, child: archived, rootID: rootID, members: [host])
        #expect(ScheduledIdeaEventProjection.resolve(ideaID: idea.id, in: archivedWorkspace) == nil)

        let first = makeChild(ideaID: idea.id, parentID: rootID, participantIDs: [host.id])
        let second = makeChild(ideaID: idea.id, parentID: rootID, participantIDs: [host.id])
        let ambiguousWorkspace = makeWorkspace(idea: idea, children: [first, second], rootID: rootID, members: [host])
        #expect(ScheduledIdeaEventProjection.resolve(ideaID: idea.id, in: ambiguousWorkspace) == nil)

        let unrelatedWorkspace = makeWorkspace(idea: idea, child: nil, rootID: rootID, members: [host])
        #expect(ScheduledIdeaEventProjection.resolve(ideaID: idea.id, in: unrelatedWorkspace) == nil)
    }

    @Test("Projection rejects deleted roots, isolated scopes, projections, and viewers without active child participation")
    func rejectsUnavailableViewerContexts() {
        let host = WorkspaceMember(name: "Host", participantRole: .host, initials: "H")
        let invited = WorkspaceMember(
            name: "Invited", participantRole: .collaborator, initials: "I",
            invitationStatus: .invited
        )
        let idea = makeIdea()
        let rootID = UUID()

        let child = makeChild(ideaID: idea.id, parentID: rootID, participantIDs: [host.id])
        let deletedWorkspace = makeWorkspace(idea: idea, child: child, rootID: rootID, members: [host], isMainEventDeleted: true)
        #expect(ScheduledIdeaEventProjection.resolve(ideaID: idea.id, in: deletedWorkspace) == nil)

        let scopedWorkspace = makeWorkspace(idea: idea, child: child, rootID: rootID, members: [host], isScopedEvent: true)
        #expect(ScheduledIdeaEventProjection.resolve(ideaID: idea.id, in: scopedWorkspace) == nil)

        let projectionWorkspace = makeWorkspace(idea: idea, child: child, rootID: rootID, members: [host])
        projectionWorkspace.isInvitationProjection = true
        #expect(ScheduledIdeaEventProjection.resolve(ideaID: idea.id, in: projectionWorkspace) == nil)

        let invitedChild = makeChild(ideaID: idea.id, parentID: rootID, participantIDs: [invited.id])
        let invitedWorkspace = makeWorkspace(idea: idea, child: invitedChild, rootID: rootID, members: [invited, host])
        #expect(ScheduledIdeaEventProjection.resolve(ideaID: idea.id, in: invitedWorkspace) == nil)

        let absentViewerChild = makeChild(ideaID: idea.id, parentID: rootID, participantIDs: [invited.id])
        let absentViewerWorkspace = makeWorkspace(idea: idea, child: absentViewerChild, rootID: rootID, members: [host, invited])
        absentViewerWorkspace.configureViewer(UserAccount(
            id: "stranger-account", email: "", displayName: "Stranger", role: .member,
            authenticationProvider: .password, createdAt: .now
        ))
        #expect(ScheduledIdeaEventProjection.resolve(ideaID: idea.id, in: absentViewerWorkspace) == nil)
    }

    private func makeWorkspace(
        idea: PlanningIdea,
        child: TimelineItem?,
        rootID: UUID = UUID(),
        members: [WorkspaceMember],
        isMainEventDeleted: Bool = false,
        isScopedEvent: Bool = false
    ) -> PlanningWorkspace {
        makeWorkspace(
            idea: idea,
            children: child.map { [$0] } ?? [],
            rootID: rootID,
            members: members,
            isMainEventDeleted: isMainEventDeleted,
            isScopedEvent: isScopedEvent
        )
    }

    private func makeWorkspace(
        idea: PlanningIdea,
        children: [TimelineItem],
        rootID: UUID,
        members: [WorkspaceMember],
        isMainEventDeleted: Bool = false,
        isScopedEvent: Bool = false
    ) -> PlanningWorkspace {
        let workspace = PlanningWorkspace(
            mainEventID: rootID,
            isScopedEvent: isScopedEvent,
            title: "Gathering", mainEventStartsAt: .now,
            venueName: "", location: "", planningMode: .openToIdeas,
            members: members, ideas: [idea], timeline: children,
            isMainEventDeleted: isMainEventDeleted,
            registry: []
        )
        // Initialization reconciles dated chosen ideas into Home children.
        // Restore the fixture's intended timeline after it seeds participation
        // relationships so empty and malformed-link cases stay intentional.
        workspace.timeline = children.map { child in
            var normalizedChild = child
            normalizedChild.parentEventID = rootID
            return normalizedChild
        }
        return workspace
    }

    private func makeIdea() -> PlanningIdea {
        PlanningIdea(
            title: "Dinner", note: "", category: .event,
            submittedBy: "Host", status: .chosen,
            configuration: .event(EventIdeaConfiguration(
                category: .reception, purpose: .planning,
                proposedDate: .now, location: nil
            ))
        )
    }

    private func makeChild(
        ideaID: UUID,
        parentID: UUID,
        participantIDs: [UUID],
        status: EventStatus = .approved
    ) -> TimelineItem {
        TimelineItem(
            title: "Dinner Event", category: .other, scheduledAt: .now,
            location: "", participantIDs: participantIDs, parentEventID: parentID,
            status: status, linkedIdeaID: ideaID
        )
    }
}
