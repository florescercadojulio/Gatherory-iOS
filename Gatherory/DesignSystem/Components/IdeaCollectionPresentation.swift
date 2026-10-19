import SwiftUI

/// Artwork-led collection card shared by live ideas and read-only previews.
/// Callers provide artwork and supporting content so this surface owns no
/// workspace, account, sync, or idea status behavior.
struct IdeaCollectionPresentation<Artwork: View, Supporting: View>: View {
    let title: String
    let category: IdeaCategory
    let aspectRatio: CGFloat
    @ViewBuilder var artwork: () -> Artwork
    @ViewBuilder var supporting: () -> Supporting

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            artwork()

            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.30),
                    .init(color: .black.opacity(0.14), location: 0.54),
                    .init(color: .black.opacity(0.74), location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Label(category.title, systemImage: category.symbol)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)

                Text(title)
                    .font(.headline)
                    .lineLimit(3)

                supporting()
                    .font(.caption)
            }
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.36), radius: 5, y: 2)
            .padding(AppTheme.Spacing.standard)
        }
        .aspectRatio(aspectRatio, contentMode: .fit)
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous)
                .stroke(.white.opacity(0.16), lineWidth: 0.5)
        }
    }
}

extension IdeaCategory {
    var collectionAspectRatio: CGFloat {
        switch self {
        case .event: 0.84
        case .registry: 0.92
        case .link: 1.06
        case .venue: 0.82
        case .attire: 0.74
        case .flowers: 1.12
        case .food: 0.94
        case .photography: 1.20
        case .music: 1.0
        case .decor: 0.78
        case .invitations: 1.14
        case .honeymoon: 0.76
        case .other: 1.06
        }
    }
}
