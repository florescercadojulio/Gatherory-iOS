import SwiftUI

struct IdeaDiscoveryCard: View {
    let entry: IdeaDiscoveryEntry
    var isAdded = false

    var body: some View {
        let category = IdeaCategory(rawValue: entry.idea.category) ?? .other
        IdeaCollectionPresentation(title: entry.idea.title, category: category,
            aspectRatio: category.collectionAspectRatio) {
            BlueprintCoverArtwork(assetID: entry.coverAssetId, publicImageURL: entry.coverImageURL,
                source: BlueprintCoverSource(catalogKey: entry.sourceBlueprintId,
                                            revision: entry.sourceVersion)) {
                MediaArtwork(imageData: nil, symbol: category.symbol,
                    colors: category.artworkColors, accent: category.artworkAccent,
                    ambientBlurRadius: 12, progressiveBlurRadius: 0)
            }
        } supporting: {
            Text(entry.sourceTitle).lineLimit(1)
        }
        .overlay(alignment: .topTrailing) {
            if isAdded {
                Label(String(localized: "ideaDiscovery.addedMarker", defaultValue: "Added"), systemImage: "checkmark.circle.fill")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.regularMaterial, in: Capsule())
                    .padding(10)
                    .accessibilityIdentifier("idea.discovery.added.\(entry.id)")
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct IdeaDiscoveryGrid: View {
    let entries: [IdeaDiscoveryEntry]
    let isLoading: Bool
    let loadFailed: Bool
    let hasLoadedFirstPage: Bool
    let shouldAutoAdvanceEmptyPage: Bool
    let nextCursor: String?
    let onSelect: (IdeaDiscoveryEntry) -> Void
    let onLoadMore: () -> Void
    let onRetry: () -> Void
    let onRefresh: () async -> Void
    var addedSourceIDs: Set<String> = []
    var adSession: ExploreAdSession? = nil
    var transitionNamespace: Namespace.ID? = nil
    var scope: BlueprintCatalogFeedScope = .all
    @Namespace private var fallbackNamespace
    @State private var lastAutomaticallyRequestedCursor: String?

    var body: some View {
        BlueprintPagedCatalogGrid(
            entries: [], ideaEntries: entries, addedIdeaSourceIDs: addedSourceIDs,
            source: .results, transitionNamespace: transitionNamespace ?? fallbackNamespace,
            scope: scope, adSession: adSession,
            isLoading: isLoading, isExhausted: hasLoadedFirstPage && nextCursor == nil,
            loadFailed: loadFailed, onSelect: { _ in }, onSelectIdea: onSelect,
            onIdeaLoadMore: { requestNextPageIfVisible() },
            onLoadMore: { requestNextPageIfVisible() }, onRetry: onRetry,
            itemsFooter: shouldAutoAdvanceEmptyPage ? AnyView(
                Color.clear.frame(height: 1).frame(maxWidth: .infinity)
                    .id("\(nextCursor ?? "end")-\(isLoading)")
                    .accessibilityHidden(true)
                    .onScrollVisibilityChange(threshold: 0.01) { visible in
                        if visible { requestNextPageIfVisible() }
                    }
            ) : nil,
            measurementIsActive: false, localExposureIsActive: false,
            scrollIdentifier: "idea.discovery.scroll"
        )
        .overlay {
            if entries.isEmpty {
                if !hasLoadedFirstPage && !loadFailed {
                    ProgressView().allowsHitTesting(false)
                } else if loadFailed {
                    ContentUnavailableView(
                        String(localized: "Ideas unavailable", defaultValue: "Ideas unavailable"),
                        systemImage: "wifi.exclamationmark",
                        description: Text(String(localized: "Check your connection and try again.", defaultValue: "Check your connection and try again."))
                    ).allowsHitTesting(false)
                } else if !isLoading && !shouldAutoAdvanceEmptyPage {
                    ContentUnavailableView.search(text: "").allowsHitTesting(false)
                }
            }
        }
        .refreshable {
            lastAutomaticallyRequestedCursor = nil
            await onRefresh()
        }
        .onChange(of: entries.first?.id) { _, _ in
            lastAutomaticallyRequestedCursor = nil
        }
    }

    private func requestNextPageIfVisible() {
        guard !isLoading, !loadFailed, let nextCursor,
              lastAutomaticallyRequestedCursor != nextCursor else { return }
        lastAutomaticallyRequestedCursor = nextCursor
        onLoadMore()
    }
}

struct IdeaDiscoveryDetailView: View {
    let entry: IdeaDiscoveryEntry
    var isAdded: Bool = false
    var onAdded: ((IdeaDiscoveryAdditionReceipt) -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var isAddPresented = false
    @State private var additionReceipt: IdeaDiscoveryAdditionReceipt?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    BlueprintCoverArtwork(assetID: entry.coverAssetId, publicImageURL: entry.coverImageURL,
                        source: BlueprintCoverSource(catalogKey: entry.sourceBlueprintId,
                                                    revision: entry.sourceVersion)) {
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .fill(AppTheme.ColorToken.accent.opacity(0.14))
                            .overlay { Image(systemName: "sparkles").font(.largeTitle).foregroundStyle(AppTheme.ColorToken.accent) }
                    }
                        .overlay(alignment: .topTrailing) {
                            if isAdded {
                                Label(String(localized: "Added", defaultValue: "Added"), systemImage: "checkmark.circle.fill")
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 7)
                                    .background(.regularMaterial, in: Capsule())
                                    .padding(12)
                                    .accessibilityIdentifier("idea.discovery.added")
                            }
                        }
                        .frame(height: 310)
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    Text(entry.idea.title).font(.largeTitle.bold())
                    Label(entry.idea.category.capitalized, systemImage: "sparkles")
                        .font(.subheadline).foregroundStyle(AppTheme.ColorToken.textSecondary)
                    if let notes = entry.idea.notes, !notes.isEmpty {
                        Text(notes).font(.body).foregroundStyle(AppTheme.ColorToken.textPrimary)
                    }
                    Text("From \(entry.sourceTitle)")
                        .font(.footnote).foregroundStyle(AppTheme.ColorToken.textSecondary)
                    if let creator = entry.creator?.displayName, !creator.isEmpty {
                        Text("By \(creator)")
                            .font(.footnote).foregroundStyle(AppTheme.ColorToken.textSecondary)
                    }
                    Button {
                        additionReceipt = nil
                        isAddPresented = true
                    } label: {
                        Label(String(localized: "Add to Event", defaultValue: "Add to Event"), systemImage: "plus")
                            .frame(maxWidth: .infinity, minHeight: 50)
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("idea.discovery.addToEvent")
                }
                .padding(20)
            }
            .navigationTitle(String(localized: "Idea", defaultValue: "Idea"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button(String(localized: "Done", defaultValue: "Done")) { dismiss() } } }
        }
        .sheet(isPresented: $isAddPresented, onDismiss: {
            guard let receipt = additionReceipt else { return }
            additionReceipt = nil
            onAdded?(receipt)
            dismiss()
        }) {
            IdeaAddToEventSheet(entry: entry) { receipt in
                additionReceipt = receipt
                isAddPresented = false
            }
        }
    }
}
