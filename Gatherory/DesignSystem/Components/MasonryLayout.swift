import SwiftUI

/// Concrete SwiftUI frames require finite, nonnegative sizes. Layout probes and
/// interrupted transitions may temporarily provide unusable geometry.
nonisolated enum LayoutDimensions {
    static func nonnegative(_ value: CGFloat) -> CGFloat {
        value.isFinite ? max(value, 0) : 0
    }

    static func size(_ value: CGSize) -> CGSize {
        CGSize(width: nonnegative(value.width), height: nonnegative(value.height))
    }

    static func heroHeight(availableHeight: CGFloat, isAccessibilitySize: Bool) -> CGFloat {
        let preferred: CGFloat = isAccessibilitySize ? 720 : 640
        guard availableHeight.isFinite, availableHeight > 0 else { return preferred }
        return min(preferred, max(isAccessibilitySize ? 640 : 420, availableHeight - 24))
    }
}

/// A compact Pinterest-style layout that fills the shortest available column.
/// Callers can collapse it to one column for larger accessibility text sizes.
struct MasonryLayout: Layout {
    let columnCount: Int
    let spacing: CGFloat
    let layoutDirection: LayoutDirection
    var minimumColumnWidth: CGFloat? = nil
    var division: LayoutDivision? = nil

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Void
    ) -> CGSize {
        // Layout probes may propose infinity. Never return that as a concrete
        // size or pass it to a child's frame; use the ideal column width.
        let width: CGFloat
        if let proposed = proposal.width, proposed.isFinite {
            width = Self.finiteDimension(proposed)
        } else {
            let idealColumnWidth = subviews.map { Self.finiteDimension($0.sizeThatFits(.unspecified).width) }.max() ?? 0
            let idealWidth = idealColumnWidth * CGFloat(max(columnCount, 1)) + CGFloat(max(columnCount - 1, 0)) * spacing
            width = Self.resolvedWidth(proposal.width, idealWidth: idealWidth)
        }
        let measurements = measurements(for: subviews, width: width)
        return CGSize(width: width, height: measurements.height)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Void
    ) {
        let measurements = measurements(for: subviews, width: bounds.width)

        for (index, subview) in subviews.enumerated() {
            let placement = measurements.placements[index]
            let visualColumn = layoutDirection == .leftToRight
                ? placement.column
                : measurements.columns - 1 - placement.column
            let x = bounds.minX + measurements.origins[visualColumn]
            let point = CGPoint(x: x, y: bounds.minY + placement.y)

            subview.place(
                at: point,
                anchor: .topLeading,
                proposal: ProposedViewSize(width: measurements.columnWidth, height: nil)
            )
        }
    }

    private func measurements(for subviews: Subviews, width: CGFloat) -> Measurements {
        let requested = Self.adaptiveColumnCount(width: width, fallback: columnCount,
                                                minimumColumnWidth: minimumColumnWidth, spacing: spacing)
        let slots = Self.columnSlots(width: width, count: requested, spacing: spacing, division: division)
        let columns = slots.origins.count
        let columnWidth = slots.width
        var columnHeights = Array(repeating: CGFloat.zero, count: columns)
        var placements: [Placement] = []

        for subview in subviews {
            let column = columnHeights.enumerated().min { lhs, rhs in
                lhs.element < rhs.element
            }?.offset ?? 0
            let size = subview.sizeThatFits(
                ProposedViewSize(width: columnWidth, height: nil)
            )

            placements.append(Placement(column: column, y: columnHeights[column]))
            columnHeights[column] += Self.finiteDimension(size.height) + spacing
        }

        let height = max((columnHeights.max() ?? 0) - (subviews.isEmpty ? 0 : spacing), 0)
        return Measurements(
            columns: columns,
            columnWidth: columnWidth,
            origins: slots.origins,
            height: height,
            placements: placements
        )
    }

    nonisolated static func finiteDimension(_ value: CGFloat) -> CGFloat {
        LayoutDimensions.nonnegative(value)
    }

    /// Keep paired columns on wider displays so the fold falls between cards.
    /// Explicit one-column accessibility layouts never gain extra columns.
    nonisolated static func adaptiveColumnCount(width: CGFloat, fallback: Int,
                                                minimumColumnWidth: CGFloat?, spacing: CGFloat) -> Int {
        guard fallback > 1, let minimumColumnWidth,
              width.isFinite, width > 0, minimumColumnWidth.isFinite, minimumColumnWidth > 0 else {
            return max(fallback, 1)
        }
        let gap = LayoutDimensions.nonnegative(spacing)
        guard width >= min(minimumColumnWidth, 140) * 2 + gap else { return 1 }
        let capacity = Int(min(6, max(2, (width + gap) / (minimumColumnWidth + gap))))
        return capacity - capacity % 2
    }

    nonisolated static func resolvedWidth(_ proposed: CGFloat?, idealWidth: CGFloat) -> CGFloat {
        guard let proposed, proposed.isFinite else { return finiteDimension(idealWidth) }
        return finiteDimension(proposed)
    }

    nonisolated static func columnSlots(width: CGFloat, count: Int, spacing: CGFloat,
                                       division: LayoutDivision?) -> (width: CGFloat, origins: [CGFloat]) {
        let width = finiteDimension(width)
        let gap = finiteDimension(spacing)
        guard let division else {
            let columns = max(count, 1)
            let itemWidth = max(0, width - CGFloat(columns - 1) * gap) / CGFloat(columns)
            return (itemWidth, (0..<columns).map { CGFloat($0) * (itemWidth + gap) })
        }
        let left = min(max(division.lowerBound, 0), width)
        let right = min(max(division.upperBound, left), width)
        let sideCapacity = Int(min(3, max(0, (min(left, width - right) + gap) / (140 + gap))))
        guard count > 1, sideCapacity > 0 else {
            let range = division.usableRange(in: width)
            return (range.upperBound - range.lowerBound, [range.lowerBound])
        }
        let perSide = min(max(count / 2, 1), sideCapacity)
        let itemWidth = max(0, min(left, width - right) - CGFloat(perSide - 1) * gap) / CGFloat(perSide)
        let groupWidth = itemWidth * CGFloat(perSide) + CGFloat(perSide - 1) * gap
        let starts = [(left - groupWidth) / 2, right + (width - right - groupWidth) / 2]
        return (itemWidth, starts.flatMap { start in (0..<perSide).map { start + CGFloat($0) * (itemWidth + gap) } })
    }

    private struct Measurements {
        let columns: Int
        let columnWidth: CGFloat
        let origins: [CGFloat]
        let height: CGFloat
        let placements: [Placement]
    }

    private struct Placement {
        let column: Int
        let y: CGFloat
    }
}
