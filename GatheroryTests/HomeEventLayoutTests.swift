import Foundation
import Testing
@testable import Gatherory

@MainActor
struct HomeEventLayoutTests {
    @Test("Home layout uses stable preference values and falls back to Cards")
    func persistedValuesAndFallback() {
        #expect(HomeEventLayout.preferenceKey == "home.layout")
        #expect(HomeEventLayout.cards.id == "cards")
        #expect(HomeEventLayout.overview.id == "overview")
        #expect(HomeEventLayout(persistedValue: "cards") == .cards)
        #expect(HomeEventLayout(persistedValue: "overview") == .overview)
        #expect(HomeEventLayout(persistedValue: "unknown-layout") == .cards)
        #expect(HomeEventLayout(persistedValue: "") == .cards)
    }

    @Test("Home overview contexts preserve a guest's child-only invitation scope")
    func childOnlyGuestScopeHidesMainEvent() throws {
        let workspace = PlanningWorkspace.sample
        let guestIndex = try #require(workspace.members.firstIndex { $0.participantRole == .guest })
        let guest = workspace.members[guestIndex]
        let child = try #require(workspace.scheduledChildEvents.first)
        workspace.members[guestIndex].userID = "home-layout-child-guest"
        workspace.members[guestIndex].email = "home-layout-child-guest@gatherory.test"

        workspace.removeParticipant(guest.id, from: .main)
        workspace.addParticipant(guest.id, to: .subevent(child.id))
        workspace.configureViewer(UserAccount(
            id: "home-layout-child-guest",
            email: "home-layout-child-guest@gatherory.test",
            displayName: guest.name,
            role: .member,
            authenticationProvider: .password,
            createdAt: .now
        ))

        #expect(workspace.visibleEventContexts == [.subevent(child.id)])
        #expect(!workspace.visibleEventContexts.contains(.main))

        let projection = HomeEventsOverviewProjection(workspace: workspace)
        #expect(!projection.mainEventIsVisible)
        #expect(projection.childEvents.map(\.id) == [child.id])
        #expect(HomeEventsOverviewDayGroup.groups(for: projection.childEvents)
            .flatMap(\.events).map(\.id) == [child.id])

        let childPresentation = HomeEventContextPresentation(
            kind: .subevent,
            statusTitle: "Upcoming",
            statusSymbol: "calendar"
        )
        #expect(childPresentation.parentContextTitle(
            mainEventTitle: workspace.title,
            mainEventIsVisible: workspace.visibleEventContexts.contains(.main)
        ) == nil)
    }

    @Test("Home overview shows only the main invitation when a guest has no child scope")
    func mainOnlyGuestScope() throws {
        let workspace = PlanningWorkspace.sample
        let guestIndex = try #require(workspace.members.firstIndex { $0.participantRole == .guest })
        workspace.members[guestIndex].userID = "home-layout-main-guest"
        workspace.members[guestIndex].email = "home-layout-main-guest@gatherory.test"
        workspace.configureViewer(UserAccount(
            id: "home-layout-main-guest",
            email: "home-layout-main-guest@gatherory.test",
            displayName: workspace.members[guestIndex].name,
            role: .member,
            authenticationProvider: .password,
            createdAt: .now
        ))

        #expect(workspace.visibleEventContexts == [.main])
        let projection = HomeEventsOverviewProjection(workspace: workspace)
        #expect(projection.mainEventIsVisible)
        #expect(projection.childEvents.isEmpty)
    }

    @Test("Home overview excludes archived children")
    func archivedChildIsExcluded() throws {
        let workspace = PlanningWorkspace.sample
        let archivedChild = try #require(workspace.scheduledChildEvents.first)
        let timelineIndex = try #require(workspace.timeline.firstIndex { $0.id == archivedChild.id })
        workspace.timeline[timelineIndex].status = .archived

        let projection = HomeEventsOverviewProjection(workspace: workspace)
        #expect(!projection.childEvents.contains { $0.id == archivedChild.id })
    }

    @Test("Adding an event idea does not add an overview schedule row")
    func ideasDoNotBecomeOverviewRows() {
        let workspace = PlanningWorkspace.sample
        let initialProjection = HomeEventsOverviewProjection(workspace: workspace)
        let initialChildIDs = initialProjection.childEvents.map(\.id)

        workspace.addIdea(PlanningIdea(
            title: "A new event proposal",
            note: "An undecided idea should stay in Ideas.",
            category: .event,
            submittedBy: "Alex"
        ))

        let updatedProjection = HomeEventsOverviewProjection(workspace: workspace)
        #expect(updatedProjection.mainEventIsVisible == initialProjection.mainEventIsVisible)
        #expect(updatedProjection.childEvents.map(\.id) == initialChildIDs)
        #expect(!updatedProjection.childEvents.contains { $0.title == "A new event proposal" })
    }

    @Test("Deleting the main event empties Home overview")
    func deletedMainEventHasEmptyProjection() {
        let workspace = PlanningWorkspace.sample
        workspace.deleteMainEvent()

        let projection = HomeEventsOverviewProjection(workspace: workspace)
        #expect(!projection.mainEventIsVisible)
        #expect(projection.childEvents.isEmpty)
    }

    @Test("Overview day groups use event-local dates across time zones")
    func localCalendarDatesGroupAcrossTimeZones() throws {
        let newYorkLate = try timelineEvent(
            id: "00000000-0000-0000-0000-000000000001",
            title: "New York evening",
            startsAt: "2026-03-02T01:00:00Z",
            timeZone: "America/New_York"
        )
        let losAngelesLate = try timelineEvent(
            id: "00000000-0000-0000-0000-000000000002",
            title: "Los Angeles evening",
            startsAt: "2026-03-02T06:00:00Z",
            timeZone: "America/Los_Angeles"
        )
        let newYorkAfterMidnight = try timelineEvent(
            id: "00000000-0000-0000-0000-000000000003",
            title: "New York after midnight",
            startsAt: "2026-03-02T07:00:00Z",
            timeZone: "America/New_York"
        )

        let groups = HomeEventsOverviewDayGroup.groups(for: [
            newYorkAfterMidnight, losAngelesLate, newYorkLate
        ])

        #expect(groups.map(\.id) == ["2026-03-01", "2026-03-02"])
        #expect(groups[0].events.map(\.title) == ["New York evening", "Los Angeles evening"])
        #expect(groups[1].events.map(\.title) == ["New York after midnight"])
        #expect(groups[0].title != groups[0].id)
    }

    @Test("Overview day events sort by time then stable UUID")
    func eventsSortChronologicallyWithStableTies() throws {
        let late = try timelineEvent(
            id: "00000000-0000-0000-0000-000000000002",
            title: "Later",
            startsAt: "2026-05-15T12:00:00Z",
            timeZone: "UTC"
        )
        let tieLaterID = try timelineEvent(
            id: "00000000-0000-0000-0000-000000000003",
            title: "Earlier tie, later ID",
            startsAt: "2026-05-15T10:00:00Z",
            timeZone: "UTC"
        )
        let tieEarlierID = try timelineEvent(
            id: "00000000-0000-0000-0000-000000000001",
            title: "Earlier tie, earlier ID",
            startsAt: "2026-05-15T10:00:00Z",
            timeZone: "UTC"
        )

        let groups = HomeEventsOverviewDayGroup.groups(for: [late, tieLaterID, tieEarlierID])

        #expect(groups.count == 1)
        #expect(groups[0].events.map(\.id) == [tieEarlierID.id, tieLaterID.id, late.id])
    }

    @Test("Overview places undated events in a final group without a fabricated date")
    func unscheduledEventsHaveFinalUndatedGroup() throws {
        let unscheduled = try timelineEvent(
            id: "00000000-0000-0000-0000-000000000002",
            title: "Needs a date",
            startsAt: "2000-01-01T00:00:00Z",
            timeZone: "UTC",
            isScheduled: false
        )
        let scheduled = try timelineEvent(
            id: "00000000-0000-0000-0000-000000000001",
            title: "Scheduled",
            startsAt: "2026-05-15T12:00:00Z",
            timeZone: "UTC"
        )

        let groups = HomeEventsOverviewDayGroup.groups(for: [unscheduled, scheduled])
        let undatedGroup = try #require(groups.last)

        #expect(groups.map(\.id) == ["2026-05-15", "unscheduled"])
        #expect(undatedGroup.title == String(localized: "Date to be decided"))
        #expect(undatedGroup.events.map(\.id) == [unscheduled.id])
        #expect(!undatedGroup.title.contains("2000"))
    }

    private func timelineEvent(
        id: String,
        title: String,
        startsAt: String,
        timeZone: String,
        isScheduled: Bool = true
    ) throws -> TimelineItem {
        let uuid = try #require(UUID(uuidString: id))
        let date = try #require(ISO8601DateFormatter().date(from: startsAt))
        return TimelineItem(
            id: uuid,
            title: title,
            category: .other,
            scheduledAt: date,
            schedulingState: isScheduled ? .scheduled : .unscheduled,
            location: "",
            timeZoneIdentifier: timeZone,
            participantIDs: []
        )
    }
}
