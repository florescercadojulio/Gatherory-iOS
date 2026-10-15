import SwiftUI

struct BlueprintExploreView: View {
    @Environment(WorkspaceCloudSyncController.self) private var cloudSync
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var model: BlueprintDiscoveryModel
    @State private var query = ""
    @FocusState private var isFocused: Bool
    @State private var setupRoute: BlueprintSetupRoute?

    init(ownerID: String) {
        _model = State(initialValue: BlueprintDiscoveryModel(ownerID: ownerID))
    }

    private var mode: BlueprintSearchMode { .resolve(isFocused: isFocused, query: query) }

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
                    blueprintList(model.entries.filter { $0.matches(query: query) }, emptyTitle: ExploreCopy.noResults, emptyMessage: ExploreCopy.tryAnotherSearch)
                }
            }
        }
        .background(AppTheme.ColorToken.background)
        .navigationTitle(ExploreCopy.searchTitle)
        .toolbarTitleDisplayMode(.inlineLarge)
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: ExploreCopy.search)
        .searchFocused($isFocused)
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
        .sheet(item: $setupRoute, onDismiss: { Task { await load() } }) { route in
            NavigationStack {
                BlueprintSetupView(catalogKey: route.catalogKey, sharedToken: route.shareToken)
            }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }

    private var categories: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.standard) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: dynamicTypeSize.isAccessibilitySize ? 1 : 2), spacing: 16) {
                    ForEach(BlueprintBrowseCategory.allCases) { category in
                        NavigationLink {
                            blueprintList(model.entries.filter { $0.browseCategories.contains(category) }, emptyTitle: ExploreCopy.emptyCategory, emptyMessage: ExploreCopy.checkBack)
                                .navigationTitle(category.title)
                                .navigationBarTitleDisplayMode(.inline)
                        } label: {
                            VStack(alignment: .leading, spacing: 24) {
                                Image(systemName: category.symbol)
                                    .font(.largeTitle)
                                    .foregroundStyle(category.tint)
                                    .accessibilityHidden(true)
                                Text(category.title).font(.headline).foregroundStyle(.primary)
                                    .multilineTextAlignment(.leading)
                            }
                            .frame(maxWidth: .infinity, minHeight: 112, alignment: .leading)
                            .padding(20)
                            .background(category.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 24))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
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
            blueprintList(model.recentEntries, emptyTitle: ExploreCopy.noRecents, emptyMessage: ExploreCopy.recentsHint)
        }
    }

    private func blueprintList(_ entries: [BlueprintCatalogEntry], emptyTitle: String, emptyMessage: String) -> some View {
        List(entries) { entry in
            Button {
                model.recordAccess(entry)
                setupRoute = BlueprintSetupRoute(catalogKey: entry.catalogKey)
            } label: {
                HStack(spacing: 16) {
                    Image(systemName: entry.browseCategories.first?.symbol ?? "sparkles.rectangle.stack")
                        .font(.title2).foregroundStyle(AppTheme.ColorToken.accent)
                        .frame(width: 44, height: 52)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(entry.definition.blueprint.name).font(.headline).foregroundStyle(.primary)
                        if let summary = entry.discovery?.summary, !summary.isEmpty {
                            Text(summary).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                        }
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(ExploreCopy.openHint)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(AppTheme.ColorToken.background)
        .overlay {
            if entries.isEmpty {
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

private struct BlueprintSetupRoute: Identifiable {
    let catalogKey: String?
    let shareToken: String?
    let id = UUID()

    init(catalogKey: String?, shareToken: String? = nil) {
        self.catalogKey = catalogKey
        self.shareToken = shareToken
    }
}

private extension BlueprintBrowseCategory {
    var tint: Color {
        switch self {
        case .weddings: .pink
        case .birthdays: .purple
        case .holidays: .green
        case .events: .blue
        }
    }
}
