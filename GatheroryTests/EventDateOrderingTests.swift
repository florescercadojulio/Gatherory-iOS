import Foundation
import Testing
@testable import Gatherory

@MainActor
struct EventDateOrderingTests {
    private let now = Date(timeIntervalSince1970: 1_793_620_800) // Nov 2, 2026, noon UTC.

    @Test("Events browse today/upcoming before recent past and undated, independent of insertion order")
    func eventLibraryOrdersDatesWithoutMutatingLibrary() {
        let today = workspace("Today", offset: 0)
        let tomorrow = workspace("Tomorrow", offset: 1)
        let later = workspace("Later", offset: 7)
        let yesterday = workspace("Yesterday", offset: -1)
        let older = workspace("Older", offset: -10)
        let undated = workspace("Undated", offset: -100)
        undated.invitationDateIsUndecided = true
        let input = [older, later, undated, yesterday, tomorrow, today]
        let library = WorkspaceLibrary(workspaces: input)
        library.open(later)
        let ordered = WorkspaceFilter.all.workspaces(from: library.workspaces, for: nil, now: now)
        #expect(ordered.map(\.title) == ["Today", "Tomorrow", "Later", "Yesterday", "Older", "Undated"])
        #expect(library.workspaces.map(\.mainEventID) == input.map(\.mainEventID))
        #expect(library.selectedWorkspaceID == later.mainEventID)
        #expect(WorkspaceFilter.past.workspaces(from: [older, yesterday], for: nil, now: now).map(\.title)
            == ["Yesterday", "Older"])
    }

    @Test("Multi-day and all-day events ending today stay before future events")
    func eventsSpanningTodayAreNotPast() {
        let ongoing = workspace("Conference", offset: -2)
        ongoing.mainEventEndsAt = now.addingTimeInterval(86_400)
        let allDay = workspace("All day", offset: -1)
        allDay.mainEventIsAllDay = true
        allDay.mainEventEndsAt = Calendar(identifier: .gregorian).startOfDay(for: now)
        let next = workspace("Next", offset: 1)
        #expect(WorkspaceFilter.all.workspaces(from: [next, allDay, ongoing], for: nil, now: now).map(\.title)
            == ["Conference", "All day", "Next"])
    }

    @Test("Event-local dates and stable identities determine order at midnight and on ties")
    func localDatesAndStableTies() throws {
        let midnightUTC = try #require(ISO8601DateFormatter().date(from: "2026-11-02T03:00:00Z"))
        let localToday = workspace("Local today", offset: 0)
        localToday.mainEventTimeZoneIdentifier = "America/New_York"
        localToday.mainEventStartsAt = try #require(ISO8601DateFormatter().date(from: "2026-11-01T15:00:00Z"))
        #expect(EventDateOrdering.key(for: localToday, now: midnightUTC).period == 0)
        localToday.mainEventTimeZoneIdentifier = "UTC"
        #expect(EventDateOrdering.key(for: localToday, now: midnightUTC).period == 1)

        let first = workspace("First", offset: 1, id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!)
        let second = workspace("Second", offset: 1, id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!)
        #expect(WorkspaceFilter.all.workspaces(from: [second, first], for: nil, now: now).map(\.title)
            == ["First", "Second"])
    }

    @Test("Home date groups show today, future days, recent past, then undated and keep times chronological")
    func homeScheduleGroupsOrderDates() throws {
        let today = event("Today", offset: 0)
        let tomorrow = event("Tomorrow", offset: 1)
        let earlyTomorrow = event("Earlier tomorrow", offset: 1, hourOffset: -2)
        let yesterday = event("Yesterday", offset: -1)
        let older = event("Older", offset: -8)
        var undated = event("Undated", offset: -100)
        undated.schedulingState = .unscheduled
        let groups = HomeEventsOverviewDayGroup.groups(
            for: [older, tomorrow, undated, yesterday, today, earlyTomorrow], now: now
        )
        #expect(groups.map { $0.events.first!.title } == ["Today", "Earlier tomorrow", "Yesterday", "Older", "Undated"])
        #expect(groups[1].events.map(\.title) == ["Earlier tomorrow", "Tomorrow"])
        #expect(groups.last?.id == "unscheduled")
    }

    @Test("Home projection sorts visible children without changing selection or the stored schedule")
    func homeProjectionRetainsContextAndPermissions() {
        let root = workspace("Main event", offset: 30)
        let yesterday = event("Yesterday", offset: -1)
        let tomorrow = event("Tomorrow", offset: 1)
        let today = event("Today", offset: 0)
        for child in [yesterday, tomorrow, today] { root.addTimelineItem(child) }
        root.selectEventContext(.subevent(yesterday.id))
        let originalIDs = root.timeline.map(\.id)
        let projection = HomeEventsOverviewProjection(workspace: root, now: now)
        #expect(projection.mainEventIsVisible)
        #expect(projection.childEvents.map(\.title) == ["Today", "Tomorrow", "Yesterday"])
        #expect(root.timeline.map(\.id) == originalIDs)
        #expect(root.selectedEventReference == .subevent(yesterday.id))
    }

    private func workspace(_ title: String, offset: Int, id: UUID = UUID()) -> PlanningWorkspace {
        PlanningWorkspace(
            mainEventID: id, title: title, mainEventStartsAt: now.addingTimeInterval(Double(offset) * 86_400),
            mainEventTimeZoneIdentifier: "UTC", venueName: "", location: "", planningMode: .openToIdeas,
            members: [WorkspaceMember(name: "Host", participantRole: .host, initials: "H", planningPermission: .manage)],
            ideas: [], timeline: [], mainEventStatus: .ongoing, registry: []
        )
    }

    private func event(_ title: String, offset: Int, hourOffset: Int = 0) -> TimelineItem {
        TimelineItem(title: title, category: .other,
                     scheduledAt: now.addingTimeInterval(Double(offset) * 86_400 + Double(hourOffset) * 3_600),
                     timeZoneIdentifier: "UTC", participantIDs: [])
    }
}
