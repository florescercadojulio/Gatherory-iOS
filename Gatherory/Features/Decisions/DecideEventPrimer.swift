import SwiftUI

/// A local practice deck: trying a choice never touches workspace decisions.
struct DecideEventPrimer: View {
    let continueAction: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var previewChoice: DecidePrimerChoice?
    @ScaledMetric(relativeTo: .footnote) private var feedbackHeight = 40

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                practiceDeck

                VStack(spacing: AppTheme.Spacing.section) {
                    VStack(spacing: AppTheme.Spacing.standard) {
                        Text(AppCopy.Primer.Decide.title)
                            .font(AppTheme.Typography.display)
                            .multilineTextAlignment(.center)
                            .accessibilityAddTraits(.isHeader)

                        Text(AppCopy.Primer.Decide.message)
                            .font(.title3)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .fixedSize(horizontal: false, vertical: true)

                    VStack(alignment: .leading, spacing: AppTheme.Spacing.spacious) {
                        primerRow(
                            symbol: "calendar.badge.checkmark",
                            title: AppCopy.Primer.Decide.datedTitle,
                            detail: AppCopy.Primer.Decide.datedDetail
                        )
                        primerRow(
                            symbol: "lightbulb",
                            title: AppCopy.Primer.Decide.undatedTitle,
                            detail: AppCopy.Primer.Decide.undatedDetail
                        )
                    }
                }
                .padding(AppTheme.Spacing.spacious)
            }
            .frame(maxWidth: 680)
            .background(AppTheme.ColorToken.surface)
            .clipShape(RoundedRectangle(cornerRadius: 44, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 44, style: .continuous)
                    .stroke(AppTheme.ColorToken.cardBorder, lineWidth: 0.5)
            }
            .padding(AppTheme.Spacing.compact)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaInset(edge: .bottom) {
            Button(action: continueAction) {
                Text(AppCopy.Primer.Decide.action)
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: AppTheme.Layout.minimumTouchTarget)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .frame(maxWidth: 632)
            .padding(.horizontal, AppTheme.Spacing.spacious)
            .padding(.vertical, AppTheme.Spacing.standard)
            .frame(maxWidth: .infinity)
            .background(AppTheme.ColorToken.background)
        }
        .background(AppTheme.ColorToken.background.ignoresSafeArea())
        .tint(AppTheme.ColorToken.accent)
    }

    private var practiceDeck: some View {
        VStack(spacing: AppTheme.Spacing.standard) {
            previewCard
                .rotationEffect(.degrees(reduceMotion ? 0 : previewChoice?.rotation ?? 0))
                .offset(x: reduceMotion ? 0 : previewChoice?.offset ?? 0)
                .background {
                    RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous)
                        .fill(AppTheme.ColorToken.onMedia.opacity(0.08))
                        .rotationEffect(.degrees(reduceMotion ? 0 : -9))
                        .offset(x: -13, y: 6)
                }
                .background {
                    RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous)
                        .fill(AppTheme.ColorToken.onMedia.opacity(0.12))
                        .rotationEffect(.degrees(reduceMotion ? 0 : 6))
                        .offset(x: 10, y: 3)
                }
                .padding(.vertical, AppTheme.Spacing.compact)
                .frame(maxWidth: .infinity)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: AppTheme.Spacing.compact) { practiceButtons }
                VStack(spacing: AppTheme.Spacing.compact) { practiceButtons }
            }

            Text(previewChoice?.feedback ?? AppCopy.Primer.Decide.practiceInstruction)
                .font(.footnote)
                .foregroundStyle(AppTheme.ColorToken.onMedia.opacity(0.85))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(minHeight: feedbackHeight, alignment: .top)
                .accessibilityIdentifier("decide-primer-feedback")
        }
        .padding(AppTheme.Spacing.spacious)
        .background {
            RadialGradient(
                colors: [AppTheme.ColorToken.accentSecondary.opacity(0.32), AppTheme.ColorToken.inverseCanvas],
                center: .center,
                startRadius: 12,
                endRadius: 320
            )
            .background(AppTheme.ColorToken.inverseCanvas)
        }
        .environment(\.colorScheme, .dark)
        .animation(reduceMotion ? nil : .snappy(duration: 0.28), value: previewChoice)
    }

    private var previewCard: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.standard) {
            Label(previewChoice?.title ?? AppCopy.Primer.Decide.practiceLabel, systemImage: previewChoice?.symbol ?? "hand.draw")
                .font(.caption.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(AppTheme.ColorToken.mediaScrim.opacity(0.88), in: Capsule())

            Spacer(minLength: AppTheme.Spacing.section)
            VStack(alignment: .leading, spacing: AppTheme.Spacing.compact) {
                Text(AppCopy.Primer.Decide.exampleEvent)
                    .font(.caption.weight(.semibold))
                Text(AppCopy.Primer.Decide.exampleTitle)
                    .font(.title3.bold())
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(AppTheme.Spacing.standard)
        .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? 320 : 220, minHeight: 190, alignment: .bottomLeading)
        .foregroundStyle(AppTheme.ColorToken.onMedia)
        .background {
            Image("DefaultVenueHero")
                .resizable()
                .scaledToFill()
                .overlay {
                    LinearGradient(
                        colors: [.clear, AppTheme.ColorToken.mediaScrim.opacity(0.95)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
        }
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(AppCopy.Primer.Decide.exampleTitle)
        .accessibilityHint(AppCopy.Primer.Decide.practiceAccessibilityHint)
        .accessibilityIdentifier("decide-primer-preview")
        .accessibilityAction(named: Text(AppCopy.Primer.Decide.pass)) { previewChoice = .pass }
        .accessibilityAction(named: Text(AppCopy.Primer.Decide.maybe)) { previewChoice = .maybe }
        .accessibilityAction(named: Text(AppCopy.Primer.Decide.love)) { previewChoice = .love }
        .gesture(
            DragGesture(minimumDistance: 20).onEnded { value in
                if value.translation.width > 40 { previewChoice = .love }
                else if value.translation.width < -40 { previewChoice = .pass }
                else if value.translation.height < -40 { previewChoice = .maybe }
            }
        )
    }

    @ViewBuilder
    private var practiceButtons: some View {
        ForEach(DecidePrimerChoice.allCases, id: \.self) { choice in
            Button {
                previewChoice = choice
            } label: {
                Label(choice.title, systemImage: choice.directionSymbol)
                    .font(.subheadline.weight(.semibold))
                    .fixedSize(horizontal: true, vertical: false)
                    .frame(maxWidth: .infinity, minHeight: AppTheme.Layout.minimumTouchTarget)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .tint(AppTheme.ColorToken.onMedia)
            .accessibilityIdentifier("decide-primer-\(choice.rawValue)")
        }
    }

    private func primerRow(symbol: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: AppTheme.Spacing.standard) {
            Image(systemName: symbol)
                .font(.title2.weight(.semibold))
                .foregroundStyle(AppTheme.ColorToken.accent)
                .frame(width: 44, height: 44)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(detail)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private enum DecidePrimerChoice: String, CaseIterable {
    case pass, maybe, love

    var title: String {
        switch self {
        case .pass: AppCopy.Primer.Decide.pass
        case .maybe: AppCopy.Primer.Decide.maybe
        case .love: AppCopy.Primer.Decide.love
        }
    }

    var feedback: String {
        switch self {
        case .pass: AppCopy.Primer.Decide.passFeedback
        case .maybe: AppCopy.Primer.Decide.maybeFeedback
        case .love: AppCopy.Primer.Decide.loveFeedback
        }
    }

    var symbol: String {
        switch self {
        case .pass: "xmark"
        case .maybe: "bookmark.fill"
        case .love: "heart.fill"
        }
    }

    var directionSymbol: String {
        switch self {
        case .pass: "arrow.left"
        case .maybe: "arrow.up"
        case .love: "arrow.right"
        }
    }

    var rotation: Double {
        switch self {
        case .pass: -5
        case .maybe: 0
        case .love: 5
        }
    }

    var offset: CGFloat {
        switch self {
        case .pass: -12
        case .maybe: 0
        case .love: 12
        }
    }
}

#Preview {
    DecideEventPrimer(continueAction: {})
}
