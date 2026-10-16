import SwiftUI

/// Read-only discovery artwork. Category identity never depends on color alone.
struct BlueprintCategoryTile: View {
    let category: BlueprintBrowseCategory
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            BlueprintDiscoveryArtwork(category: category)
                .frame(height: 104)
            Text(category.title)
                .font(.headline)
                .foregroundStyle(AppTheme.ColorToken.textPrimary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(16)
                .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
        }
        .background(AppTheme.ColorToken.surface)
        .clipShape(.rect(cornerRadius: 24))
        .overlay {
            RoundedRectangle(cornerRadius: 24)
                .strokeBorder(AppTheme.ColorToken.hairline.opacity(contrast == .increased ? 1 : 0.35))
        }
        .contentShape(.rect(cornerRadius: 24))
        .accessibilityElement(children: .combine)
    }
}

/// Same artwork-led collection language as workspace ideas, without live status.
struct BlueprintCatalogTile: View {
    let entry: BlueprintCatalogEntry
    private var category: BlueprintBrowseCategory { entry.browseCategories.first ?? .events }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            BlueprintDiscoveryArtwork(category: category)
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.30),
                    .init(color: .black.opacity(0.14), location: 0.54),
                    .init(color: .black.opacity(0.74), location: 1)
                ], startPoint: .top, endPoint: .bottom
            )
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Label(category.title, systemImage: category.symbol)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Text(entry.definition.blueprint.name)
                    .font(.headline)
                    .lineLimit(3)
                if let summary = entry.discovery?.summary,
                   !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(summary).font(.caption).lineLimit(2)
                }
            }
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.36), radius: 5, y: 2)
            .padding(AppTheme.Spacing.standard)
        }
        .aspectRatio(category.catalogAspectRatio, contentMode: .fit)
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipShape(.rect(cornerRadius: AppTheme.Radius.card))
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.Radius.card)
                .stroke(.white.opacity(0.16), lineWidth: 0.5)
        }
        .contentShape(.rect(cornerRadius: AppTheme.Radius.card))
        .accessibilityElement(children: .combine)
    }
}

/// Presentation-only grid. Selection and source retention belong to Explore.
struct BlueprintCatalogGrid: View {
    let entries: [BlueprintCatalogEntry]
    let source: BlueprintCatalogSource
    let transitionNamespace: Namespace.ID
    let onSelect: (BlueprintCatalogEntry) -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.layoutDirection) private var layoutDirection

    var body: some View {
        ScrollView {
            MasonryLayout(
                columnCount: dynamicTypeSize.isAccessibilitySize ? 1 : 2,
                spacing: 12, layoutDirection: layoutDirection
            ) {
                ForEach(entries) { entry in
                    Button { onSelect(entry) } label: {
                        BlueprintCatalogTile(entry: entry)
                            .matchedTransitionSource(
                                id: BlueprintPreviewTransitionID(source: source, entryID: entry.id),
                                in: transitionNamespace
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(ExploreCopy.openHint)
                }
            }
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, AppTheme.Layout.screenHorizontal)
            .padding(.top, AppTheme.Layout.screenTop)
            .padding(.bottom, AppTheme.Layout.screenBottom)
        }
        .scrollIndicators(.hidden)
        .appSoftScrollEdges()
    }
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
    var catalogAspectRatio: CGFloat {
        switch self {
        case .weddings: 0.82
        case .birthdays: 1.06
        case .holidays: 0.92
        case .events: 0.88
        }
    }

    var artworkCategory: TimelineCategory {
        switch self {
        case .weddings: .ceremony
        case .birthdays: .bachelorBachelorette
        case .holidays: .weddingShower
        case .events: .venue
        }
    }
}
