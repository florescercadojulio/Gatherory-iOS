import SwiftUI

/// Category results use the same server cursor stream as search and Explore.
/// The category screen remains the zoom owner for its visible cards.
struct BlueprintCategoryResultsView: View {
    let category: BlueprintBrowseCategory
    let ownerID: String
    var actionStore: BlueprintActionStore? = nil
    let onAccess: (BlueprintCatalogEntry) -> Void
    var onVisibilityChange: (Bool) -> Void = { _ in }
    @Environment(WorkspaceCloudSyncController.self) private var cloudSync
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.blueprintPreviewPresented) private var previewPresented
    @Namespace private var blueprintTransition
    @State private var navigation = BlueprintDiscoveryNavigation()
    @State private var feed: BlueprintCatalogFeedModel
    @State private var adSession: ExploreAdSession
    let isActive: Bool

    init(category: BlueprintBrowseCategory, ownerID: String, isActive: Bool = true,
         actionStore: BlueprintActionStore? = nil,
         onVisibilityChange: @escaping (Bool) -> Void = { _ in },
         onAccess: @escaping (BlueprintCatalogEntry) -> Void) {
        self.category = category
        self.ownerID = ownerID
        self.isActive = isActive
        self.actionStore = actionStore
        self.onVisibilityChange = onVisibilityChange
        self.onAccess = onAccess
        _feed = State(initialValue: BlueprintCatalogFeedModel(ownerID: ownerID))
        _adSession = State(initialValue: ExploreAdSession(scopeID: UUID().uuidString))
    }

    private var source: BlueprintCatalogSource { .category(category.rawValue) }
    private var displayedEntries: [BlueprintCatalogEntry] {
        navigation.entries(for: source, fallback: feed.entries).filter {
            !(actionStore?.states[$0.catalogKey]?.notInterested ?? $0.viewerState?.notInterested ?? false)
        }
    }
    private var accountStateID: String { String(describing: cloudSync.accountOnboardingState) }
    private var catalogTaskID: String {
        "\(ownerID)|\(isActive)|\(scenePhase == .active)|\(accountStateID)|\(category.rawValue)"
    }
    private var adTaskID: String {
        "\(ownerID)|\(isActive)|\(scenePhase == .active)|\(accountStateID)|\(navigation.selection?.entry.id ?? "")"
    }

    var body: some View {
        BlueprintPagedCatalogGrid(
            entries: displayedEntries,
            source: source,
            transitionNamespace: blueprintTransition,
            scope: .category(category),
            adSession: isActive && scenePhase == .active && navigation.selection == nil ? adSession : nil,
            isLoading: feed.isLoading,
            isExhausted: feed.isExhausted,
            loadFailed: feed.loadFailed,
            onSelect: { entry in
                if let actionStore { Task { await actionStore.record(.open, for: entry) } }
                previewPresented.wrappedValue = true
                navigation.open(entry, from: source, entries: displayedEntries, mode: .browse, query: "")
            },
            onLoadMore: { Task { await loadNextPage() } },
            onRetry: { Task { await refresh() } },
            actionStore: actionStore,
            measurementIsActive: isActive && scenePhase == .active && navigation.selection == nil,
            measurementScopeID: catalogTaskID
        )
        .background(AppTheme.ColorToken.background)
        .overlay {
            if !feed.isLoading && displayedEntries.isEmpty {
                ContentUnavailableView(
                    feed.loadFailed ? ExploreCopy.unavailable : ExploreCopy.emptyCategory,
                    systemImage: feed.loadFailed ? "wifi.exclamationmark" : "magnifyingglass",
                    description: Text(feed.loadFailed ? ExploreCopy.connection : ExploreCopy.checkBack)
                )
                .allowsHitTesting(false)
            }
        }
        .navigationTitle(category.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ExploreAdvertisingPrivacyButton(session: adSession)
            }
        }
        .refreshable { await refresh() }
        .onAppear { onVisibilityChange(true) }
        .onDisappear { onVisibilityChange(false) }
        .fullScreenCover(item: $navigation.selection, onDismiss: { previewPresented.wrappedValue = false }) { selection in
            BlueprintPreviewView(entry: selection.entry, actionStore: actionStore)
                .onAppear { onAccess(selection.entry) }
        }
        .onChange(of: navigation.selection?.id) { _, selected in
            if selected != nil { resetAdSession() }
            else { navigation.completeReturn() }
        }
        .onChange(of: ownerID) { _, newOwnerID in
            feed = BlueprintCatalogFeedModel(ownerID: newOwnerID)
            navigation = BlueprintDiscoveryNavigation()
            resetAdSession()
        }
        .onChange(of: accountStateID) { _, _ in
            feed = BlueprintCatalogFeedModel(ownerID: ownerID)
            navigation = BlueprintDiscoveryNavigation()
            resetAdSession()
        }
        .task(id: catalogTaskID) {
            guard isActive, scenePhase == .active, navigation.selection == nil else { return }
            feed.activate(.category(category))
            if !feed.hasLoadedFirstPage || feed.loadFailed {
                await feed.loadNextPage(fetch: fetchPage)
            }
        }
        .task(id: adTaskID) {
            guard isActive, scenePhase == .active, navigation.selection == nil else {
                resetAdSession()
                return
            }
            await adSession.prepare()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { resetAdSession() }
        }
        .onChange(of: isActive) { _, active in
            if !active { resetAdSession() }
        }
        .onDisappear { resetAdSession() }
    }

    private func loadNextPage() async {
        guard isActive, scenePhase == .active else { return }
        await feed.loadNextPage(fetch: fetchPage)
    }

    private func refresh() async {
        guard isActive, scenePhase == .active else { return }
        if feed.scope != .category(category) { feed.activate(.category(category)) }
        await feed.refresh(fetch: fetchPage)
    }

    private func fetchPage(cursor: String?, category: String?, query: String?) async throws -> BlueprintCatalogResponse {
        guard let coordinator = cloudSync.makeBlueprintInstallationCoordinator() else {
            throw CloudSyncFailure.invalidSession
        }
        return try await coordinator.catalogPage(
            cursor: cursor,
            limit: BlueprintCatalogFeedModel.pageSize,
            category: category,
            query: query
        )
    }

    private func resetAdSession() {
        adSession.reset()
        adSession = ExploreAdSession(scopeID: UUID().uuidString)
    }
}
