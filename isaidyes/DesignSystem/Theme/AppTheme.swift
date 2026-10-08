import SwiftUI

enum AppTheme {
    enum ColorToken {
        static let background = Color(uiColor: .systemGroupedBackground)
        static let surface = Color(uiColor: .secondarySystemGroupedBackground)
        static let elevatedSurface = Color(uiColor: .tertiarySystemGroupedBackground)
        static let textPrimary = Color.primary
        static let textSecondary = Color.secondary
        static let accent = Color.accentColor
        static let celebration = Color.pink
    }

    enum Spacing {
        static let compact: CGFloat = 8
        static let standard: CGFloat = 16
        static let spacious: CGFloat = 24
        static let section: CGFloat = 32
    }

    enum Radius {
        static let control: CGFloat = 12
        static let card: CGFloat = 20
        static let hero: CGFloat = 28
    }
}

extension View {
    func appCard(padding: CGFloat = AppTheme.Spacing.standard) -> some View {
        self
            .padding(padding)
            .background(AppTheme.ColorToken.surface, in: RoundedRectangle(cornerRadius: AppTheme.Radius.card))
    }
}

extension IdeaCategory {
    var tint: Color {
        switch self {
        case .venue: .indigo
        case .attire: .purple
        case .flowers: .pink
        case .food: .orange
        case .photography: .blue
        case .music: .mint
        case .decor: .teal
        case .invitations: .brown
        case .honeymoon: .cyan
        case .other: .gray
        }
    }
}

extension IdeaStatus {
    var tint: Color {
        switch self {
        case .new: .blue
        case .maybe: .orange
        case .shortlisted: .pink
        case .chosen: .green
        case .passed: .secondary
        }
    }
}
