import SwiftUI

struct BlueprintPublicCollectionView: View {
    enum Kind: Equatable { case saved, liked }

    let kind: Kind
    let actionStore: BlueprintActionStore?
    let onExplore: () -> Void

    @Environment(WorkspaceCloudSyncController.self) private var cloudSync
    @Environment(AuthenticationSession.self) private var authentication
    @Environment(\.blueprintPreviewPresented) private var presentationActive
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.layoutDirection) private var layoutDirection
    @State private var openingID: String?
    @State private var openingTask: Task<Void, Never>?
    @State private var openingGeneration = UUID()
    @State private var openEntry: BlueprintCatalogEntry?
    @State private var failedToOpen = false

    private var items: [BlueprintSavedPreference] {
        guard let actionStore, actionStore.ownerID == authentication.currentUser?.id else { return [] }
        return actionStore.savedItems.filter { kind == .saved ? $0.bookmarked : $0.liked }
    }

    var body: some View {
        Group {
            if actionStore == nil || (actionStore?.isLoading == true && items.isEmpty) {
                ProgressView().frame(maxWidth: .infinity, minHeight: 160)
            } else if let actionStore, actionStore.preferencesLoadFailed, items.isEmpty {
                ContentUnavailableView {
                    Label(ExploreCopy.connection, systemImage: "wifi.exclamationmark")
                } description: {
                    Text(BlueprintCopy.libraryRefreshFailed)
                } actions: {
                    Button(AppCopy.Common.retry) { Task { await actionStore.loadPreferences() } }
                }
            } else if items.isEmpty {
                ContentUnavailableView {
                    Label(emptyTitle, systemImage: kind == .saved ? "bookmark" : "heart")
                } description: {
                    Text(emptyMessage)
                } actions: {
                    Button(BlueprintCopy.exploreBlueprints, action: onExplore)
                        .buttonStyle(.borderedProminent)
                }
            } else {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.standard) {
                    if let actionStore, actionStore.preferencesLoadFailed {
                        HStack {
                            Label(ExploreCopy.connection, systemImage: "wifi.exclamationmark")
                                .font(.footnote).foregroundStyle(.secondary)
                            Spacer()
                            Button(AppCopy.Common.retry) { Task { await actionStore.loadPreferences() } }
                        }
                    }
                    AdaptiveMasonry(
                        columnCount: dynamicTypeSize.isAccessibilitySize ? 1 : 2,
                        spacing: 12,
                        layoutDirection: layoutDirection,
                        minimumColumnWidth: 170
                    ) {
                        ForEach(items) { item in
                            ZStack(alignment: .topTrailing) {
                                Button { beginOpen(item) } label: { publicCard(item) }
                                    .buttonStyle(.plain)
                                    .accessibilityIdentifier("blueprint.library.public.\(item.catalogKey)")
                                    .disabled(openingID == item.id || !isAvailable(item))
                                    .accessibilityHint(BlueprintCopy.previewTitle)

                                if !isAvailable(item) {
                                    Button { Task { await remove(item) } } label: {
                                        Image(systemName: kind == .saved ? "bookmark.slash" : "heart.slash")
                                            .font(.body.weight(.semibold))
                                            .foregroundStyle(AppTheme.ColorToken.onMedia)
                                            .frame(minWidth: 44, minHeight: 44)
                                            .background(.ultraThinMaterial, in: Circle())
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel(removeActionTitle)
                                }
                            }
                            .contextMenu {
                                Button(removeActionTitle,
                                       systemImage: kind == .saved ? "bookmark.slash" : "heart.slash",
                                       role: .destructive) { Task { await remove(item) } }
                            }
                        }
                    }
                    .frame(maxWidth: 800)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .fullScreenCover(item: $openEntry, onDismiss: {
            presentationActive.wrappedValue = false
        }) { entry in
            if let actionStore { BlueprintPreviewView(entry: entry, presentationContext: .collection, actionStore: actionStore) }
        }
        .alert(BlueprintCopy.savedOpenUnavailable, isPresented: $failedToOpen) {
            Button(AppCopy.Common.cancel, role: .cancel) {}
        } message: { Text(BlueprintCopy.savedUnavailableExplanation) }
        .alert(BlueprintCopy.actionUpdateFailed, isPresented: Binding(
            get: { actionStore?.ownerID == authentication.currentUser?.id && actionStore?.error != nil },
            set: { if !$0 { actionStore?.clearError() } }
        )) {
            Button(AppCopy.Common.retry) { Task { await actionStore?.retryLastAction() } }
            Button(AppCopy.Common.cancel, role: .cancel) { actionStore?.clearError() }
        } message: {
            Text(actionStore?.error?.localizedDescription ?? BlueprintCopy.actionUpdateFailed)
        }
        .task(id: actionStore?.ownerID) { await actionStore?.loadPreferences() }
        .onChange(of: kind) { _, _ in cancelOpeningAndPreview() }
        .onChange(of: authentication.currentUser?.id) { _, _ in cancelOpeningAndPreview() }
        .onDisappear { cancelOpening() }
    }

    private var emptyTitle: String {
        kind == .saved ? BlueprintCopy.librarySavedEmptyTitle : BlueprintCopy.libraryLikedEmptyTitle
    }

    private var emptyMessage: String {
        kind == .saved ? BlueprintCopy.librarySavedEmptyMessage : BlueprintCopy.libraryLikedEmptyMessage
    }

    private func isAvailable(_ item: BlueprintSavedPreference) -> Bool {
        kind == .saved ? item.isAvailable : item.isLikeAvailable
    }

    private var removeActionTitle: String {
        kind == .saved ? BlueprintCopy.removeBookmark : BlueprintCopy.unlike
    }

    private func remove(_ item: BlueprintSavedPreference) async {
        guard let actionStore, authentication.currentUser?.id == actionStore.ownerID else { return }
        _ = await actionStore.set(kind == .saved ? .bookmark : .like, enabled: false, for: item)
    }

    private func beginOpen(_ item: BlueprintSavedPreference) {
        guard openingID == nil, isAvailable(item) else { return }
        cancelOpening()
        let generation = UUID()
        openingGeneration = generation
        openingID = item.id
        openingTask = Task { await open(item, generation: generation, expectedKind: kind) }
    }

    private func cancelOpening() {
        openingTask?.cancel()
        openingTask = nil
        openingGeneration = UUID()
        openingID = nil
    }

    private func cancelOpeningAndPreview() {
        cancelOpening()
        openEntry = nil
        failedToOpen = false
        presentationActive.wrappedValue = false
    }

    @ViewBuilder
    private func publicCard(_ item: BlueprintSavedPreference) -> some View {
        BlueprintPublicCollectionCard(item: item, kind: kind)
    }

    @MainActor
    private func open(_ item: BlueprintSavedPreference, generation: UUID, expectedKind: Kind) async {
        defer {
            if generation == openingGeneration {
                openingID = nil
                openingTask = nil
            }
        }
        guard let actionStore, authentication.currentUser?.id == actionStore.ownerID else { return }
        guard isAvailable(item) else { return }
        guard let coordinator = cloudSync.makeBlueprintInstallationCoordinator() else {
            if generation == openingGeneration { failedToOpen = true }
            return
        }
        let session = actionStore.sessionIdentity
        do {
            let catalog: BlueprintCatalogResponse
#if DEBUG
            if let fixture = BlueprintPreviewActionsVisualFixture.load(ownerID: actionStore.ownerID) {
                catalog = BlueprintCatalogResponse(entries: [fixture.entry])
            } else { catalog = try await coordinator.catalog() }
#else
            catalog = try await coordinator.catalog()
#endif
            guard !Task.isCancelled, generation == openingGeneration, kind == expectedKind,
                  actionStore.isCurrentSession(session),
                  authentication.currentUser?.id == actionStore.ownerID else { return }
            guard let entry = actionStore.publicEntry(for: item, in: catalog.entries) else {
                failedToOpen = true
                return
            }
            openEntry = entry
            presentationActive.wrappedValue = true
        } catch {
            guard !Task.isCancelled, generation == openingGeneration,
                  actionStore.isCurrentSession(session), authentication.currentUser?.id == actionStore.ownerID else { return }
            failedToOpen = true
        }
    }
}

private struct BlueprintPublicCollectionCard: View {
    let item: BlueprintSavedPreference
    let kind: BlueprintPublicCollectionView.Kind

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            BlueprintCoverArtwork(
                assetID: nil,
                publicImageURL: item.entry?.coverImageURL,
                source: BlueprintCoverSource(catalogKey: item.catalogKey, revision: item.revision)
            ) {
                ProgressiveArtwork(
                    symbol: kind == .saved ? "bookmark.fill" : "heart.fill",
                    colors: TimelineCategory.venue.artworkColors,
                    accent: TimelineCategory.venue.artworkAccent,
                    ambientBlurRadius: 12,
                    progressiveBlurRadius: 0
                )
            }
            LinearGradient(
                stops: [.init(color: .clear, location: 0.2),
                        .init(color: AppTheme.ColorToken.mediaScrim.opacity(0.82), location: 1)],
                startPoint: .top,
                endPoint: .bottom
            )
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(item.entry?.name ?? BlueprintCopy.savedUnavailable)
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                if let creator = item.entry?.creatorName, !creator.isEmpty {
                    Text(BlueprintCopy.creatorByline(creator))
                        .font(.caption)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .foregroundStyle(AppTheme.ColorToken.onMedia)
            .shadow(color: AppTheme.ColorToken.mediaScrim.opacity(0.36), radius: 5, y: 2)
            .padding(AppTheme.Spacing.standard)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 176, alignment: .bottomLeading)
        .background(AppTheme.ColorToken.mediaScrim)
        .clipShape(.rect(cornerRadius: AppTheme.Radius.card))
        .overlay { RoundedRectangle(cornerRadius: AppTheme.Radius.card).stroke(AppTheme.ColorToken.onMedia.opacity(0.16), lineWidth: 0.5) }
        .contentShape(.rect(cornerRadius: AppTheme.Radius.card))
        .accessibilityElement(children: .combine)
    }
}


#Preview("Saved and Liked Blueprint cards") {
    VStack(alignment: .leading, spacing: AppTheme.Spacing.standard) {
        Picker(BlueprintCopy.libraryCollectionPickerLabel, selection: .constant(BlueprintLibraryPrimaryCollection.saved)) {
            Text(BlueprintCopy.libraryYours).tag(BlueprintLibraryPrimaryCollection.yours)
            Text(BlueprintCopy.librarySaved).tag(BlueprintLibraryPrimaryCollection.saved)
            Text(BlueprintCopy.libraryLiked).tag(BlueprintLibraryPrimaryCollection.liked)
        }
        .pickerStyle(.segmented)
        BlueprintPublicCollectionCard(
            item: BlueprintSavedPreference(
                catalogKey: "garden_gathering",
                revision: 1,
                contentHash: String(repeating: "a", count: 64),
                liked: false,
                bookmarked: true,
                notInterested: false,
                bookmarkAvailability: "available",
                entry: .init(name: "A Gathering in the Garden", creatorName: "Gatherory")
            ),
            kind: .saved
        )
        BlueprintPublicCollectionCard(
            item: BlueprintSavedPreference(
                catalogKey: "coastal_weekend",
                revision: 2,
                contentHash: String(repeating: "a", count: 64),
                liked: true,
                bookmarked: false,
                notInterested: false,
                bookmarkAvailability: "available",
                entry: .init(name: "A Long Weekend by the Coast", creatorName: "Gatherory")
            ),
            kind: .liked
        )
    }
    .padding()
}
