import SwiftUI

/// A compact Pinterest-style layout that fills the shortest available column.
/// Callers can collapse it to one column for larger accessibility text sizes.
struct MasonryLayout: Layout {
    let columnCount: Int
    let spacing: CGFloat
    let layoutDirection: LayoutDirection

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Void
    ) -> CGSize {
        let width = proposal.width ?? 0
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
            let x = bounds.minX + CGFloat(visualColumn) * (measurements.columnWidth + spacing)
            let point = CGPoint(x: x, y: bounds.minY + placement.y)

            subview.place(
                at: point,
                anchor: .topLeading,
                proposal: ProposedViewSize(width: measurements.columnWidth, height: nil)
            )
        }
    }

    private func measurements(for subviews: Subviews, width: CGFloat) -> Measurements {
        let columns = max(columnCount, 1)
        let availableWidth = max(width - (CGFloat(columns - 1) * spacing), 0)
        let columnWidth = availableWidth / CGFloat(columns)
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
            columnHeights[column] += size.height + spacing
        }

        let height = max((columnHeights.max() ?? 0) - (subviews.isEmpty ? 0 : spacing), 0)
        return Measurements(
            columns: columns,
            columnWidth: columnWidth,
            height: height,
            placements: placements
        )
    }

    private struct Measurements {
        let columns: Int
        let columnWidth: CGFloat
        let height: CGFloat
        let placements: [Placement]
    }

    private struct Placement {
        let column: Int
        let y: CGFloat
    }
}
