import SwiftUI

/// A presentation command, independent of queue membership and undo data.
struct DecisionCardFlight<Card>: Identifiable {
    let id: UUID
    let revision = UUID()
    let card: Card
    let choice: DecisionChoice
    let isReturning: Bool
    let origin: CGSize
    let continuesFlight: Bool

    init(
        card: Card, choice: DecisionChoice, isReturning: Bool, origin: CGSize, id: UUID = UUID(),
        continuesFlight: Bool = false
    ) {
        self.id = id
        self.card = card
        self.choice = choice
        self.isReturning = isReturning
        self.origin = origin
        self.continuesFlight = continuesFlight
    }

    var duration: Double { isReturning ? 0.24 : 0.22 }

    /// If Undo arrives before the exit's first animation update, the mounted
    /// card is still at the gesture origin, not at the far edge of the deck.
    func initialOffset(size: CGSize) -> CGSize {
        continuesFlight ? origin : offset(at: 0, size: size)
    }

    var initialRotation: Double {
        continuesFlight ? Double(origin.width / 24) : rotation(at: 0)
    }

    func offset(at progress: Double, size: CGSize) -> CGSize {
        let p = progress.isFinite ? min(1, max(0, progress)) : 1
        let width = LayoutDimensions.nonnegative(size.width)
        let height = LayoutDimensions.nonnegative(size.height)
        let edge: CGSize =
            switch choice {
            case .love: CGSize(width: width * 2 + 200, height: 0)
            case .pass: CGSize(width: -width * 2 - 200, height: 0)
            case .maybe: CGSize(width: 0, height: -height * 2 - 200)
            }
        let start = isReturning ? edge : origin
        let end = isReturning ? CGSize.zero : edge
        return CGSize(
            width: start.width + (end.width - start.width) * p,
            height: start.height + (end.height - start.height) * p)
    }

    func rotation(at progress: Double) -> Double {
        let p = progress.isFinite ? min(1, max(0, progress)) : 1
        let tilt = isReturning ? (choice == .love ? 8.0 : choice == .pass ? -8.0 : 0) : Double(origin.width / 24)
        return tilt * (1 - p)
    }
}

/// A single slot replaces interrupted flights instead of retaining removal views.
/// Stale completion callbacks cannot remove a newer flight or mutate decisions.
struct DecisionCardFlightState<Card> {
    private(set) var current: DecisionCardFlight<Card>?

    mutating func start(card: Card, choice: DecisionChoice, isReturning: Bool = false, origin: CGSize = .zero) {
        current = DecisionCardFlight(card: card, choice: choice, isReturning: isReturning, origin: origin)
    }

    /// Keep the explicit view alive to reverse its in-flight offset continuously.
    /// The command token changes, so completion of the interrupted exit is stale.
    mutating func returnCard(_ card: Card, choice: DecisionChoice, matches: (Card) -> Bool) {
        let interrupted = current.flatMap { matches($0.card) && $0.choice == choice ? $0 : nil }
        current = DecisionCardFlight(
            card: card, choice: choice, isReturning: true,
            origin: interrupted?.origin ?? .zero, id: interrupted?.id ?? UUID(),
            continuesFlight: interrupted != nil)
    }

    @discardableResult
    mutating func finish(_ token: UUID) -> Bool {
        guard current?.revision == token else { return false }
        current = nil
        return true
    }

    mutating func reset() { current = nil }

    /// Queue cards and the interrupted card share one identity-keyed rendering lane.
    /// Never create a second view for the same card during a departure or Undo.
    func cards(in queue: [Card], identifiedBy identity: (Card) -> AnyHashable) -> [Card] {
        var cards = Array(queue.prefix(2))
        if let current, !cards.contains(where: { identity($0) == identity(current.card) }) {
            cards.append(current.card)
        }
        return cards
    }
}

/// The same modifier stays mounted from drag through departure and reversal.
/// Changing a command retargets the existing SwiftUI animation, without a task,
/// a visual copy, or a removal transition holding old cards alive.
struct DecisionCardMotion<Card>: ViewModifier {
    let flight: DecisionCardFlight<Card>?
    let dragOffset: CGSize
    var onFinished: (UUID) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var offset: CGSize?
    @State private var rotation: Double?

    func body(content: Content) -> some View {
        GeometryReader { proxy in
            content
                .frame(width: proxy.size.width, height: proxy.size.height)
                .offset(flight.map { offset ?? $0.initialOffset(size: proxy.size) } ?? dragOffset)
                .rotationEffect(.degrees(flight.map { rotation ?? $0.initialRotation } ?? Double(dragOffset.width / 24)))
                .onChange(of: flight?.revision, initial: true) { _, _ in
                    guard let flight else {
                        offset = nil
                        rotation = nil
                        return
                    }
                    let token = flight.revision
                    withAnimation(
                        reduceMotion ? nil : .easeOut(duration: flight.duration), completionCriteria: .removed
                    ) {
                        offset = flight.offset(at: 1, size: proxy.size)
                        rotation = 0
                    } completion: {
                        onFinished(token)
                    }
                }
        }
    }
}
