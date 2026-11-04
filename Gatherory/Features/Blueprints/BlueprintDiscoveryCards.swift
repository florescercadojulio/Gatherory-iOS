import SwiftUI
import UIKit

/// Read-only discovery artwork. Category identity never depends on color alone.
struct BlueprintCategoryTile: View {
    let category: BlueprintBrowseCategory
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.standard) {
            Image(systemName: category.symbol)
                .font(.system(size: 44, weight: .medium))
                .symbolRenderingMode(.monochrome)
                .frame(width: 52, height: 52, alignment: .leading)
                .accessibilityHidden(true)

            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    Text(category.title).lineLimit(nil)
                } else {
                    Text(category.title).lineLimit(2, reservesSpace: true)
                }
            }
            .font(.headline)
            .foregroundStyle(category.categoryTileForeground)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(category.categoryTileForeground)
        .padding(AppTheme.Spacing.standard)
        .frame(maxWidth: .infinity, minHeight: 156, alignment: .leading)
        .background(category.categoryTileBackground)
        .clipShape(.rect(cornerRadius: 24))
        .overlay {
            RoundedRectangle(cornerRadius: 24)
                .strokeBorder(category.categoryTileForeground.opacity(contrast == .increased ? 0.9 : 0.22))
        }
        .contentShape(.rect(cornerRadius: 24))
        .accessibilityElement(children: .combine)
    }
}

/// Same artwork-led collection language as workspace ideas, without live status.
struct BlueprintCatalogTile: View {
    static let estimatedTextHeight: CGFloat = 104
    let entry: BlueprintCatalogEntry
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private var category: BlueprintBrowseCategory { entry.browseCategories.first ?? .events }
    // Listing geometry must not depend on asynchronously decoded artwork.
    // The cover fills/crops inside this reserved area on every mount.
    private var tileAspectRatio: CGFloat { category.catalogTileAspectRatio }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear
                .aspectRatio(1 / tileAspectRatio, contentMode: .fit)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                Text(entry.definition.blueprint.name)
                    .font(.headline)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                    .fixedSize(horizontal: false, vertical: true)
                if let creatorName = entry.creator?.displayName,
                   !creatorName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(BlueprintCopy.creatorByline(creatorName))
                        .font(.caption)
                        .foregroundStyle(AppTheme.ColorToken.onMedia)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(AppTheme.Spacing.standard)
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(AppTheme.ColorToken.onMedia)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            BlueprintCoverArtwork(
                assetID: entry.definition.presentation?.coverAssetID,
                publicImageURL: entry.discovery?.coverImageURL,
                source: BlueprintCoverSource(catalogKey: entry.catalogKey, revision: entry.revision)
            ) {
                BlueprintDiscoveryArtwork(category: category)
            }
            .overlay {
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .clear, location: 0.25),
                        .init(color: AppTheme.ColorToken.mediaScrim.opacity(0.65), location: 0.62),
                        .init(color: AppTheme.ColorToken.mediaScrim.opacity(0.78), location: 1)
                    ], startPoint: .top, endPoint: .bottom
                )
                .accessibilityHidden(true)
            }
        }
        .clipShape(.rect(cornerRadius: AppTheme.Radius.card))
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.Radius.card)
                .stroke(AppTheme.ColorToken.hairline.opacity(0.5), lineWidth: 0.5)
        }
        .contentShape(.rect(cornerRadius: AppTheme.Radius.card))
        .accessibilityElement(children: .combine)
    }
}

private struct BlueprintCatalogCardButton: View {
    let entry: BlueprintCatalogEntry
    let actionStore: BlueprintActionStore?
    let measurementIsActive: Bool
    let localExposureIsActive: Bool
    let transitionID: BlueprintPreviewTransitionID
    let namespace: Namespace.ID
    let measurementScopeID: String
    let onMeaningfulExposure: ((String) -> Void)?
    let onSelect: () -> Void
    var guidedSelectionKey: String? = nil
    var guidedTourActive = false
    var onGuidedSelection: (() -> Void)? = nil
    @State private var isVisible = false

    private var state: BlueprintViewerState { actionStore?.states[entry.catalogKey] ?? entry.viewerState ?? .init() }
    private var isGuidedCard: Bool { guidedTourActive }
    private var isGuidedSelection: Bool {
        MovieNightTourExplorePolicy.isSelectable(
            catalogKey: entry.catalogKey,
            guidedTourActive: guidedTourActive,
            guidedSelectionKey: guidedSelectionKey
        ) && guidedTourActive
    }
    private var dwellTaskID: String {
        "\(isVisible)-\(measurementIsActive)-\(localExposureIsActive)-\(measurementScopeID)-\(actionStore?.ownerID ?? "anonymous")-\(actionStore?.measurementEnabled ?? false)-\(entry.discoveryContext?.exposureId ?? "")"
    }

    var body: some View {
        Button {
            if isGuidedCard {
                guard isGuidedSelection else { return }
                onGuidedSelection?()
            } else {
                onSelect()
            }
        } label: {
            cardTile
                .matchedTransitionSource(id: transitionID, in: namespace)
        }
        .buttonStyle(.plain)
        .disabled(isGuidedCard && !isGuidedSelection)
        .accessibilityIdentifier(isGuidedSelection ? "movieNightTour.explore.movieNight" : "blueprint.catalog.card.\(entry.catalogKey)")
        .accessibilityHint(ExploreCopy.openHint)
        .contextMenu {
            if !isGuidedCard, entry.viewerState != nil, let actionStore {
                Button {
                    Task { _ = await actionStore.set(.like, enabled: !state.liked, for: entry) }
                } label: { Label(state.liked ? BlueprintCopy.unlike : BlueprintCopy.like, systemImage: state.liked ? "heart.slash" : "heart") }
                Button {
                    Task { _ = await actionStore.set(.bookmark, enabled: !state.bookmarked, for: entry) }
                } label: { Label(state.bookmarked ? BlueprintCopy.removeBookmark : BlueprintCopy.saveBookmark, systemImage: state.bookmarked ? "bookmark.slash" : "bookmark") }
                Button(role: .destructive) {
                    Task { _ = await actionStore.set(.notInterested, enabled: !state.notInterested, for: entry) }
                } label: { Label(state.notInterested ? BlueprintCopy.undoNotInterested : BlueprintCopy.notInterested, systemImage: "eye.slash") }
            }
        }
        .onScrollVisibilityChange(threshold: BlueprintImpressionPolicy.visibilityThreshold) { isVisible = $0 }
        .task(id: dwellTaskID) {
            guard !isGuidedCard, isVisible, measurementIsActive || localExposureIsActive else { return }
            let began = Date()
            do { try await Task.sleep(for: .seconds(BlueprintImpressionPolicy.minimumDuration)) } catch { return }
            guard !Task.isCancelled else { return }
            let duration = Date().timeIntervalSince(began)
            let qualifies = BlueprintImpressionPolicy.qualifies(
                visibleFraction: Double(BlueprintImpressionPolicy.visibilityThreshold),
                visibleDuration: duration,
                sceneIsActive: measurementIsActive || localExposureIsActive,
                previewIsPresented: !(measurementIsActive || localExposureIsActive)
            )
            guard qualifies else { return }
            if localExposureIsActive { onMeaningfulExposure?(entry.catalogKey) }
            if measurementIsActive, let actionStore { await actionStore.record(.impression, for: entry) }
        }
    }

    @ViewBuilder
    private var cardTile: some View {
        if isGuidedSelection {
            BlueprintCatalogTile(entry: entry)
                .overlay {
                    RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous)
                        .strokeBorder(AppTheme.ColorToken.accent, lineWidth: 3)
                        .padding(1.5)
                        .accessibilityIdentifier("movieNightTour.explore.movieNight.highlight")
                        .accessibilityHidden(true)
                        .allowsHitTesting(false)
                }
                .movieNightTourTarget(.movieNightBlueprint)
                .background { MovieNightTourWindowTarget(target: .movieNightBlueprint) }
        } else {
            BlueprintCatalogTile(entry: entry)
        }
    }
}

/// Presentation-only grid. Selection and source retention belong to Explore.
struct BlueprintCatalogGrid: View {
    let entries: [BlueprintCatalogEntry]
    let source: BlueprintCatalogSource
    let transitionNamespace: Namespace.ID
    let onSelect: (BlueprintCatalogEntry) -> Void
    var actionStore: BlueprintActionStore? = nil
    var measurementIsActive = true
    var localExposureIsActive = true
    var measurementScopeID = "default"
    var onMeaningfulExposure: ((String) -> Void)? = nil
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        GeometryReader { viewport in
            let viewportWidth = LayoutDimensions.nonnegative(viewport.size.width)
            let horizontalInset = LayoutDimensions.nonnegative(AppTheme.Layout.screenHorizontal)
            let contentWidth = min(760, max(viewportWidth - 2 * horizontalInset, 0))

            ScrollView {
                LazyVStack(alignment: .leading, spacing: AppTheme.Spacing.standard) {
                    catalogItems(contentWidth: contentWidth)
                }
                .frame(width: contentWidth, alignment: .leading)
                .frame(width: viewportWidth)
                .padding(.top, AppTheme.Layout.screenTop)
                .padding(.bottom, AppTheme.Layout.screenBottom)
            }
            .scrollIndicators(.hidden)
            .appSoftScrollEdges()
        }
    }

    private func catalogItems(contentWidth: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.standard) {
            AdaptiveLazyMasonry(
                items: entries,
                columnCount: dynamicTypeSize.isAccessibilitySize ? 1 : 2,
                spacing: 12,
                minimumColumnWidth: 170,
                estimatedHeight: { entry, width in
                    let aspectRatio = entry.browseCategories.first?.catalogTileAspectRatio
                        ?? BlueprintBrowseCategory.events.catalogTileAspectRatio
                    return width * aspectRatio + BlueprintCatalogTile.estimatedTextHeight
                }
            ) { entry, index in
                BlueprintCatalogCardButton(entry: entry, actionStore: actionStore,
                    measurementIsActive: measurementIsActive,
                    localExposureIsActive: localExposureIsActive,
                    transitionID: BlueprintPreviewTransitionID(source: source, entryID: entry.id),
                    namespace: transitionNamespace, measurementScopeID: measurementScopeID,
                    onMeaningfulExposure: onMeaningfulExposure,
                    onSelect: { onSelect(entry) })
                .accessibilitySortPriority(Double(entries.count - index) * 2)
            }
        }
        .frame(width: contentWidth)
    }
}

/// A server-paged discovery collection. Ad slots are anchored to organic item
/// positions so adding another page never moves an already visible slot.
struct BlueprintPagedCatalogGrid: View {
    let entries: [BlueprintCatalogEntry]
    var ideaEntries: [IdeaDiscoveryEntry] = []
    var addedIdeaSourceIDs: Set<String> = []
    var showsIdeas = true
    var projectionIsReady = true
    let source: BlueprintCatalogSource
    let transitionNamespace: Namespace.ID
    let scope: BlueprintCatalogFeedScope
    let adSession: ExploreAdSession?
    let isLoading: Bool
    let isExhausted: Bool
    let loadFailed: Bool
    let onSelect: (BlueprintCatalogEntry) -> Void
    var onSelectIdea: ((IdeaDiscoveryEntry) -> Void)? = nil
    var onIdeaLoadMore: (() -> Void)? = nil
    var guidedSelectionKey: String? = nil
    var onGuidedSelection: ((BlueprintCatalogEntry) -> Void)? = nil
    var guidedTourActive = false
    let onLoadMore: () -> Void
    let onRetry: () -> Void
    var actionStore: BlueprintActionStore? = nil
    var itemsHeader: AnyView? = nil
    var itemsFooter: AnyView? = nil
    var measurementIsActive = true
    var localExposureIsActive = true
    var measurementScopeID = "default"
    var onMeaningfulExposure: ((String) -> Void)? = nil
    var scrollIdentifier = "blueprint.catalog.scroll"
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var lastAutomaticLoadOffset: CGFloat = -1
    @State private var viewportSize = CGSize.zero
    @State private var adColumnWidth: CGFloat = 0
    @State private var adPlacements = ExploreAdPlacementState()
    @State private var placementIdentity: AdFeedLayoutIdentity?
    @State private var visibleOrganicIndices: Set<Int> = []
    @State private var feedProjection = ExploreFeedProjectionCache()
    @State private var scrollPosition = ScrollPosition(edge: .top)
    @Environment(\.locale) private var locale

    private var adLayoutIdentity: AdFeedLayoutIdentity {
        .init(scope: scope, includesIdeas: showsIdeas, sessionID: adSession?.scopeID,
              resetGeneration: adSession?.resetGeneration ?? 0,
              viewportWidth: viewportSize.width, columnWidth: adColumnWidth, textSize: dynamicTypeSize,
              locale: locale.identifier)
    }

    private var prefetchSlotIDs: [String] {
        let firstVisible = visibleOrganicIndices.min() ?? 0
        return feedRows.enumerated().compactMap { index, row -> String? in
            guard index + 1 >= firstVisible, let slotID = row.adSlotID,
                  !adPlacements.skippedSlots.contains(slotID) else { return nil }
            return slotID
        }.prefix(3).map { $0 }
    }
    private var projectionInput: ExploreFeedProjectionInput {
        .init(context: projectionContext,
              blueprintIDs: projectionIsReady ? entries.map(\.id) : [],
              ideaIDs: projectionIsReady ? ideaEntries.map(\.id) : [])
    }
    private var projectionContext: String {
        let sourceID: String = switch source {
        case .results: "results"
        case .recent: "recent"
        case .category(let category): "category:\(category)"
        }
        return "\(sourceID)|\(scope.category ?? "")|\(scope.query ?? "")"
    }
    private var loadMoreTitle: String {
        String(localized: "explore.loadMore", defaultValue: "Load More")
    }
    private var feedRows: [BlueprintPagedCatalogRow] {
        guard projectionIsReady else { return [] }
        var rows: [BlueprintPagedCatalogRow] = []
        let blueprintByID = Dictionary(entries.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let ideaByID = Dictionary(ideaEntries.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let input = projectionInput
        var projection = feedProjection
        projection.update(context: input.context, blueprintIDs: input.blueprintIDs, ideaIDs: input.ideaIDs)
        let identities = projection.identities
        for identity in identities {
            let content: BlueprintPagedCatalogContent
            switch identity {
            case .blueprint(let id):
                guard let entry = blueprintByID[id] else { continue }
                content = .blueprint(entry)
            case .idea(let id):
                guard showsIdeas, let entry = ideaByID[id] else { continue }
                content = .idea(entry)
            }
            let slotID = adSession == nil ? nil : ExploreAdFeedPolicy.slotID(afterOrganicCount: rows.count + 1)
            rows.append(BlueprintPagedCatalogRow(content: content, adSlotID: slotID))
        }
        return rows
    }

    var body: some View {
        let horizontalInset = LayoutDimensions.nonnegative(AppTheme.Layout.screenHorizontal)

        let contentIdentity = PagedGridContentIdentity(source: source, scope: scope)
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.standard) {
                catalogItems
            }
            .containerRelativeFrame(.horizontal) { width, _ in
                min(1200, max(width - 2 * horizontalInset, 0))
            }
            .frame(maxWidth: .infinity)
            .padding(.top, AppTheme.Layout.screenTop)
            .padding(.bottom, AppTheme.Layout.screenBottom)
        }
        .frame(maxWidth: .infinity)
        .scrollPosition($scrollPosition)
        .accessibilityIdentifier(scrollIdentifier)
        .onGeometryChange(for: CGSize.self) { $0.size } action: { viewportSize = $0 }
        .background {
            if let adSession {
                ZStack {
                    ForEach(prefetchSlotIDs, id: \.self) { slotID in
                        ExploreAdSlotLoader(slotID: slotID, session: adSession)
                    }
                }
                .id(adSession.scopeID)
                .accessibilityHidden(true)
            }
        }
        .onChange(of: adLayoutIdentity) { _, _ in ensureAdLayoutIdentity() }
        .onChange(of: adSession?.loadedSlotIDs ?? []) { _, _ in admitReadyAds() }
        .onChange(of: entries.isEmpty && (!showsIdeas || ideaEntries.isEmpty)) { _, empty in
            if empty { adPlacements.reset(); visibleOrganicIndices.removeAll() }
        }
        .scrollIndicators(.hidden)
        .appSoftScrollEdges()
        .onScrollGeometryChange(for: PagedFeedScrollState.self) { geometry in
            PagedFeedScrollState(
                offset: max(geometry.contentOffset.y, 0),
                remaining: geometry.contentSize.height - geometry.contentOffset.y - geometry.containerSize.height
            )
        } action: { _, state in
            guard !isLoading, !isExhausted, !loadFailed,
                  state.remaining < 520,
                  state.offset >= lastAutomaticLoadOffset + 140 else { return }
            lastAutomaticLoadOffset = state.offset
            onLoadMore()
        }
        .onChange(of: contentIdentity) { _, _ in
            lastAutomaticLoadOffset = -1
            // Keep the native scroll/search hierarchy alive while showing the
            // first result of a new query. Page appends do not change identity.
            scrollPosition.scrollTo(edge: .top)
        }
        .onChange(of: guidedTourActive, initial: true) { _, isGuided in
            if isGuided { scrollPosition.scrollTo(edge: .top) }
        }
        .onAppear { updateProjection(projectionInput) }
        .onChange(of: projectionInput) { _, input in updateProjection(input) }
    }

    private func updateProjection(_ input: ExploreFeedProjectionInput) {
        feedProjection.update(context: input.context,
                              blueprintIDs: input.blueprintIDs,
                              ideaIDs: input.ideaIDs)
    }

    private var catalogItems: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.standard) {
            if let itemsHeader { itemsHeader }
            AdaptiveLazyMasonry(
                items: feedRows,
                columnCount: dynamicTypeSize.isAccessibilitySize ? 1 : 2,
                spacing: 12,
                minimumColumnWidth: 170,
                estimatedHeight: { row, width in
                    let cardHeight: CGFloat
                    switch row.content {
                    case .blueprint(let entry):
                        let imageHeight = width * (
                            entry.browseCategories.first?.catalogTileAspectRatio
                                ?? BlueprintBrowseCategory.events.catalogTileAspectRatio
                        )
                        cardHeight = imageHeight + BlueprintCatalogTile.estimatedTextHeight
                    case .idea(let entry):
                        let category = IdeaCategory(rawValue: entry.idea.category) ?? .other
                        cardHeight = width / category.collectionAspectRatio
                    }
                    return cardHeight + (row.adSlotID == nil ? 0 : 12 + 360)
                }
            ) { row, index in
                let sourcePriority = Double(feedRows.count - index) * 2
                rowView(row, index: index, sourcePriority: sourcePriority)
            }

            if let itemsFooter { itemsFooter }

            if loadFailed {
                Button(AppCopy.Common.retry, action: onRetry)
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity)
                    .disabled(guidedTourActive)
            } else if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            } else if !isExhausted {
                Button(loadMoreTitle, action: onLoadMore)
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity)
                    .disabled(guidedTourActive)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func rowView(_ row: BlueprintPagedCatalogRow, index: Int, sourcePriority: Double) -> some View {
        VStack(spacing: 12) {
            organicCard(row, sourcePriority: sourcePriority)
                .onScrollVisibilityChange(threshold: 0.01) { visible in
                    guard adSession != nil else { return }
                    if visible { visibleOrganicIndices.insert(index + 1) }
                    else { visibleOrganicIndices.remove(index + 1) }
                }
                .onGeometryChange(for: AdInsertionGeometry.self) { proxy in
                    AdInsertionGeometry(
                        identity: adLayoutIdentity, width: proxy.size.width,
                        viewportIsKnown: viewportSize.height > 0,
                        belowViewport: proxy.frame(in: .scrollView(axis: .vertical)).maxY > viewportSize.height
                    )
                } action: { geometry in
                    guard let slotID = row.adSlotID, geometry.viewportIsKnown else { return }
                    recordAdAnchor(slotID: slotID, geometry: geometry)
                }
            if let slotID = row.adSlotID, let adSession,
               let reservedHeight = adPlacements.reservedHeight(for: slotID) {
                Group {
                    if let ad = adSession.ad(forSlotID: slotID),
                       adPlacements.renders(slotID: slotID, creativeID: String(describing: ObjectIdentifier(ad))) {
                        AdMobNativeAdCard(slotID: slotID, session: adSession)
                    } else { Color.clear.accessibilityHidden(true) }
                }
                .frame(minHeight: reservedHeight, alignment: .top)
                .id(adSession.scopeID)
                .accessibilitySortPriority(sourcePriority - 1)
            }
        }
    }

    @ViewBuilder
    private func organicCard(_ row: BlueprintPagedCatalogRow, sourcePriority: Double) -> some View {
        switch row.content {
        case .blueprint(let entry):
            BlueprintCatalogCardButton(entry: entry, actionStore: actionStore,
                measurementIsActive: measurementIsActive,
                localExposureIsActive: localExposureIsActive,
                transitionID: BlueprintPreviewTransitionID(source: source, entryID: entry.id),
                namespace: transitionNamespace, measurementScopeID: measurementScopeID,
                onMeaningfulExposure: onMeaningfulExposure,
                onSelect: { onSelect(entry) },
                guidedSelectionKey: guidedSelectionKey,
                guidedTourActive: guidedTourActive,
                onGuidedSelection: { onGuidedSelection?(entry) })
                .accessibilitySortPriority(sourcePriority)
        case .idea(let entry):
            if let onSelectIdea {
                Button { onSelectIdea(entry) } label: {
                    IdeaDiscoveryCard(entry: entry, isAdded: addedIdeaSourceIDs.contains(entry.id))
                }
                .buttonStyle(.plain)
                .disabled(guidedTourActive)
                .accessibilityIdentifier("idea.discovery.card.\(entry.id)")
                .accessibilitySortPriority(sourcePriority)
                .onScrollVisibilityChange(threshold: 0.01) { visible in
                    guard visible, ideaEntries.suffix(4).contains(where: { $0.id == entry.id }) else { return }
                    onIdeaLoadMore?()
                }
            }
        }
    }

    private func ensureAdLayoutIdentity() {
        guard placementIdentity != adLayoutIdentity else { return }
        adPlacements.reset()
        visibleOrganicIndices.removeAll()
        placementIdentity = adLayoutIdentity
    }

    private func recordAdAnchor(slotID: String, geometry: AdInsertionGeometry) {
        guard geometry.identity == adLayoutIdentity else { return }
        // Fold reservations can change column width without resizing the window.
        if geometry.width.isFinite, geometry.width > 0, adColumnWidth != geometry.width {
            adColumnWidth = geometry.width
        }
        ensureAdLayoutIdentity()
        guard adSession?.isSuspended == false else { return }
        adPlacements.updateAnchor(slotID: slotID, width: geometry.width,
                                  insertionBelowViewport: geometry.belowViewport)
        admitReadyAds()
    }

    private func admitReadyAds() {
        ensureAdLayoutIdentity()
        guard let adSession, !adSession.isSuspended else { return }
        for (slotID, placement) in adPlacements.placements {
            if adSession.ad(forSlotID: slotID) == nil, let creativeID = placement.creativeID {
                adPlacements.removeCreative(slotID: slotID, creativeID: creativeID)
            }
        }
        for (slotID, anchor) in adPlacements.anchors {
            guard let ad = adSession.ad(forSlotID: slotID) else { continue }
            let creativeID = String(describing: ObjectIdentifier(ad))
            guard !adPlacements.renders(slotID: slotID, creativeID: creativeID) else { continue }
            let height = AdMobNativeAdCard.measuredHeight(
                for: ad, width: anchor.width, contentSizeCategory: adContentSizeCategory
            )
            adPlacements.admit(slotID: slotID, creativeID: creativeID, height: height)
        }
    }

    private var adContentSizeCategory: UIContentSizeCategory {
        switch dynamicTypeSize {
        case .xSmall: .extraSmall
        case .small: .small
        case .medium: .medium
        case .large: .large
        case .xLarge: .extraLarge
        case .xxLarge: .extraExtraLarge
        case .xxxLarge: .extraExtraExtraLarge
        case .accessibility1: .accessibilityMedium
        case .accessibility2: .accessibilityLarge
        case .accessibility3: .accessibilityExtraLarge
        case .accessibility4: .accessibilityExtraExtraLarge
        case .accessibility5: .accessibilityExtraExtraExtraLarge
        @unknown default: .large
        }
    }

}

private struct ExploreFeedProjectionInput: Equatable {
    let context: String
    let blueprintIDs: [String]
    let ideaIDs: [String]
}

private struct PagedGridContentIdentity: Hashable {
    let source: BlueprintCatalogSource
    let scope: BlueprintCatalogFeedScope
}

private enum BlueprintPagedCatalogContent {
    case blueprint(BlueprintCatalogEntry)
    case idea(IdeaDiscoveryEntry)
}

private struct BlueprintPagedCatalogRow: Identifiable {
    let content: BlueprintPagedCatalogContent
    let adSlotID: String?
    var id: String {
        switch content {
        case .blueprint(let entry): "blueprint:\(entry.id)"
        case .idea(let entry): "idea:\(entry.id)"
        }
    }
}

private struct PagedFeedScrollState: Equatable {
    let offset: CGFloat
    let remaining: CGFloat
}

private struct BlueprintDiscoveryArtwork: View {
    let category: BlueprintBrowseCategory

    var body: some View {
        ProgressiveArtwork(
            symbol: category.symbol,
            colors: category.artworkCategory.artworkColors,
            accent: category.artworkCategory.artworkAccent,
            ambientBlurRadius: 12,
            progressiveBlurRadius: 0
        )
        .accessibilityHidden(true)
    }
}

extension BlueprintBrowseCategory {
    private static let categoryTilePalette: [(background: Color, foreground: Color)] =
        [
            (Color(red: 32 / 255, green: 201 / 255, blue: 151 / 255), Color(red: 6 / 255, green: 59 / 255, blue: 47 / 255)), // emerald
            (Color(red: 123 / 255, green: 231 / 255, blue: 196 / 255), Color(red: 6 / 255, green: 61 / 255, blue: 53 / 255)), // mint
            (Color(red: 255 / 255, green: 212 / 255, blue: 59 / 255), Color(red: 61 / 255, green: 48 / 255, blue: 0 / 255)), // yellow
            (Color(red: 255 / 255, green: 111 / 255, blue: 174 / 255), Color(red: 75 / 255, green: 16 / 255, blue: 43 / 255)), // pink
            (Color(red: 49 / 255, green: 95 / 255, blue: 234 / 255), .white), // cobalt
            (Color(red: 135 / 255, green: 150 / 255, blue: 255 / 255), Color(red: 16 / 255, green: 24 / 255, blue: 73 / 255)), // periwinkle
            (Color(red: 255 / 255, green: 159 / 255, blue: 28 / 255), Color(red: 70 / 255, green: 32 / 255, blue: 0 / 255)), // orange
            (Color(red: 255 / 255, green: 107 / 255, blue: 107 / 255), Color(red: 77 / 255, green: 16 / 255, blue: 16 / 255)), // coral
            (Color(red: 165 / 255, green: 107 / 255, blue: 255 / 255), Color(red: 36 / 255, green: 16 / 255, blue: 68 / 255)) // violet
        ]
    private var categoryTileColors: (background: Color, foreground: Color) {
        // Keep each category's color stable when cases are added or reordered.
        let index = switch self {
        case .weddings, .dinnerParties: 0
        case .birthdays, .picnics: 1
        case .holidays, .gameNights: 2
        case .engagements, .trips: 3
        case .showers, .cottageStays: 4
        case .bachelorParties, .guestStays: 5
        case .anniversaries, .retreats: 6
        case .graduations, .community: 7
        case .reunions, .events: 8
        }
        return Self.categoryTilePalette[index]
    }

    var categoryTileBackground: Color { categoryTileColors.background }
    var categoryTileForeground: Color { categoryTileColors.foreground }

    var catalogTileAspectRatio: CGFloat {
        min(0.92, max(0.70, catalogAspectRatio * 0.96))
    }

    var catalogAspectRatio: CGFloat {
        switch self {
        case .weddings: 0.82
        case .birthdays: 1.06
        case .holidays: 0.92
        case .events: 0.88
        case .engagements, .anniversaries, .cottageStays, .trips: 0.82
        case .showers, .graduations, .picnics, .community: 1.06
        case .bachelorParties, .reunions, .dinnerParties, .gameNights, .guestStays, .retreats: 0.92
        }
    }

    var artworkCategory: TimelineCategory {
        switch self {
        case .weddings: .ceremony
        case .birthdays: .bachelorBachelorette
        case .holidays: .weddingShower
        case .events: .venue
        case .engagements, .anniversaries: .ceremony
        case .showers, .reunions: .weddingShower
        case .bachelorParties, .gameNights: .bachelorBachelorette
        case .graduations, .dinnerParties, .community: .reception
        case .picnics, .cottageStays, .guestStays, .retreats: .venue
        case .trips: .honeymoon
        }
    }
}

nonisolated private struct AdFeedLayoutIdentity: Equatable, Sendable {
    let scope: BlueprintCatalogFeedScope
    let includesIdeas: Bool
    let sessionID: String?
    let resetGeneration: Int
    let viewportWidth: CGFloat
    let columnWidth: CGFloat
    let textSize: DynamicTypeSize
    let locale: String
}

nonisolated private struct AdInsertionGeometry: Equatable, Sendable {
    let identity: AdFeedLayoutIdentity
    let width: CGFloat
    let viewportIsKnown: Bool
    let belowViewport: Bool
}
