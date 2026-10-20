import SwiftUI

/// An authored-only event reading screen for blueprint previews.
/// The caller supplies the already projected root or leaf event content.
struct BlueprintWorkspaceEventDetail: View {
    let event: BlueprintPreviewEventContent
    let artwork: BlueprintPreviewEventArtwork
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var scrollProgress = CGFloat.zero

    var body: some View {
        GeometryReader { proxy in
            let heroHeight = max(
                proxy.size.height + proxy.safeAreaInsets.top,
                dynamicTypeSize.isAccessibilitySize ? 760 : 680
            )

            ZStack {
                backdrop(progress: scrollProgress)

                ScrollView {
                    VStack(spacing: 0) {
                        EventReadingHero(
                            title: event.title,
                            height: heroHeight,
                            topSpacer: dynamicTypeSize.isAccessibilitySize ? 150 : 260
                        ) {
                            Text(artwork.category.title)
                                .font(.subheadline.weight(.medium))
                        } timingLocation: {
                            if let proposal = event.scheduleProposal,
                               let schedule = BlueprintReviewPresentation.schedule(
                                    dayOffset: proposal.dayOffset,
                                    localTime: proposal.localTime
                               ) {
                                Text(String.localizedStringWithFormat(BlueprintCopy.previewSuggestedScheduleFormat, schedule))
                                .font(.headline)
                                .fixedSize(horizontal: false, vertical: true)
                            }
                        } response: {
                            EmptyView()
                        }

                        information(bottomInset: proxy.safeAreaInsets.bottom)
                    }
                }
                .scrollIndicators(.hidden)
                .scrollBounceBehavior(.basedOnSize)
                .appSoftScrollEdges()
                .onScrollGeometryChange(for: CGFloat.self) { geometry in
                    min(max((geometry.contentOffset.y + geometry.contentInsets.top) / 220, 0), 1)
                } action: { _, newProgress in
                    scrollProgress = newProgress
                }
            }
            .ignoresSafeArea(edges: .top)
        }
        .background(.black)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func backdrop(progress: CGFloat) -> some View {
        ZStack {
            Color.black
            MediaArtwork(
                imageData: nil,
                symbol: artwork.symbol,
                colors: artwork.colors,
                accent: artwork.accent,
                ambientBlurRadius: 36,
                progressiveBlurRadius: 0
            )
            .scaleEffect(1 + (0.06 * (reduceMotion ? 0 : progress)))
            .blur(radius: reduceTransparency || reduceMotion ? 0 : 38 * progress, opaque: true)
            .clipped()
            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.02), location: 0),
                    .init(color: .black.opacity(0.18 + 0.18 * progress), location: 0.55),
                    .init(color: .black.opacity((reduceTransparency ? 0.82 : 0.64) + 0.18 * progress), location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .clipped()
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func information(bottomInset: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.spacious) {
            if let summary = event.summary,
               !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                EventInvitationSection(title: "About This Event", symbol: "text.quote") {
                    Text(summary)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }

            ForEach(event.guidance) { section in
                EventInvitationSection(title: section.title, symbol: "book.closed") {
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.compact) {
                        Text(section.audience == .planningOnly
                             ? BlueprintCopy.audiencePlanningOnly
                             : BlueprintCopy.audienceEventParticipants)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(section.body)
                            .font(.body)
                            .textSelection(.enabled)
                    }
                }
            }

            if !event.ideas.isEmpty {
                EventInvitationSection(title: BlueprintCopy.captureIdeas, symbol: "lightbulb") {
                    VStack(spacing: 0) {
                        ForEach(Array(event.ideas.enumerated()), id: \.element.id) { index, idea in
                            NavigationLink {
                                BlueprintIdeaPreview(idea: idea)
                            } label: {
                                HStack(spacing: 12) {
                                    let ideaCategory = IdeaCategory(rawValue: idea.category) ?? .other
                                    ProgressiveArtwork(
                                        symbol: ideaCategory.symbol,
                                        colors: ideaCategory.artworkColors,
                                        accent: ideaCategory.artworkAccent,
                                        ambientBlurRadius: 8,
                                        progressiveBlurRadius: 0
                                    )
                                    .frame(width: 48, height: 56)
                                    .clipShape(.rect(cornerRadius: 12))

                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(idea.title).font(.headline)
                                        if let notes = idea.notes, !notes.isEmpty {
                                            Text(notes)
                                                .font(.subheadline)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(2)
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                    Image(systemName: "chevron.right")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                        .accessibilityHidden(true)
                                }
                                .foregroundStyle(.primary)
                                .padding(.vertical, 12)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)

                            if index < event.ideas.count - 1 {
                                Divider()
                            }
                        }
                    }
                }
            }
        }
        .padding(.horizontal, AppTheme.Layout.screenHorizontal)
        .padding(.top, AppTheme.Spacing.section)
        .padding(.bottom, max(bottomInset, 96))
        .foregroundStyle(.white)
        .appImageOverlayAppearance()
    }
}
