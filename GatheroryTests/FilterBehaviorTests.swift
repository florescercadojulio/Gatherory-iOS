import Foundation
import Testing
@testable import Gatherory

struct FilterBehaviorTests {
    @Test("Idea filters expose every status")
    func ideaFiltersCoverEveryStatus() {
        let ideas = IdeaStatus.allCases.map { status in
            PlanningIdea(
                title: status.title,
                note: "",
                category: .other,
                submittedBy: "Planner",
                status: status
            )
        }

        #expect(ideas.filter(IdeaFilter.all.includes).map(\.status).contains(.passed))
        #expect(!ideas.filter(IdeaFilter.all.includes).map(\.status).contains(.archived))
        #expect(ideas.filter(IdeaFilter.inbox.includes).map(\.status) == [.new])
        #expect(Set(ideas.filter(IdeaFilter.saved.includes).map(\.status)) == [.maybe, .shortlisted])
        #expect(ideas.filter(IdeaFilter.approved.includes).map(\.status) == [.chosen])
        #expect(ideas.filter(IdeaFilter.passed.includes).map(\.status) == [.passed])
        #expect(ideas.filter(IdeaFilter.archived.includes).map(\.status) == [.archived])
    }

    @Test("Timeline filters separate completion from archive status")
    func timelineFiltersUseTheRightState() {
        let upcoming = makeEvent(status: .draft, completion: .upcoming)
        let completed = makeEvent(status: .approved, completion: .complete)
        let archived = makeEvent(status: .archived, completion: .upcoming)
        let needsDate = makeEvent(
            status: .approved,
            completion: .upcoming,
            schedulingState: .unscheduled
        )
        let events = [upcoming, completed, archived, needsDate]

        #expect(events.filter(TimelineFilter.all.includes).map(\.id) == [upcoming.id, completed.id, needsDate.id])
        #expect(events.filter(TimelineFilter.needsDate.includes).map(\.id) == [needsDate.id])
        #expect(events.filter(TimelineFilter.upcoming.includes).map(\.id) == [upcoming.id])
        #expect(events.filter(TimelineFilter.completed.includes).map(\.id) == [completed.id])
        #expect(events.filter(TimelineFilter.archived.includes).map(\.id) == [archived.id])
    }

    @Test("Partially reserved registry items remain available and appear as reserved")
    func registryFiltersHandlePartialReservations() {
        let untouched = makeRegistryItem(quantity: 2, committed: 0)
        let partial = makeRegistryItem(quantity: 2, committed: 1)
        let fulfilled = makeRegistryItem(quantity: 2, committed: 2)
        let items = [untouched, partial, fulfilled]

        #expect(items.filter(RegistryCollection.available.includes).map(\.id) == [untouched.id, partial.id])
        #expect(items.filter(RegistryCollection.reserved.includes).map(\.id) == [partial.id, fulfilled.id])
    }

    private func makeEvent(
        status: EventStatus,
        completion: EventCompletionStatus,
        schedulingState: EventSchedulingState = .scheduled
    ) -> TimelineItem {
        TimelineItem(
            title: "Event",
            category: .other,
            scheduledAt: .now,
            schedulingState: schedulingState,
            location: "",
            participantIDs: [],
            status: status,
            completionStatus: completion
        )
    }

    private func makeRegistryItem(quantity: Int, committed: Int) -> RegistryItem {
        RegistryItem(
            title: "Gift",
            note: "",
            category: .home,
            price: 10,
            quantity: quantity,
            committedCount: committed
        )
    }
}
