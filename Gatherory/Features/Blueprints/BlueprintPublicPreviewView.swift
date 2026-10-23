import SwiftUI

/// A single read-only public preview for discovery, collections, and shared links.
struct BlueprintPublicPreviewView: View {
    let content: BlueprintPreviewContent
    let category: BlueprintBrowseCategory
    let onSelectEvent: (BlueprintPreviewEventID) -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.layoutDirection) private var layoutDirection
    @State private var selectedEvent: BlueprintPreviewEventID?
    @State private var selectedIdeaKey: String?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: AppTheme.Spacing.spacious) {
                mainEvent

                if !content.children.isEmpty {
                    includedEvents
                }

                if !content.ideas.isEmpty {
                    ideasSection
                }
            }
            .padding(.horizontal, AppTheme.Layout.screenHorizontal)
            .padding(.top, AppTheme.Layout.screenTop)
            .padding(.bottom, AppTheme.Layout.screenBottom)
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize)
        .appSoftScrollEdges()
        .background(AppTheme.ColorToken.background)
        .accessibilityIdentifier("blueprint.preview.publicScroll")
        .navigationDestination(item: $selectedEvent) { id in
            if let event = content.event(for: id) {
                let artwork = BlueprintPreviewEventArtwork.resolve(
                    id: id,
                    rawCategory: event.category,
                    browseCategory: category
                )
                BlueprintWorkspaceEventDetail(event: event, artwork: artwork)
                    .accessibilityIdentifier("blueprint.preview.eventDetail")
            }
        }
        .navigationDestination(item: $selectedIdeaKey) { key in
            if let idea = content.ideas.first(where: { $0.key == key }) {
                BlueprintIdeaPreview(
                    idea: idea,
                    publicImageURL: content.publicIdeaCoverImageURLs[idea.key]
                )
                .accessibilityIdentifier("blueprint.preview.ideaDetail")
            }
        }
    }

    private var mainEvent: some View {
        Button {
            onSelectEvent(.main)
            selectedEvent = .main
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .topLeading) {
                    BlueprintCoverArtwork(assetID: content.coverAssetID, publicImageURL: content.publicCoverImageURL) {
                        let artwork = BlueprintPreviewEventArtwork.resolve(
                            id: .main, rawCategory: "event", browseCategory: category
                        )
                        MediaArtwork(imageData: nil, symbol: artwork.symbol, colors: artwork.colors,
                                     accent: artwork.accent, ambientBlurRadius: 22, progressiveBlurRadius: 0)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: dynamicTypeSize.isAccessibilitySize ? 260 : 240)
                    .clipped()

                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0.24),
                            .init(color: .black.opacity(0.32), location: 0.58),
                            .init(color: .black.opacity(0.84), location: 1)
                        ], startPoint: .top, endPoint: .bottom
                    )
                    .accessibilityHidden(true)

                    Label(BlueprintCopy.mainEventDetails, systemImage: "calendar")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, AppTheme.Spacing.standard)
                        .padding(.vertical, AppTheme.Spacing.compact)
                        .background(.regularMaterial, in: Capsule())
                        .padding(AppTheme.Spacing.standard)
                }

                VStack(alignment: .leading, spacing: AppTheme.Spacing.compact) {
                    Text(content.title)
                        .font(.system(.largeTitle, design: .rounded, weight: .bold))
                        .fixedSize(horizontal: false, vertical: true)

                    if let summary = nonempty(content.summary) {
                        Text(summary)
                            .font(.body)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if let creator = nonempty(content.creatorName) {
                        Text(BlueprintCopy.creatorByline(creator))
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Label(BlueprintCopy.viewEventDetails, systemImage: "arrow.up.right")
                        .font(.subheadline.weight(.semibold))
                        .padding(.top, 2)
                }
                .foregroundStyle(.primary)
                .padding(AppTheme.Spacing.standard)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(AppTheme.ColorToken.surface)
            .clipShape(.rect(cornerRadius: AppTheme.Radius.hero))
            .overlay {
                RoundedRectangle(cornerRadius: AppTheme.Radius.hero)
                    .stroke(.primary.opacity(0.12), lineWidth: 0.5)
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("blueprint.preview.mainEvent")
        .accessibilityHint(BlueprintCopy.viewEventDetails)
    }

    private var includedEvents: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.compact) {
            sectionTitle(BlueprintCopy.includedEvents, identifier: "events", count: content.children.count)

            VStack(spacing: 0) {
                ForEach(Array(content.children.enumerated()), id: \.element.key) { index, child in
                    Button {
                        onSelectEvent(.child(child.key))
                        selectedEvent = .child(child.key)
                    } label: {
                        HStack(spacing: AppTheme.Spacing.standard) {
                            childArtwork(child)
                                .frame(width: 76, height: 76)
                                .clipShape(.rect(cornerRadius: AppTheme.Radius.card))

                            VStack(alignment: .leading, spacing: 5) {
                                Text(child.title)
                                    .font(.headline)
                                    .multilineTextAlignment(.leading)
                                    .fixedSize(horizontal: false, vertical: true)
                                if let proposal = child.scheduleProposal,
                                   let schedule = BlueprintReviewPresentation.schedule(
                                    dayOffset: proposal.dayOffset,
                                    localTime: proposal.localTime
                                   ) {
                                    Text(String.localizedStringWithFormat(
                                        BlueprintCopy.previewSuggestedScheduleFormat, schedule
                                    ))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.leading)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)

                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .accessibilityHidden(true)
                        }
                        .foregroundStyle(.primary)
                        .padding(AppTheme.Spacing.standard)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("blueprint.preview.event.\(child.key)")
                    .accessibilityHint(BlueprintCopy.viewEventDetails)

                    if index < content.children.count - 1 { Divider() }
                }
            }
            .background(AppTheme.ColorToken.surface, in: .rect(cornerRadius: AppTheme.Radius.card))
        }
    }

    private var ideasSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.compact) {
            sectionTitle(AppCopy.Tab.ideas, identifier: "ideas", count: content.ideas.count)

            AdaptiveMasonry(
                columnCount: dynamicTypeSize.isAccessibilitySize ? 1 : 2,
                spacing: 12,
                layoutDirection: layoutDirection,
                minimumColumnWidth: 170
            ) {
                ForEach(content.ideas) { idea in
                    let ideaCategory = IdeaCategory(rawValue: idea.category) ?? .other
                    Button {
                        selectedIdeaKey = idea.key
                    } label: {
                        IdeaCollectionPresentation(
                            title: idea.title,
                            category: ideaCategory,
                            aspectRatio: ideaCategory.collectionAspectRatio
                        ) {
                            BlueprintCoverArtwork(
                                assetID: idea.coverAssetId,
                                publicImageURL: content.publicIdeaCoverImageURLs[idea.key]
                            ) {
                                MediaArtwork(imageData: nil, symbol: ideaCategory.symbol,
                                             colors: ideaCategory.artworkColors,
                                             accent: ideaCategory.artworkAccent,
                                             ambientBlurRadius: 12, progressiveBlurRadius: 22,
                                             blurStart: 0.30)
                            }
                        } supporting: {
                            if let notes = nonempty(idea.notes) { Text(notes).lineLimit(2) }
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("blueprint.preview.idea.\(idea.key)")
                    .accessibilityHint(BlueprintCopy.previewTitle)
                }
            }
        }
    }

    private func sectionTitle(_ title: String, identifier: String, count: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: AppTheme.Spacing.compact) {
            Text(title)
                .font(.title2.weight(.bold))
                .tracking(-0.3)
            Text(count.formatted())
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .accessibilityLabel(BlueprintCopy.publicItemCount(count))
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("blueprint.preview.heading.\(identifier)")
    }

    private func childArtwork(_ child: BlueprintCatalogChild) -> some View {
        BlueprintCoverArtwork(
            assetID: child.coverAssetId,
            publicImageURL: content.publicChildCoverImageURLs[child.key]
        ) {
            let artwork = BlueprintPreviewEventArtwork.resolve(
                id: .child(child.key), rawCategory: child.category, browseCategory: category
            )
            MediaArtwork(imageData: nil, symbol: artwork.symbol, colors: artwork.colors,
                         accent: artwork.accent, progressiveBlurRadius: 0)
        }
    }

    private func nonempty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
