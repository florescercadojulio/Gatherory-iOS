import SwiftUI

/// The Home event card's presentation. Live and template callers supply only
/// the content they actually have; this view owns no workspace or actions.
struct WorkspaceEventHero<Artwork: View, People: View, Metadata: View, Badge: View>: View {
    let title: String
    @ViewBuilder var artwork: () -> Artwork
    @ViewBuilder var people: () -> People
    @ViewBuilder var metadata: () -> Metadata
    @ViewBuilder var badge: () -> Badge
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        ZStack(alignment: .bottom) {
            artwork()
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.34),
                    .init(color: .black.opacity(reduceTransparency ? 0.24 : 0.08), location: 0.52),
                    .init(color: .black.opacity(reduceTransparency ? 0.76 : 0.46), location: 0.76),
                    .init(color: .black.opacity(reduceTransparency ? 0.90 : 0.70), location: 1)
                ], startPoint: .top, endPoint: .bottom
            )
            VStack(spacing: AppTheme.Spacing.standard) {
                Spacer(minLength: dynamicTypeSize.isAccessibilitySize ? 120 : 220)
                people()
                VStack(spacing: 8) {
                    Text(title)
                        .font(.system(.largeTitle, design: .rounded, weight: .bold))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    metadata()
                }
                .padding(.horizontal, AppTheme.Spacing.compact)
                .shadow(color: .black.opacity(0.28), radius: 10, y: 4)
            }
            .foregroundStyle(.white)
            .padding(AppTheme.Spacing.spacious)
            VStack {
                HStack {
                    badge()
                    Spacer(minLength: 0)
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(.white)
            .padding(AppTheme.Spacing.spacious)
        }
    }
}
