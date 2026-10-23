import SwiftUI
import UIKit

private func adaptiveBrandColor(
    light: UInt,
    dark: UInt,
    highContrastLight: UInt,
    highContrastDark: UInt
) -> Color {
    Color(
        uiColor: UIColor { traits in
            let isDark = traits.userInterfaceStyle == .dark
            let isHighContrast = traits.accessibilityContrast == .high
            let hex: UInt
            switch (isDark, isHighContrast) {
            case (true, true): hex = highContrastDark
            case (true, false): hex = dark
            case (false, true): hex = highContrastLight
            case (false, false): hex = light
            }
            return UIColor(
                red: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: 1
            )
        }
    )
}

private var adaptiveAccentForeground: Color {
    Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? .black : .white
    })
}

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
        accent: adaptiveBrandColor(light: 0x7540A3, dark: 0xC49AEB, highContrastLight: 0x63318D, highContrastDark: 0xD4B1F2),
        secondary: adaptiveBrandColor(light: 0x41489A, dark: 0xA1A7FF, highContrastLight: 0x30357D, highContrastDark: 0xB3B8FF),
        tertiary: adaptiveBrandColor(light: 0x9A315D, dark: 0xF08FB5, highContrastLight: 0x812348, highContrastDark: 0xF6A5C5)
    )

    static let sage = AppVisualTheme.branded(
        name: "Sage",
        accent: adaptiveBrandColor(light: 0x246B50, dark: 0x7ACAA5, highContrastLight: 0x18543C, highContrastDark: 0x8AD9B6),
        secondary: adaptiveBrandColor(light: 0x146B62, dark: 0x6FE0D1, highContrastLight: 0x0D514A, highContrastDark: 0x81EBDD),
        tertiary: adaptiveBrandColor(light: 0x59681E, dark: 0xB1C86A, highContrastLight: 0x414D12, highContrastDark: 0xC3D87B)
    )

    static let rose = AppVisualTheme.branded(
        name: "Rose",
        accent: adaptiveBrandColor(light: 0xA12C57, dark: 0xF284AA, highContrastLight: 0x852044, highContrastDark: 0xF99ABB),
        secondary: adaptiveBrandColor(light: 0x6B3B91, dark: 0xC0A0F0, highContrastLight: 0x542A77, highContrastDark: 0xD0B5FA),
        tertiary: adaptiveBrandColor(light: 0x9A4A25, dark: 0xE6A071, highContrastLight: 0x7C3517, highContrastDark: 0xF0B38B)
    )

    static let coral = AppVisualTheme.branded(
        name: "Coral",
        accent: adaptiveBrandColor(light: 0xA83827, dark: 0xF28B78, highContrastLight: 0x8C2C1D, highContrastDark: 0xF8A092),
        secondary: adaptiveBrandColor(light: 0x8B315D, dark: 0xED91B5, highContrastLight: 0x702148, highContrastDark: 0xF3A8C6),
        tertiary: adaptiveBrandColor(light: 0x755020, dark: 0xDAB276, highContrastLight: 0x5D3D15, highContrastDark: 0xE7C18E)
    )

    static let amber = AppVisualTheme.branded(
        name: "Amber",
        accent: adaptiveBrandColor(light: 0x895600, dark: 0xE8AE43, highContrastLight: 0x704500, highContrastDark: 0xF2C15E),
        secondary: adaptiveBrandColor(light: 0x754183, dark: 0xD19BE5, highContrastLight: 0x5F326C, highContrastDark: 0xDEB2EE),
        tertiary: adaptiveBrandColor(light: 0x00664F, dark: 0x63D3AB, highContrastLight: 0x00513E, highContrastDark: 0x7BE2BC)
    )

    static let ocean = AppVisualTheme.branded(
        name: "Ocean",
        accent: adaptiveBrandColor(light: 0x00617A, dark: 0x62CBE5, highContrastLight: 0x004D62, highContrastDark: 0x7DDBF1),
        secondary: adaptiveBrandColor(light: 0x35468C, dark: 0x97A7F4, highContrastLight: 0x29366F, highContrastDark: 0xAAB7FF),
        tertiary: adaptiveBrandColor(light: 0x006B60, dark: 0x60D2C6, highContrastLight: 0x00544B, highContrastDark: 0x79E1D7)
    )

    static let midnight = AppVisualTheme.branded(
        name: "Midnight",
        accent: adaptiveBrandColor(light: 0x3C478E, dark: 0x9AA8F5, highContrastLight: 0x2F3978, highContrastDark: 0xAFBAFF),
        secondary: adaptiveBrandColor(light: 0x6C3D88, dark: 0xCEA1E4, highContrastLight: 0x56316E, highContrastDark: 0xDDB8EF),
        tertiary: adaptiveBrandColor(light: 0x00666E, dark: 0x4AC7CE, highContrastLight: 0x005156, highContrastDark: 0x65D5DB)
    )

    /// Convenience for quickly auditioning a brand trio while retaining
    /// Gatherory's adaptive surfaces and distinct category artwork.
    static func branded(
        name: String,
        accent: Color,
        secondary: Color,
        tertiary: Color
    ) -> AppVisualTheme {
        let colors = AppColorTheme(
            accent: accent,
            accentSecondary: secondary,
            accentTertiary: tertiary
        )
        return AppVisualTheme(
            name: name,
            colors: colors,
            artwork: .gatheroryBlue.applyingBrandTint(colors)
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

    // Contrast roles for colorful artwork and prominent controls.
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
        foregroundOnAccent: Color = adaptiveAccentForeground,
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
        self.avatarPalette = avatarPalette ?? [accent, accentSecondary, accentTertiary]
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
        navy: Color(red: 31 / 255, green: 29 / 255, blue: 61 / 255)
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

private extension AppArtworkTheme {
    func applyingBrandTint(_ brand: AppColorTheme, amount: CGFloat = 0.30) -> AppArtworkTheme {
        let lightTraits = UITraitCollection(userInterfaceStyle: .light)
        let brandStops = [brand.accent, brand.accentSecondary, brand.accentTertiary].map {
            UIColor($0).resolvedColor(with: lightTraits)
        }

        func tint(_ colors: [Color]) -> [Color] {
            colors.enumerated().map { index, baseColor in
                var baseRed: CGFloat = 0
                var baseGreen: CGFloat = 0
                var baseBlue: CGFloat = 0
                var baseAlpha: CGFloat = 1
                var brandRed: CGFloat = 0
                var brandGreen: CGFloat = 0
                var brandBlue: CGFloat = 0
                var brandAlpha: CGFloat = 1
                let baseUIColor = UIColor(baseColor)
                let brandUIColor = brandStops[index % brandStops.count]

                guard
                    baseUIColor.getRed(&baseRed, green: &baseGreen, blue: &baseBlue, alpha: &baseAlpha),
                    brandUIColor.getRed(&brandRed, green: &brandGreen, blue: &brandBlue, alpha: &brandAlpha)
                else { return baseColor }

                return Color(
                    red: baseRed * (1 - amount) + brandRed * amount,
                    green: baseGreen * (1 - amount) + brandGreen * amount,
                    blue: baseBlue * (1 - amount) + brandBlue * amount,
                    opacity: baseAlpha * (1 - amount) + brandAlpha * amount
                )
            }
        }

        return AppArtworkTheme(
            ideas: ideas.mapValues(tint),
            registry: registry.mapValues(tint),
            timeline: timeline.mapValues(tint)
        )
    }
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
enum AppColorThemeChoice: String, CaseIterable, Identifiable, Sendable {
    static let storageKey = "appColorTheme"

    case gatheroryBlue
    case orchid
    case sage
    case rose
    case coral
    case amber
    case ocean
    case midnight

    var id: Self { self }

    var visualTheme: AppVisualTheme {
        switch self {
        case .gatheroryBlue: .gatheroryBlue
        case .orchid: .orchid
        case .sage: .sage
        case .rose: .rose
        case .coral: .coral
        case .amber: .amber
        case .ocean: .ocean
        case .midnight: .midnight
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

@available(iOS 17.0, *)
private struct AppColorThemeTrait: UITraitDefinition {
    static let defaultValue = AppColorThemeChoice.gatheroryBlue
    static let affectsColorAppearance = true
}

@available(iOS 17.0, *)
extension UITraitCollection {
    fileprivate var appColorThemeChoice: AppColorThemeChoice {
        self[AppColorThemeTrait.self]
    }
}

@available(iOS 17.0, *)
extension UIMutableTraits {
    fileprivate var appColorThemeChoice: AppColorThemeChoice {
        get { self[AppColorThemeTrait.self] }
        set { self[AppColorThemeTrait.self] = newValue }
    }
}

@available(iOS 17.0, *)
private struct AppColorThemeChoiceKey: UITraitBridgedEnvironmentKey {
    static let defaultValue = AppColorThemeChoice.gatheroryBlue

    static func read(from traitCollection: UITraitCollection) -> AppColorThemeChoice {
        traitCollection.appColorThemeChoice
    }

    static func write(to mutableTraits: inout any UIMutableTraits, value: AppColorThemeChoice) {
        mutableTraits.appColorThemeChoice = value
    }
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

    private static func dynamicColor(
        _ colorForTheme: @escaping (AppVisualTheme) -> Color
    ) -> Color {
        Color(uiColor: UIColor { traits in
            let choice = traits.appColorThemeChoice
            return UIColor(colorForTheme(choice.visualTheme)).resolvedColor(with: traits)
        })
    }

    enum ColorToken {
        static let background = token(\.background)
        static let surface = token(\.surface)
        static let elevatedSurface = token(\.elevatedSurface)
        static let textPrimary = token(\.textPrimary)
        static let textSecondary = token(\.textSecondary)
        static let ink = textPrimary
        static let onPastel = token(\.foregroundOnPastel)
        static let inverseCanvas = token(\.immersiveCanvas)
        static let inverseInk = token(\.foregroundOnMedia)
        static let hairline = token(\.hairline)
        static let cardBorder = token(\.cardBorder)

        static let accent = token(\.accent)
        static let accentSecondary = token(\.accentSecondary)
        static let accentTertiary = token(\.accentTertiary)
        static let celebration = token(\.celebration)
        static let success = token(\.success)
        static let warning = token(\.warning)
        static let destructive = token(\.destructive)
        static let informational = token(\.informational)
        static let mainEventMarker = token(\.mainEventMarker)
        static let onAccent = token(\.foregroundOnAccent)
        static let onMedia = token(\.foregroundOnMedia)
        static let mediaScrim = token(\.mediaScrim)

        static let lime = token(\.lime)
        static let lilac = token(\.lilac)
        static let cream = token(\.cream)
        static let pink = token(\.pink)
        static let mint = token(\.mint)
        static let coral = token(\.coral)
        static let navy = token(\.navy)

        private static func token(_ keyPath: KeyPath<AppColorTheme, Color>) -> Color {
            AppTheme.dynamicColor { $0.colors[keyPath: keyPath] }
        }

        static func avatar(_ index: Int) -> Color {
            AppTheme.dynamicColor { theme in
                guard !theme.colors.avatarPalette.isEmpty else { return theme.colors.accent }
                return theme.colors.avatarPalette[index % theme.colors.avatarPalette.count]
            }
        }
    }

    enum Artwork {
        static func colors(for category: IdeaCategory) -> [Color] {
            (0..<3).map { index in
                AppTheme.dynamicColor { theme in
                    guard let palette = theme.artwork.ideas[category], index < palette.count else {
                        return fallbackColor(index, in: theme)
                    }
                    return palette[index]
                }
            }
        }

        static func colors(for category: RegistryCategory) -> [Color] {
            (0..<3).map { index in
                AppTheme.dynamicColor { theme in
                    guard let palette = theme.artwork.registry[category], index < palette.count else {
                        return fallbackColor(index, in: theme)
                    }
                    return palette[index]
                }
            }
        }

        static func colors(for category: TimelineCategory) -> [Color] {
            (0..<3).map { index in
                AppTheme.dynamicColor { theme in
                    guard let palette = theme.artwork.timeline[category], index < palette.count else {
                        return fallbackColor(index, in: theme)
                    }
                    return palette[index]
                }
            }
        }

        private static func fallbackColor(_ index: Int, in theme: AppVisualTheme) -> Color {
            let fallback = [theme.colors.accentSecondary, theme.colors.accent, theme.colors.accentTertiary]
            return fallback[index % fallback.count]
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
        scrollEdgeEffectStyle(.soft, for: .all)
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
