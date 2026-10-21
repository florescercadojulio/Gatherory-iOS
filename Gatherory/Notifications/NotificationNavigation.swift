import Foundation
import Observation

struct NotificationPlanningDestination: Identifiable, Hashable {
    let id = UUID()
    let workspaceID: UUID
    let reference: EventReference
    let todoID: UUID?
    var announcementID: UUID? = nil
}

struct NotificationAttendanceAnnouncementDestination: Identifiable, Hashable {
    let eventID: UUID
    let announcementID: UUID
    var id: UUID { announcementID }
}

@Observable @MainActor
final class NotificationNavigationState {
    var destination: NotificationPlanningDestination?
    var attendanceAnnouncement: NotificationAttendanceAnnouncementDestination?
}

enum AuthorizedNotificationDestination: Equatable {
    case planning(workspaceID: UUID, reference: EventReference, todoID: UUID?)
    case attendance(eventID: UUID)
    case announcement(workspaceID: UUID, reference: EventReference, announcementID: UUID)
    case attendanceAnnouncement(eventID: UUID, announcementID: UUID)

    /// Call only after a successful refresh using the current principal.
    /// The payload is a hint; the canonical event and task decide what opens.
    @MainActor
    static func resolve(_ intent: NotificationRouteIntent, workspaces: [PlanningWorkspace],
                        attendanceEventIDs: Set<UUID>) -> Self? {
        let eventID: UUID
        let todoID: UUID?
        var announcementID: UUID?
        switch intent {
        case .event(let id):
            guard let id = UUID(uuidString: id) else { return nil }
            eventID = id
            todoID = nil
        case .todo(let id, let task):
            guard let id = UUID(uuidString: id), let task = UUID(uuidString: task) else { return nil }
            eventID = id
            todoID = task
        case .announcement(let id, let announcement):
            guard let id = UUID(uuidString: id), let announcement = UUID(uuidString: announcement) else { return nil }
            eventID = id
            todoID = nil
            announcementID = announcement
        }
        for workspace in workspaces where !workspace.isMainEventDeleted && !workspace.isLocalGuestViewer {
            let reference: EventReference = workspace.mainEventID == eventID ? .main : .subevent(eventID)
            guard workspace.visibleEventContexts.contains(reference),
                  let viewer = workspace.currentViewerMember(for: reference),
                  viewer.invitationStatus == .active else { continue }
            if let todoID {
                guard workspace.canReadTodos(for: reference),
                      workspace.todos(for: reference).contains(where: {
                          $0.id == todoID && !$0.isCompleted && $0.assigneePersonID == viewer.id
                      }) else { return nil }
            }
            if let announcementID {
                return .announcement(workspaceID: workspace.mainEventID, reference: reference, announcementID: announcementID)
            }
            return .planning(workspaceID: workspace.mainEventID, reference: reference, todoID: todoID)
        }
        if let announcementID, attendanceEventIDs.contains(eventID) {
            return .attendanceAnnouncement(eventID: eventID, announcementID: announcementID)
        }
        if todoID == nil, attendanceEventIDs.contains(eventID) { return .attendance(eventID: eventID) }
        return nil
    }
}
