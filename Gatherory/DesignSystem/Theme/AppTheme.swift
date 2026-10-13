import SwiftUI
import UIKit

/// A complete, swappable visual theme. Views consume semantic tokens and
/// never need to know the palette's hues.
struct AppVisualTheme {
    let name: String
    let colors: AppColorTheme
    let artwork: AppArtworkTheme

    static let gatheroryBlue = AppVisualTheme(
        name: "Gatherory Blue",
        colors: .gatheroryBlue,
        artwork: .gatheroryBlue
    )

    static let orchid = AppVisualTheme.branded(
        name: "Orchid",
        accent: Color(uiColor: .systemPurple),
        secondary: Color(uiColor: .systemIndigo),
        tertiary: Color(uiColor: .systemPink)
    )

    static let sage = AppVisualTheme.branded(
        name: "Sage",
        accent: Color(red: 0.18, green: 0.53, blue: 0.43),
        secondary: Color(red: 0.17, green: 0.42, blue: 0.40),
        tertiary: Color(red: 0.53, green: 0.61, blue: 0.32)
    )

    /// Convenience for quickly auditioning a new brand trio while retaining
    /// Gatherory's adaptive surfaces, feedback colors, and event artwork.
    static func branded(
        name: String,
        accent: Color,
        secondary: Color,
        tertiary: Color
    ) -> AppVisualTheme {
        AppVisualTheme(
            name: name,
            colors: AppColorTheme(
                accent: accent,
                accentSecondary: secondary,
                accentTertiary: tertiary
            ),
            artwork: .gatheroryBlue
        )
    }
}

struct AppColorTheme {
    // Adaptive content surfaces and labels.
    let background: Color
    let surface: Color
    let elevatedSurface: Color
    let textPrimary: Color
    let textSecondary: Color
    let hairline: Color
    let cardBorder: Color

    // Brand and interaction.
    let accent: Color
    let accentSecondary: Color
    let accentTertiary: Color
    let celebration: Color

    // Feedback. Meaning stays stable even when the brand palette changes.
    let success: Color
    let warning: Color
    let destructive: Color
    let informational: Color
    let mainEventMarker: Color

    // Fixed contrast roles for colorful artwork and prominent controls.
    let foregroundOnAccent: Color
    let foregroundOnMedia: Color
    let foregroundOnPastel: Color
    let immersiveCanvas: Color
    let mediaScrim: Color

    // Decorative swatches used by category and onboarding content.
    let lime: Color
    let lilac: Color
    let cream: Color
    let pink: Color
    let mint: Color
    let coral: Color
    let navy: Color
    let avatarPalette: [Color]

    init(
        background: Color = Color(uiColor: .systemBackground),
        surface: Color = Color(uiColor: .secondarySystemBackground),
        elevatedSurface: Color = Color(uiColor: .tertiarySystemBackground),
        textPrimary: Color = .primary,
        textSecondary: Color = .secondary,
        hairline: Color = Color(uiColor: .separator),
        cardBorder: Color = Color(uiColor: .opaqueSeparator).opacity(0.34),
        accent: Color,
        accentSecondary: Color,
        accentTertiary: Color,
        celebration: Color? = nil,
        success: Color = Color(uiColor: .systemGreen),
        warning: Color = Color(uiColor: .systemOrange),
        destructive: Color = Color(uiColor: .systemRed),
        informational: Color? = nil,
        mainEventMarker: Color = Color(uiColor: .systemOrange),
        foregroundOnAccent: Color = .white,
        foregroundOnMedia: Color = .white,
        foregroundOnPastel: Color = .black,
        immersiveCanvas: Color = .black,
        mediaScrim: Color = .black,
        lime: Color = Color(red: 220 / 255, green: 238 / 255, blue: 177 / 255),
        lilac: Color = Color(red: 197 / 255, green: 176 / 255, blue: 244 / 255),
        cream: Color = Color(red: 244 / 255, green: 236 / 255, blue: 214 / 255),
        pink: Color = Color(red: 239 / 255, green: 212 / 255, blue: 212 / 255),
        mint: Color = Color(red: 200 / 255, green: 230 / 255, blue: 205 / 255),
        coral: Color = Color(red: 243 / 255, green: 201 / 255, blue: 182 / 255),
        navy: Color = Color(red: 31 / 255, green: 29 / 255, blue: 61 / 255),
        avatarPalette: [Color]? = nil
    ) {
        self.background = background
        self.surface = surface
        self.elevatedSurface = elevatedSurface
        self.textPrimary = textPrimary
        self.textSecondary = textSecondary
        self.hairline = hairline
        self.cardBorder = cardBorder
        self.accent = accent
        self.accentSecondary = accentSecondary
        self.accentTertiary = accentTertiary
        self.celebration = celebration ?? accent
        self.success = success
        self.warning = warning
        self.destructive = destructive
        self.informational = informational ?? accent
        self.mainEventMarker = mainEventMarker
        self.foregroundOnAccent = foregroundOnAccent
        self.foregroundOnMedia = foregroundOnMedia
        self.foregroundOnPastel = foregroundOnPastel
        self.immersiveCanvas = immersiveCanvas
        self.mediaScrim = mediaScrim
        self.lime = lime
        self.lilac = lilac
        self.cream = cream
        self.pink = pink
        self.mint = mint
        self.coral = coral
        self.navy = navy
        self.avatarPalette = avatarPalette ?? [
            accent,
            accentSecondary,
            accentTertiary,
            Color(uiColor: .systemPurple),
            Color(uiColor: .systemCyan),
            Color(uiColor: .systemOrange)
        ]
    }

    static let gatheroryBlue = AppColorTheme(
        background: Color(uiColor: .systemBackground),
        surface: Color(uiColor: .secondarySystemBackground),
        elevatedSurface: Color(uiColor: .tertiarySystemBackground),
        textPrimary: .primary,
        textSecondary: .secondary,
        hairline: Color(uiColor: .separator),
        cardBorder: Color(uiColor: .opaqueSeparator).opacity(0.34),
        accent: Color(uiColor: .systemBlue),
        accentSecondary: Color(uiColor: .systemIndigo),
        accentTertiary: Color(uiColor: .systemTeal),
        celebration: Color(uiColor: .systemBlue),
        success: Color(uiColor: .systemGreen),
        warning: Color(uiColor: .systemOrange),
        destructive: Color(uiColor: .systemRed),
        informational: Color(uiColor: .systemBlue),
        mainEventMarker: Color(uiColor: .systemOrange),
        foregroundOnAccent: .white,
        foregroundOnMedia: .white,
        foregroundOnPastel: .black,
        immersiveCanvas: .black,
        mediaScrim: .black,
        lime: Color(red: 220 / 255, green: 238 / 255, blue: 177 / 255),
        lilac: Color(red: 197 / 255, green: 176 / 255, blue: 244 / 255),
        cream: Color(red: 244 / 255, green: 236 / 255, blue: 214 / 255),
        pink: Color(red: 239 / 255, green: 212 / 255, blue: 212 / 255),
        mint: Color(red: 200 / 255, green: 230 / 255, blue: 205 / 255),
        coral: Color(red: 243 / 255, green: 201 / 255, blue: 182 / 255),
        navy: Color(red: 31 / 255, green: 29 / 255, blue: 61 / 255),
        avatarPalette: [
            Color(uiColor: .systemBlue),
            Color(uiColor: .systemIndigo),
            Color(uiColor: .systemTeal),
            Color(uiColor: .systemPurple),
            Color(uiColor: .systemCyan),
            Color(uiColor: .systemOrange)
        ]
    )
}

struct AppArtworkTheme {
    let ideas: [IdeaCategory: [Color]]
    let registry: [RegistryCategory: [Color]]
    let timeline: [TimelineCategory: [Color]]

    static let gatheroryBlue = AppArtworkTheme(
        ideas: [
            .event: [Color(red: 0.10, green: 0.31, blue: 0.49), Color(red: 0.24, green: 0.57, blue: 0.78), Color(red: 0.95, green: 0.70, blue: 0.43)],
            .registry: [Color(red: 0.24, green: 0.18, blue: 0.43), Color(red: 0.60, green: 0.39, blue: 0.72), Color(red: 0.93, green: 0.60, blue: 0.66)],
            .link: [Color(red: 0.07, green: 0.28, blue: 0.46), Color(red: 0.12, green: 0.53, blue: 0.70), Color(red: 0.46, green: 0.82, blue: 0.77)],
            .venue: [Color(red: 0.34, green: 0.23, blue: 0.62), Color(red: 0.78, green: 0.59, blue: 0.86), Color(red: 0.96, green: 0.72, blue: 0.62)],
            .attire: [Color(red: 0.32, green: 0.19, blue: 0.31), Color(red: 0.78, green: 0.45, blue: 0.58), Color(red: 0.96, green: 0.78, blue: 0.72)],
            .flowers: [Color(red: 0.16, green: 0.36, blue: 0.30), Color(red: 0.78, green: 0.40, blue: 0.42), Color(red: 0.98, green: 0.72, blue: 0.55)],
            .food: [Color(red: 0.42, green: 0.20, blue: 0.12), Color(red: 0.82, green: 0.48, blue: 0.24), Color(red: 0.98, green: 0.79, blue: 0.49)],
            .photography: [Color(red: 0.10, green: 0.22, blue: 0.29), Color(red: 0.19, green: 0.55, blue: 0.57), Color(red: 0.76, green: 0.78, blue: 0.62)],
            .music: [Color(red: 0.14, green: 0.15, blue: 0.32), Color(red: 0.45, green: 0.28, blue: 0.68), Color(red: 0.93, green: 0.43, blue: 0.55)],
            .decor: [Color(red: 0.24, green: 0.16, blue: 0.43), Color(red: 0.56, green: 0.38, blue: 0.78), Color(red: 0.96, green: 0.65, blue: 0.56)],
            .invitations: [Color(red: 0.22, green: 0.35, blue: 0.43), Color(red: 0.48, green: 0.67, blue: 0.64), Color(red: 0.94, green: 0.76, blue: 0.60)],
            .honeymoon: [Color(red: 0.08, green: 0.40, blue: 0.57), Color(red: 0.32, green: 0.70, blue: 0.75), Color(red: 0.98, green: 0.68, blue: 0.38)],
            .other: [Color(red: 0.25, green: 0.20, blue: 0.49), Color(red: 0.70, green: 0.40, blue: 0.72), Color(red: 0.97, green: 0.61, blue: 0.54)]
        ],
        registry: [
            .home: [Color(red: 0.20, green: 0.24, blue: 0.40), Color(red: 0.46, green: 0.45, blue: 0.68), Color(red: 0.88, green: 0.67, blue: 0.60)],
            .kitchen: [Color(red: 0.16, green: 0.24, blue: 0.22), Color(red: 0.42, green: 0.60, blue: 0.43), Color(red: 0.91, green: 0.72, blue: 0.40)],
            .travel: [Color(red: 0.08, green: 0.35, blue: 0.56), Color(red: 0.32, green: 0.67, blue: 0.74), Color(red: 0.98, green: 0.65, blue: 0.40)],
            .experience: [Color(red: 0.28, green: 0.16, blue: 0.42), Color(red: 0.65, green: 0.37, blue: 0.65), Color(red: 0.94, green: 0.57, blue: 0.48)],
            .cashFund: [Color(red: 0.13, green: 0.28, blue: 0.38), Color(red: 0.25, green: 0.60, blue: 0.58), Color(red: 0.85, green: 0.73, blue: 0.43)]
        ],
        timeline: [
            .venue: [Color(red: 0.16, green: 0.31, blue: 0.42), Color(red: 0.40, green: 0.68, blue: 0.73), Color(red: 0.95, green: 0.67, blue: 0.43)],
            .foodTasting: [Color(red: 0.30, green: 0.18, blue: 0.12), Color(red: 0.72, green: 0.43, blue: 0.26), Color(red: 0.94, green: 0.75, blue: 0.48)],
            .photography: [Color(red: 0.10, green: 0.24, blue: 0.36), Color(red: 0.31, green: 0.57, blue: 0.68), Color(red: 0.83, green: 0.72, blue: 0.52)],
            .honeymoon: [Color(red: 0.08, green: 0.34, blue: 0.50), Color(red: 0.31, green: 0.69, blue: 0.72), Color(red: 0.96, green: 0.69, blue: 0.45)],
            .attireFitting: [Color(red: 0.22, green: 0.20, blue: 0.34), Color(red: 0.61, green: 0.50, blue: 0.72), Color(red: 0.90, green: 0.76, blue: 0.71)],
            .weddingShower: [Color(red: 0.24, green: 0.33, blue: 0.28), Color(red: 0.55, green: 0.72, blue: 0.58), Color(red: 0.94, green: 0.72, blue: 0.67)],
            .bachelorBachelorette: [Color(red: 0.17, green: 0.18, blue: 0.38), Color(red: 0.50, green: 0.35, blue: 0.69), Color(red: 0.94, green: 0.48, blue: 0.60)],
            .rehearsal: [Color(red: 0.17, green: 0.27, blue: 0.28), Color(red: 0.39, green: 0.62, blue: 0.57), Color(red: 0.86, green: 0.70, blue: 0.49)],
            .ceremony: [Color(red: 0.30, green: 0.18, blue: 0.29), Color(red: 0.68, green: 0.40, blue: 0.55), Color(red: 0.94, green: 0.69, blue: 0.68)],
            .reception: [Color(red: 0.13, green: 0.18, blue: 0.35), Color(red: 0.33, green: 0.45, blue: 0.70), Color(red: 0.84, green: 0.58, blue: 0.73)],
            .other: [Color(red: 0.20, green: 0.25, blue: 0.31), Color(red: 0.47, green: 0.55, blue: 0.61), Color(red: 0.81, green: 0.69, blue: 0.55)]
        ]
    )
}

enum AppAppearance: String, CaseIterable, Identifiable {
    static let storageKey = "appAppearance"

    case system
    case light
    case dark

    var id: Self { self }

    var title: String {
        switch self {
        case .system: AppCopy.Appearance.system
        case .light: AppCopy.Appearance.light
        case .dark: AppCopy.Appearance.dark
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    func resolvedColorScheme(systemColorScheme: ColorScheme) -> ColorScheme {
        colorScheme ?? systemColorScheme
    }
}

/// The person's app-wide color preference. This belongs to their account
/// settings rather than to any individual workspace.
enum AppColorThemeChoice: String, CaseIterable, Identifiable {
    static let storageKey = "appColorTheme"

    case gatheroryBlue
    case orchid
    case sage

    var id: Self { self }

    var visualTheme: AppVisualTheme {
        switch self {
        case .gatheroryBlue: .gatheroryBlue
        case .orchid: .orchid
        case .sage: .sage
        }
    }

    var title: String { visualTheme.name }

    var previewColors: [Color] {
        let colors = visualTheme.colors
        return [colors.accent, colors.accentSecondary, colors.accentTertiary]
    }

    static var selected: AppColorThemeChoice {
        guard
            let storedValue = UserDefaults.standard.string(forKey: storageKey),
            let selection = AppColorThemeChoice(rawValue: storedValue)
        else {
            return .gatheroryBlue
        }

        return selection
    }
}

private struct AppColorThemeChoiceKey: EnvironmentKey {
    static let defaultValue = AppColorThemeChoice.gatheroryBlue
}

private struct AppContentColorSchemeKey: EnvironmentKey {
    static let defaultValue = ColorScheme.light
}

extension EnvironmentValues {
    var appColorThemeChoice: AppColorThemeChoice {
        get { self[AppColorThemeChoiceKey.self] }
        set { self[AppColorThemeChoiceKey.self] = newValue }
    }

    /// The saved app appearance before individual photo-led views introduce
    /// local readability overrides such as a dark image overlay.
    var appContentColorScheme: ColorScheme {
        get { self[AppContentColorSchemeKey.self] }
        set { self[AppContentColorSchemeKey.self] = newValue }
    }
}

enum AppTheme {
    static var active: AppVisualTheme {
        AppColorThemeChoice.selected.visualTheme
    }

    enum ColorToken {
        private static var theme: AppColorTheme { AppTheme.active.colors }

        static var background: Color { theme.background }
        static var surface: Color { theme.surface }
        static var elevatedSurface: Color { theme.elevatedSurface }
        static var textPrimary: Color { theme.textPrimary }
        static var textSecondary: Color { theme.textSecondary }
        static var ink: Color { theme.textPrimary }
        static var onPastel: Color { theme.foregroundOnPastel }
        static var inverseCanvas: Color { theme.immersiveCanvas }
        static var inverseInk: Color { theme.foregroundOnMedia }
        static var hairline: Color { theme.hairline }
        static var cardBorder: Color { theme.cardBorder }

        static var accent: Color { theme.accent }
        static var accentSecondary: Color { theme.accentSecondary }
        static var accentTertiary: Color { theme.accentTertiary }
        static var celebration: Color { theme.celebration }
        static var success: Color { theme.success }
        static var warning: Color { theme.warning }
        static var destructive: Color { theme.destructive }
        static var informational: Color { theme.informational }
        static var mainEventMarker: Color { theme.mainEventMarker }
        static var onAccent: Color { theme.foregroundOnAccent }
        static var onMedia: Color { theme.foregroundOnMedia }
        static var mediaScrim: Color { theme.mediaScrim }

        static var lime: Color { theme.lime }
        static var lilac: Color { theme.lilac }
        static var cream: Color { theme.cream }
        static var pink: Color { theme.pink }
        static var mint: Color { theme.mint }
        static var coral: Color { theme.coral }
        static var navy: Color { theme.navy }

        static func avatar(_ index: Int) -> Color {
            guard !theme.avatarPalette.isEmpty else { return accent }
            return theme.avatarPalette[index % theme.avatarPalette.count]
        }
    }

    enum Artwork {
        static func colors(for category: IdeaCategory) -> [Color] {
            active.artwork.ideas[category] ?? fallback
        }

        static func colors(for category: RegistryCategory) -> [Color] {
            active.artwork.registry[category] ?? fallback
        }

        static func colors(for category: TimelineCategory) -> [Color] {
            active.artwork.timeline[category] ?? fallback
        }

        private static var fallback: [Color] {
            [ColorToken.accentSecondary, ColorToken.accent, ColorToken.accentTertiary]
        }
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
    /// Gives form-style editors a consistent way to dismiss keyboards that do
    /// not provide a Return key, including number and decimal pads.
    func appKeyboardDismissal() -> some View {
        scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()

                    Button("Done") {
                        UIApplication.shared.sendAction(
                            #selector(UIResponder.resignFirstResponder),
                            to: nil,
                            from: nil,
                            for: nil
                        )
                    }
                }
            }
    }

    /// Applies the person's app-wide appearance choice. Keep this at the app
    /// presentation root so feature views inherit one consistent preference.
    func appUserAppearance(_ appearance: AppAppearance) -> some View {
        preferredColorScheme(appearance.colorScheme)
    }

    /// Publishes the selected palette through the view tree so changing the
    /// account preference refreshes existing screens and presented sheets.
    func appColorTheme(_ selection: AppColorThemeChoice) -> some View {
        environment(\.appColorThemeChoice, selection)
            .tint(selection.visualTheme.colors.accent)
    }

    /// Gives controls placed directly over photography a stable dark-material
    /// rendering without publishing an appearance preference to parent views.
    func appImageOverlayAppearance() -> some View {
        environment(\.colorScheme, .dark)
    }

    /// Uses light navigation content over an image-led detail screen while
    /// leaving the rest of the app free to follow its selected appearance.
    func appImageNavigationBarAppearance() -> some View {
        toolbarColorScheme(.dark, for: .navigationBar)
    }

    /// Standard appearance for a complete image-led detail experience.
    func appImageDetailAppearance() -> some View {
        appImageOverlayAppearance()
            .appImageNavigationBarAppearance()
    }

    /// Keeps content legible beneath floating navigation controls without
    /// introducing a hard, opaque boundary as the user scrolls.
    func appSoftScrollEdges() -> some View {
        scrollEdgeEffectStyle(.soft, for: .top)
    }

    /// Keeps the navigation bar visually connected to the content beneath it.
    func appClearNavigationBar() -> some View {
        toolbarBackgroundVisibility(.hidden, for: .navigationBar)
    }

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
                        .stroke(AppTheme.ColorToken.cardBorder, lineWidth: 0.5)
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
        case .event: AppTheme.ColorToken.mint
        case .registry: AppTheme.ColorToken.lilac
        case .link: AppTheme.ColorToken.mint
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
        case .new: AppTheme.ColorToken.accent
        case .maybe: AppTheme.ColorToken.warning
        case .shortlisted: AppTheme.ColorToken.accent
        case .chosen: AppTheme.ColorToken.success
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
