import CoreGraphics
import SwiftUI
import Testing
@testable import Gatherory

@MainActor
struct DecisionSwipeMappingTests {
    @Test("Confirmed drag stays with the outgoing card and does not move the next card")
    func dragBelongsToCard() {
        var drag = DecisionDeckDrag<String>()
        let translation = CGSize(width: 160, height: -20)
        drag.update(translation, for: "first")
        #expect(drag.offset(for: "first") == translation)
        #expect(drag.offset(for: "next") == .zero)
        #expect(drag.offset(for: nil) == .zero)
        drag.update(CGSize(width: -130, height: 5), for: "next")
        #expect(drag.offset(for: "first") == .zero)
        #expect(drag.offset(for: "next").width == -130)
        drag.update(.zero, for: "next")
        #expect(drag.offset(for: "next") == .zero)
    }

    @Test("Undo motion reverses repeated decisions in order without owning response data")
    func undoMotionDirections() {
        var history = DecisionDeckMotionHistory<String>()
        history.record(.pass, for: "one")
        history.record(.maybe, for: "one")
        history.record(.love, for: "two")
        #expect(history.undo(for: "two") == .love)
        #expect(history.undo(for: "one") == .maybe)
        #expect(history.undo(for: "one") == .pass)
        #expect(history.undo(for: "one") == nil)
        history.record(.love, for: "one")
        #expect(history.undo(for: "different-account-record") == nil)
        #expect(history.undo(for: "one") == nil)
        #expect(DecisionSwipeMapping.edge(for: .love) == .trailing)
        #expect(DecisionSwipeMapping.edge(for: .pass) == .leading)
        #expect(DecisionSwipeMapping.edge(for: .maybe) == .top)
    }

    @Test("Incoming card depth interpolates and renders clear and blurred states")
    func incomingCardDepth() throws {
        var effect = DecisionCardDepth(depth: 1)
        effect.animatableData = 0.5
        #expect(effect.depth == 0.5)
        effect.animatableData = 0
        #expect(effect.depth == 0)

        for depth in [0.0, 0.5, 1.0] {
                let renderer = ImageRenderer(content:
                    ZStack {
                        LinearGradient(colors: [.blue, .orange], startPoint: .topLeading, endPoint: .bottomTrailing)
                        Text("Next idea").font(.title.bold())
                    }
                    .frame(width: 200, height: 260)
                    .modifier(DecisionCardDepth(depth: depth))
                )
                renderer.scale = 1
                let image = try #require(renderer.uiImage)
                #expect(image.size == CGSize(width: 200, height: 260))
        }
    }

    @Test("Live and preview swipe thresholds preserve horizontal precedence")
    func swipeThresholdsAndPrecedence() {
        #expect(DecisionSwipeMapping.choice(for: CGSize(width: 101, height: -500)) == .love)
        #expect(DecisionSwipeMapping.choice(for: CGSize(width: -101, height: -500)) == .pass)
        #expect(DecisionSwipeMapping.choice(for: CGSize(width: 100, height: -101)) == .maybe)
        #expect(DecisionSwipeMapping.choice(for: CGSize(width: 100, height: 0)) == nil)
        #expect(DecisionSwipeMapping.choice(for: CGSize(width: 0, height: -100)) == nil)
    }

    @Test("Swipe feedback uses the existing 35 point threshold and direction precedence")
    func feedbackThresholdsAndPrecedence() {
        #expect(DecisionSwipeMapping.feedbackChoice(for: CGSize(width: 36, height: -80)) == .love)
        #expect(DecisionSwipeMapping.feedbackChoice(for: CGSize(width: -36, height: -80)) == .pass)
        #expect(DecisionSwipeMapping.feedbackChoice(for: CGSize(width: 35, height: -36)) == .maybe)
        #expect(DecisionSwipeMapping.feedbackChoice(for: CGSize(width: 35, height: 0)) == nil)
    }

    @Test("Preview queue advances unanswered ideas and prevents rereview loops")
    func previewQueueReviewProgress() {
        let ideas = [idea("one"), idea("two"), idea("three")]
        var responses: [String: DecisionChoice] = [:]
        var reviewed: Set<String> = []

        #expect(BlueprintDecisionQueue.nextIdea(in: ideas, responses: responses, filter: .unanswered, reviewedKeys: reviewed)?.key == "one")
        responses["one"] = .maybe
        #expect(BlueprintDecisionQueue.nextIdea(in: ideas, responses: responses, filter: .unanswered, reviewedKeys: reviewed)?.key == "two")
        responses["two"] = .pass
        responses["three"] = .love
        #expect(BlueprintDecisionQueue.nextIdea(in: ideas, responses: responses, filter: .unanswered, reviewedKeys: reviewed) == nil)

        #expect(BlueprintDecisionQueue.nextIdea(in: ideas, responses: responses, filter: .maybes, reviewedKeys: reviewed)?.key == "one")
        reviewed.insert("one")
        #expect(BlueprintDecisionQueue.nextIdea(in: ideas, responses: responses, filter: .maybes, reviewedKeys: reviewed) == nil)
        reviewed.removeAll()
        #expect(BlueprintDecisionQueue.nextIdea(in: ideas, responses: responses, filter: .maybes, reviewedKeys: reviewed)?.key == "one")
        #expect(BlueprintDecisionQueue.nextIdea(in: ideas, responses: responses, filter: .passes, reviewedKeys: [])?.key == "two")
    }

    @Test("Review all ideas includes loved responses and stops after each idea is reviewed")
    func reviewAllIncludesAnsweredIdeasWithoutLooping() {
        let ideas = [idea("loved"), idea("maybe"), idea("passed")]
        let responses: [String: DecisionChoice] = [
            "loved": .love,
            "maybe": .maybe,
            "passed": .pass
        ]
        var reviewed: Set<String> = []

        #expect(BlueprintDecisionQueue.nextIdea(
            in: ideas, responses: responses, filter: .unanswered, reviewedKeys: reviewed,
            includesAnswered: true
        )?.key == "loved")

        reviewed.insert("loved")
        #expect(BlueprintDecisionQueue.nextIdea(
            in: ideas, responses: responses, filter: .unanswered, reviewedKeys: reviewed,
            includesAnswered: true
        )?.key == "maybe")

        reviewed.insert("maybe")
        #expect(BlueprintDecisionQueue.nextIdea(
            in: ideas, responses: responses, filter: .unanswered, reviewedKeys: reviewed,
            includesAnswered: true
        )?.key == "passed")

        reviewed.insert("passed")
        #expect(BlueprintDecisionQueue.nextIdea(
            in: ideas, responses: responses, filter: .unanswered, reviewedKeys: reviewed,
            includesAnswered: true
        ) == nil)
        #expect(responses["loved"] == .love)
    }

    @Test("Incoming card lookahead is read-only and respects every review filter")
    func incomingCardLookahead() {
        let ideas = [idea("one"), idea("two"), idea("three")]
        for filter in DecisionQueueFilter.allCases {
            let responses: [String: DecisionChoice] = filter == .unanswered ? [:] : [
                "one": filter == .maybes ? .maybe : .pass,
                "two": .love,
                "three": filter == .maybes ? .maybe : .pass
            ]
            let next = BlueprintDecisionQueue.nextIdea(
                in: ideas, responses: responses, filter: filter, reviewedKeys: [], excludingKey: "one"
            )
            #expect(next?.key == (filter == .unanswered ? "two" : "three"))
            #expect(BlueprintDecisionQueue.nextIdea(
                in: ideas, responses: responses, filter: filter, reviewedKeys: []
            )?.key == "one")
        }
        #expect(BlueprintDecisionQueue.nextIdea(
            in: [idea("one")], responses: [:], filter: .unanswered, reviewedKeys: [], excludingKey: "one"
        ) == nil)
        #expect(BlueprintDecisionQueue.nextIdea(
            in: ideas, responses: ["two": .love], filter: .unanswered,
            reviewedKeys: ["three"], includesAnswered: true, excludingKey: "one"
        )?.key == "two")
        #expect(DecisionSwipeMapping.feedbackChoice(for: .zero) == nil)
    }

    private func idea(_ key: String) -> BlueprintCatalogIdea {
        BlueprintCatalogIdea(
            key: key,
            title: key,
            category: "flowers",
            notes: nil,
            target: .main,
            configuration: [:]
        )
    }
}
