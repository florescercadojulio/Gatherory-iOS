import SwiftUI

/// Coordinates are local, physical x positions, independent of reading order.
nonisolated struct LayoutDivision: Equatable, Sendable {
    let lowerBound: CGFloat
    let upperBound: CGFloat

    func usableRange(in width: CGFloat) -> ClosedRange<CGFloat> {
        let left = min(max(lowerBound, 0), width)
        let right = min(max(upperBound, left), width)
        return left >= width - right ? 0...left : right...width
    }
}

nonisolated private struct AdaptiveContentGeometry: Equatable, Sendable {
    var width: CGFloat = 0
    var division: LayoutDivision?

    init() {}

    init(_ proxy: GeometryProxy, layoutDirection: LayoutDirection) {
        width = LayoutDimensions.nonnegative(proxy.size.width)
        if #available(iOS 27.1, *) {
            // Layout already handles RTL column order; do not mirror physical
            // reserved-region coordinates a second time.
            let region = proxy.reservedRegions(kind: .division, layoutDirectionBehavior: .fixed)
                .first { $0.isActive && $0.frame.height > $0.frame.width }
            if let region {
                let leftMargin = layoutDirection == .leftToRight ? region.margins.leading : region.margins.trailing
                let rightMargin = layoutDirection == .leftToRight ? region.margins.trailing : region.margins.leading
                let lower = max(0, region.frame.minX - leftMargin)
                let upper = min(width, region.frame.maxX + rightMargin)
                if lower < upper && lower < width && upper > 0 {
                    division = LayoutDivision(lowerBound: lower, upperBound: upper)
                }
            }
        }
    }
}

/// Maintains one collection and stable item identities throughout a resize.
struct AdaptiveMasonry<Content: View>: View {
    let columnCount: Int
    let spacing: CGFloat
    let layoutDirection: LayoutDirection
    var minimumColumnWidth: CGFloat = 170
    @ViewBuilder var content: () -> Content
    @State private var geometry = AdaptiveContentGeometry()

    var body: some View {
        MasonryLayout(
            columnCount: columnCount, spacing: spacing, layoutDirection: layoutDirection,
            minimumColumnWidth: minimumColumnWidth, division: geometry.division
        ) {
            content()
        }
        .onGeometryChange(for: AdaptiveContentGeometry.self) {
            AdaptiveContentGeometry($0, layoutDirection: layoutDirection)
        } action: {
            geometry = $0
        }
    }
}

/// A viewport-lazy grid that adapts its column widths around an active fold.
/// The same LazyVGrid remains in place while geometry changes, preserving item
/// identity and the native grid's viewport-based child creation.
struct AdaptiveLazyGrid<Content: View>: View {
    let columnCount: Int
    let spacing: CGFloat
    var minimumColumnWidth: CGFloat = 170
    @ViewBuilder var content: () -> Content
    @Environment(\.layoutDirection) private var layoutDirection
    @State private var geometry = AdaptiveContentGeometry()

    private var gridLayout: (columns: [GridItem], physicalLeftInset: CGFloat, physicalRightInset: CGFloat)? {
        guard geometry.width > 0 else { return nil }

        let count = MasonryLayout.adaptiveColumnCount(
            width: geometry.width,
            fallback: columnCount,
            minimumColumnWidth: minimumColumnWidth,
            spacing: spacing
        )
        let slots = MasonryLayout.columnSlots(
            width: geometry.width,
            count: count,
            spacing: spacing,
            division: geometry.division
        )
        guard let firstOrigin = slots.origins.first, let lastOrigin = slots.origins.last else { return nil }

        let physicalGaps = zip(slots.origins, slots.origins.dropFirst()).map { pair in
            let (origin, nextOrigin) = pair
            return max(0, nextOrigin - origin - slots.width)
        }
        let logicalGaps = layoutDirection == .leftToRight ? physicalGaps : Array(physicalGaps.reversed())
        let columns = slots.origins.indices.map { index in
            GridItem(
                .fixed(slots.width),
                spacing: index < logicalGaps.count ? logicalGaps[index] : nil,
                alignment: .leading
            )
        }
        let physicalRightInset = max(geometry.width - lastOrigin - slots.width, 0)

        return (columns, max(firstOrigin, 0), physicalRightInset)
    }

    var body: some View {
        let safeSpacing = LayoutDimensions.nonnegative(spacing)
        let layout = gridLayout
        let columns = layout?.columns ?? Array(
            repeating: GridItem(.flexible(), spacing: safeSpacing),
            count: max(columnCount, 1)
        )
        let leadingInset = layout.map {
            layoutDirection == .leftToRight ? $0.physicalLeftInset : $0.physicalRightInset
        } ?? 0
        let trailingInset = layout.map {
            layoutDirection == .leftToRight ? $0.physicalRightInset : $0.physicalLeftInset
        } ?? 0

        LazyVGrid(columns: columns, alignment: .leading, spacing: safeSpacing) {
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, leadingInset)
        .padding(.trailing, trailingInset)
        .onGeometryChange(for: AdaptiveContentGeometry.self) {
            AdaptiveContentGeometry($0, layoutDirection: layoutDirection)
        } action: {
            geometry = $0
        }
    }
}

private struct AdaptiveMasonryPlacement<Item: Identifiable>: Identifiable where Item.ID: Hashable {
    let item: Item
    let sourceIndex: Int

    var id: Item.ID { item.id }
}

/// A viewport-lazy masonry collection. Items are assigned to columns in source
/// order using stable height estimates; each column remains a LazyVStack so
/// offscreen cards and their image/ad lifecycle work stay unmounted.
struct AdaptiveLazyMasonry<Item: Identifiable, Content: View>: View where Item.ID: Hashable {
    let items: [Item]
    let columnCount: Int
    let spacing: CGFloat
    var minimumColumnWidth: CGFloat = 170
    let estimatedHeight: (Item, CGFloat) -> CGFloat
    @ViewBuilder let content: (Item, Int) -> Content
    @Environment(\.layoutDirection) private var layoutDirection
    @State private var geometry = AdaptiveContentGeometry()

    private var layout: (
        width: CGFloat,
        itemWidth: CGFloat,
        origins: [CGFloat],
        columns: [[AdaptiveMasonryPlacement<Item>]]
    )? {
        let width = geometry.width
        guard width > 0 else { return nil }
        let requested = MasonryLayout.adaptiveColumnCount(
            width: width,
            fallback: columnCount,
            minimumColumnWidth: minimumColumnWidth,
            spacing: spacing
        )
        let slots = MasonryLayout.columnSlots(
            width: width,
            count: requested,
            spacing: spacing,
            division: geometry.division
        )
        let count = max(slots.origins.count, 1)
        var heights = Array(repeating: CGFloat.zero, count: count)
        var columns = Array(repeating: [AdaptiveMasonryPlacement<Item>](), count: count)

        for (index, item) in items.enumerated() {
            let column = heights.enumerated().min { $0.element < $1.element }?.offset ?? 0
            columns[column].append(AdaptiveMasonryPlacement(item: item, sourceIndex: index))
            let estimate = estimatedHeight(item, slots.width)
            heights[column] += LayoutDimensions.nonnegative(estimate) + LayoutDimensions.nonnegative(spacing)
        }

        return (width, slots.width, slots.origins, columns)
    }

    var body: some View {
        Group {
            if let layout {
                ZStack(alignment: .topLeading) {
                    ForEach(Array(layout.columns.enumerated()), id: \.offset) { column in
                        let logicalColumn = column.offset
                        let placements = column.element
                        let visualColumn = layoutDirection == .leftToRight
                            ? logicalColumn
                            : layout.columns.count - 1 - logicalColumn
                        LazyVStack(alignment: .leading, spacing: LayoutDimensions.nonnegative(spacing)) {
                            ForEach(placements) { placement in
                                content(placement.item, placement.sourceIndex)
                                    .frame(width: layout.itemWidth, alignment: .leading)
                                    .environment(\.layoutDirection, layoutDirection)
                            }
                        }
                        .frame(width: layout.itemWidth, alignment: .topLeading)
                        .offset(x: layout.origins[visualColumn])
                    }
                }
                .environment(\.layoutDirection, .leftToRight)
                .frame(width: layout.width, alignment: .topLeading)
            } else {
                AdaptiveLazyGrid(
                    columnCount: columnCount,
                    spacing: spacing,
                    minimumColumnWidth: minimumColumnWidth
                ) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { placement in
                        content(placement.element, placement.offset)
                    }
                }
            }
        }
        // ScrollView/VStack children can otherwise report the width of their
        // smallest ideal cell. Establish the parent-proposed collection width
        // before reading geometry so column slots use the viewport width.
        .frame(maxWidth: .infinity, alignment: .leading)
        .onGeometryChange(for: AdaptiveContentGeometry.self) {
            AdaptiveContentGeometry($0, layoutDirection: layoutDirection)
        } action: {
            geometry = $0
        }
    }
}

private struct AdaptiveReadingFrame: ViewModifier {
    let maximumWidth: CGFloat
    @Environment(\.layoutDirection) private var layoutDirection
    @State private var geometry = AdaptiveContentGeometry()

    func body(content: Content) -> some View {
        let range = geometry.division?.usableRange(in: geometry.width)
        let leftInset = range?.lowerBound ?? 0
        let rightInset = range.map { geometry.width - $0.upperBound } ?? 0
        content
            .frame(maxWidth: min(maximumWidth, range.map { $0.upperBound - $0.lowerBound } ?? maximumWidth))
            .frame(maxWidth: .infinity)
            .padding(.leading, layoutDirection == .leftToRight ? leftInset : rightInset)
            .padding(.trailing, layoutDirection == .leftToRight ? rightInset : leftInset)
            .onGeometryChange(for: AdaptiveContentGeometry.self) {
                AdaptiveContentGeometry($0, layoutDirection: layoutDirection)
            } action: {
                geometry = $0
            }
    }
}

extension View {
    /// Keep text and single-card tasks comfortably sized and clear of an active
    /// book fold without replacing their view or resetting navigation state.
    func adaptiveReadingWidth(_ maximumWidth: CGFloat) -> some View {
        modifier(AdaptiveReadingFrame(maximumWidth: maximumWidth))
    }
}

/// The artwork and its reading controls overlay when flat, and occupy usable
/// panes when folded. Navigation stays outside this content-only container.
/// Full-screen readers extend artwork into safe areas; bounded deck cards
/// retain clipping so their artwork cannot escape the card's geometry.
struct AdaptiveArtworkPresentation<Content: View, Artwork: View>: View {
    var artworkExtendsIntoSafeAreas = false
    @ViewBuilder var content: () -> Content
    @ViewBuilder var artwork: () -> Artwork

    var body: some View {
        if #available(iOS 27.1, *) {
            ArrangementView {
                content()
            } secondary: {
                if artworkExtendsIntoSafeAreas {
                    artwork()
                } else {
                    artwork().clipped()
                }
            }
            .arrangementViewStyle(.overlay)
        } else {
            ZStack {
                artwork()
                content()
            }
        }
    }
}
