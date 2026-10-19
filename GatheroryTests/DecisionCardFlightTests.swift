import CoreGraphics
import Testing

@testable import Gatherory

@MainActor
struct DecisionCardFlightTests {
    @Test(
        "Each flight uses its own direction and reaches fully outside the deck",
        arguments: [DecisionChoice.love, .pass, .maybe])
    func endpoints(choice: DecisionChoice) throws {
        let size = CGSize(width: 390, height: 844)
        let origin = CGSize(width: -135, height: -160)
        var state = DecisionCardFlightState<String>()
        state.start(card: "idea", choice: choice, origin: origin)
        let departure = try #require(state.current)
        #expect(departure.offset(at: 0, size: size) == origin)
        let outside = departure.offset(at: 1, size: size)
        switch choice {
        case .love: #expect(outside.width > size.width * 2)
        case .pass: #expect(outside.width < -size.width * 2)
        case .maybe: #expect(outside.height < -size.height * 2)
        }
        #expect(departure.rotation(at: 1) == 0)
        state.start(card: "idea", choice: choice, isReturning: true)
        let arrival = try #require(state.current)
        #expect(arrival.offset(at: 0, size: size) == outside)
        #expect(arrival.offset(at: 1, size: size) == .zero)
        #expect(arrival.rotation(at: 1) == 0)
        #expect(arrival.duration == 0.24)
        #expect(departure.duration == 0.22)
    }

    @Test(
        "Immediate Undo replaces a departure; old callbacks cannot strand or delete the return",
        arguments: [DecisionChoice.love, .pass, .maybe])
    func immediateUndo(choice: DecisionChoice) throws {
        var state = DecisionCardFlightState<String>()
        state.start(card: "earlier", choice: .love)
        let stale = try #require(state.current)
        state.start(card: "last", choice: choice, origin: CGSize(width: -150, height: 0))
        let exit = try #require(state.current)
        state.returnCard("last", choice: choice) { $0 == "last" }
        let returning = try #require(state.current)
        #expect(returning.id == exit.id)
        #expect(returning.revision != exit.revision)
        #expect(returning.origin == exit.origin)
        #expect(returning.continuesFlight)
        #expect(returning.choice == choice)
        #expect(returning.isReturning)
        let staleFinished = state.finish(stale.revision)
        let exitFinished = state.finish(exit.revision)
        #expect(!staleFinished)
        #expect(!exitFinished)
        #expect(state.current?.id == returning.id)
        let returnFinished = state.finish(returning.revision)
        #expect(returnFinished)
        #expect(state.current == nil)
        let duplicateFinished = state.finish(returning.revision)
        #expect(!duplicateFinished)
    }

    @Test("A thousand rapid swipes retain only one immutable flight, not removal trails")
    func boundedRapidSwipes() throws {
        var state = DecisionCardFlightState<Int>()
        let choices: [DecisionChoice] = [.pass, .maybe, .love]
        for index in 0..<1000 {
            let previous = state.current
            state.start(card: index, choice: choices[index % 3])
            let latest = try #require(state.current)
            #expect(latest.card == index)
            #expect(latest.choice == choices[index % 3])
            if let previous {
                let staleFinished = state.finish(previous.revision)
                #expect(!staleFinished)
                #expect(state.current?.id == latest.id)
            }
        }
        let last = try #require(state.current)
        state.reset()
        let staleFinished = state.finish(last.revision)
        #expect(!staleFinished)
        #expect(state.current == nil)
    }

    @Test("Consecutive Undo directions survive pending completions and lifecycle reset")
    func consecutiveUndo() throws {
        var history = DecisionDeckMotionHistory<Int>()
        var state = DecisionCardFlightState<Int>()
        let choices: [DecisionChoice] = [.love, .pass, .maybe]
        for index in 0..<3 { history.record(choices[index], for: index) }
        for index in (0..<3).reversed() {
            let previous = state.current
            let undoneChoice = history.undo(for: index)
            let choice = try #require(undoneChoice)
            state.start(card: index, choice: choice, isReturning: true)
            let latest = try #require(state.current)
            if let previous {
                let staleFinished = state.finish(previous.revision)
                #expect(!staleFinished)
            }
            #expect(state.current?.id == latest.id)
            #expect(latest.choice == choices[index])
        }
        state.reset()
        #expect(state.current == nil)
    }

    @Test("Drag, departure and immediate Undo retain one rendering identity")
    func stableRenderingLane() throws {
        var state = DecisionCardFlightState<String>()
        #expect(state.cards(in: ["a", "b", "c"], identifiedBy: { AnyHashable($0) }) == ["a", "b"])
        state.start(card: "a", choice: .pass, origin: CGSize(width: -130, height: 10))
        let departing = state.cards(in: ["b", "c"], identifiedBy: { AnyHashable($0) })
        #expect(departing == ["b", "c", "a"])
        #expect(departing.filter { $0 == "a" }.count == 1)
        state.returnCard("a", choice: .pass) { $0 == "a" }
        #expect(state.cards(in: ["a", "b"], identifiedBy: { AnyHashable($0) }) == ["a", "b"])
        let returning = try #require(state.current)
        let finished = state.finish(returning.revision)
        #expect(finished)
        #expect(state.cards(in: ["a", "b"], identifiedBy: { AnyHashable($0) }) == ["a", "b"])
    }

    @Test("Undo before the first animation update starts at the drag, not the opposite edge",
          arguments: [DecisionChoice.love, .pass, .maybe])
    func undoBeforeAnimationStarts(choice: DecisionChoice) throws {
        let size = CGSize(width: 390, height: 844)
        let origin = CGSize(width: choice == .pass ? -140 : 140, height: -120)
        var state = DecisionCardFlightState<String>()
        state.start(card: "a", choice: choice, origin: origin)
        state.returnCard("a", choice: choice) { $0 == "a" }
        let returning = try #require(state.current)
        #expect(returning.initialOffset(size: size) == origin)
        #expect(returning.initialRotation == Double(origin.width / 24))
        #expect(returning.offset(at: 1, size: size) == .zero)
    }

    @Test("Rapid mixed directions keep only the active pair and one departing identity")
    func boundedRenderingLane() throws {
        var state = DecisionCardFlightState<Int>()
        let choices: [DecisionChoice] = [.love, .pass, .maybe]
        for index in 0..<1000 {
            let old = state.current
            state.start(card: index, choice: choices[index % 3])
            let cards = state.cards(in: [index + 1, index + 2], identifiedBy: { AnyHashable($0) })
            #expect(cards == [index + 1, index + 2, index])
            #expect(Set(cards).count == cards.count)
            if let old {
                let staleFinished = state.finish(old.revision)
                #expect(!staleFinished)
                #expect(state.cards(in: [index + 1, index + 2], identifiedBy: { AnyHashable($0) }) == cards)
            }
        }
    }

    @Test("Undo from an empty queue adds one card and cleanup leaves that same queue card")
    func lastCardRendering() throws {
        var state = DecisionCardFlightState<String>()
        state.start(card: "last", choice: .maybe)
        #expect(state.cards(in: [], identifiedBy: { AnyHashable($0) }) == ["last"])
        let exit = try #require(state.current)
        let finished = state.finish(exit.revision)
        #expect(finished)
        #expect(state.cards(in: [], identifiedBy: { AnyHashable($0) }).isEmpty)
        state.returnCard("last", choice: .maybe) { $0 == "last" }
        let returning = try #require(state.current)
        #expect(!returning.continuesFlight)
        #expect(returning.initialOffset(size: CGSize(width: 390, height: 844)).height < -844)
        #expect(state.cards(in: ["last"], identifiedBy: { AnyHashable($0) }) == ["last"])
        state.reset()
        let staleFinished = state.finish(returning.revision)
        #expect(!staleFinished)
        #expect(state.cards(in: ["last"], identifiedBy: { AnyHashable($0) }) == ["last"])
    }
}
