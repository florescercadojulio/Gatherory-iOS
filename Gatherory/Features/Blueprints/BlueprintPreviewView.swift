import SwiftUI

/// An invitation-like reading experience, deliberately separate from the live
/// event screen's attendance, media, location and workspace dependencies.
struct BlueprintPreviewView: View {
    let entry: BlueprintCatalogEntry
    var sharedToken: String? = nil
    var usesSavedPreview = false
    var hasPendingInstallation = false
    @State private var showsSetup = false

    private var content: BlueprintPreviewContent? { BlueprintPreviewContent(entry: entry) }

    var body: some View {
        Group {
            if let content, let event = content.event() {
                BlueprintEventPreview(
                    event: event, content: content,
                    symbol: entry.browseCategories.first?.symbol ?? "sparkles.rectangle.stack",
                    artworkCategory: (entry.browseCategories.first ?? .events).artworkCategory,
                    isMainEvent: true, usesSavedPreview: usesSavedPreview
                )
            } else {
                ContentUnavailableView(BlueprintCopy.loadFailed, systemImage: "square.stack.3d.up.slash")
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.automatic, for: .navigationBar)
        .appImageNavigationBarAppearance()
        .toolbar {
            if content != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(hasPendingInstallation ? BlueprintCopy.retryInstall : BlueprintCopy.starter) {
                        showsSetup = true
                    }
                    .font(.subheadline.weight(.semibold))
                    .tint(.primary)
                }
            }
        }
        .sheet(isPresented: $showsSetup) {
            NavigationStack {
                BlueprintSetupView(
                    catalogKey: sharedToken == nil ? entry.catalogKey : nil,
                    sharedToken: sharedToken,
                    returnsToPreview: true
                )
            }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }
}

/// The same reading experience for a template's main event and its leaf events.
private struct BlueprintEventPreview: View {
    let event: BlueprintPreviewEventContent
    let content: BlueprintPreviewContent
    let symbol: String
    let artworkCategory: TimelineCategory
    var isMainEvent = false
    var usesSavedPreview = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                BlueprintPreviewBackdrop(
                    symbol: symbol,
                    category: artworkCategory
                )
                ScrollView {
                    VStack(spacing: AppTheme.Spacing.standard) {
                        summaryCard
                            .padding(.horizontal, AppTheme.Layout.screenHorizontal)
                        information(bottomInset: proxy.safeAreaInsets.bottom)
                    }
                    .padding(.top, AppTheme.Spacing.standard)
                }
                .scrollEdgeEffectStyle(.soft, for: .all)
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.automatic, for: .navigationBar)
        .appImageNavigationBarAppearance()
    }

    private var summaryNote: String {
        guard let summary = event.summary,
              !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return "" }
        return summary
    }

    /// Reuse the idea summary itself: category eyebrow, left-aligned title,
    /// authored description and material, with read-only event context below.
    private var summaryCard: some View {
        IdeaSummaryContent(title: event.title, note: summaryNote, category: .event) {
            EmptyView()
        } footer: {
            if let proposal = event.scheduleProposal {
                Divider()
                Label(
                    String.localizedStringWithFormat(BlueprintCopy.scheduleProposalExplanation, proposal.localTime, Int64(proposal.dayOffset)),
                    systemImage: "calendar"
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            if usesSavedPreview {
                Divider()
                Label(BlueprintCopy.savedPreviewExplanation, systemImage: "wifi.slash")
                    .font(.footnote).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .foregroundStyle(Color.primary)
    }

    private func information(bottomInset: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.spacious) {
            BlueprintPreviewGuidance(sections: event.guidance)
                .padding(.horizontal, AppTheme.Layout.screenHorizontal)
            if !event.children.isEmpty { activities }
            BlueprintPreviewIdeas(ideas: event.ideas, horizontalInset: AppTheme.Layout.screenHorizontal)
            Text(isMainEvent ? BlueprintCopy.previewExplanation : BlueprintCopy.previewDatesExplanation)
                .font(.footnote).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(AppTheme.Spacing.standard)
                .ideaContentSurface()
                .foregroundStyle(Color.primary)
                .padding(.horizontal, AppTheme.Layout.screenHorizontal)
        }
        .foregroundStyle(.white)
        // The floating tab bar does not always contribute its full height to
        // GeometryReader's inset. Keep the final lines clear at the scroll end.
        .padding(.bottom, max(bottomInset, 96))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var activities: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(BlueprintCopy.captureChildren).font(.title2.bold()).accessibilityAddTraits(.isHeader)
                .padding(.horizontal, AppTheme.Layout.screenHorizontal)
            // The activity sequence is authored order, not a fabricated dated timeline.
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 16) {
                    ForEach(Array(BlueprintPreviewPages.events(event.children, accessibility: dynamicTypeSize.isAccessibilitySize).enumerated()), id: \.offset) { _, page in
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: dynamicTypeSize.isAccessibilitySize ? 1 : 2), alignment: .leading, spacing: 12) {
                            ForEach(page) { child in
                                NavigationLink {
                                    if let childEvent = content.event(for: child.key) {
                                        BlueprintEventPreview(
                                            event: childEvent, content: content,
                                            symbol: (TimelineCategory(rawValue: child.category) ?? .other).symbol,
                                            artworkCategory: TimelineCategory(rawValue: child.category) ?? .other
                                        )
                                    }
                                } label: {
                                    BlueprintActivityCard(child: child)
                                }
                                .buttonStyle(BlueprintPreviewCardStyle())
                            }
                        }
                        .accessibilityElement(children: .contain)
                        .containerRelativeFrame(.horizontal) { length, _ in
                            dynamicTypeSize.isAccessibilitySize ? length : length * 0.94
                        }
                    }
                }
                .scrollTargetLayout()
            }
            // Inset the resting position, not the scroll viewport: cards may
            // travel all the way to either screen edge during a swipe.
            .contentMargins(.horizontal, AppTheme.Layout.screenHorizontal, for: .scrollContent)
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(.viewAligned(limitBehavior: .always))
        }
    }
}

/// Fully Glurred from first presentation, without a scroll-dependent clear band.
private struct BlueprintPreviewBackdrop: View {
    let symbol: String
    var category: TimelineCategory? = nil

    var body: some View {
        GlurredArtwork {
            ProgressiveArtwork(
                symbol: symbol,
                colors: category?.artworkColors ?? IdeaCategory.event.artworkColors,
                accent: category?.artworkAccent ?? IdeaCategory.event.artworkAccent,
                progressiveBlurRadius: 0
            )
        }
        .clipped()
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct BlueprintActivityCard: View {
    let child: BlueprintCatalogChild
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private var category: TimelineCategory { TimelineCategory(rawValue: child.category) ?? .other }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ProgressiveArtwork(symbol: category.symbol, colors: category.artworkColors, accent: category.artworkAccent)
                .frame(height: dynamicTypeSize.isAccessibilitySize ? 100 : 88)
                .clipped()
            HStack(alignment: .top, spacing: 12) {
                Text(child.title).font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary).accessibilityHidden(true)
            }
            .padding(12)
        }
        .ideaContentSurface()
        .foregroundStyle(Color.primary)
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .contentShape(RoundedRectangle(cornerRadius: 24))
        .accessibilityElement(children: .combine)
    }
}

private struct BlueprintPreviewIdeas: View {
    let ideas: [BlueprintCatalogIdea]
    var horizontalInset: CGFloat = 0
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        if !ideas.isEmpty {
            VStack(alignment: .leading, spacing: 16) {
                Text(BlueprintCopy.captureIdeas).font(.title2.bold()).accessibilityAddTraits(.isHeader)
                    .padding(.horizontal, horizontalInset)
                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: 16) {
                        ForEach(Array(BlueprintPreviewPages.ideas(ideas).enumerated()), id: \.offset) { _, page in
                            VStack(spacing: 0) {
                                ForEach(page) { idea in
                                    NavigationLink {
                                        BlueprintIdeaPreview(idea: idea)
                                    } label: {
                                        BlueprintPreviewIdeaRow(idea: idea)
                                    }
                                    .buttonStyle(BlueprintPreviewCardStyle())
                                    if idea.id != page.last?.id {
                                        Divider().padding(.leading, dynamicTypeSize.isAccessibilitySize ? 0 : 64)
                                    }
                                }
                            }
                            .padding(.horizontal, 16)
                            .ideaContentSurface()
                            .foregroundStyle(Color.primary)
                            .accessibilityElement(children: .contain)
                            .containerRelativeFrame(.horizontal) { length, _ in
                                dynamicTypeSize.isAccessibilitySize ? length : length * 0.94
                            }
                        }
                    }
                    .scrollTargetLayout()
                }
                .contentMargins(.horizontal, horizontalInset, for: .scrollContent)
                .scrollIndicators(.hidden)
                .scrollTargetBehavior(.viewAligned(limitBehavior: .always))
            }
        }
    }
}

private struct BlueprintPreviewIdeaRow: View {
    let idea: BlueprintCatalogIdea
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private var category: IdeaCategory { IdeaCategory(rawValue: idea.category) ?? .other }

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 12))
        layout {
            ProgressiveArtwork(symbol: category.symbol, colors: category.artworkColors, accent: category.artworkAccent, ambientBlurRadius: 8, progressiveBlurRadius: 0)
                .frame(width: 48, height: 56)
                .clipShape(.rect(cornerRadius: 12))
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(idea.title).font(.headline)
                        .fixedSize(horizontal: false, vertical: true)
                    if let notes = idea.notes, !notes.isEmpty {
                        Text(notes).font(.subheadline).foregroundStyle(.secondary)
                            .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary).accessibilityHidden(true)
            }
        }
        .foregroundStyle(.primary)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

private struct BlueprintIdeaPreview: View {
    let idea: BlueprintCatalogIdea
    private var category: IdeaCategory { IdeaCategory(rawValue: idea.category) ?? .other }
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        IdeaDetailScreen(content: IdeaDetailContent(preview: idea)) {
            EmptyView()
        } footer: {
            EmptyView()
        } details: {
            IdeaCategoryDetailContent(idea: IdeaDetailContent(preview: idea))
        } artwork: {
            MediaArtwork(
                imageData: nil, symbol: category.symbol,
                colors: category.artworkColors, accent: category.artworkAccent,
                ambientBlurRadius: 10,
                progressiveBlurRadius: reduceTransparency ? 0 : 22,
                blurStart: 0.40
            )
        }
        .textSelection(.enabled)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .appClearNavigationBar()
    }
}

private struct BlueprintPreviewGuidance: View {
    let sections: [BlueprintCatalogInstruction]

    var body: some View {
        if !sections.isEmpty {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.standard) {
                Text(BlueprintCopy.captureGuidance).font(.title2.bold()).accessibilityAddTraits(.isHeader)
                ForEach(sections) { section in
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.compact) {
                        Text(section.title).font(.headline)
                        Text(section.audience == .planningOnly ? BlueprintCopy.audiencePlanningOnly : BlueprintCopy.audienceEventParticipants)
                            .font(.caption).foregroundStyle(.secondary)
                        Text(section.body).font(.body).textSelection(.enabled)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(AppTheme.Spacing.standard)
                    .ideaContentSurface()
                    .foregroundStyle(Color.primary)
                }
            }
        }
    }
}

private struct BlueprintPreviewCardStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.72 : 1)
    }
}
