import Foundation
import Testing
@testable import Gatherory

@MainActor
struct ManageNoteHistoryTests {
    @Test("History isolates main and child notes and treats legacy nil event IDs as main")
    func eventIsolationAndLegacyMainNotes() throws {
        let workspace = makeWorkspace()
        let child = makeChild(parentEventID: workspace.mainEventID)
        workspace.timeline = [child]
        workspace.addParticipant(workspace.members[0].id, to: .subevent(child.id))
        let earlier = Date(timeIntervalSince1970: 1_700_000_000)
        let later = earlier.addingTimeInterval(60)
        let mainOld = EventNote(eventID: workspace.mainEventID, body: "Main old", sentAt: earlier)
        let mainLatest = EventNote(eventID: nil, body: "Legacy main", sentAt: later)
        let childNote = EventNote(eventID: child.id, body: "Child", sentAt: later)
        workspace.notes = [mainOld, childNote, mainLatest]

        let mainNotes = ManageNoteHistory.notes(in: workspace, reference: .main, isBlocked: { _ in false })
        let childNotes = ManageNoteHistory.notes(in: workspace, reference: .subevent(child.id), isBlocked: { _ in false })

        #expect(mainNotes.map(\.body) == ["Legacy main", "Main old"])
        #expect(childNotes.map(\.body) == ["Child"])
    }

    @Test("History excludes blocked authors and keeps equal timestamps stable")
    func blockedAuthorsAndStableOrdering() {
        let workspace = makeWorkspace()
        let sameTime = Date(timeIntervalSince1970: 1_700_000_000)
        let first = EventNote(authorUserID: "visible", body: "First", sentAt: sameTime)
        let blocked = EventNote(authorUserID: "blocked", body: "Hidden", sentAt: sameTime.addingTimeInterval(30))
        let second = EventNote(authorUserID: "visible", body: "Second", sentAt: sameTime)
        workspace.notes = [first, blocked, second]

        let result = ManageNoteHistory.notes(in: workspace, reference: .main) { $0 == "blocked" }

        #expect(result.map(\.body) == ["First", "Second"])
    }

    @Test("Valid read-only planners can read history, while guests cannot")
    func readPermissionAndGuestIsolation() {
        let reader = makeWorkspace(role: .collaborator, permission: .viewOnly)
        let note = EventNote(body: "Visible to planner")
        reader.notes = [note]
        #expect(ManageEventSummary(workspace: reader, reference: .main) != nil)
        #expect(ManageNoteHistory.notes(in: reader, reference: .main, isBlocked: { _ in false }) == [note])

        let guest = makeWorkspace(role: .guest, permission: .viewOnly)
        guest.notes = [note]
        #expect(ManageEventSummary(workspace: guest, reference: .main) == nil)
        #expect(ManageNoteHistory.notes(in: guest, reference: .main, isBlocked: { _ in false }).isEmpty)
    }

    @Test("Invalid and out-of-scope references return no note history")
    func invalidReferencesDoNotLeak() {
        let scoped = makeWorkspace(isScoped: true)
        let sibling = makeChild(parentEventID: scoped.mainEventID)
        scoped.timeline = [sibling]
        scoped.notes = [EventNote(eventID: sibling.id, body: "Sibling secret")]

        #expect(ManageNoteHistory.notes(in: scoped, reference: .subevent(sibling.id), isBlocked: { _ in false }).isEmpty)
        #expect(ManageNoteHistory.notes(in: scoped, reference: .idea(UUID()), isBlocked: { _ in false }).isEmpty)
        #expect(ManageNoteHistory.notes(in: scoped, reference: .subevent(UUID()), isBlocked: { _ in false }).isEmpty)
    }

    private func makeWorkspace(
        isScoped: Bool = false,
        role: WorkspaceRole = .host,
        permission: PlanningPermission = .manage
    ) -> PlanningWorkspace {
        let userID = "note-history-user"
        let member = WorkspaceMember(userID: userID, name: "Planner", participantRole: role,
                                     initials: "P", planningPermission: permission)
        let workspace = PlanningWorkspace(
            isScopedEvent: isScoped,
            title: "Weekend",
            mainEventStartsAt: .now,
            venueName: "Venue",
            location: "Address",
            planningMode: .openToIdeas,
            members: [member],
            ideas: [],
            timeline: [],
            registry: []
        )
        workspace.configureViewer(UserAccount(id: userID, email: "planner@example.test",
                                              displayName: member.name, role: .planner,
                                              authenticationProvider: .password, createdAt: .now))
        return workspace
    }

    private func makeChild(parentEventID: UUID) -> TimelineItem {
        TimelineItem(title: "Dinner", category: .other, scheduledAt: .now, location: "",
                     participantIDs: [], parentEventID: parentEventID, status: .approved)
    }
}
