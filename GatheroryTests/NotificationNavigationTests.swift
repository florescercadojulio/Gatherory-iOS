import Foundation
import Testing
@testable import Gatherory

@MainActor
struct NotificationNavigationTests {
    @Test("Notification navigation requires an exact active event and never follows URLs")
    func eventAccess() {
        let workspace = makeWorkspace()
        let event = workspace.mainEventID
        #expect(AuthorizedNotificationDestination.resolve(.event(id: event.uuidString), workspaces: [workspace],
            attendanceEventIDs: []) == .planning(workspaceID: event, reference: .main, todoID: nil))
        #expect(AuthorizedNotificationDestination.resolve(.event(id: UUID().uuidString), workspaces: [workspace],
            attendanceEventIDs: []) == nil)
        #expect(AuthorizedNotificationDestination.resolve(.event(id: "https://example.test/event"), workspaces: [workspace],
            attendanceEventIDs: []) == nil)
        workspace.configureViewer(account(id: "another-account"))
        #expect(AuthorizedNotificationDestination.resolve(.event(id: event.uuidString), workspaces: [workspace],
            attendanceEventIDs: []) == nil)
    }

    @Test("Assignment taps require the unfinished task to remain assigned to this viewer")
    func assignmentAccess() throws {
        let workspace = makeWorkspace()
        let task = try #require(workspace.addTodo(title: "Confirm the cake",
            assigneePersonID: workspace.members[0].id, to: .main))
        let intent = NotificationRouteIntent.todo(eventID: workspace.mainEventID.uuidString, todoID: task.id.uuidString)
        #expect(AuthorizedNotificationDestination.resolve(intent, workspaces: [workspace], attendanceEventIDs: []) != nil)
        #expect(workspace.setTodoCompleted(id: task.id, isCompleted: true))
        #expect(AuthorizedNotificationDestination.resolve(intent, workspaces: [workspace], attendanceEventIDs: []) == nil)
        #expect(workspace.setTodoCompleted(id: task.id, isCompleted: false))
        #expect(workspace.assignTodo(id: task.id, assigneePersonID: nil))
        #expect(AuthorizedNotificationDestination.resolve(intent, workspaces: [workspace], attendanceEventIDs: []) == nil)
    }

    @Test("Attendance notifications cannot open planner tasks or unrelated events")
    func attendanceAccess() {
        let event = UUID()
        #expect(AuthorizedNotificationDestination.resolve(.event(id: event.uuidString), workspaces: [],
            attendanceEventIDs: [event]) == .attendance(eventID: event))
        #expect(AuthorizedNotificationDestination.resolve(.todo(eventID: event.uuidString, todoID: UUID().uuidString),
            workspaces: [], attendanceEventIDs: [event]) == nil)
        #expect(AuthorizedNotificationDestination.resolve(.event(id: UUID().uuidString), workspaces: [],
            attendanceEventIDs: [event]) == nil)
    }

    @Test("Local guest plans are never notification-authorized server plans")
    func localGuestPlans() {
        let workspace = makeWorkspace()
        workspace.configureLocalGuestViewer(LocalGuestProfile(displayName: "Morgan"))
        #expect(AuthorizedNotificationDestination.resolve(.event(id: workspace.mainEventID.uuidString),
            workspaces: [workspace], attendanceEventIDs: []) == nil)
    }

    @Test("Announcement taps open only an accessible exact event and never imply planning rights")
    func announcementAccess() {
        let workspace = makeWorkspace()
        let announcement = UUID()
        let intent = NotificationRouteIntent.announcement(eventID: workspace.mainEventID.uuidString,
                                                         announcementID: announcement.uuidString)
        #expect(AuthorizedNotificationDestination.resolve(intent, workspaces: [workspace], attendanceEventIDs: []) ==
            .announcement(workspaceID: workspace.mainEventID, reference: .main, announcementID: announcement))
        #expect(AuthorizedNotificationDestination.resolve(intent, workspaces: [],
            attendanceEventIDs: [workspace.mainEventID]) ==
            .attendanceAnnouncement(eventID: workspace.mainEventID, announcementID: announcement))
        #expect(AuthorizedNotificationDestination.resolve(intent, workspaces: [], attendanceEventIDs: []) == nil)
        #expect(AuthorizedNotificationDestination.resolve(
            .announcement(eventID: UUID().uuidString, announcementID: announcement.uuidString),
            workspaces: [workspace], attendanceEventIDs: [workspace.mainEventID]) == nil)
        #expect(AuthorizedNotificationDestination.resolve(
            .announcement(eventID: workspace.mainEventID.uuidString, announcementID: "../private"),
            workspaces: [workspace], attendanceEventIDs: [workspace.mainEventID]) == nil)
        workspace.configureViewer(account(id: "another-account"))
        #expect(AuthorizedNotificationDestination.resolve(intent, workspaces: [workspace], attendanceEventIDs: []) == nil)
        workspace.configureLocalGuestViewer(LocalGuestProfile(displayName: "Local planner"))
        #expect(AuthorizedNotificationDestination.resolve(intent, workspaces: [workspace], attendanceEventIDs: []) == nil)
    }

    private func account(id: String = "notification-planner") -> UserAccount {
        UserAccount(id: id, email: "planner@example.test", displayName: "Planner", role: .planner,
                    authenticationProvider: .password, createdAt: .now)
    }

    private func makeWorkspace() -> PlanningWorkspace {
        let id = UUID()
        let member = WorkspaceMember(userID: "notification-planner", name: "Planner", participantRole: .host,
                                     initials: "P", planningPermission: .manage)
        let workspace = PlanningWorkspace(mainEventID: id, title: "Event", mainEventStartsAt: .now,
            venueName: "", location: "", planningMode: .openToIdeas, members: [member],
            eventParticipations: [EventParticipation(eventID: id, memberID: member.id, role: .host,
                planningPermission: .manage, attendance: .going, invitationStatus: .active)],
            mainEventParticipantIDs: [member.id], ideas: [], timeline: [], registry: [])
        workspace.configureViewer(account())
        return workspace
    }
}
