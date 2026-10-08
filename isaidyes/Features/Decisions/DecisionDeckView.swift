import SwiftUI
import Glur

struct DecisionDeckView: View {
    @Environment(WeddingWorkspace.self) private var workspace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dragOffset: CGSize = .zero

    private var currentIdea: WeddingIdea? {
        workspace.decisionQueue.first
    }

    var body: some View {
        VStack(spacing: AppTheme.Spacing.compact) {
            if let idea = currentIdea {
                DecisionCard(idea: idea, dragOffset: dragOffset)
                    .frame(maxHeight: .infinity)
                    .offset(dragOffset)
                    .rotationEffect(.degrees(Double(dragOffset.width / 24)))
                    .gesture(dragGesture(for: idea))
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
        .toolbarVisibility(.hidden, for: .navigationBar)
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
}

private struct DecisionCard: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    let idea: WeddingIdea
    let dragOffset: CGSize

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
        .accessibilityElement(children: .combine)
        .accessibilityHint("Swipe left to pass, right to love it, or up to save for later.")
    }

    @ViewBuilder
    private var artwork: some View {
        if reduceTransparency {
            DecisionArtwork(category: idea.category)
        } else {
            DecisionArtwork(category: idea.category)
                .glur(
                    radius: 22,
                    mask: .linear(
                        stops: [
                            .init(intensity: 0, location: 0),
                            .init(intensity: 0, location: 0.38),
                            .init(intensity: 0.22, location: 0.54),
                            .init(intensity: 0.72, location: 0.72),
                            .init(intensity: 1, location: 0.88)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    noise: 0.035
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
                    Text(cost, format: .currency(code: Locale.current.currency?.identifier ?? "USD").precision(.fractionLength(0)))
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

private struct DecisionArtwork: View {
    let category: IdeaCategory

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                LinearGradient(
                    colors: category.artworkColors,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                Circle()
                    .fill(.white.opacity(0.26))
                    .frame(width: proxy.size.width * 0.92)
                    .blur(radius: 36)
                    .offset(x: -proxy.size.width * 0.34, y: -proxy.size.height * 0.34)

                Circle()
                    .fill(category.artworkAccent.opacity(0.72))
                    .frame(width: proxy.size.width * 1.08)
                    .blur(radius: 42)
                    .offset(x: proxy.size.width * 0.42, y: proxy.size.height * 0.18)

                Image(systemName: category.symbol)
                    .font(.system(size: min(proxy.size.width * 0.34, 136), weight: .ultraLight))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.white.opacity(0.82))
                    .shadow(color: .black.opacity(0.14), radius: 24, y: 12)
                    .offset(y: -proxy.size.height * 0.16)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .accessibilityHidden(true)
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

private extension IdeaCategory {
    var artworkColors: [Color] {
        switch self {
        case .venue: [Color(red: 0.34, green: 0.23, blue: 0.62), Color(red: 0.78, green: 0.59, blue: 0.86), Color(red: 0.96, green: 0.72, blue: 0.62)]
        case .attire: [Color(red: 0.32, green: 0.19, blue: 0.31), Color(red: 0.78, green: 0.45, blue: 0.58), Color(red: 0.96, green: 0.78, blue: 0.72)]
        case .flowers: [Color(red: 0.16, green: 0.36, blue: 0.30), Color(red: 0.78, green: 0.40, blue: 0.42), Color(red: 0.98, green: 0.72, blue: 0.55)]
        case .food: [Color(red: 0.42, green: 0.20, blue: 0.12), Color(red: 0.82, green: 0.48, blue: 0.24), Color(red: 0.98, green: 0.79, blue: 0.49)]
        case .photography: [Color(red: 0.10, green: 0.22, blue: 0.29), Color(red: 0.19, green: 0.55, blue: 0.57), Color(red: 0.76, green: 0.78, blue: 0.62)]
        case .music: [Color(red: 0.14, green: 0.15, blue: 0.32), Color(red: 0.45, green: 0.28, blue: 0.68), Color(red: 0.93, green: 0.43, blue: 0.55)]
        case .decor: [Color(red: 0.24, green: 0.16, blue: 0.43), Color(red: 0.56, green: 0.38, blue: 0.78), Color(red: 0.96, green: 0.65, blue: 0.56)]
        case .invitations: [Color(red: 0.22, green: 0.35, blue: 0.43), Color(red: 0.48, green: 0.67, blue: 0.64), Color(red: 0.94, green: 0.76, blue: 0.60)]
        case .honeymoon: [Color(red: 0.08, green: 0.40, blue: 0.57), Color(red: 0.32, green: 0.70, blue: 0.75), Color(red: 0.98, green: 0.68, blue: 0.38)]
        case .other: [Color(red: 0.25, green: 0.20, blue: 0.49), Color(red: 0.70, green: 0.40, blue: 0.72), Color(red: 0.97, green: 0.61, blue: 0.54)]
        }
    }

    var artworkAccent: Color {
        artworkColors.last ?? tint
    }
}

#Preview {
    NavigationStack {
        DecisionDeckView()
            .environment(WeddingWorkspace.sample)
    }
}
