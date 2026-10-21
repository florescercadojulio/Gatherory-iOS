import PostHog
import SwiftUI

enum DecidePrimerPresentationPolicy {
    static func shouldPresent(hasSeenPrimer: Bool, isDecideTabActive: Bool) -> Bool {
        !hasSeenPrimer && isDecideTabActive
    }
}

struct DecisionDeckView: View {
    @Environment(ImageSafetyStore.self) private var safety
    var isActive = true
    var onExitWorkspace: (() -> Void)?

    @Environment(PlanningWorkspace.self) private var workspace
    @Environment(\.currentUserAccount) private var currentUserAccount
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("hasSeenDecideTimelinePrimer") private var hasSeenDecidePrimer = false
    @State private var drag = DecisionDeckDrag<UUID>()
    @State private var selectedIdeaID: UUID?
    @State private var isShowingDecidePrimer = false
    @State private var decisionScope: DecisionScope = .queue
    @State private var session = DecisionDeckSession()
    @State private var motionHistory = DecisionDeckMotionHistory<UUID>()
    @State private var flight = DecisionCardFlightState<PlanningIdea>()
    @Namespace private var decisionTransition

    private var visibleQueue: [PlanningIdea] {
        session.queue(in: workspace, eventID: decisionScope.eventID)
            .filter { !safety.isBlocked($0.submittedByUserID) }
    }

    private var currentIdea: PlanningIdea? { visibleQueue.first }

    private var dragOffset: CGSize { drag.offset(for: currentIdea?.id) }
    private var dragBinding: Binding<CGSize> {
        Binding(get: { dragOffset }, set: { drag.update($0, for: currentIdea?.id) })
    }

    private var scopeTitle: String {
        switch decisionScope {
        case .queue:
            session.filter != .unanswered
                ? session.filter.title
                : currentIdea.map(workspace.eventTitle(for:)) ?? "Decide"
        case .event(let eventID):
            workspace.eventTitle(for: eventID)
        }
    }

    private var isFilteringToEvent: Bool {
        decisionScope.eventID != nil
    }

    private func count(for filter: DecisionQueueFilter) -> Int {
        workspace.decisionQueue(for: decisionScope.eventID, filter: filter)
            .filter { !safety.isBlocked($0.submittedByUserID) }.count
    }

    var body: some View {
        VStack(spacing: AppTheme.Spacing.compact) {
            ZStack {
                DecisionSwipeBackdrop(offset: visibleQueue.count == 1 ? dragOffset : .zero) {
                    RoundedRectangle(cornerRadius: AppTheme.Radius.hero)
                        .fill(AppTheme.ColorToken.surface)
                }
                .opacity(currentIdea == nil ? 0 : 1)
                ForEach(flight.cards(in: visibleQueue, identifiedBy: { AnyHashable($0.id) })) { cardIdea in
                    let isCurrent = cardIdea.id == currentIdea?.id
                    let command = flight.current.flatMap { $0.card.id == cardIdea.id ? $0 : nil }
                    DecisionCard(
                        idea: cardIdea,
                        eventTitle: workspace.eventTitle(for: cardIdea),
                        currencyCode: workspace.currencyCode,
                        teamSummary: workspace.teamResponseSummary(for: cardIdea),
                        dragOffset: dragOffset,
                        transitionNamespace: decisionTransition
                    )
                    .frame(maxHeight: .infinity)
                    .modifier(DecisionCardDepth(depth: isCurrent || command != nil ? 0 : 1))
                    .overlay {
                        if !isCurrent && command == nil {
                            DecisionSwipeBackdrop(offset: dragOffset) { Color.clear }
                        }
                    }
                    .modifier(DecisionCardMotion(flight: command, dragOffset: isCurrent ? dragOffset : .zero,
                                                 onFinished: finishFlight))
                    .modifier(
                        DecisionSwipeInteraction(offset: dragBinding) { choice in
                            decide(choice, idea: cardIdea)
                        }
                    )
                    .onTapGesture {
                        openDetails(for: cardIdea)
                    }
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction(named: Text("Open details")) {
                        openDetails(for: cardIdea)
                    }
                    .accessibilityAction(named: Text("Pass")) {
                        decide(.pass, idea: cardIdea)
                    }
                    .accessibilityAction(named: Text("Maybe")) {
                        decide(.maybe, idea: cardIdea)
                    }
                    .accessibilityAction(named: Text("Love It")) {
                        decide(.love, idea: cardIdea)
                    }
                    .allowsHitTesting(isCurrent && command == nil)
                    .accessibilityHidden(!isCurrent || command != nil)
                    .zIndex(command != nil ? 3 : isCurrent ? 2 : 1)
                    .transition(.identity)
                }
                if currentIdea == nil {
                    ContentUnavailableView {
                        if session.filter == .maybes {
                            Label(
                                count(for: .maybes) > 0 ? "Maybes reviewed" : "No Maybes",
                                systemImage: "questionmark.circle")
                        } else if session.filter == .passes {
                            Label(
                                count(for: .passes) > 0 ? "Passes reviewed" : "No Passes",
                                systemImage: "hand.thumbsdown")
                        } else {
                            Label(
                                isFilteringToEvent ? "Nothing left for \(scopeTitle)" : "You're all caught up",
                                systemImage: "checkmark.circle.fill"
                            )
                        }
                    } description: {
                        if session.filter == .maybes {
                            Text(
                                count(for: .maybes) > 0
                                    ? "Your Maybe responses are kept. Revisit them whenever you're ready."
                                    : "Ideas you mark Maybe will appear here.")
                        } else if session.filter == .passes {
                            Text(
                                count(for: .passes) > 0
                                    ? "Your Pass responses are kept. Revisit them whenever you're ready."
                                    : "Ideas you pass on will appear here.")
                        } else {
                            Text(
                                isFilteringToEvent
                                    ? "Continue through the rest of your decision queue."
                                    : "New ideas from your support circle will appear here."
                            )
                        }
                    } actions: {
                        if session.filter != .unanswered {
                            if count(for: session.filter) > 0 {
                                Button(
                                    session.filter == .maybes ? "Review Maybes Again" : "Review Passes Again",
                                    systemImage: "arrow.clockwise"
                                ) {
                                    withAnimation(reduceMotion ? nil : .snappy) {
                                        drag = .init()
                                        flight.reset()
                                        session.restartReview()
                                    }
                                }
                                .buttonStyle(.bordered)
                            }
                            Button("Review Unanswered Ideas", systemImage: "tray") {
                                selectFilter(.unanswered)
                            }
                            .buttonStyle(.bordered)
                        }
                        if session.filter != .maybes && count(for: .maybes) > 0 {
                            Button("Review My Maybes", systemImage: "questionmark.circle") {
                                selectFilter(.maybes)
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        if session.filter != .passes && count(for: .passes) > 0 {
                            Button("Review My Passes", systemImage: "hand.thumbsdown") {
                                selectFilter(.passes)
                            }
                            .buttonStyle(.bordered)
                        }
                        if isFilteringToEvent {
                            Button("Continue deciding", systemImage: "arrow.triangle.branch") {
                                withAnimation(.snappy) {
                                    decisionScope = .queue
                                }
                            }
                            .buttonStyle(.bordered)
                        }

                    }
                    .frame(maxHeight: .infinity)
                    .transition(.opacity)
                }
            }
            // The artwork is masked by DecisionCard; the deck must not crop
            // the moving card or its shadow at the layout container's edges.
        }
        .padding(.horizontal, AppTheme.Layout.screenHorizontal)
        .padding(.top, AppTheme.Layout.screenTop)
        .padding(.bottom, AppTheme.Layout.screenTop)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.ColorToken.background)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .appClearNavigationBar()
        .toolbar {
            ToolbarItemGroup(placement: .topBarLeading) {
                decisionScopeMenu
                decisionResponseFilterMenu
            }

            ToolbarItem(placement: .topBarTrailing) {
                ToolbarGlassActionGroup {
                    if workspace.canUndoDecision {
                        Button("Undo last decision", systemImage: "arrow.uturn.backward") {
                            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.24)) {
                                if let ideaID = workspace.undoLastDecision() {
                                    let choice = motionHistory.undo(for: ideaID) ?? .love
                                    let restored = workspace.ideas.first { $0.id == ideaID }
                                    if !reduceMotion, let restored {
                                        flight.returnCard(restored, choice: choice) { $0.id == ideaID }
                                    } else {
                                        flight.reset()
                                    }
                                    let filter = DecisionQueueFilter(restoring: restored.flatMap(workspace.response(on:)))
                                    if session.filter != filter { session.selectFilter(filter) }
                                    session.undoDecision(on: ideaID)
                                }
                                drag = .init()
                                decisionScope = .queue
                            }
                        }
                        .labelStyle(.iconOnly)
                        .frame(width: 44, height: 44)
                    }

                    AccountToolbarButton(avatarSize: 28)
                        .frame(width: 44, height: 44)
                }
            }
            .sharedBackgroundVisibility(.hidden)
        }
        .navigationDestination(item: $selectedIdeaID) { ideaID in
            IdeaDetailView(
                ideaID: ideaID,
                transitionNamespace: decisionTransition
            )
        }
        .sheet(isPresented: $isShowingDecidePrimer) {
            DecideEventPrimer {
                hasSeenDecidePrimer = true
                isShowingDecidePrimer = false
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .task {
            presentPrimerIfNeeded()
        }
        .onChange(of: isActive) { _, isActive in
            guard isActive else { return }
            presentPrimerIfNeeded()
        }
        .onChange(of: isShowingDecidePrimer) { wasShowing, isShowing in
            if wasShowing && !isShowing {
                hasSeenDecidePrimer = true
            }
        }
        .onChange(of: currentUserAccount?.id) { _, _ in
            session = DecisionDeckSession()
            decisionScope = .queue
            drag = .init()
            motionHistory = .init()
            flight.reset()
        }
        .onDisappear {
            flight.reset()
            drag = .init()
        }
    }

    private var decisionResponseFilterMenu: some View {
        Menu {
            ForEach(DecisionQueueFilter.allCases, id: \.self) { filter in
                Button { selectFilter(filter) } label: {
                    Label {
                        Text("\(filter.title) (\(count(for: filter)))")
                    } icon: {
                        Image(systemName: session.filter == filter ? "checkmark" : filter.symbol)
                    }
                }
            }
        } label: {
            Label(session.filter.title, systemImage: session.filter.symbol)
                .labelStyle(.iconOnly)
                .frame(minWidth: AppTheme.Layout.minimumTouchTarget,
                       minHeight: AppTheme.Layout.minimumTouchTarget)
        }
        .accessibilityLabel("Decision response filter")
        .accessibilityValue(session.filter.title)
    }

    private func selectFilter(_ filter: DecisionQueueFilter) {
        flight.reset()
        withAnimation(reduceMotion ? nil : .snappy) {
            session.selectFilter(filter)
            drag = .init()
        }
    }

    private var decisionScopeMenu: some View {
        Menu {
            Button {
                decisionScope = .queue
            } label: {
                Label(
                    "Follow decision queue",
                    systemImage: decisionScope == .queue ? "checkmark" : "arrow.triangle.branch"
                )
            }

            Divider()

            ForEach(workspace.availableEventContexts, id: \.self) { reference in
                let scope = DecisionScope.event(eventID(for: reference))
                Button {
                    decisionScope = scope
                } label: {
                    Label(
                        workspace.eventTitle(for: eventID(for: reference)),
                        systemImage: decisionScope == scope ? "checkmark" : "calendar"
                    )
                }
            }
        } label: {
            Label("Decision event filter", systemImage: "calendar")
                .labelStyle(.iconOnly)
                .frame(minWidth: AppTheme.Layout.minimumTouchTarget,
                       minHeight: AppTheme.Layout.minimumTouchTarget)
        }
        .accessibilityLabel("Decision event filter")
        .accessibilityIdentifier("decision-event-filter")
        .accessibilityValue(isFilteringToEvent ? "\(scopeTitle), filtered" : "\(scopeTitle), following queue")
    }

    private func presentPrimerIfNeeded() {
        guard DecidePrimerPresentationPolicy.shouldPresent(
            hasSeenPrimer: hasSeenDecidePrimer,
            isDecideTabActive: isActive
        ) else { return }

        isShowingDecidePrimer = true
    }

    private func decide(_ choice: DecisionChoice, idea: PlanningIdea) {
        guard currentIdea?.id == idea.id, workspace.canRespond(to: idea) else { return }
        flight.reset()
        if !reduceMotion {
            flight.start(card: idea, choice: choice, origin: dragOffset)
        }
        drag = .init()
        motionHistory.record(choice, for: idea.id)
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.22)) {
            workspace.decide(choice, on: idea)
            session.recordDecision(on: idea.id)
            PostHogSDK.shared.capture(
                "idea_decided",
                properties: ["choice": String(describing: choice)]
            )
            returnToQueueIfNeeded()
        }
    }

    private func finishFlight(_ token: UUID) {
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) { _ = flight.finish(token) }
    }

    private func returnToQueueIfNeeded() {
        guard case .event(let eventID) = decisionScope,
              session.queue(in: workspace, eventID: eventID)
                .allSatisfy({ safety.isBlocked($0.submittedByUserID) }) else {
            return
        }
        decisionScope = .queue
    }

    private func eventID(for reference: EventReference) -> UUID {
        switch reference {
        case .main:
            workspace.mainEventID
        case .subevent(let eventID):
            eventID
        case .idea:
            workspace.mainEventID
        }
    }

    private func openDetails(for idea: PlanningIdea) {
        guard abs(dragOffset.width) < 10, abs(dragOffset.height) < 10 else { return }
        drag = .init()
        selectedIdeaID = idea.id
    }
}

private struct DecisionCard: View {
    @Environment(ImageSafetyStore.self) private var imageSafety

    let idea: PlanningIdea
    let eventTitle: String
    let currencyCode: String
    let teamSummary: TeamResponseSummary
    let dragOffset: CGSize
    let transitionNamespace: Namespace.ID

    var body: some View {
        DecisionCardPresentation {
            artwork
        } guide: {
            DecisionEventHeading(title: eventTitle)
        } feedback: {
            EmptyView()
        } summary: {
            ideaDetails
        }
        .foregroundStyle(.primary)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.hero, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.Radius.hero, style: .continuous)
                .stroke(Color(uiColor: .separator), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.18), radius: 20, y: 10)
        .matchedTransitionSource(id: idea.id, in: transitionNamespace)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens idea details. Swipe left to pass, right to love it, or up to save for later.")
    }

    @ViewBuilder
    private var artwork: some View {
        if idea.category == .music {
            MusicPlaylistArtwork(
                imageData: imageSafety.visibleImageData(idea.imageData, assetID: idea.mediaAssetID),
                tracks: idea.musicTracks,
                symbol: idea.category.symbol,
                colors: idea.category.artworkColors,
                accent: idea.category.artworkAccent,
                blurStart: 0.46
            )
        } else {
            MediaArtwork(
                imageData: imageSafety.visibleImageData(idea.imageData, assetID: idea.mediaAssetID),
                symbol: idea.category.symbol,
                colors: idea.category.artworkColors,
                accent: idea.category.artworkAccent,
                blurStart: 0.46
            )
        }
    }

    private var ideaDetails: some View {
        IdeaSummaryCard(idea: idea, currencyCode: currencyCode, teamSummary: teamSummary)
    }

}

/// The same summary surface in the deck and its expanded detail destination.
struct IdeaSummaryCard<Footer: View>: View {
    let idea: PlanningIdea
    let currencyCode: String
    let teamSummary: TeamResponseSummary
    @ViewBuilder var footer: () -> Footer

    var body: some View {
        IdeaSummaryContent(title: idea.title, note: idea.note, category: idea.category) {
            if let cost = idea.estimatedCost {
                Text(cost, format: .currency(code: currencyCode).precision(.fractionLength(0)))
                    .font(.subheadline.weight(.semibold))
            }
        } footer: {
            IdeaSummaryCollaboration(idea: idea, teamSummary: teamSummary, footer: footer)
        }
    }

}

/// Live-only summary content. Template previews never instantiate this view.
struct IdeaSummaryCollaboration<Footer: View>: View {
    let idea: PlanningIdea
    let teamSummary: TeamResponseSummary
    @ViewBuilder var footer: () -> Footer

    var body: some View {
        Group {
            TeamResponseBar(summary: teamSummary, ideaStatus: idea.status, showsTitle: false)
                .id(idea.id)

            Label(idea.submittedBy, systemImage: "person.crop.circle.fill")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel("Suggested by \(idea.submittedBy)")

            footer()
        }
    }

}

extension IdeaSummaryCard where Footer == EmptyView {
    init(idea: PlanningIdea, currencyCode: String, teamSummary: TeamResponseSummary) {
        self.init(idea: idea, currencyCode: currencyCode, teamSummary: teamSummary) { EmptyView() }
    }
}

private enum DecisionScope: Hashable {
    case queue
    case event(UUID)

    var eventID: UUID? {
        guard case .event(let eventID) = self else { return nil }
        return eventID
    }
}

#if DEBUG
private struct DecisionCardAppearancePreview: View {
    @Namespace private var transition
    @State private var safety = ImageSafetyStore()
    @State private var replayID = 0
    private let idea = PlanningIdea(
        title: "Reception Decor", note: "", category: .decor,
        submittedBy: "Julio Flores Cercado"
    )

    var body: some View {
        VStack {
            Button { replayID += 1 } label: { Text(verbatim: "Replay entrance") }
                .buttonStyle(.bordered)
            DecisionCard(
                idea: idea, eventTitle: "Wedding reception", currencyCode: "USD",
                teamSummary: .init(love: 1, unanswered: 1),
                dragOffset: .zero, transitionNamespace: transition
            )
            .id(replayID)
        }
        .padding(16)
        .background(Color(uiColor: .systemBackground))
        .environment(safety)
    }
}

#Preview("Decide card · Light") {
    DecisionCardAppearancePreview().preferredColorScheme(.light)
}

#Preview("Decide card · Dark") {
    DecisionCardAppearancePreview().preferredColorScheme(.dark)
}

#endif
