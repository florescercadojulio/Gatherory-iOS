import SwiftUI

/// Shared by the Decide card and its detail tiles; inherits the user's appearance.
private struct IdeaContentSurface: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        content
            .foregroundStyle(.primary)
            .background(
                reduceTransparency
                    ? AnyShapeStyle(Color(uiColor: .secondarySystemGroupedBackground))
                    : AnyShapeStyle(.regularMaterial),
                in: RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous)
                    .stroke(Color(uiColor: .separator), lineWidth: 0.5)
                    .allowsHitTesting(false)
            }
    }
}

extension View {
    func ideaContentSurface() -> some View {
        modifier(IdeaContentSurface())
    }
}
