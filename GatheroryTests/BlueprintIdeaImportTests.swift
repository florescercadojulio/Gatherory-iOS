import Foundation
import Testing
@testable import Gatherory

@MainActor
struct BlueprintIdeaImportTests {
    @Test("A catalog idea imports as a fresh proposal without importing budget or relation records")
    func importsAsFreshIdea() throws {
        let workspace = PlanningWorkspace.newWorkspace(
            title: "Weekend",
            startsAt: .now,
            eventLocation: nil,
            imageData: nil
        )
        let source = source()
        let image = Data([0x01, 0x02, 0x03])
        let copyID = UUID()

        let result = BlueprintIdeaImport.add(
            source,
            to: .main,
            in: workspace,
            ideaID: copyID,
            imageData: image
        )

        guard case .added(let copied) = result else {
            Issue.record("Expected a new copy")
            return
        }
        #expect(copied.id == copyID)
        #expect(copied.id != UUID(uuidString: source.idea.key))
        #expect(copied.eventID == workspace.mainEventID)
        #expect(copied.title == "Garden picnic")
        #expect(copied.note.hasPrefix("Pack a shared lunch."))
        #expect(copied.note.contains("Weekend Retreat"))
        #expect(copied.note.contains("Riley Example"))
        #expect(!copied.note.contains("weekend-retreat"))
        #expect(copied.category == .other)
        #expect(copied.submittedBy == workspace.currentViewerMember(for: .main)?.name)
        #expect(copied.submittedBy != "Riley Example")
        #expect(copied.submittedByUserID == nil)
        #expect(copied.estimatedCost == nil)
        #expect(copied.status == .new)
        #expect(copied.imageData == image)
        #expect(copied.mediaAssetID == nil)
        #expect(workspace.ideaResponses.isEmpty)
        #expect(workspace.todos.isEmpty)
        #expect(workspace.timeline.isEmpty)
        #expect(workspace.eventExpenses.isEmpty)
    }

    @Test("A stable request ID retries idempotently while a fresh ID permits a later copy")
    func retryUsesStableIdeaID() throws {
        let workspace = PlanningWorkspace.newWorkspace(title: "Weekend", startsAt: .now, eventLocation: nil, imageData: nil)
        let source = source()
        let requestID = UUID()

        _ = BlueprintIdeaImport.add(source, to: .main, in: workspace, ideaID: requestID)
        let retry = BlueprintIdeaImport.add(source, to: .main, in: workspace, ideaID: requestID)
        let laterCopy = BlueprintIdeaImport.add(source, to: .main, in: workspace, ideaID: UUID())

        guard case .alreadyAdded(let original) = retry else {
            Issue.record("Expected retry to resolve to the existing copy")
            return
        }
        #expect(original.id == requestID)
        guard case .added = laterCopy else {
            Issue.record("Expected a later deliberate copy to add another idea")
            return
        }
        #expect(workspace.ideas.count == 2)
    }

    @Test("A failed save rolls back the imported idea")
    func failedSaveRollsBack() {
        let workspace = PlanningWorkspace.newWorkspace(title: "Weekend", startsAt: .now, eventLocation: nil, imageData: nil)
        let result = BlueprintIdeaImport.add(
            source(),
            to: .main,
            in: workspace,
            ideaID: UUID(),
            persist: { throw TestSaveError.failed }
        )

        #expect(result == .persistenceFailed)
        #expect(workspace.ideas.isEmpty)
        #expect(workspace.eventExpenses.isEmpty)
    }

    @Test("A child-event import keeps the chosen child association")
    func importsIntoSelectedChild() throws {
        let workspace = PlanningWorkspace.newWorkspace(title: "Weekend", startsAt: .now, eventLocation: nil, imageData: nil)
        let host = try #require(workspace.currentViewerMember(for: .main))
        let childID = UUID()
        workspace.timeline.append(TimelineItem(
            id: childID,
            title: "Dinner",
            category: .other,
            scheduledAt: .now,
            location: "",
            participantIDs: [host.id],
            parentEventID: workspace.mainEventID
        ))
        workspace.addParticipant(host.id, to: .subevent(childID))

        let result = BlueprintIdeaImport.add(source(), to: .subevent(childID), in: workspace, ideaID: UUID())

        guard case .added(let idea) = result else {
            Issue.record("Expected a child-scoped copy")
            return
        }
        #expect(idea.eventID == childID)
    }

    @Test("Only active event planners with write permission can add an idea")
    func enforcesDestinationPermission() {
        for (role, permission, invitation, expected) in [
            (WorkspaceRole.collaborator, PlanningPermission.contribute, CollaborationInvitationStatus.active, true),
            (.collaborator, .manage, .active, true),
            (.collaborator, .viewOnly, .active, false),
            (.collaborator, .contribute, .invited, false),
            (.guest, .manage, .active, false)
        ] {
            let member = WorkspaceMember(
                name: "Planner",
                participantRole: role,
                initials: "P",
                planningPermission: permission,
                invitationStatus: invitation
            )
            let workspace = PlanningWorkspace(
                title: "Weekend",
                mainEventStartsAt: .now,
                venueName: "",
                location: "",
                planningMode: .openToIdeas,
                members: [member],
                ideas: [],
                timeline: [],
                registry: []
            )
            #expect(BlueprintIdeaImport.canAdd(to: .main, in: workspace) == expected)
        }
    }

    @Test("Finished, cancelled, deleted and invitation projection destinations reject imports")
    func rejectsReadOnlyDestinations() {
        for status in [MainEventStatus.finished, .cancelled] {
            let workspace = PlanningWorkspace.newWorkspace(title: "Weekend", startsAt: .now, eventLocation: nil, imageData: nil)
            workspace.mainEventStatus = status
            #expect(!BlueprintIdeaImport.canAdd(to: .main, in: workspace))
        }
        let deleted = PlanningWorkspace.newWorkspace(title: "Weekend", startsAt: .now, eventLocation: nil, imageData: nil)
        deleted.isMainEventDeleted = true
        #expect(!BlueprintIdeaImport.canAdd(to: .main, in: deleted))

        let invitation = PlanningWorkspace.newWorkspace(title: "Weekend", startsAt: .now, eventLocation: nil, imageData: nil)
        invitation.isInvitationProjection = true
        #expect(!BlueprintIdeaImport.canAdd(to: .main, in: invitation))
    }

    private func source() -> BlueprintIdeaImportSource {
        BlueprintIdeaImportSource(
            idea: BlueprintCatalogIdea(
                key: "garden-picnic",
                title: "Garden picnic",
                category: "other",
                notes: "Pack a shared lunch.",
                target: .main,
                configuration: ["version": .integer(1)],
                coverAssetId: UUID()
            ),
            blueprintKey: "weekend-retreat",
            blueprintRevision: 2,
            blueprintTitle: "Weekend Retreat",
            creatorName: "Riley Example",
            publicCoverURL: URL(string: "https://cdn.gatherory.com/explore/covers/weekend-retreat/\(String(repeating: "a", count: 64))/card.jpg")
        )
    }

    private enum TestSaveError: Error {
        case failed
    }
}
