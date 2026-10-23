import SwiftUI

/// The Yours overview keeps the editable blueprint's events and ideas in one scroll.
struct BlueprintWorkspaceSingleScrollView: View {
    let content: BlueprintPreviewContent
    let category: BlueprintBrowseCategory
    let creatorName: String?
    let mainEventSchedule: String?
    let canEditContent: Bool
    let canAddEvent: Bool
    let canAddIdea: Bool
    let canCreateEvents: Bool
    let createEventsTitle: String
    let onEditEvent: (BlueprintPreviewEventID) -> Void
    let onEditIdea: (BlueprintCatalogIdea) -> Void
    let onAddEvent: () -> Void
    let onAddIdea: () -> Void
    let onCreateEvents: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.layoutDirection) private var layoutDirection

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.spacious) {
                mainEvent
                if !content.children.isEmpty { includedEvents }
                if !content.ideas.isEmpty { ideasSection }
            }
            .padding(.horizontal, AppTheme.Layout.screenHorizontal)
            .padding(.top, AppTheme.Layout.screenTop)
            .padding(.bottom, AppTheme.Layout.screenBottom)
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize)
        .appSoftScrollEdges()
        .background(AppTheme.ColorToken.background)
        .accessibilityIdentifier("blueprint.preview.singleScroll")
        .toolbar {
            ToolbarItemGroup(placement: .bottomBar) {
                if canAddEvent || canAddIdea {
                    Menu {
                        if canAddEvent {
                            Button(BlueprintCopy.addSubEvent, systemImage: "calendar.badge.plus", action: onAddEvent)
                                .accessibilityIdentifier("blueprint.preview.addEvent")
                        }
                        if canAddIdea {
                            Button(BlueprintCopy.addIdea, systemImage: "sparkles.rectangle.stack", action: onAddIdea)
                                .accessibilityIdentifier("blueprint.preview.addIdea")
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel(AppCopy.Common.add)
                    .accessibilityIdentifier("blueprint.preview.add")
                }
                Spacer()
                Button(createEventsTitle, systemImage: "calendar.badge.plus", action: onCreateEvents)
                    .labelStyle(.titleOnly)
                    .disabled(!canCreateEvents)
                    .accessibilityIdentifier("blueprint.preview.createEvents")
            }
        }
    }

    private var mainEvent: some View {
        Button { onEditEvent(.main) } label: {
            VStack(alignment: .leading, spacing: 0) {
                BlueprintCoverArtwork(assetID: content.coverAssetID, publicImageURL: content.publicCoverImageURL) {
                    let artwork = BlueprintPreviewEventArtwork.resolve(id: .main, rawCategory: "event", browseCategory: category)
                    MediaArtwork(imageData: nil, symbol: artwork.symbol, colors: artwork.colors,
                                 accent: artwork.accent, ambientBlurRadius: 22, progressiveBlurRadius: 0)
                }
                .frame(maxWidth: .infinity)
                .frame(height: dynamicTypeSize.isAccessibilitySize ? 260 : 240)
                .clipped()
                VStack(alignment: .leading, spacing: AppTheme.Spacing.compact) {
                    Text(content.title)
                        .font(.system(.largeTitle, design: .rounded, weight: .bold))
                        .fixedSize(horizontal: false, vertical: true)
                    if let summary = nonempty(content.summary) {
                        Text(summary).font(.body).fixedSize(horizontal: false, vertical: true)
                    }
                    if let creatorName = nonempty(creatorName) {
                        Text(BlueprintCopy.creatorByline(creatorName))
                            .font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                    }
                    if let mainEventSchedule {
                        Label(mainEventSchedule, systemImage: "calendar")
                            .font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                    }
                    Label(BlueprintCopy.editEvent(content.title), systemImage: "pencil")
                        .font(.subheadline.weight(.semibold)).padding(.top, 2)
                }
                .foregroundStyle(.primary)
                .padding(AppTheme.Spacing.standard)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(AppTheme.ColorToken.surface)
            .clipShape(.rect(cornerRadius: AppTheme.Radius.hero))
            .overlay { RoundedRectangle(cornerRadius: AppTheme.Radius.hero).stroke(.primary.opacity(0.12), lineWidth: 0.5) }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("blueprint.preview.mainEvent")
        .disabled(!canEditContent)
    }

    private var includedEvents: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.compact) {
            sectionTitle(BlueprintCopy.previewEvents, count: content.children.count)
            VStack(spacing: 0) {
                ForEach(Array(content.children.enumerated()), id: \.element.key) { index, child in
                    let rowLayout = dynamicTypeSize.isAccessibilitySize
                        ? AnyLayout(VStackLayout(alignment: .leading, spacing: AppTheme.Spacing.compact))
                        : AnyLayout(HStackLayout(spacing: AppTheme.Spacing.compact))
                    rowLayout {
                        Button { onEditEvent(.child(child.key)) } label: {
                            HStack(spacing: AppTheme.Spacing.standard) {
                                childArtwork(child)
                                    .frame(width: 64, height: 64)
                                    .clipShape(.rect(cornerRadius: AppTheme.Radius.card))
                                VStack(alignment: .leading, spacing: AppTheme.Spacing.compact) {
                                    Text(child.title).font(.headline).fixedSize(horizontal: false, vertical: true)
                                    if let proposal = child.scheduleProposal,
                                       let schedule = BlueprintReviewPresentation.schedule(
                                        dayOffset: proposal.dayOffset, localTime: proposal.localTime
                                       ) {
                                        Text(String.localizedStringWithFormat(
                                            BlueprintCopy.previewSuggestedScheduleFormat, schedule
                                        ))
                                        .font(.subheadline).foregroundStyle(.secondary)
                                        .multilineTextAlignment(.leading)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            }
                            .foregroundStyle(.primary)
                            .padding(AppTheme.Spacing.standard)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("blueprint.preview.event.\(child.key)")
                        .disabled(!canEditContent)
                    }
                    if index < content.children.count - 1 { Divider() }
                }
            }
            .background(AppTheme.ColorToken.surface, in: .rect(cornerRadius: AppTheme.Radius.card))
        }
    }

    private var ideasSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.compact) {
            let headingLayout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: AppTheme.Spacing.compact))
                : AnyLayout(HStackLayout())
            headingLayout {
                sectionTitle(AppCopy.Tab.ideas, count: content.ideas.count)
                if !dynamicTypeSize.isAccessibilitySize { Spacer() }
            }
            AdaptiveMasonry(columnCount: dynamicTypeSize.isAccessibilitySize ? 1 : 2,
                            spacing: 12, layoutDirection: layoutDirection, minimumColumnWidth: 170) {
                ForEach(content.ideas) { idea in
                    Button { onEditIdea(idea) } label: {
                        ideaCard(idea)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("blueprint.preview.idea.\(idea.key)")
                    .disabled(!canEditContent)
                }
            }
        }
    }

    private func sectionTitle(_ title: String, count: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: AppTheme.Spacing.compact) {
            Text(title).font(.title2.weight(.bold)).tracking(-0.3)
            Text(count.formatted()).font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                .accessibilityLabel(BlueprintCopy.publicItemCount(count))
        }
        .accessibilityElement(children: .combine)
    }

    private func ideaCard(_ idea: BlueprintCatalogIdea) -> some View {
        let ideaCategory = IdeaCategory(rawValue: idea.category) ?? .other
        return IdeaCollectionPresentation(title: idea.title, category: ideaCategory,
                                          aspectRatio: ideaCategory.collectionAspectRatio) {
            BlueprintCoverArtwork(assetID: idea.coverAssetId, publicImageURL: content.publicIdeaCoverImageURLs[idea.key]) {
                MediaArtwork(imageData: nil, symbol: ideaCategory.symbol, colors: ideaCategory.artworkColors,
                             accent: ideaCategory.artworkAccent, ambientBlurRadius: 12,
                             progressiveBlurRadius: 22, blurStart: 0.30)
            }
        } supporting: {
            if let notes = nonempty(idea.notes) { Text(notes).lineLimit(2) }
        }
    }

    private func childArtwork(_ child: BlueprintCatalogChild) -> some View {
        BlueprintCoverArtwork(assetID: child.coverAssetId, publicImageURL: content.publicChildCoverImageURLs[child.key]) {
            let artwork = BlueprintPreviewEventArtwork.resolve(id: .child(child.key), rawCategory: child.category, browseCategory: category)
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
