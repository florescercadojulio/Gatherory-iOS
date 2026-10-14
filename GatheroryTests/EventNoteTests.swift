import Foundation
import SwiftData
import Testing
@testable import Gatherory

@MainActor
struct EventNoteTests {
    private func workspace(role: WorkspaceRole = .host, permission: PlanningPermission = .manage) -> PlanningWorkspace {
        let workspace = PlanningWorkspace(title: "Note test", mainEventStartsAt: .now.addingTimeInterval(86_400),
            venueName: "", location: "", planningMode: .openToIdeas,
            members: [WorkspaceMember(userID: "note-author", name: "Author", participantRole: role,
                initials: "A", planningPermission: permission)],
            ideas: [], timeline: [], mainEventStatus: .draft, registry: [])
        workspace.timeline.append(TimelineItem(title: "Dinner", category: .other,
            scheduledAt: .now.addingTimeInterval(86_500), location: "",
            participantIDs: workspace.members.map(\.id), parentEventID: workspace.mainEventID, status: .approved))
        workspace.configureViewer(UserAccount(id: "note-author", email: "note@example.test",
            displayName: "Author", role: .planner, authenticationProvider: .password, createdAt: .now))
        return workspace
    }

    @Test("A note retains its explicit event and signed-in author when selection changes")
    func targetAndAuthor() throws {
        let workspace = workspace()
        let child = try #require(workspace.childEvents.first)
        workspace.selectEventContext(.subevent(child.id))
        let note = try #require(workspace.sendNote("  Bring an umbrella.\n", to: .main))
        #expect(note.eventID == workspace.mainEventID)
        #expect(note.authorUserID == "note-author")
        #expect(note.body == "Bring an umbrella.")
        #expect(!workspace.contextualNotes.contains { $0.id == note.id })
    }

    @Test("Notes reject blank and oversized text without truncating Unicode")
    func validation() throws {
        let workspace = workspace()
        let count = workspace.notes.count
        #expect(workspace.sendNote(" \n ") == nil)
        #expect(workspace.sendNote(String(repeating: "a", count: 751)) == nil)
        #expect(workspace.sendNote(String(repeating: "🎉", count: 376)) == nil)
        #expect(workspace.notes.count == count)
        let body = String(repeating: "🎉", count: 375)
        #expect(try #require(workspace.sendNote(body)).body == body)
    }

    @Test("Guests, view-only members, signed-out viewers and finished events cannot send")
    func permissions() {
        #expect(workspace(role: .guest).sendNote("No") == nil)
        #expect(workspace(role: .collaborator, permission: .viewOnly).sendNote("No") == nil)
        #expect(workspace(role: .collaborator, permission: .contribute).sendNote("Yes") != nil)
        let finished = workspace()
        finished.mainEventStatus = .finished
        #expect(finished.sendNote("No") == nil)
        let signedOut = workspace()
        signedOut.configureViewer(nil)
        #expect(signedOut.sendNote("No") == nil)
    }

    @Test("A saved note survives reopening and creates one authored sync payload")
    func durableNote() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "NoteTests-\(UUID())", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: "Notes.store")
        let persistence = try WorkspacePersistenceController(storeURL: url)
        let library = persistence.restoreLibrary(seedData: false)
        let workspace = workspace()
        library.add(workspace)
        let note = try #require(workspace.sendNote("Meet at the entrance.", to: .main))
        try persistence.saveChanges(in: library)
        try persistence.saveChanges(in: library)
        let reopened = try WorkspacePersistenceController(storeURL: url)
        let restored = try #require(reopened.restoreLibrary(seedData: false).workspaces.first)
        #expect(restored.notes.contains(note))
        let mutations = try ModelContext(reopened.container).fetch(FetchDescriptor<PendingMutation>())
        #expect(mutations.filter { $0.entityID == note.id }.count == 1)
        let mutation = try #require(mutations.first { $0.entityID == note.id })
        #expect(try JSONDecoder().decode(EventNote.self, from: mutation.payload) == note)
    }
}
