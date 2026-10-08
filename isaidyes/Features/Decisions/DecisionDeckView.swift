import SwiftUI

struct DecisionDeckView: View {
    @Environment(WeddingWorkspace.self) private var workspace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dragOffset: CGSize = .zero

    private var currentIdea: WeddingIdea? {
        workspace.decisionQueue.first
    }

    var body: some View {
        VStack(spacing: AppTheme.Spacing.spacious) {
            if let idea = currentIdea {
                deckProgress

                DecisionCard(idea: idea, dragOffset: dragOffset)
                    .offset(dragOffset)
                    .rotationEffect(.degrees(Double(dragOffset.width / 24)))
                    .gesture(dragGesture(for: idea))
                    .animation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.82), value: dragOffset)

                decisionButtons(for: idea)
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
        .padding(AppTheme.Spacing.standard)
        .background(AppTheme.ColorToken.background)
        .navigationTitle("Decision deck")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Undo", systemImage: "arrow.uturn.backward") {
                    workspace.undoLastDecision()
                }
                .labelStyle(.iconOnly)
                .disabled(!workspace.canUndoDecision)
            }
        }
    }

    private var deckProgress: some View {
        HStack {
            Text("\(workspace.decisionQueue.count) ideas waiting")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    private func decisionButtons(for idea: WeddingIdea) -> some View {
        HStack(spacing: AppTheme.Spacing.spacious) {
            DecisionButton(title: "Pass", symbol: "xmark", tint: .secondary) {
                decide(.pass, idea: idea)
            }

            DecisionButton(title: "Maybe", symbol: "bookmark.fill", tint: .orange) {
                decide(.maybe, idea: idea)
            }

            DecisionButton(title: "Love it", symbol: "heart.fill", tint: .pink) {
                decide(.love, idea: idea)
            }
        }
        .frame(maxWidth: .infinity)
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
                LinearGradient(
                    colors: [idea.category.tint.opacity(0.58), idea.category.tint],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                Image(systemName: idea.category.symbol)
                    .font(.system(size: 88, weight: .light))
                    .foregroundStyle(.white.opacity(0.9))
                    .accessibilityHidden(true)

                swipeFeedback
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 240)

            VStack(alignment: .leading, spacing: AppTheme.Spacing.standard) {
                HStack {
                    Label(idea.category.title, systemImage: idea.category.symbol)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(idea.category.tint)
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
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Label("Suggested by \(idea.submittedBy)", systemImage: "person.crop.circle")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(AppTheme.Spacing.spacious)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.ColorToken.surface)
        }
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.hero))
        .shadow(color: .black.opacity(0.12), radius: 18, y: 8)
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

private struct DecisionButton: View {
    let title: String
    let symbol: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.title3.bold())
                    .frame(width: 52, height: 52)
                    .background(tint.opacity(0.14), in: Circle())
                Text(title)
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(tint)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .accessibilityLabel(title)
    }
}

#Preview {
    NavigationStack {
        DecisionDeckView()
            .environment(WeddingWorkspace.sample)
    }
}
