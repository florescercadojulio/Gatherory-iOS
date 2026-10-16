import Foundation
import SwiftData
import Testing
@testable import Gatherory

@MainActor
struct IdeaEventEditingTests {
    @Test("Event idea names can be edited by active planners with write permission",
          arguments: [PlanningPermission.manage, .contribute, .viewOnly])
    func eventIdeaEditingPermission(permission: PlanningPermission) {
        let member = WorkspaceMember(
            name: "Planner",
            participantRole: .collaborator,
            initials: "P",
            planningPermission: permission
        )
        let workspace = PlanningWorkspace(
            title: "Gathering",
            mainEventStartsAt: .now,
            venueName: "",
            location: "",
            planningMode: .openToIdeas,
            members: [member],
            ideas: [],
            timeline: [],
            registry: []
        )
        let idea = eventIdea(in: workspace)

        #expect(IdeaEventEditing.canEdit(idea, in: workspace) == (permission != .viewOnly))
        workspace.isInvitationProjection = true
        #expect(!IdeaEventEditing.canEdit(idea, in: workspace))

        let pendingMember = WorkspaceMember(
            name: "Pending planner",
            participantRole: .collaborator,
            initials: "P",
            planningPermission: .manage,
            invitationStatus: .invited
        )
        let pendingWorkspace = PlanningWorkspace(
            title: "Gathering",
            mainEventStartsAt: .now,
            venueName: "",
            location: "",
            planningMode: .openToIdeas,
            members: [pendingMember],
            ideas: [],
            timeline: [],
            registry: []
        )
        #expect(!IdeaEventEditing.canEdit(eventIdea(in: pendingWorkspace), in: pendingWorkspace))

        let guestMember = WorkspaceMember(
            name: "Guest",
            participantRole: .guest,
            initials: "G",
            planningPermission: .manage
        )
        let guestWorkspace = PlanningWorkspace(
            title: "Gathering",
            mainEventStartsAt: .now,
            venueName: "",
            location: "",
            planningMode: .openToIdeas,
            members: [guestMember],
            ideas: [],
            timeline: [],
            registry: []
        )
        #expect(!IdeaEventEditing.canEdit(eventIdea(in: guestWorkspace), in: guestWorkspace))
    }

    @Test("Renaming a dated approved event idea updates its linked Home event in place")
    func approvedEventRenameUpdatesLinkedEvent() throws {
        let workspace = PlanningWorkspace.newWorkspace(
            title: "Gathering",
            startsAt: .now,
            eventLocation: nil,
            imageData: nil
        )
        let idea = PlanningIdea(
            eventID: workspace.mainEventID,
            title: "Dinner",
            note: "A shared meal",
            category: .event,
            submittedBy: "Host",
            status: .chosen,
            configuration: .event(EventIdeaConfiguration(
                category: .reception,
                purpose: .eventExperience,
                proposedDate: .now.addingTimeInterval(86_400),
                location: nil
            ))
        )
        workspace.addIdea(idea)
        let linkedEvent = try #require(workspace.timeline.first { $0.linkedIdeaID == idea.id })
        var renamedIdea = try #require(workspace.ideas.first { $0.id == idea.id })
        renamedIdea.title = "Welcome Dinner"

        workspace.updateIdea(renamedIdea)

        let updatedIdea = try #require(workspace.ideas.first { $0.id == idea.id })
        let updatedEvent = try #require(workspace.timeline.first { $0.linkedIdeaID == idea.id })
        #expect(updatedIdea.title == "Welcome Dinner")
        #expect(updatedIdea.id == idea.id)
        #expect(updatedIdea.status == .chosen)
        #expect(updatedIdea.eventConfiguration == idea.eventConfiguration)
        #expect(updatedEvent.id == linkedEvent.id)
        #expect(updatedEvent.title == "Welcome Dinner")
        #expect(updatedEvent.status == linkedEvent.status)
    }

    @Test("Renaming an approved event idea is persisted as idea and linked-event updates")
    func approvedEventRenamePersistsToOutbox() throws {
        let persistence = try WorkspacePersistenceController(isStoredInMemoryOnly: true)
        let library = persistence.restoreLibrary(seedData: false)
        persistence.startObserving(library)
        let workspace = PlanningWorkspace.newWorkspace(
            title: "Gathering",
            startsAt: .now,
            eventLocation: nil,
            imageData: nil
        )
        library.add(workspace)
        let idea = PlanningIdea(
            eventID: workspace.mainEventID,
            title: "Dinner",
            note: "A shared meal",
            category: .event,
            submittedBy: "Host",
            status: .chosen,
            configuration: .event(EventIdeaConfiguration(
                category: .reception,
                purpose: .eventExperience,
                proposedDate: .now.addingTimeInterval(86_400),
                location: nil
            ))
        )
        workspace.addIdea(idea)
        let linkedEventID = try #require(workspace.timeline.first { $0.linkedIdeaID == idea.id }?.id)
        try persistence.saveChanges(in: library)

        let context = ModelContext(persistence.container)
        for mutation in try context.fetch(FetchDescriptor<PendingMutation>()) {
            context.delete(mutation)
        }
        try context.save()

        var renamedIdea = try #require(workspace.ideas.first { $0.id == idea.id })
        renamedIdea.title = "Welcome Dinner"
        workspace.updateIdea(renamedIdea)
        try persistence.saveChanges(in: library)

        let mutations = try context.fetch(FetchDescriptor<PendingMutation>())
        let ideaMutation = try #require(mutations.first {
            $0.entityType == .idea && $0.entityID == idea.id && $0.operation == .update
        })
        let eventMutation = try #require(mutations.first {
            $0.entityType == .event && $0.entityID == linkedEventID && $0.operation == .update
        })
        #expect(try JSONDecoder().decode(PlanningIdea.self, from: ideaMutation.payload).title == "Welcome Dinner")
        #expect(try JSONDecoder().decode(TimelineItem.self, from: eventMutation.payload).title == "Welcome Dinner")
        #expect(try JSONDecoder().decode(TimelineItem.self, from: eventMutation.payload).linkedIdeaID == idea.id)
    }

    private func eventIdea(in workspace: PlanningWorkspace) -> PlanningIdea {
        PlanningIdea(
            eventID: workspace.mainEventID,
            title: "Dinner",
            note: "",
            category: .event,
            submittedBy: "Planner",
            configuration: .event(EventIdeaConfiguration(
                category: .reception,
                purpose: .eventExperience,
                proposedDate: nil,
                location: nil
            ))
        )
    }
}
