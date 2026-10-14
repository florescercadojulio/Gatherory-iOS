import Foundation
import SwiftData
import Testing
@testable import Gatherory

@MainActor
struct EventRemovalTests {
    @Test("Only a draft main event offers deletion", arguments: MainEventStatus.allCases)
    func mainEventLifecycle(status: MainEventStatus) {
        let workspace = makeWorkspace(status: status)
        let action = workspace.eventRemovalAction(for: .main)
        #expect(action == (status == .draft ? .deleteDraftMainEvent : nil))
        let removed = workspace.removeEventFromHome(.main, expecting: .deleteDraftMainEvent)
        #expect(removed == (status == .draft))
        #expect(workspace.isMainEventDeleted == removed)
        #expect(workspace.eventRemovalAction(for: .main) == nil)
    }

    @Test("Sub-events leave Home by archiving, not losing their records", arguments: EventStatus.allCases)
    func archiveSubevent(status: EventStatus) throws {
        let workspace = makeWorkspace()
        let child = makeChild(in: workspace, status: status)
        workspace.timeline.append(child)
        workspace.selectEventContext(.subevent(child.id))
        let before = workspace.timeline.count
        let removed = workspace.removeEventFromHome(.subevent(child.id), expecting: .archiveSubevent)
        #expect(removed == (status != .archived))
        let archived = try #require(workspace.timeline.first { $0.id == child.id })
        #expect(archived.status == .archived)
        #expect(archived.budgetCap == child.budgetCap)
        #expect(archived.imageData == child.imageData)
        #expect(workspace.timeline.count == before)
        #expect(!workspace.visibleEventContexts.contains(.subevent(child.id)))
        if removed { #expect(workspace.selectedEventReference == .main) }
    }

    @Test("Archiving keeps completed sub-event history in an active workspace")
    func completedChild() throws {
        let workspace = makeWorkspace()
        var child = makeChild(in: workspace)
        child.completionStatus = .complete
        workspace.timeline.append(child)
        #expect(!workspace.canManageEvent(.subevent(child.id)))
        #expect(workspace.removeEventFromHome(.subevent(child.id), expecting: .archiveSubevent))
        #expect(workspace.timeline.first?.completionStatus == .complete)
    }

    @Test("Archiving keeps the child's ideas, expenses, and notes")
    func archiveKeepsPlanningRecords() {
        let workspace = makeWorkspace()
        let child = makeChild(in: workspace)
        workspace.timeline.append(child)
        var idea = PlanningIdea(title: "Music", note: "", category: .other, submittedBy: "Planner")
        idea.eventID = child.id
        workspace.addIdea(idea)
        let expense = EventExpense(eventID: child.id, title: "Dinner", amount: 200, status: .paid)
        workspace.replaceExpenses([expense], forEventID: child.id)
        let note = EventNote(eventID: child.id, body: "Directions")
        workspace.notes.append(note)
        #expect(workspace.removeEventFromHome(.subevent(child.id), expecting: .archiveSubevent))
        #expect(workspace.ideas.contains { $0.id == idea.id })
        #expect(workspace.eventExpenses.contains { $0.id == expense.id && $0.amount == 200 })
        #expect(workspace.notes.contains { $0.id == note.id })
    }

    @Test("Guests and read-only collaborators cannot remove shared events")
    func participantPermissions() {
        for (role, permission) in [
            (WorkspaceRole.guest, PlanningPermission.viewOnly),
            (.collaborator, .viewOnly)
        ] {
            let workspace = makeWorkspace(role: role, permission: permission)
            let child = makeChild(in: workspace)
            workspace.timeline.append(child)
            #expect(workspace.eventRemovalAction(for: .main) == nil)
            #expect(workspace.eventRemovalAction(for: .subevent(child.id)) == nil)
            #expect(!workspace.removeEventFromHome(.main, expecting: .deleteDraftMainEvent))
            #expect(!workspace.removeEventFromHome(.subevent(child.id), expecting: .archiveSubevent))
            #expect(!workspace.isMainEventDeleted)
            #expect(workspace.timeline.first?.status == .approved)
        }
    }

    @Test("Writable collaborators can remove events using the same lifecycle rules")
    func collaborator() {
        let workspace = makeWorkspace(role: .collaborator, permission: .contribute)
        let child = makeChild(in: workspace)
        workspace.timeline.append(child)
        #expect(workspace.eventRemovalAction(for: .main) == .deleteDraftMainEvent)
        #expect(workspace.removeEventFromHome(.subevent(child.id), expecting: .archiveSubevent))
    }

    @Test("A stale confirmation cannot delete an event after its status changes")
    func staleConfirmation() {
        let workspace = makeWorkspace()
        #expect(workspace.eventRemovalAction(for: .main) == .deleteDraftMainEvent)
        workspace.mainEventStatus = .ongoing
        #expect(!workspace.removeEventFromHome(.main, expecting: .deleteDraftMainEvent))
        #expect(!workspace.isMainEventDeleted)
        let child = makeChild(in: workspace)
        workspace.timeline.append(child)
        workspace.mainEventStatus = .finished
        #expect(!workspace.removeEventFromHome(.subevent(child.id), expecting: .archiveSubevent))
        #expect(workspace.timeline.first?.status == .approved)
    }

    @Test("Removal rejects missing events, idea references, and the wrong action")
    func invalidReferences() {
        let workspace = makeWorkspace()
        let child = makeChild(in: workspace)
        workspace.timeline.append(child)
        #expect(workspace.eventRemovalAction(for: .subevent(UUID())) == nil)
        #expect(workspace.eventRemovalAction(for: .idea(UUID())) == nil)
        #expect(!workspace.removeEventFromHome(.main, expecting: .archiveSubevent))
        #expect(!workspace.removeEventFromHome(.subevent(child.id), expecting: .deleteDraftMainEvent))
        #expect(workspace.timeline.first?.status == .approved)
        workspace.isInvitationProjection = true
        #expect(workspace.eventRemovalAction(for: .main) == nil)
        #expect(workspace.eventRemovalAction(for: .subevent(child.id)) == nil)
    }

    @Test("Home archival survives local restoration and queues its original event ID for sync")
    func archivePersistence() throws {
        let persistence = try WorkspacePersistenceController(isStoredInMemoryOnly: true)
        let library = persistence.restoreLibrary(seedData: false)
        let workspace = makeWorkspace()
        let child = makeChild(in: workspace)
        workspace.timeline.append(child)
        library.add(workspace)
        persistence.flush(library)
        #expect(workspace.removeEventFromHome(.subevent(child.id), expecting: .archiveSubevent))
        persistence.flush(library)
        #expect(persistence.lastError == nil)
        let restored = try #require(persistence.restoreLibrary(seedData: false).workspaces.first)
        #expect(restored.timeline.first?.id == child.id)
        #expect(restored.timeline.first?.status == .archived)
        #expect(!restored.visibleEventContexts.contains(.subevent(child.id)))
        let context = ModelContext(persistence.container)
        let pending = try context.fetch(FetchDescriptor<PendingMutation>())
        #expect(pending.contains { $0.entityType == .event && $0.entityID == child.id })
    }

    @Test("Draft main-event removal survives local restoration without deleting its workspace")
    func draftDeletionPersistence() throws {
        let persistence = try WorkspacePersistenceController(isStoredInMemoryOnly: true)
        let library = persistence.restoreLibrary(seedData: false)
        let workspace = makeWorkspace()
        workspace.timeline.append(makeChild(in: workspace))
        library.add(workspace)
        persistence.flush(library)
        #expect(workspace.removeEventFromHome(.main, expecting: .deleteDraftMainEvent))
        persistence.flush(library)
        #expect(persistence.lastError == nil)
        let restored = try #require(persistence.restoreLibrary(seedData: false).workspaces.first)
        #expect(restored.mainEventID == workspace.mainEventID)
        #expect(restored.isMainEventDeleted)
        #expect(restored.timeline.isEmpty)
        #expect(restored.eventRemovalAction(for: .main) == nil)
    }

    @Test("An archived event idea does not recreate its Home card after restoration")
    func archivedEventIdea() throws {
        let persistence = try WorkspacePersistenceController(isStoredInMemoryOnly: true)
        let library = persistence.restoreLibrary(seedData: false)
        let workspace = makeWorkspace()
        let idea = PlanningIdea(
            title: "Dinner", note: "", category: .event, submittedBy: "Planner",
            configuration: .event(EventIdeaConfiguration(
                category: .reception, purpose: .eventExperience,
                proposedDate: .now.addingTimeInterval(86_500), location: nil
            ))
        )
        workspace.addIdea(idea)
        workspace.updateIdea(idea, status: .chosen)
        let child = try #require(workspace.timeline.first { $0.linkedIdeaID == idea.id })
        library.add(workspace)
        #expect(workspace.removeEventFromHome(.subevent(child.id), expecting: .archiveSubevent))
        persistence.flush(library)
        let restored = try #require(persistence.restoreLibrary(seedData: false).workspaces.first)
        #expect(restored.timeline.filter { $0.linkedIdeaID == idea.id }.count == 1)
        #expect(restored.timeline.first { $0.id == child.id }?.status == .archived)
        #expect(!restored.visibleEventContexts.contains(.subevent(child.id)))
        #expect(restored.ideas.contains { $0.id == idea.id })
    }

    @Test("Restoring archived events preserves their original approval status", arguments: EventStatus.allCases.filter { $0 != .archived })
    func restoreStatus(status: EventStatus) throws {
        let workspace = makeWorkspace()
        let child = makeChild(in: workspace, status: status)
        workspace.timeline.append(child)
        #expect(workspace.removeEventFromHome(.subevent(child.id), expecting: .archiveSubevent))
        #expect(workspace.archivedChildEvents.count == 1)
        #expect(workspace.restoreArchivedEvent(child.id))
        #expect(workspace.timeline.first?.status == status)
        #expect(workspace.timeline.first?.statusBeforeArchiving == nil)
        #expect(workspace.archivedChildEvents.isEmpty)
        #expect(!workspace.restoreArchivedEvent(child.id))
    }

    @Test("Legacy archived events restore as drafts, not approved invitations")
    func restoreLegacyArchive() {
        let workspace = makeWorkspace()
        workspace.timeline.append(makeChild(in: workspace, status: .archived))
        #expect(workspace.restoreArchivedEvent(workspace.timeline[0].id))
        #expect(workspace.timeline[0].status == .draft)
    }

    @Test("Restoration preserves the saved status across relaunches")
    func restorePersistence() throws {
        let persistence = try WorkspacePersistenceController(isStoredInMemoryOnly: true)
        let library = persistence.restoreLibrary(seedData: false)
        let workspace = makeWorkspace()
        let child = makeChild(in: workspace, status: .rejected)
        workspace.timeline.append(child)
        library.add(workspace)
        #expect(workspace.removeEventFromHome(.subevent(child.id), expecting: .archiveSubevent))
        persistence.flush(library)
        let restored = try #require(persistence.restoreLibrary(seedData: false).workspaces.first)
        #expect(restored.timeline.first?.statusBeforeArchiving == .rejected)
        #expect(restored.restoreArchivedEvent(child.id))
        #expect(restored.timeline.first?.status == .rejected)
    }

    @Test("Restoration checks current permissions and lifecycle")
    func restorePermissions() {
        for (role, permission) in [(WorkspaceRole.guest, PlanningPermission.viewOnly), (.collaborator, .viewOnly)] {
            let workspace = makeWorkspace(role: role, permission: permission)
            let child = makeChild(in: workspace, status: .archived)
            workspace.timeline.append(child)
            #expect(!workspace.restoreArchivedEvent(child.id))
        }
        let workspace = makeWorkspace(status: .finished)
        let child = makeChild(in: workspace, status: .archived)
        workspace.timeline.append(child)
        #expect(!workspace.restoreArchivedEvent(child.id))
    }

    @Test("Undo works before the remaining decision queue is empty")
    func undoWhileQueuePopulated() {
        let workspace = makeWorkspace()
        let first = PlanningIdea(title: "First", note: "", category: .other, submittedBy: "Planner")
        let second = PlanningIdea(title: "Second", note: "", category: .other, submittedBy: "Planner")
        workspace.addIdea(first); workspace.addIdea(second)
        workspace.decide(.pass, on: first)
        #expect(workspace.canUndoDecision)
        workspace.undoLastDecision()
        #expect(workspace.ideas.first { $0.id == first.id }?.status == first.status)
        #expect(workspace.ideas.first { $0.id == second.id }?.status == second.status)
        #expect(!workspace.canUndoDecision)
    }

    @Test("Cancellation preserves records but closes planning, decisions, and photo additions")
    func cancellation() {
        let workspace = makeWorkspace(status: .ongoing)
        let child = makeChild(in: workspace)
        workspace.timeline.append(child)
        let idea = PlanningIdea(title: "Flowers", note: "", category: .other, submittedBy: "Planner")
        workspace.addIdea(idea)
        workspace.decide(.pass, on: idea)
        #expect(workspace.canUndoDecision)
        #expect(workspace.cancelEvent(.main))
        #expect(workspace.currentMainEventStatus == .cancelled)
        #expect(!workspace.canUndoDecision)
        workspace.undoLastDecision()
        workspace.decide(.love, on: idea)
        #expect(workspace.ideas.first?.status == .new)
        #expect(workspace.response(on: idea) == .pass)
        #expect(!workspace.canManageEvent(.subevent(child.id)))
        #expect(!workspace.canAddEventMoments(to: .subevent(child.id)))
        workspace.toggleTimelineItem(child)
        #expect(workspace.timeline.first?.completionStatus == child.completionStatus)
        #expect(workspace.timeline.count == 1)
        #expect(!workspace.cancelEvent(.main))
        #expect(!workspace.isMainEventDeleted)
    }

    @Test("Cancelling one sub-event does not close its parent or other sub-events")
    func cancelChild() {
        let workspace = makeWorkspace()
        let child = makeChild(in: workspace)
        let other = makeChild(in: workspace)
        workspace.timeline = [child, other]
        #expect(workspace.cancelEvent(.subevent(child.id)))
        #expect(workspace.timeline.first?.status == .cancelled)
        #expect(!workspace.canAddEventMoments(to: .subevent(child.id)))
        #expect(workspace.canManageEvent(.main))
        #expect(workspace.canManageEvent(.subevent(other.id)))
        #expect(workspace.canAddEventMoments(to: .subevent(other.id)))
    }

    @Test("Cancellation requires host or manage access and rechecks closed status")
    func cancelPermissions() {
        for (role, permission) in [(WorkspaceRole.guest, PlanningPermission.viewOnly), (.collaborator, .viewOnly), (.collaborator, .contribute)] {
            let workspace = makeWorkspace(role: role, permission: permission)
            #expect(!workspace.cancelEvent(.main))
            #expect(workspace.mainEventStatus == .draft)
        }
        let manager = makeWorkspace(role: .collaborator, permission: .manage)
        #expect(manager.cancelEvent(.main))
        let finished = makeWorkspace(status: .finished)
        #expect(!finished.cancelEvent(.main))
    }

    @Test("Cancelled lifecycle survives restoration without deleting its event")
    func cancellationPersistence() throws {
        let persistence = try WorkspacePersistenceController(isStoredInMemoryOnly: true)
        let library = persistence.restoreLibrary(seedData: false)
        let workspace = makeWorkspace()
        workspace.timeline.append(makeChild(in: workspace))
        library.add(workspace)
        #expect(workspace.cancelEvent(.main))
        persistence.flush(library)
        let restored = try #require(persistence.restoreLibrary(seedData: false).workspaces.first)
        #expect(restored.currentMainEventStatus == .cancelled)
        #expect(restored.timeline.count == 1)
        #expect(!restored.isMainEventDeleted)
    }

    private func makeWorkspace(
        status: MainEventStatus = .draft,
        role: WorkspaceRole = .host,
        permission: PlanningPermission = .manage
    ) -> PlanningWorkspace {
        PlanningWorkspace(
            title: "Removal test", mainEventStartsAt: .now.addingTimeInterval(86_400),
            venueName: "", location: "", planningMode: .openToIdeas,
            members: [WorkspaceMember(name: "Planner", participantRole: role, initials: "P", planningPermission: permission)],
            ideas: [], timeline: [], mainEventStatus: status, registry: []
        )
    }

    private func makeChild(in workspace: PlanningWorkspace, status: EventStatus = .approved) -> TimelineItem {
        TimelineItem(
            title: "Dinner", category: .other, scheduledAt: .now.addingTimeInterval(86_500),
            location: "", participantIDs: workspace.members.map(\.id),
            parentEventID: workspace.mainEventID, status: status,
            imageData: Data([0xFF, 0xD8, 0xFF, 0x01]), budgetCap: 100
        )
    }
}
