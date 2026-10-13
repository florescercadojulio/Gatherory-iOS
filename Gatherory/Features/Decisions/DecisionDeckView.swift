import SwiftUI

enum DecidePrimerPresentationPolicy {
    static func shouldPresent(hasSeenPrimer: Bool, isDecideTabActive: Bool) -> Bool {
        !hasSeenPrimer && isDecideTabActive
    }
}

struct DecisionDeckView: View {
    var isActive = true
    var onExitWorkspace: (() -> Void)?

    @Environment(PlanningWorkspace.self) private var workspace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("hasSeenDecideTimelinePrimer") private var hasSeenDecidePrimer = false
    @State private var dragOffset: CGSize = .zero
    @State private var selectedIdeaID: UUID?
    @State private var isShowingDecidePrimer = false
    @State private var decisionScope: DecisionScope = .queue
    @Namespace private var decisionTransition

    private var currentIdea: PlanningIdea? {
        workspace.decisionQueue(for: decisionScope.eventID).first
    }

    private var scopeTitle: String {
        switch decisionScope {
        case .queue:
            currentIdea.map(workspace.eventTitle(for:)) ?? "Decide"
        case .event(let eventID):
            workspace.eventTitle(for: eventID)
        }
    }

    private var isFilteringToEvent: Bool {
        decisionScope.eventID != nil
    }

    var body: some View {
        VStack(spacing: AppTheme.Spacing.compact) {
            if let idea = currentIdea {
                DecisionCard(
                    idea: idea,
                    eventTitle: idea.category == .event ? nil : workspace.eventTitle(for: idea),
                    currencyCode: workspace.currencyCode,
                    dragOffset: dragOffset,
                    transitionNamespace: decisionTransition
                )
                    .frame(maxHeight: .infinity)
                    .offset(dragOffset)
                    .rotationEffect(.degrees(Double(dragOffset.width / 24)))
                    .gesture(dragGesture(for: idea))
                    .onTapGesture {
                        openDetails(for: idea)
                    }
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction(named: Text("Open details")) {
                        openDetails(for: idea)
                    }
                    .accessibilityAction(named: Text("Pass")) {
                        decide(.pass, idea: idea)
                    }
                    .accessibilityAction(named: Text("Maybe")) {
                        decide(.maybe, idea: idea)
                    }
                    .accessibilityAction(named: Text("Love It")) {
                        decide(.love, idea: idea)
                    }
                    .animation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.82), value: dragOffset)
            } else {
                ContentUnavailableView {
                    Label(
                        isFilteringToEvent ? "Nothing left for \(scopeTitle)" : "You're all caught up",
                        systemImage: "checkmark.circle.fill"
                    )
                } description: {
                    Text(
                        isFilteringToEvent
                            ? "Continue through the rest of your decision queue."
                            : "New ideas from your support circle will appear here."
                    )
                } actions: {
                    if isFilteringToEvent {
                        Button("Continue deciding", systemImage: "arrow.triangle.branch") {
                            withAnimation(.snappy) {
                                decisionScope = .queue
                            }
                        }
                        .buttonStyle(.bordered)
                    }

                    if workspace.canUndoDecision {
                        Button("Undo last decision", systemImage: "arrow.uturn.backward") {
                            workspace.undoLastDecision()
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .frame(maxHeight: .infinity)
            }
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
            ToolbarItem(placement: .topBarLeading) {
                decisionScopeMenu
            }

            ToolbarItem(placement: .topBarTrailing) {
                AccountToolbarButton()
            }
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
            HStack(spacing: 5) {
                Text(scopeTitle)
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption.weight(.semibold))
            }
            .font(.headline.weight(.semibold))
            .foregroundStyle(.primary)
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

    private func dragGesture(for idea: PlanningIdea) -> some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { value in
                dragOffset = value.translation
            }
            .onEnded { value in
                if value.translation.width > 100 {
                    decide(.love, idea: idea)
                } else if value.translation.width < -100 {
                    decide(.pass, idea: idea)
                } else if value.translation.height < -100 {
                    decide(.maybe, idea: idea)
                } else {
                    dragOffset = .zero
                }
            }
    }

    private func decide(_ choice: DecisionChoice, idea: PlanningIdea) {
        withAnimation(reduceMotion ? nil : .snappy) {
            workspace.decide(choice, on: idea)
            dragOffset = .zero
            returnToQueueIfNeeded()
        }
    }

    private func returnToQueueIfNeeded() {
        guard case .event(let eventID) = decisionScope,
              workspace.decisionQueue(for: eventID).isEmpty else {
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
        dragOffset = .zero
        selectedIdeaID = idea.id
    }
}

private struct DecisionCard: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    let idea: PlanningIdea
    let eventTitle: String?
    let currencyCode: String
    let dragOffset: CGSize
    let transitionNamespace: Namespace.ID

    var body: some View {
        ZStack {
            artwork

            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.28),
                    .init(color: .black.opacity(0.14), location: 0.48),
                    .init(color: .black.opacity(reduceTransparency ? 0.88 : 0.72), location: 0.78),
                    .init(color: .black.opacity(reduceTransparency ? 0.96 : 0.88), location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(spacing: 0) {
                SwipeGuide()

                Spacer(minLength: AppTheme.Spacing.section)

                swipeFeedback

                Spacer(minLength: AppTheme.Spacing.standard)

                ideaDetails
            }
            .padding(AppTheme.Spacing.standard)
        }
        .foregroundStyle(.white)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.hero, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.Radius.hero, style: .continuous)
                .stroke(.white.opacity(0.16), lineWidth: 1)
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
                imageData: idea.imageData,
                tracks: idea.musicTracks,
                symbol: idea.category.symbol,
                colors: idea.category.artworkColors,
                accent: idea.category.artworkAccent
            )
        } else {
            MediaArtwork(
                imageData: idea.imageData,
                symbol: idea.category.symbol,
                colors: idea.category.artworkColors,
                accent: idea.category.artworkAccent
            )
        }
    }

    private var ideaDetails: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let eventTitle {
                Label(eventTitle, systemImage: "calendar")
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .padding(.horizontal, 10)
                    .frame(minHeight: AppTheme.Layout.minimumTouchTarget)
                    .background(.black.opacity(reduceTransparency ? 0.72 : 0.24), in: Capsule())
                    .overlay {
                        Capsule()
                            .stroke(.white.opacity(0.14), lineWidth: 0.5)
                    }
                    .accessibilityLabel("For \(eventTitle)")
            }

            HStack(spacing: AppTheme.Spacing.compact) {
                Label(idea.category.title, systemImage: idea.category.symbol)
                    .font(.caption.weight(.semibold))

                Spacer(minLength: AppTheme.Spacing.compact)

                if let cost = idea.estimatedCost {
                    Text(cost, format: .currency(code: currencyCode).precision(.fractionLength(0)))
                        .font(.subheadline.weight(.semibold))
                }
            }

            Text(idea.title)
                .font(.largeTitle.bold())
                .tracking(-0.7)
                .fixedSize(horizontal: false, vertical: true)

            Text(idea.note)
                .font(.body)
                .foregroundStyle(.white.opacity(0.82))
                .fixedSize(horizontal: false, vertical: true)

            Label("Suggested by \(idea.submittedBy)", systemImage: "person.crop.circle.fill")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white.opacity(0.9))
                .padding(.horizontal, 12)
                .frame(minHeight: AppTheme.Layout.minimumTouchTarget)
                .background(.black.opacity(reduceTransparency ? 0.72 : 0.24), in: Capsule())
                .overlay {
                    Capsule()
                        .stroke(.white.opacity(0.14), lineWidth: 0.5)
                }
        }
        .padding(AppTheme.Spacing.standard)
        .background(.black.opacity(reduceTransparency ? 0.62 : 0.18), in: RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous)
                .stroke(.white.opacity(0.12), lineWidth: 0.5)
        }
    }

    @ViewBuilder
    private var swipeFeedback: some View {
        if dragOffset.width > 35 {
            SwipeLabel(title: "Love it", symbol: "heart.fill")
        } else if dragOffset.width < -35 {
            SwipeLabel(title: "Pass", symbol: "xmark")
        } else if dragOffset.height < -35 {
            SwipeLabel(title: "Maybe", symbol: "bookmark.fill")
        }
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

private struct SwipeLabel: View {
    let title: String
    let symbol: String

    var body: some View {
        Label(title, systemImage: symbol)
            .font(.title2.bold())
            .padding(.horizontal, AppTheme.Spacing.standard)
            .padding(.vertical, AppTheme.Spacing.compact)
            .background(.black.opacity(0.55), in: Capsule())
            .foregroundStyle(.white)
    }
}

private struct SwipeGuide: View {
    var body: some View {
        HStack(spacing: 6) {
            SwipeGuideLabel(title: "Pass", symbol: "arrow.left")
            Spacer(minLength: 0)
            SwipeGuideLabel(title: "Maybe", symbol: "arrow.up")
            Spacer(minLength: 0)
            SwipeGuideLabel(title: "Love", symbol: "arrow.right")
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Swipe left to pass, up for maybe, or right to love")
    }
}

private struct SwipeGuideLabel: View {
    let title: String
    let symbol: String

    var body: some View {
        Label(title, systemImage: symbol)
            .font(.caption.weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .frame(minHeight: AppTheme.Layout.minimumTouchTarget)
            .background(.black.opacity(0.28), in: Capsule())
            .overlay {
                Capsule()
                    .stroke(.white.opacity(0.16), lineWidth: 0.5)
            }
    }
}

#Preview {
    NavigationStack {
        DecisionDeckView()
            .environment(PlanningWorkspace.sample)
            .environment(MusicCatalog())
    }
}
