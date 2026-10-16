import SwiftUI

struct BlueprintExploreView: View {
    @Environment(WorkspaceCloudSyncController.self) private var cloudSync
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var blueprintTransition
    @State private var model: BlueprintDiscoveryModel
    @State private var query = ""
    @State private var navigation = BlueprintDiscoveryNavigation()
    @FocusState private var isFocused: Bool

    init(ownerID: String) {
        _model = State(initialValue: BlueprintDiscoveryModel(ownerID: ownerID))
    }

    private var mode: BlueprintSearchMode { navigation.mode(isFocused: isFocused, query: query) }

    var body: some View {
        Group {
            if model.loading && model.entries.isEmpty {
                ProgressView(ExploreCopy.loading)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.loadFailed && model.entries.isEmpty {
                ContentUnavailableView {
                    Label(ExploreCopy.unavailable, systemImage: "wifi.exclamationmark")
                } description: {
                    Text(ExploreCopy.connection)
                } actions: {
                    Button(AppCopy.Common.retry) { Task { await load() } }
                }
            } else {
                switch mode {
                case .browse: categories
                case .recent: recent
                case .results:
                    blueprintGrid(model.entries.filter { $0.matches(query: query) }, source: .results, emptyTitle: ExploreCopy.noResults, emptyMessage: ExploreCopy.tryAnotherSearch)
                }
            }
        }
        .background(AppTheme.ColorToken.background)
        .navigationTitle(ExploreCopy.searchTitle)
        .toolbarTitleDisplayMode(.inlineLarge)
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: ExploreCopy.search)
        .searchFocused($isFocused)
        .navigationDestination(item: $navigation.selection) { selection in
            Group {
                if reduceMotion {
                    BlueprintPreviewView(entry: selection.entry)
                } else {
                    BlueprintPreviewView(entry: selection.entry)
                        .navigationTransition(.zoom(sourceID: selection.id, in: blueprintTransition))
                }
            }
            .onAppear { model.recordAccess(selection.entry) }
        }
        .onChange(of: navigation.selection?.id) { _, selected in
            guard selected == nil else { return }
            if navigation.restoresSearchFocus {
                query = navigation.retainedQuery ?? query
                if isFocused { navigation.completeReturn() }
                else { isFocused = true }
            } else {
                navigation.completeReturn()
            }
        }
        .onChange(of: isFocused) { _, focused in
            if focused { navigation.completeReturn() }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                AccountToolbarButton(avatarSize: 44)
            }
            .sharedBackgroundVisibility(.hidden)
        }
        .safeAreaInset(edge: .bottom) {
            if model.loadFailed && !model.entries.isEmpty {
                HStack {
                    Text(ExploreCopy.refreshFailed).font(.footnote)
                    Button(AppCopy.Common.retry) { Task { await load() } }
                }
                .padding().background(.regularMaterial)
            }
        }
        .task(id: String(describing: cloudSync.accountOnboardingState)) { await load() }
    }

    private var categories: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.standard) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: dynamicTypeSize.isAccessibilitySize ? 1 : 2), spacing: 16) {
                    ForEach(BlueprintBrowseCategory.allCases) { category in
                        NavigationLink {
                            BlueprintCategoryResultsView(
                                category: category,
                                entries: model.entries.filter { $0.browseCategories.contains(category) },
                                onAccess: { model.recordAccess($0) },
                                onRefresh: { await load() }
                            )
                        } label: {
                            BlueprintCategoryTile(category: category)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
            .padding(AppTheme.Layout.screenHorizontal)
        }
        .refreshable { await load() }
    }

    private var recent: some View {
        VStack(spacing: 0) {
            HStack {
                Text(ExploreCopy.recent).font(.title2.bold())
                Spacer()
                if !model.recentEntries.isEmpty {
                    Button(ExploreCopy.clear) { model.clearRecents() }
                        .frame(minHeight: 44)
                }
            }.padding(.horizontal)
            blueprintGrid(model.recentEntries, source: .recent, emptyTitle: ExploreCopy.noRecents, emptyMessage: ExploreCopy.recentsHint)
        }
    }

    private func blueprintGrid(_ entries: [BlueprintCatalogEntry], source: BlueprintCatalogSource,
                               emptyTitle: String, emptyMessage: String) -> some View {
        let displayed = navigation.entries(for: source, fallback: entries)
        return BlueprintCatalogGrid(entries: displayed, source: source, transitionNamespace: blueprintTransition) { entry in
            navigation.open(entry, from: source, entries: displayed, mode: mode, query: query)
        }
        .background(AppTheme.ColorToken.background)
        .overlay {
            if displayed.isEmpty {
                ContentUnavailableView(emptyTitle, systemImage: "magnifyingglass", description: Text(emptyMessage))
                    .allowsHitTesting(false)
            }
        }
        .refreshable { await load() }
    }

    private func load() async {
        await model.load {
            guard let coordinator = cloudSync.makeBlueprintInstallationCoordinator() else {
                throw CloudSyncFailure.invalidSession
            }
            return try await coordinator.catalog()
        }
    }
}
