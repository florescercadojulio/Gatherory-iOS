import Testing
@testable import Gatherory

@MainActor
struct MovieNightTourNavigationPolicyTests {
    @Test("Previous browses through earlier instructions without changing actual progress")
    func previousAndBoundedBrowsing() {
        #expect(MovieNightTourNavigationPolicy.previousStep(from: .previewUsed) == nil)
        #expect(MovieNightTourNavigationPolicy.previousStep(from: .ideas) == .previewUsed)
        #expect(MovieNightTourNavigationPolicy.previousStep(from: .loveIt) == .ideas)
        #expect(MovieNightTourNavigationPolicy.previousStep(from: .approve) == .loveIt)
        #expect(MovieNightTourNavigationPolicy.previousStep(from: .schedule) == .approve)
        #expect(MovieNightTourNavigationPolicy.boundedStep(.previewUsed, actualProgress: .approve) == .previewUsed)
        #expect(MovieNightTourNavigationPolicy.boundedStep(.loveIt, actualProgress: .approve) == .loveIt)
        #expect(MovieNightTourNavigationPolicy.boundedStep(.schedule, actualProgress: .approve) == .approve)
        #expect(MovieNightTourNavigationPolicy.boundedStep(.schedule, actualProgress: .completed) == nil)
    }

    @Test("Next cannot cross an action gate until persisted progress advances")
    func nextStopsAtActionGates() {
        #expect(MovieNightTourNavigationPolicy.nextStep(from: .previewUsed, actualProgress: .previewUsed) == .ideas)
        #expect(MovieNightTourNavigationPolicy.nextStep(from: .ideas, actualProgress: .previewUsed) == nil)
        #expect(MovieNightTourNavigationPolicy.nextStep(from: .ideas, actualProgress: .ideas) == nil)
        #expect(MovieNightTourNavigationPolicy.nextStep(from: .ideas, actualProgress: .loveIt) == .loveIt)
        #expect(MovieNightTourNavigationPolicy.nextStep(from: .loveIt, actualProgress: .loveIt) == nil)
        #expect(MovieNightTourNavigationPolicy.nextStep(from: .loveIt, actualProgress: .approve) == .approve)
        #expect(MovieNightTourNavigationPolicy.nextStep(from: .approve, actualProgress: .approve) == nil)
        #expect(MovieNightTourNavigationPolicy.nextStep(from: .approve, actualProgress: .schedule) == .schedule)
        #expect(MovieNightTourNavigationPolicy.nextStep(from: .schedule, actualProgress: .schedule) == nil)
        #expect(MovieNightTourNavigationPolicy.nextStep(from: .previewUsed, actualProgress: .completed) == nil)
    }

    @Test("Earlier instructions are recaps, not active unfinished actions")
    func identifiesEarlierReviewSteps() {
        #expect(MovieNightTourNavigationPolicy.isReviewingEarlierStep(.ideas, actualProgress: .loveIt))
        #expect(MovieNightTourNavigationPolicy.isReviewingEarlierStep(.loveIt, actualProgress: .approve))
        #expect(MovieNightTourNavigationPolicy.isReviewingEarlierStep(.approve, actualProgress: .schedule))
        #expect(!MovieNightTourNavigationPolicy.isReviewingEarlierStep(.approve, actualProgress: .approve))
        #expect(!MovieNightTourNavigationPolicy.isReviewingEarlierStep(.ideas, actualProgress: .previewUsed))
    }

    @Test("The final chevron finishes only at the scheduled action stage")
    func finishRequiresObservedSchedule() {
        #expect(!MovieNightTourNavigationPolicy.canFinish(
            from: .schedule, actualProgress: .approve, actionsAreComplete: true
        ))
        #expect(!MovieNightTourNavigationPolicy.canFinish(
            from: .schedule, actualProgress: .schedule, actionsAreComplete: false
        ))
        #expect(MovieNightTourNavigationPolicy.canFinish(
            from: .schedule, actualProgress: .schedule, actionsAreComplete: true
        ))
        #expect(!MovieNightTourNavigationPolicy.canFinish(
            from: .approve, actualProgress: .schedule, actionsAreComplete: true
        ))
    }
}
