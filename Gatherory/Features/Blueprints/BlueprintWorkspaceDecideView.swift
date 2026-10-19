import SwiftUI

/// A transient Decide deck for browsing and reviewing ideas in a blueprint.
struct BlueprintWorkspaceDecideView: View {
    let content: BlueprintPreviewContent
    @Binding var scope: BlueprintPreviewScope
    let onDecide: (DecisionChoice, String) -> Void
    let responses: [String: DecisionChoice]
    let onSaveDraft: (() -> Void)?
    var allowsDecisions: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var reviewedKeys: Set<String> = []
    @State private var filter: DecisionQueueFilter = .unanswered
    @State private var reviewsAllIdeas = false
    @State private var drag = DecisionDeckDrag<String>()
    @State private var presentedIdeaKey: String?
    @State private var flight = DecisionCardFlightState<BlueprintCatalogIdea>()
    @Namespace private var previewTransition

    init(
        content: BlueprintPreviewContent,
        scope: Binding<BlueprintPreviewScope>,
        responses: [String: DecisionChoice],
        onSaveDraft: (() -> Void)? = nil,
        allowsDecisions: Bool = true,
        onDecide: @escaping (DecisionChoice, String) -> Void
    ) {
        self.content = content
        self._scope = scope
        self.onDecide = onDecide
        self.responses = responses
        self.onSaveDraft = onSaveDraft
        self.allowsDecisions = allowsDecisions
    }

    private var ideas: [BlueprintCatalogIdea] { content.ideas(in: scope) }

    private var currentIdea: BlueprintCatalogIdea? {
        BlueprintDecisionQueue.nextIdea(
            in: ideas,
            responses: responses,
            filter: filter,
            reviewedKeys: reviewedKeys,
            includesAnswered: reviewsAllIdeas
        )
    }

    private var dragOffset: CGSize { drag.offset(for: currentIdea?.key) }
    private var dragBinding: Binding<CGSize> {
        Binding(get: { dragOffset }, set: { drag.update($0, for: currentIdea?.key) })
    }

    private var deckIdeas: [BlueprintCatalogIdea] {
        guard let currentIdea else { return [] }
        let next = BlueprintDecisionQueue.nextIdea(
            in: ideas, responses: responses, filter: filter,
            reviewedKeys: reviewedKeys, includesAnswered: reviewsAllIdeas,
            excludingKey: currentIdea.key
        )
        return [currentIdea, next].compactMap { $0 }
    }

    var body: some View {
        VStack(spacing: AppTheme.Spacing.standard) {
            ZStack {
                DecisionSwipeBackdrop(offset: deckIdeas.count == 1 ? dragOffset : .zero) {
                    RoundedRectangle(cornerRadius: AppTheme.Radius.hero)
                        .fill(AppTheme.ColorToken.surface)
                }
                .opacity(currentIdea == nil ? 0 : 1)
                ForEach(flight.cards(in: deckIdeas, identifiedBy: { AnyHashable($0.key) })) { idea in
                    let isCurrent = idea.key == currentIdea?.key
                    let command = flight.current.flatMap { $0.card.key == idea.key ? $0 : nil }
                    decisionCard(for: idea, isCurrent: isCurrent)
                        .matchedTransitionSource(id: idea.id, in: previewTransition)
                        .allowsHitTesting(isCurrent && command == nil)
                        .accessibilityHidden(!isCurrent || command != nil)
                        .zIndex(command != nil ? 3 : isCurrent ? 2 : 1)
                        .transition(.identity)
                }
                if currentIdea == nil {
                    emptyQueue.transition(.opacity)
                }
            }
            // Mask the artwork, not the deck: swipes may leave its layout bounds.
        }
        .padding(.horizontal, AppTheme.Layout.screenHorizontal)
        .padding(.top, AppTheme.Layout.screenTop)
        .padding(.bottom, AppTheme.Layout.screenTop)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.ColorToken.background)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    Picker("Event", selection: $scope) {
                        Text(BlueprintCopy.allIdeas).tag(BlueprintPreviewScope.all)
                        Text(content.title).tag(BlueprintPreviewScope.main)
                        ForEach(content.children) { child in
                            Text(child.title).tag(BlueprintPreviewScope.child(child.key))
                        }
                    }
                } label: {
                    Label("Decision event filter", systemImage: "calendar")
                        .labelStyle(.iconOnly)
                        .frame(minWidth: AppTheme.Layout.minimumTouchTarget,
                               minHeight: AppTheme.Layout.minimumTouchTarget)
                }
                .accessibilityLabel("Decision event filter")
                .accessibilityValue(BlueprintDecideContext.title(content: content, scope: scope, ideaTarget: nil))
            }
            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    if let onSaveDraft {
                        Button(action: onSaveDraft) {
                            Label(BlueprintCopy.saveDraft, systemImage: "square.and.arrow.down")
                        }
                        Divider()
                    }
                    Button {
                        withAnimation(reduceMotion ? nil : .snappy) {
                            reviewsAllIdeas = true
                            reviewedKeys.removeAll()
                            drag = .init()
                            flight.reset()
                        }
                    } label: {
                        Label(
                            "Review All Ideas",
                            systemImage: reviewsAllIdeas ? "checkmark" : "square.stack.3d.up"
                        )
                    }
                    Divider()
                    ForEach(DecisionQueueFilter.allCases, id: \.self) { queueFilter in
                        Button {
                            selectFilter(queueFilter)
                        } label: {
                            Label(
                                "\(queueFilter.title) (\(count(for: queueFilter)))",
                                systemImage: filter == queueFilter ? "checkmark" : queueFilter.symbol
                            )
                        }
                    }
                } label: {
                    Label(
                        reviewsAllIdeas ? "All Ideas" : filter.title,
                        systemImage: reviewsAllIdeas ? "square.stack.3d.up" : filter.symbol
                    )
                        .labelStyle(.iconOnly)
                }
                .accessibilityLabel("Decision response filter")
                .accessibilityValue(reviewsAllIdeas ? "All Ideas" : filter.title)
            }
            ToolbarItem(placement: .topBarTrailing) { AccountToolbarButton() }
        }
        .navigationDestination(item: $presentedIdeaKey) { ideaKey in
            if let idea = ideas.first(where: { $0.key == ideaKey }) {
                Group {
                    if reduceMotion {
                        BlueprintIdeaPreview(idea: idea)
                    } else {
                        BlueprintIdeaPreview(idea: idea)
                            .navigationTransition(.zoom(sourceID: idea.id, in: previewTransition))
                    }
                }
            } else {
                ContentUnavailableView("No Ideas", systemImage: "lightbulb")
            }
        }
        .onChange(of: ideas.map(\.key)) { _, _ in
            reviewedKeys.formIntersection(ideas.map(\.key))
            drag = .init()
            flight.reset()
        }
        .onDisappear {
            flight.reset()
            drag = .init()
        }
    }

    private func cardArtwork(for idea: BlueprintCatalogIdea) -> some View {
        let category = IdeaCategory(rawValue: idea.category) ?? .other
        return MediaArtwork(imageData: nil, symbol: category.symbol,
                            colors: category.artworkColors, accent: category.artworkAccent,
                            ambientBlurRadius: 10, progressiveBlurRadius: 22, blurStart: 0.46)
    }

    private func cardSummary(for idea: BlueprintCatalogIdea) -> some View {
        IdeaSummaryContent(title: idea.title, note: idea.notes ?? "",
                           category: IdeaCategory(rawValue: idea.category) ?? .other) {
            EmptyView()
        } footer: {
            EmptyView()
        }
    }

    private func cardPresentation(for idea: BlueprintCatalogIdea) -> some View {
        DecisionCardPresentation {
            cardArtwork(for: idea)
        } guide: {
            DecisionEventHeading(title: BlueprintDecideContext.title(content: content, scope: scope, ideaTarget: idea.target))
        } feedback: {
            EmptyView()
        } summary: {
            cardSummary(for: idea)
        }
        .foregroundStyle(.primary)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.hero, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.Radius.hero, style: .continuous)
                .stroke(Color(uiColor: .separator), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.18), radius: 20, y: 10)
    }

    private func decisionCard(for idea: BlueprintCatalogIdea, isCurrent: Bool) -> some View {
        let command = flight.current.flatMap { $0.card.key == idea.key ? $0 : nil }
        return cardPresentation(for: idea)
            .contentShape(RoundedRectangle(cornerRadius: AppTheme.Radius.hero, style: .continuous))
            .modifier(DecisionCardDepth(depth: isCurrent || command != nil ? 0 : 1))
            .overlay {
                if !isCurrent && command == nil {
                    DecisionSwipeBackdrop(offset: dragOffset) { Color.clear }
                }
            }
            .modifier(DecisionCardMotion(flight: command, dragOffset: isCurrent ? dragOffset : .zero,
                                         onFinished: finishFlight))
            .modifier(DecisionSwipeInteraction(offset: dragBinding, isEnabled: allowsDecisions) { choice in decide(choice, for: idea) })
            .onTapGesture { openDetails(for: idea) }
            .accessibilityAddTraits(.isButton)
            .accessibilityAction(named: Text("Open details")) { openDetails(for: idea) }
            .accessibilityHint("Opens the idea preview. Swipe left to pass, right to love it, or up to save for later.")
            .accessibilityAction(named: Text("Pass")) { decide(.pass, for: idea) }
            .accessibilityAction(named: Text("Maybe")) { decide(.maybe, for: idea) }
            .accessibilityAction(named: Text("Love It")) { decide(.love, for: idea) }
            .frame(maxHeight: .infinity)
    }

    @ViewBuilder
    private var emptyQueue: some View {
        ContentUnavailableView {
            Label(emptyTitle, systemImage: reviewsAllIdeas ? "square.stack.3d.up" : (filter == .unanswered ? "checkmark.circle.fill" : filter.symbol))
        } description: {
            Text(emptyDescription)
        } actions: {
            if reviewsAllIdeas {
                Button("Review All Ideas Again", systemImage: "arrow.clockwise") {
                    withAnimation(reduceMotion ? nil : .snappy) {
                        drag = .init()
                        flight.reset()
                        reviewedKeys.removeAll()
                    }
                }
                .buttonStyle(.bordered)
            } else if filter != .unanswered {
                Button(filter == .maybes ? "Review Maybes Again" : "Review Passes Again", systemImage: "arrow.clockwise") {
                    withAnimation(reduceMotion ? nil : .snappy) {
                        drag = .init()
                        flight.reset()
                        reviewedKeys.removeAll()
                    }
                }
                .buttonStyle(.bordered)
                Button("Review Unanswered Ideas", systemImage: "tray") {
                    selectFilter(.unanswered)
                }
                .buttonStyle(.bordered)
            }
            if filter != .maybes && count(for: .maybes) > 0 {
                Button("Review My Maybes", systemImage: "questionmark.circle") {
                    selectFilter(.maybes)
                }
                .buttonStyle(.borderedProminent)
            }
            if filter != .passes && count(for: .passes) > 0 {
                Button("Review My Passes", systemImage: "hand.thumbsdown") {
                    selectFilter(.passes)
                }
                .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyTitle: String {
        if reviewsAllIdeas { return ideas.isEmpty ? String(localized: "No Ideas") : String(localized: "All Ideas Reviewed") }
        return switch filter {
        case .unanswered: ideas.isEmpty ? String(localized: "No Ideas") : String(localized: "You're all caught up")
        case .maybes: count(for: .maybes) > 0 ? String(localized: "Maybes reviewed") : String(localized: "No Maybes")
        case .passes: count(for: .passes) > 0 ? String(localized: "Passes reviewed") : String(localized: "No Passes")
        }
    }

    private var emptyDescription: String {
        if reviewsAllIdeas {
            return ideas.isEmpty ? BlueprintCopy.previewNoIdeas : String(localized: "Your decisions are kept. Review all ideas again whenever you're ready.")
        }
        return switch filter {
        case .unanswered:
            ideas.isEmpty ? BlueprintCopy.previewNoIdeas : BlueprintCopy.previewChoicesExplanation
        case .maybes:
            count(for: .maybes) > 0 ? String(localized: "Your Maybe responses are kept. Revisit them whenever you're ready.") : String(localized: "Ideas you mark Maybe will appear here.")
        case .passes:
            count(for: .passes) > 0 ? String(localized: "Your Pass responses are kept. Revisit them whenever you're ready.") : String(localized: "Ideas you pass on will appear here.")
        }
    }

    private func count(for queueFilter: DecisionQueueFilter) -> Int {
        ideas.filter { idea in
            switch queueFilter {
            case .unanswered: responses[idea.key] == nil
            case .maybes: responses[idea.key] == .maybe
            case .passes: responses[idea.key] == .pass
            }
        }.count
    }

    private func selectFilter(_ queueFilter: DecisionQueueFilter) {
        withAnimation(reduceMotion ? nil : .snappy) {
            reviewsAllIdeas = false
            filter = queueFilter
            reviewedKeys.removeAll()
            drag = .init()
            flight.reset()
        }
    }

    private func decide(_ choice: DecisionChoice, for idea: BlueprintCatalogIdea) {
        guard allowsDecisions, currentIdea?.key == idea.key else { return }
        flight.reset()
        if !reduceMotion {
            flight.start(card: idea, choice: choice, origin: dragOffset)
        }
        drag = .init()
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.22)) {
            if reviewsAllIdeas || filter != .unanswered { reviewedKeys.insert(idea.key) }
            onDecide(choice, idea.key)
        }
    }

    private func finishFlight(_ token: UUID) {
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) { _ = flight.finish(token) }
    }

    private func openDetails(for idea: BlueprintCatalogIdea) {
        guard abs(dragOffset.width) < 10, abs(dragOffset.height) < 10 else { return }
        drag = .init()
        presentedIdeaKey = idea.key
    }
}

/// Pure event-title resolver, colocated with the preview Decide screen.
enum BlueprintDecideContext {
    static func title(content: BlueprintPreviewContent, scope: BlueprintPreviewScope,
                      ideaTarget: BlueprintTarget?) -> String {
        let fallback = scopeTitle(content: content, scope: scope)
        guard let ideaTarget else { return fallback }
        return switch ideaTarget {
        case .main: nonempty(content.title) ?? fallback
        case .child(let key):
            content.children.first { $0.key == key }.flatMap { nonempty($0.title) } ?? fallback
        }
    }

    private static func scopeTitle(content: BlueprintPreviewContent, scope: BlueprintPreviewScope) -> String {
        switch scope {
        case .all: BlueprintCopy.allIdeas
        case .main: nonempty(content.title) ?? BlueprintCopy.allIdeas
        case .child(let key):
            content.children.first { $0.key == key }.flatMap { nonempty($0.title) } ?? BlueprintCopy.allIdeas
        }
    }

    private static func nonempty(_ title: String) -> String? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
