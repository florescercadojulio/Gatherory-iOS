import SwiftUI

enum DecisionSwipeMapping {
    static func choice(for translation: CGSize) -> DecisionChoice? {
        if translation.width > 100 { .love }
        else if translation.width < -100 { .pass }
        else if translation.height < -100 { .maybe }
        else { nil }
    }

    static func feedbackChoice(for offset: CGSize) -> DecisionChoice? {
        if offset.width > 35 { .love }
        else if offset.width < -35 { .pass }
        else if offset.height < -35 { .maybe }
        else { nil }
    }
}

struct DecisionSwipeInteraction: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var offset: CGSize
    var isEnabled = true
    var onDecide: (DecisionChoice) -> Void

    func body(content: Content) -> some View {
        content.gesture(
            DragGesture(minimumDistance: 10)
                .onChanged { value in
                    withTransaction(Transaction(animation: nil)) { offset = value.translation }
                }
                .onEnded { value in
                    if let choice = DecisionSwipeMapping.choice(for: value.translation) {
                        onDecide(choice)
                    } else {
                        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) { offset = .zero }
                    }
                },
            including: isEnabled ? .all : .none
        )
    }
}

/// Only the active gesture is retained; a departing flight captures its own origin.
struct DecisionDeckDrag<ID: Hashable> {
    private var cardID: ID?
    private var translation: CGSize = .zero

    func offset(for id: ID?) -> CGSize {
        guard let id, id == cardID else { return .zero }
        return translation
    }

    mutating func update(_ offset: CGSize, for id: ID?) {
        guard let id else { return }
        cardID = id
        translation = offset
    }
}

/// Presentation-only directions, never a replacement for the workspace's undo log.
struct DecisionDeckMotionHistory<ID: Hashable> {
    private var records: [(id: ID, choice: DecisionChoice)] = []

    mutating func record(_ choice: DecisionChoice, for id: ID) {
        records.append((id, choice))
    }

    mutating func undo(for id: ID) -> DecisionChoice? {
        guard records.last?.id == id else {
            records.removeAll()
            return nil
        }
        return records.popLast()?.choice
    }
}

extension DecisionSwipeMapping {
    static func edge(for choice: DecisionChoice) -> Edge {
        switch choice {
        case .love: .trailing
        case .pass: .leading
        case .maybe: .top
        }
    }
}

struct DecisionEventHeading: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let title: String

    var body: some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .foregroundStyle(.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: AppTheme.Layout.minimumTouchTarget)
            .background(
                reduceTransparency
                    ? AnyShapeStyle(Color(uiColor: .secondarySystemBackground))
                    : AnyShapeStyle(.regularMaterial),
                in: RoundedRectangle(cornerRadius: 16)
            )
            .accessibilityAddTraits(.isHeader)
    }
}

struct DecisionSwipeFeedback: View {
    let offset: CGSize

    var body: some View {
        Group {
            switch DecisionSwipeMapping.feedbackChoice(for: offset) {
            case .love: DecisionSwipeLabel(title: "Love it", symbol: "heart.fill")
            case .pass: DecisionSwipeLabel(title: "Pass", symbol: "xmark")
            case .maybe: DecisionSwipeLabel(title: "Maybe", symbol: "bookmark.fill")
            case nil: EmptyView()
            }
        }
    }
}

/// Shared depth for a stable card identity as it moves from next to current.
struct DecisionCardDepth: AnimatableModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var depth: Double

    var animatableData: Double {
        get { depth }
        set { depth = newValue }
    }

    func body(content: Content) -> some View {
        content
            .blur(radius: reduceTransparency ? 0 : 8 * max(0, min(1, depth)))
            .scaleEffect(reduceMotion ? 1 : 1 - 0.025 * max(0, min(1, depth)))
    }
}

/// Feedback remains sharp above the incoming card's light native blur.
struct DecisionSwipeBackdrop<Content: View>: View {
    let offset: CGSize
    @ViewBuilder var content: () -> Content

    private var feedbackAlignment: Alignment {
        switch DecisionSwipeMapping.feedbackChoice(for: offset) {
        case .love: .leading
        case .pass: .trailing
        case .maybe: .bottom
        case nil: .center
        }
    }

    var body: some View {
        content()
            .overlay(alignment: feedbackAlignment) {
                DecisionSwipeFeedback(offset: offset)
                    .padding(12)
            }
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.hero, style: .continuous))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

private struct DecisionSwipeLabel: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let title: LocalizedStringKey
    let symbol: String

    var body: some View {
        Label(title, systemImage: symbol)
            .font(.title2.bold())
            .padding(.horizontal, AppTheme.Spacing.standard)
            .padding(.vertical, AppTheme.Spacing.compact)
            .background(
                reduceTransparency
                    ? AnyShapeStyle(Color(uiColor: .secondarySystemBackground))
                    : AnyShapeStyle(.regularMaterial),
                in: Capsule()
            )
            .foregroundStyle(.primary)
    }
}

enum BlueprintDecisionQueue {
    static func nextIdea(
        in ideas: [BlueprintCatalogIdea],
        responses: [String: DecisionChoice],
        filter: DecisionQueueFilter,
        reviewedKeys: Set<String>,
        includesAnswered: Bool = false,
        excludingKey: String? = nil
    ) -> BlueprintCatalogIdea? {
        ideas.first { idea in
            guard idea.key != excludingKey else { return false }
            if includesAnswered { return !reviewedKeys.contains(idea.key) }
            let response = responses[idea.key]
            return switch filter {
            case .unanswered:
                response == nil
            case .maybes:
                response == .maybe && !reviewedKeys.contains(idea.key)
            case .passes:
                response == .pass && !reviewedKeys.contains(idea.key)
            }
        }
    }
}
