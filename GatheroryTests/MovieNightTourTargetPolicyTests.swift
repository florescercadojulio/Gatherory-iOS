import Foundation
import Testing
@testable import Gatherory

struct MovieNightTourTargetPolicyTests {
    @Test("Intro and Ideas point to Decide until the snack decision is visible")
    func decideRouting() {
        let snackID = UUID()
        #expect(target(.previewUsed, tab: .home) == .decideTab)
        #expect(target(.previewUsed, tab: .ideas) == .decideTab)
        #expect(target(.previewUsed, tab: .decide) == nil)
        #expect(target(.ideas, tab: .home) == .decideTab)
        #expect(target(.ideas, tab: .ideas) == .decideTab)
        #expect(target(.ideas, tab: .decide, snackID: snackID) == .decision(snackID))
        #expect(target(.ideas, tab: .decide) == nil)
    }

    @Test("Love It and approval point to Ideas, then the filter or exact idea")
    func ideasRouting() {
        let snackID = UUID()
        let eventID = UUID()
        #expect(target(.loveIt, tab: .home) == .ideasTab)
        #expect(target(.loveIt, tab: .decide) == .ideasTab)
        #expect(target(.loveIt, tab: .ideas, filter: IdeaFilter.all.rawValue) == .ideasFilter)
        #expect(target(.loveIt, tab: .ideas, filter: IdeaFilter.liked.rawValue, snackID: snackID) == .idea(snackID))
        #expect(target(.approve, tab: .home) == .ideasTab)
        #expect(target(.approve, tab: .decide) == .ideasTab)
        #expect(target(.approve, tab: .ideas, filter: IdeaFilter.liked.rawValue) == .ideasFilter)
        #expect(target(.approve, tab: .ideas, filter: IdeaFilter.all.rawValue, eventID: eventID) == .idea(eventID))
        #expect(target(.approve, tab: .ideas, filter: IdeaFilter.all.rawValue) == nil)
    }

    @Test("Schedule points to Home only when another tab is selected")
    func scheduleRouting() {
        #expect(target(.schedule, tab: .ideas) == .homeTab)
        #expect(target(.schedule, tab: .decide) == .homeTab)
        #expect(target(.schedule, tab: .home) == nil)
        #expect(target(.completed, tab: .home) == nil)
    }

    @Test("Reviewing earlier instructions does not point at current controls")
    func earlierReviewHasNoTarget() {
        for step in [MovieNightTourStep.previewUsed, .ideas, .loveIt, .approve, .schedule] {
            #expect(target(step, tab: .home, reviewingEarlier: true) == nil)
        }
    }

    private func target(
        _ step: MovieNightTourStep,
        tab: WorkspaceTab,
        filter: String? = nil,
        snackID: UUID? = nil,
        eventID: UUID? = nil,
        reviewingEarlier: Bool = false
    ) -> MovieNightTourTarget? {
        MovieNightTourTargetPolicy.target(
            for: step,
            selectedTab: tab,
            ideasFilter: filter,
            snackIdeaID: snackID,
            eventIdeaID: eventID,
            isReviewingEarlier: reviewingEarlier
        )
    }
}
