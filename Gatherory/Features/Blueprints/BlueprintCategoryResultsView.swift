import SwiftUI

/// Own the zoom at the visible category level, not at the Search screen below it.
struct BlueprintCategoryResultsView: View {
    let category: BlueprintBrowseCategory
    let entries: [BlueprintCatalogEntry]
    let onAccess: (BlueprintCatalogEntry) -> Void
    let onRefresh: () async -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var blueprintTransition
    @State private var navigation = BlueprintDiscoveryNavigation()

    private var source: BlueprintCatalogSource { .category(category.rawValue) }
    private var displayedEntries: [BlueprintCatalogEntry] {
        navigation.entries(for: source, fallback: entries)
    }

    var body: some View {
        BlueprintCatalogGrid(
            entries: displayedEntries, source: source,
            transitionNamespace: blueprintTransition
        ) { entry in
            navigation.open(entry, from: source, entries: displayedEntries, mode: .browse, query: "")
        }
        .background(AppTheme.ColorToken.background)
        .overlay {
            if displayedEntries.isEmpty {
                ContentUnavailableView(
                    ExploreCopy.emptyCategory, systemImage: "magnifyingglass",
                    description: Text(ExploreCopy.checkBack)
                )
                .allowsHitTesting(false)
            }
        }
        .navigationTitle(category.title)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await onRefresh() }
        .navigationDestination(item: $navigation.selection) { selection in
            Group {
                if reduceMotion {
                    BlueprintPreviewView(entry: selection.entry)
                } else {
                    BlueprintPreviewView(entry: selection.entry)
                        .navigationTransition(.zoom(sourceID: selection.id, in: blueprintTransition))
                }
            }
            .onAppear { onAccess(selection.entry) }
        }
        .onChange(of: navigation.selection?.id) { _, selected in
            if selected == nil { navigation.completeReturn() }
        }
    }
}
