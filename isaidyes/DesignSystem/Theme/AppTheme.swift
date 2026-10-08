import SwiftUI

enum AppAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: Self { self }

    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

enum AppTheme {
    enum ColorToken {
        static let background = Color(uiColor: .systemBackground)
        static let surface = Color(uiColor: .secondarySystemBackground)
        static let elevatedSurface = Color(uiColor: .tertiarySystemBackground)
        static let textPrimary = Color.primary
        static let textSecondary = Color.secondary
        static let ink = Color.primary
        static let onPastel = Color.black
        static let inverseCanvas = Color.black
        static let inverseInk = Color.white
        static let hairline = Color(uiColor: .separator)

        static let lime = Color(red: 220 / 255, green: 238 / 255, blue: 177 / 255)
        static let lilac = Color(red: 197 / 255, green: 176 / 255, blue: 244 / 255)
        static let cream = Color(red: 244 / 255, green: 236 / 255, blue: 214 / 255)
        static let pink = Color(red: 239 / 255, green: 212 / 255, blue: 212 / 255)
        static let mint = Color(red: 200 / 255, green: 230 / 255, blue: 205 / 255)
        static let coral = Color(red: 243 / 255, green: 201 / 255, blue: 182 / 255)
        static let navy = Color(red: 31 / 255, green: 29 / 255, blue: 61 / 255)
        static let accent = Color(red: 255 / 255, green: 61 / 255, blue: 139 / 255)
        static let celebration = accent
    }

    enum Spacing {
        static let compact: CGFloat = 8
        static let standard: CGFloat = 16
        static let spacious: CGFloat = 24
        static let section: CGFloat = 32
    }

    enum Layout {
        static let screenHorizontal: CGFloat = Spacing.standard
        static let screenTop: CGFloat = Spacing.compact
        static let screenBottom: CGFloat = Spacing.section
        static let listRowVertical: CGFloat = 6
        static let featuredRowVertical: CGFloat = Spacing.compact
        static let minimumTouchTarget: CGFloat = 44

        static let listRowInsets = EdgeInsets(
            top: listRowVertical,
            leading: screenHorizontal,
            bottom: listRowVertical,
            trailing: screenHorizontal
        )

        static let featuredRowInsets = EdgeInsets(
            top: featuredRowVertical,
            leading: screenHorizontal,
            bottom: featuredRowVertical,
            trailing: screenHorizontal
        )
    }

    enum Radius {
        static let control: CGFloat = 12
        static let card: CGFloat = 24
        static let hero: CGFloat = 32
    }

    enum Typography {
        static let display = Font.system(.largeTitle, design: .default, weight: .semibold)
        static let sectionTitle = Font.system(.title2, design: .default, weight: .bold)
        static let cardTitle = Font.system(.title3, design: .default, weight: .bold)
        static let eyebrow = Font.system(.caption2, design: .monospaced, weight: .semibold)
    }
}

extension View {
    func appCard(
        background: Color = AppTheme.ColorToken.surface,
        foreground: Color = AppTheme.ColorToken.textPrimary,
        padding: CGFloat = AppTheme.Spacing.standard,
        border: Bool = true
    ) -> some View {
        self
            .padding(padding)
            .foregroundStyle(foreground)
            .background(background, in: RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous))
            .overlay {
                if border {
                    RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous)
                        .stroke(AppTheme.ColorToken.hairline, lineWidth: 0.5)
                }
            }
    }

    func editorialEyebrow() -> some View {
        self
            .font(AppTheme.Typography.eyebrow)
            .textCase(.uppercase)
            .tracking(0.8)
    }
}

extension IdeaCategory {
    var tint: Color {
        switch self {
        case .venue: AppTheme.ColorToken.lilac
        case .attire: AppTheme.ColorToken.pink
        case .flowers: AppTheme.ColorToken.coral
        case .food: AppTheme.ColorToken.cream
        case .photography: AppTheme.ColorToken.mint
        case .music: AppTheme.ColorToken.lime
        case .decor: AppTheme.ColorToken.lilac
        case .invitations: AppTheme.ColorToken.cream
        case .honeymoon: AppTheme.ColorToken.mint
        case .other: AppTheme.ColorToken.pink
        }
    }
}

extension IdeaStatus {
    var tint: Color {
        switch self {
        case .new: AppTheme.ColorToken.navy
        case .maybe: .orange
        case .shortlisted: AppTheme.ColorToken.accent
        case .chosen: .green
        case .passed: .secondary
        case .archived: .secondary
        }
    }
}

extension RegistryCategory {
    var tint: Color {
        switch self {
        case .home: AppTheme.ColorToken.lilac
        case .kitchen: AppTheme.ColorToken.lime
        case .travel: AppTheme.ColorToken.mint
        case .experience: AppTheme.ColorToken.coral
        case .cashFund: AppTheme.ColorToken.pink
        }
    }
}
