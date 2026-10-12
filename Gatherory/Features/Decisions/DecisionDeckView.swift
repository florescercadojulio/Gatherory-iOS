import SwiftUI

enum DecidePrimerPresentationPolicy {
    static func shouldPresent(hasSeenPrimer: Bool, isDecideTabActive: Bool) -> Bool {
        !hasSeenPrimer && isDecideTabActive
    }
}

struct DecisionDeckView: View {
    var isActive = true
    var onExitWorkspace: (() -> Void)?

    @Environment(WeddingWorkspace.self) private var workspace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("hasSeenDecideTimelinePrimer") private var hasSeenTimelinePrimer = false
    @State private var dragOffset: CGSize = .zero
    @State private var selectedIdeaID: UUID?
    @State private var isShowingTimelinePrimer = false
    @Namespace private var decisionTransition

    private var currentIdea: WeddingIdea? {
        workspace.decisionQueue.first
    }

    var body: some View {
        VStack(spacing: AppTheme.Spacing.compact) {
            if let idea = currentIdea {
                DecisionCard(
                    idea: idea,
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
                    Label("You're all caught up", systemImage: "checkmark.circle.fill")
                } description: {
                    Text("New ideas from your support circle will appear here.")
                } actions: {
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
        .navigationTitle("Decide")
        .navigationBarTitleDisplayMode(.inline)
        .appClearNavigationBar()
        .toolbar {
            ToolbarItem(placement: .principal) {
                EventContextLabel(section: "Decide", eventTitle: workspace.selectedEventTitle)
            }

            if let onExitWorkspace {
                ToolbarItem(placement: .topBarLeading) {
                    WorkspaceLibraryToolbarButton(action: onExitWorkspace)
                }
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
        .sheet(isPresented: $isShowingTimelinePrimer) {
            DecideTimelinePrimer {
                hasSeenTimelinePrimer = true
                isShowingTimelinePrimer = false
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
        .onChange(of: isShowingTimelinePrimer) { wasShowing, isShowing in
            if wasShowing && !isShowing {
                hasSeenTimelinePrimer = true
            }
        }
    }

    private func presentPrimerIfNeeded() {
        guard DecidePrimerPresentationPolicy.shouldPresent(
            hasSeenPrimer: hasSeenTimelinePrimer,
            isDecideTabActive: isActive
        ) else { return }

        isShowingTimelinePrimer = true
    }

    private func dragGesture(for idea: WeddingIdea) -> some Gesture {
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

    private func decide(_ choice: DecisionChoice, idea: WeddingIdea) {
        withAnimation(reduceMotion ? nil : .snappy) {
            workspace.decide(choice, on: idea)
            dragOffset = .zero
        }
    }

    private func openDetails(for idea: WeddingIdea) {
        guard abs(dragOffset.width) < 10, abs(dragOffset.height) < 10 else { return }
        dragOffset = .zero
        selectedIdeaID = idea.id
    }
}

private struct DecideTimelinePrimer: View {
    let continueAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.section) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.compact) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.title.bold())
                    .foregroundStyle(AppTheme.ColorToken.accent)
                    .accessibilityHidden(true)

                Text("Decide what moves forward")
                    .font(.title2.bold())

                Text("Love an idea to approve it. Gatherory sends approved event ideas to Timeline so the next step is always clear.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: AppTheme.Spacing.standard) {
                primerRow(
                    symbol: "calendar.badge.checkmark",
                    title: "Already has a date",
                    detail: "It joins your scheduled events."
                )
                primerRow(
                    symbol: "calendar.badge.exclamationmark",
                    title: "Still needs a date",
                    detail: "It waits in Timeline under Needs Date and stays off Home until you schedule it."
                )
            }

            Spacer(minLength: 0)

            Button(action: continueAction) {
                Text("Start Deciding")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
        }
        .padding(AppTheme.Spacing.spacious)
        .background(AppTheme.ColorToken.background)
    }

    private func primerRow(symbol: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: AppTheme.Spacing.standard) {
            Image(systemName: symbol)
                .font(.title3.weight(.semibold))
                .foregroundStyle(AppTheme.ColorToken.accent)
                .frame(width: 32)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct DecisionCard: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    let idea: WeddingIdea
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
            .environment(WeddingWorkspace.sample)
            .environment(MusicCatalog())
    }
}
