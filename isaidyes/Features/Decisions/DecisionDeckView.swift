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
    let idea: WeddingIdea
    let dragOffset: CGSize

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                idea.category.tint

                Image(systemName: idea.category.symbol)
                    .font(.system(size: 112, weight: .light))
                    .foregroundStyle(.black.opacity(0.76))
                    .accessibilityHidden(true)
            }
            .glur(
                radius: 12,
                offset: 0.58,
                interpolation: 0.34,
                direction: .up,
                noise: 0.04
            )
            .overlay(alignment: .top) {
                SwipeGuide()
                    .padding(AppTheme.Spacing.standard)
            }
            .overlay {
                swipeFeedback
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 330, maxHeight: .infinity)

            VStack(alignment: .leading, spacing: AppTheme.Spacing.standard) {
                HStack {
                    Label(idea.category.title, systemImage: idea.category.symbol)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(AppTheme.ColorToken.lime, in: Capsule())
                    Spacer()
                    if let cost = idea.estimatedCost {
                        Text(cost, format: .currency(code: Locale.current.currency?.identifier ?? "USD").precision(.fractionLength(0)))
                            .font(.subheadline.weight(.semibold))
                    }
                }

                Text(idea.title)
                    .font(.title2.bold())
                    .fixedSize(horizontal: false, vertical: true)

                Text(idea.note)
                    .font(.body)
                    .foregroundStyle(.black.opacity(0.62))
                    .fixedSize(horizontal: false, vertical: true)

                Label("Suggested by \(idea.submittedBy)", systemImage: "person.crop.circle")
                    .font(.subheadline)
                    .foregroundStyle(.black.opacity(0.58))
            }
            .padding(AppTheme.Spacing.spacious)
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(.black)
            .background(AppTheme.ColorToken.cream)
        }
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.hero, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.Radius.hero, style: .continuous)
                .stroke(.black.opacity(0.08), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.1), radius: 16, y: 8)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Swipe left to pass, right to love it, or up to save for later. Decision buttons are also available below.")
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
            .padding(.vertical, 7)
            .background(.black.opacity(0.58), in: Capsule())
    }
}

#Preview {
    NavigationStack {
        DecisionDeckView()
            .environment(WeddingWorkspace.sample)
    }
}
