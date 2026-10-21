import SwiftUI

nonisolated enum ManageDashboardLayoutPolicy {
    static func columnHeights(budget: CGFloat, guests: CGFloat, collaborators: CGFloat, spacing: CGFloat) -> (budget: CGFloat, total: CGFloat) {
        let total = max(budget + spacing + guests, collaborators)
        return (total - spacing - guests, total)
    }

    static func usesColumns(availableWidth: CGFloat, isAccessibilitySize: Bool) -> Bool {
        availableWidth.isFinite && availableWidth >= 360 && !isAccessibilitySize
    }
}

/// Stable dashboard placement: Budget/Guests in the leading column, Collaborators
/// spanning both on the trailing side. No measured-height state or fixed screen sizes.
struct ManageDashboardLayout: Layout {
    let isAccessibilitySize: Bool
    let layoutDirection: LayoutDirection
    private let spacing: CGFloat = 12

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let width = MasonryLayout.resolvedWidth(proposal.width, idealWidth: 360)
        let frames = frames(width: width, subviews: subviews)
        return CGSize(width: width, height: frames.map(\.maxY).max() ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        let width = LayoutDimensions.nonnegative(bounds.width)
        let frames = frames(width: width, subviews: subviews)
        for (index, subview) in subviews.enumerated() {
            let frame = frames[index]
            let x = layoutDirection == .rightToLeft ? width - frame.maxX : frame.minX
            subview.place(at: CGPoint(x: bounds.minX + x, y: bounds.minY + frame.minY), anchor: .topLeading,
                          proposal: ProposedViewSize(width: frame.width, height: frame.height))
        }
    }

    private func frames(width: CGFloat, subviews: Subviews) -> [CGRect] {
        let columns = (subviews.count == 3 || subviews.count == 4) && ManageDashboardLayoutPolicy.usesColumns(
            availableWidth: width, isAccessibilitySize: isAccessibilitySize
        )
        let itemWidth = columns ? max(0, width - spacing) / 2 : width
        let heights = subviews.map {
            LayoutDimensions.nonnegative($0.sizeThatFits(ProposedViewSize(width: itemWidth, height: nil)).height)
        }
        if columns && subviews.count == 4 {
            let leftHeight = heights[0] + spacing + heights[1]
            let quickApprovalHeight = max(heights[3], leftHeight - spacing - heights[2])
            return [
                CGRect(x: 0, y: 0, width: itemWidth, height: heights[0]),
                CGRect(x: 0, y: heights[0] + spacing, width: itemWidth, height: heights[1]),
                CGRect(x: itemWidth + spacing, y: 0, width: itemWidth, height: heights[2]),
                CGRect(x: itemWidth + spacing, y: heights[2] + spacing, width: itemWidth, height: quickApprovalHeight),
            ]
        }
        if columns {
            let sizing = ManageDashboardLayoutPolicy.columnHeights(
                budget: heights[0], guests: heights[1], collaborators: heights[2], spacing: spacing)
            return [
                CGRect(x: 0, y: 0, width: itemWidth, height: sizing.budget),
                CGRect(x: 0, y: sizing.budget + spacing, width: itemWidth, height: heights[1]),
                CGRect(x: itemWidth + spacing, y: 0, width: itemWidth, height: sizing.total),
            ]
        }
        var y: CGFloat = 0
        return heights.map { height in
            defer { y += height + spacing }
            return CGRect(x: 0, y: y, width: itemWidth, height: height)
        }
    }
}
