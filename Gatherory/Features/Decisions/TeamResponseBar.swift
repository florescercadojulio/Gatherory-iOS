import SwiftUI

/// A bounded, proportional bar: ten or ten thousand responses use the same space.
struct TeamResponseBar: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hasAppeared = false
    let summary: TeamResponseSummary
    var showsTitle = true
    var showsSymbols = true
    var barHeight: CGFloat = 18
    private var segments: [(count: Int, color: Color, symbol: String)] {
        [(summary.love, .green, "heart.fill"), (summary.maybe, .yellow, "questionmark"),
         (summary.pass, .red, "xmark"), (summary.unanswered, .gray, "ellipsis")].filter { $0.0 > 0 }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if showsTitle {
                Text(summary.responded == 0 ? "Waiting for team input" : "Team input")
                    .font(.caption.weight(.semibold))
            }
            GeometryReader { proxy in
                HStack(spacing: 2) {
                    ForEach(segments.indices, id: \.self) { index in
                        let segment = segments[index]
                        let width = max(0, proxy.size.width - CGFloat(max(0, segments.count - 1)) * 2)
                            * CGFloat(segment.count) / CGFloat(max(1, summary.total))
                        Rectangle().fill(segment.color)
                            .overlay {
                                if showsSymbols && width >= 20 {
                                    Image(systemName: segment.symbol)
                                        .font(.system(size: 10, weight: .bold)).foregroundStyle(.black)
                                }
                            }
                            .frame(width: width)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .background(Color.gray.opacity(0.3))
                .clipShape(Capsule())
                .overlay { Capsule().stroke(.primary.opacity(0.3), lineWidth: 0.5) }
            }
            .frame(height: barHeight)
            .scaleEffect(
                x: hasAppeared || reduceMotion ? 1 : 0.92,
                y: hasAppeared || reduceMotion ? 1 : 0.65
            )
            .opacity(hasAppeared || reduceMotion ? 1 : 0)
            .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: summary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Team input")
        .accessibilityValue("\(summary.love) love it, \(summary.maybe) maybe, \(summary.pass) pass, \(summary.unanswered) unanswered")
        .task {
            guard !reduceMotion else { hasAppeared = true; return }
            // Allow the initial layout to settle before the one-shot entrance.
            do { try await Task.sleep(for: .milliseconds(60)) } catch { return }
            guard !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.5, dampingFraction: 0.65)) {
                hasAppeared = true
            }
        }
        .onDisappear { hasAppeared = false }
    }
}

struct IdeaTeamResponseSection: View {
    @Environment(PlanningWorkspace.self) private var workspace
    let idea: PlanningIdea
    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.standard) {
            TeamResponseBar(summary: workspace.teamResponseSummary(for: idea))
                .id(idea.id)
            IdeaResponseControls(idea: idea)
        }
        .padding(AppTheme.Spacing.standard)
        .ideaContentSurface()
    }
}

struct IdeaResponseControls: View {
    @Environment(PlanningWorkspace.self) private var workspace
    let idea: PlanningIdea

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.standard) {
            if workspace.canRespond(to: idea) {
                ViewThatFits(in: .horizontal) {
                    HStack { responseButtons }
                    VStack(alignment: .leading) { responseButtons }
                }
            }
        }
    }
    private var responseButtons: some View {
        ForEach([DecisionChoice.love, .maybe, .pass], id: \.self) { choice in
            Button { workspace.decide(choice, on: idea) } label: {
                Label(title(choice), systemImage: workspace.response(on: idea) == choice ? "checkmark.circle.fill" : symbol(choice))
                    .frame(minHeight: 32)
            }
            .buttonStyle(.bordered)
            .accessibilityAddTraits(workspace.response(on: idea) == choice ? .isSelected : [])
        }
    }
    private func title(_ choice: DecisionChoice) -> String {
        switch choice {
        case .love: String(localized: "Love It")
        case .maybe: String(localized: "Maybe")
        case .pass: String(localized: "Pass")
        }
    }
    private func symbol(_ choice: DecisionChoice) -> String {
        switch choice { case .love: "heart"; case .maybe: "questionmark"; case .pass: "xmark" }
    }
}

#if DEBUG
/// Preview-only fixtures. Uses the real bar without loading an account or syncing.
private struct TeamResponsePreviewGallery: View {
    @State private var replayID = 0
    private let examples: [(title: String, summary: TeamResponseSummary)] = [
        ("Mostly Love It", .init(love: 8, maybe: 1, pass: 1)),
        ("Mostly Maybe", .init(love: 1, maybe: 8, pass: 1)),
        ("Mostly Pass", .init(love: 1, maybe: 1, pass: 8)),
        ("Still waiting on teammates", .init(love: 2, maybe: 1, unanswered: 7)),
        ("No responses yet", .init(unanswered: 10)),
        ("Everyone loves it", .init(love: 10)),
        ("Large team · 1,000 responses", .init(love: 600, maybe: 220, pass: 180))
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(verbatim: "Team response bar")
                    .font(.largeTitle.bold())
                Button { replayID += 1 } label: {
                    Text(verbatim: "Replay entrance")
                }
                .buttonStyle(.bordered)
                ForEach(examples.indices, id: \.self) { index in
                    VStack(alignment: .leading, spacing: 16) {
                        Text(verbatim: examples[index].title)
                            .font(.headline)
                        TeamResponseBar(summary: examples[index].summary)
                            .id("\(index)-\(replayID)")
                    }
                    .padding(20)
                    .background(Color(uiColor: .secondarySystemGroupedBackground),
                                in: RoundedRectangle(cornerRadius: 20))
                }
            }
            .padding(20)
        }
        .background(Color(uiColor: .systemGroupedBackground))
    }
}

#Preview("Team input · Light") {
    TeamResponsePreviewGallery()
        .preferredColorScheme(.light)
}

#Preview("Team input · Dark") {
    TeamResponsePreviewGallery()
        .preferredColorScheme(.dark)
}

#Preview("Team input · Large text") {
    TeamResponsePreviewGallery()
        .preferredColorScheme(.light)
        .dynamicTypeSize(.accessibility3)
}

#endif
