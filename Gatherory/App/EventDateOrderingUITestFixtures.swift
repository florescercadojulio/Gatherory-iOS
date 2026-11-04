#if DEBUG
import Foundation

@MainActor
enum EventDateOrderingUITestFixtures {
    static var isEnabled: Bool {
        let arguments = ProcessInfo.processInfo.arguments
        return arguments.contains("-EventDateOrderingUITest")
            && arguments.contains("-UseEphemeralDataStore")
            && arguments.contains("-SkipAuthentication")
    }

    static func makeLibrary() -> WorkspaceLibrary {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Detroit")!
        let today = calendar.startOfDay(for: .now)
        func date(_ day: Int, hour: Int = 12) -> Date {
            calendar.date(byAdding: .hour, value: hour,
                          to: calendar.date(byAdding: .day, value: day, to: today)!)!
        }
        func workspace(_ title: String, day: Int) -> PlanningWorkspace {
            PlanningWorkspace.newWorkspace(
                title: title, startsAt: date(day), timeZoneIdentifier: calendar.timeZone.identifier,
                eventLocation: nil, imageData: nil, owner: DevelopmentAccountFixtures.planner
            )
        }
        let next = workspace("Next gathering", day: 1)
        for (title, day, hour) in [
            ("Old session", -7, 10), ("Tomorrow session", 1, 11),
            ("Today session", 0, 12), ("Yesterday session", -1, 10),
            ("Later session", 3, 10), ("Morning session", 1, 9)
        ] {
            next.addTimelineItem(TimelineItem(
                title: title, category: .other, scheduledAt: date(day, hour: hour),
                timeZoneIdentifier: calendar.timeZone.identifier,
                participantIDs: next.mainEventParticipantIDs, parentEventID: next.mainEventID
            ))
        }
        return WorkspaceLibrary(workspaces: [
            workspace("Older gathering", day: -30), workspace("Later gathering", day: 14),
            workspace("Recent gathering", day: -3), next
        ])
    }
}
#endif
