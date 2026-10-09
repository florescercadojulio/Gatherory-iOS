import SwiftUI
import Glur

struct ProgressiveArtwork: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    let symbol: String
    let colors: [Color]
    let accent: Color
    var ambientBlurRadius: CGFloat = 36
    var progressiveBlurRadius: CGFloat = 22
    var blurStart: CGFloat = 0.38

    var body: some View {
        if reduceTransparency || progressiveBlurRadius == 0 {
            artwork
        } else {
            artwork
                .glur(
                    radius: progressiveBlurRadius,
                    mask: .linear(
                        stops: [
                            .init(intensity: 0, location: 0),
                            .init(intensity: 0, location: blurStart),
                            .init(intensity: 0.22, location: min(blurStart + 0.16, 1)),
                            .init(intensity: 0.72, location: min(blurStart + 0.34, 1)),
                            .init(intensity: 1, location: min(blurStart + 0.50, 1))
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    noise: 0.035
                )
        }
    }

    private var artwork: some View {
        GeometryReader { proxy in
            ZStack {
                LinearGradient(
                    colors: colors,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                Circle()
                    .fill(.white.opacity(0.26))
                    .frame(width: proxy.size.width * 0.92)
                    .blur(radius: ambientBlurRadius)
                    .offset(x: -proxy.size.width * 0.34, y: -proxy.size.height * 0.34)

                Circle()
                    .fill(accent.opacity(0.72))
                    .frame(width: proxy.size.width * 1.08)
                    .blur(radius: ambientBlurRadius * 1.17)
                    .offset(x: proxy.size.width * 0.42, y: proxy.size.height * 0.18)

                Image(systemName: symbol)
                    .font(.system(size: min(proxy.size.width * 0.34, 136), weight: .ultraLight))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.white.opacity(0.82))
                    .shadow(color: .black.opacity(0.14), radius: 24, y: 12)
                    .offset(y: -proxy.size.height * 0.16)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .accessibilityHidden(true)
    }
}

extension IdeaCategory {
    var artworkColors: [Color] {
        switch self {
        case .event: [Color(red: 0.10, green: 0.31, blue: 0.49), Color(red: 0.24, green: 0.57, blue: 0.78), Color(red: 0.95, green: 0.70, blue: 0.43)]
        case .registry: [Color(red: 0.24, green: 0.18, blue: 0.43), Color(red: 0.60, green: 0.39, blue: 0.72), Color(red: 0.93, green: 0.60, blue: 0.66)]
        case .venue: [Color(red: 0.34, green: 0.23, blue: 0.62), Color(red: 0.78, green: 0.59, blue: 0.86), Color(red: 0.96, green: 0.72, blue: 0.62)]
        case .attire: [Color(red: 0.32, green: 0.19, blue: 0.31), Color(red: 0.78, green: 0.45, blue: 0.58), Color(red: 0.96, green: 0.78, blue: 0.72)]
        case .flowers: [Color(red: 0.16, green: 0.36, blue: 0.30), Color(red: 0.78, green: 0.40, blue: 0.42), Color(red: 0.98, green: 0.72, blue: 0.55)]
        case .food: [Color(red: 0.42, green: 0.20, blue: 0.12), Color(red: 0.82, green: 0.48, blue: 0.24), Color(red: 0.98, green: 0.79, blue: 0.49)]
        case .photography: [Color(red: 0.10, green: 0.22, blue: 0.29), Color(red: 0.19, green: 0.55, blue: 0.57), Color(red: 0.76, green: 0.78, blue: 0.62)]
        case .music: [Color(red: 0.14, green: 0.15, blue: 0.32), Color(red: 0.45, green: 0.28, blue: 0.68), Color(red: 0.93, green: 0.43, blue: 0.55)]
        case .decor: [Color(red: 0.24, green: 0.16, blue: 0.43), Color(red: 0.56, green: 0.38, blue: 0.78), Color(red: 0.96, green: 0.65, blue: 0.56)]
        case .invitations: [Color(red: 0.22, green: 0.35, blue: 0.43), Color(red: 0.48, green: 0.67, blue: 0.64), Color(red: 0.94, green: 0.76, blue: 0.60)]
        case .honeymoon: [Color(red: 0.08, green: 0.40, blue: 0.57), Color(red: 0.32, green: 0.70, blue: 0.75), Color(red: 0.98, green: 0.68, blue: 0.38)]
        case .other: [Color(red: 0.25, green: 0.20, blue: 0.49), Color(red: 0.70, green: 0.40, blue: 0.72), Color(red: 0.97, green: 0.61, blue: 0.54)]
        }
    }

    var artworkAccent: Color {
        artworkColors.last ?? tint
    }
}

extension RegistryCategory {
    var artworkColors: [Color] {
        switch self {
        case .home: [Color(red: 0.20, green: 0.24, blue: 0.40), Color(red: 0.46, green: 0.45, blue: 0.68), Color(red: 0.88, green: 0.67, blue: 0.60)]
        case .kitchen: [Color(red: 0.16, green: 0.24, blue: 0.22), Color(red: 0.42, green: 0.60, blue: 0.43), Color(red: 0.91, green: 0.72, blue: 0.40)]
        case .travel: [Color(red: 0.08, green: 0.35, blue: 0.56), Color(red: 0.32, green: 0.67, blue: 0.74), Color(red: 0.98, green: 0.65, blue: 0.40)]
        case .experience: [Color(red: 0.28, green: 0.16, blue: 0.42), Color(red: 0.65, green: 0.37, blue: 0.65), Color(red: 0.94, green: 0.57, blue: 0.48)]
        case .cashFund: [Color(red: 0.13, green: 0.28, blue: 0.38), Color(red: 0.25, green: 0.60, blue: 0.58), Color(red: 0.85, green: 0.73, blue: 0.43)]
        }
    }

    var artworkAccent: Color {
        artworkColors.last ?? tint
    }
}

extension TimelineCategory {
    var artworkColors: [Color] {
        switch self {
        case .venue: [Color(red: 0.16, green: 0.31, blue: 0.42), Color(red: 0.40, green: 0.68, blue: 0.73), Color(red: 0.95, green: 0.67, blue: 0.43)]
        case .foodTasting: [Color(red: 0.30, green: 0.18, blue: 0.12), Color(red: 0.72, green: 0.43, blue: 0.26), Color(red: 0.94, green: 0.75, blue: 0.48)]
        case .attireFitting: [Color(red: 0.22, green: 0.20, blue: 0.34), Color(red: 0.61, green: 0.50, blue: 0.72), Color(red: 0.90, green: 0.76, blue: 0.71)]
        case .weddingShower: [Color(red: 0.24, green: 0.33, blue: 0.28), Color(red: 0.55, green: 0.72, blue: 0.58), Color(red: 0.94, green: 0.72, blue: 0.67)]
        case .bachelorBachelorette: [Color(red: 0.17, green: 0.18, blue: 0.38), Color(red: 0.50, green: 0.35, blue: 0.69), Color(red: 0.94, green: 0.48, blue: 0.60)]
        case .rehearsal: [Color(red: 0.17, green: 0.27, blue: 0.28), Color(red: 0.39, green: 0.62, blue: 0.57), Color(red: 0.86, green: 0.70, blue: 0.49)]
        case .ceremony: [Color(red: 0.30, green: 0.18, blue: 0.29), Color(red: 0.68, green: 0.40, blue: 0.55), Color(red: 0.94, green: 0.69, blue: 0.68)]
        case .reception: [Color(red: 0.13, green: 0.18, blue: 0.35), Color(red: 0.33, green: 0.45, blue: 0.70), Color(red: 0.84, green: 0.58, blue: 0.73)]
        case .other: [Color(red: 0.20, green: 0.25, blue: 0.31), Color(red: 0.47, green: 0.55, blue: 0.61), Color(red: 0.81, green: 0.69, blue: 0.55)]
        }
    }

    var artworkAccent: Color {
        artworkColors.last ?? AppTheme.ColorToken.accent
    }
}
