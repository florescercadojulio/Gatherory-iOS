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
                MeshGradient(
                    width: 3,
                    height: 3,
                    points: [
                        SIMD2<Float>(0, 0), SIMD2<Float>(0.48, 0), SIMD2<Float>(1, 0),
                        SIMD2<Float>(0, 0.46), SIMD2<Float>(0.42, 0.38), SIMD2<Float>(1, 0.54),
                        SIMD2<Float>(0, 1), SIMD2<Float>(0.58, 1), SIMD2<Float>(1, 1)
                    ],
                    colors: [
                        palette(0), palette(1), palette(2),
                        palette(1), palette(2), palette(0),
                        palette(2), palette(0), palette(1)
                    ]
                )

                LinearGradient(
                    colors: [.white.opacity(0.22), .clear, .black.opacity(0.18)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                decorativeShapes(in: proxy.size)

                artworkBadge(in: proxy.size)
                    .offset(
                        x: proxy.size.width * horizontalBadgeOffset,
                        y: -proxy.size.height * 0.12
                    )

                Ellipse()
                    .fill(.white.opacity(reduceTransparency ? 0 : 0.14))
                    .frame(width: proxy.size.width * 0.72, height: proxy.size.height * 0.16)
                    .blur(radius: ambientBlurRadius * 0.34)
                    .rotationEffect(.degrees(-12 + Double(signature % 18)))
                    .offset(x: -proxy.size.width * 0.25, y: proxy.size.height * 0.42)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
        .accessibilityHidden(true)
    }

    private var signature: Int {
        symbol.unicodeScalars.reduce(17) { partial, scalar in
            (partial &* 31 &+ Int(scalar.value)) & 0x7fff
        }
    }

    private var horizontalBadgeOffset: CGFloat {
        switch signature % 3 {
        case 0: -0.08
        case 1: 0.06
        default: 0
        }
    }

    private func palette(_ index: Int) -> Color {
        guard !colors.isEmpty else { return accent }
        return colors[(index + signature) % colors.count]
    }

    @ViewBuilder
    private func artworkBadge(in size: CGSize) -> some View {
        let diameter = min(size.width * 0.48, size.height * 0.34, 190)

        ZStack {
            if reduceTransparency {
                Circle()
                    .fill(palette(0))
            } else {
                Circle()
                    .fill(.ultraThinMaterial)
            }

            Circle()
                .fill(
                    LinearGradient(
                        colors: [.white.opacity(0.22), .clear],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Image(systemName: symbol)
                .font(.system(size: diameter * 0.43, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.16), radius: 10, y: 6)
        }
        .frame(width: diameter, height: diameter)
        .overlay {
            Circle()
                .stroke(.white.opacity(0.30), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.20), radius: 24, y: 16)
    }

    @ViewBuilder
    private func decorativeShapes(in size: CGSize) -> some View {
        let turn = Double(signature % 22) - 11

        RoundedRectangle(cornerRadius: min(size.width, size.height) * 0.09, style: .continuous)
            .fill(.white.opacity(reduceTransparency ? 0.10 : 0.19))
            .frame(width: size.width * 0.70, height: size.height * 0.18)
            .rotationEffect(.degrees(-31 + turn))
            .offset(x: size.width * 0.34, y: -size.height * 0.28)

        Circle()
            .fill(accent.opacity(0.62))
            .frame(width: min(size.width, size.height) * 0.24)
            .blur(radius: reduceTransparency ? 0 : ambientBlurRadius * 0.22)
            .offset(x: -size.width * 0.38, y: size.height * 0.19)

        Circle()
            .stroke(.white.opacity(0.30), lineWidth: max(2, size.width * 0.012))
            .frame(width: min(size.width, size.height) * 0.18)
            .offset(x: size.width * 0.34, y: size.height * 0.25)

        Image(systemName: "sparkle")
            .font(.system(size: min(size.width, size.height) * 0.11, weight: .bold))
            .foregroundStyle(.white.opacity(0.74))
            .rotationEffect(.degrees(turn))
            .offset(x: -size.width * 0.33, y: -size.height * 0.31)

        Image(systemName: "circle.fill")
            .font(.system(size: min(size.width, size.height) * 0.055))
            .foregroundStyle(.white.opacity(0.70))
            .offset(x: size.width * 0.38, y: -size.height * 0.17)
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
        case .photography: [Color(red: 0.10, green: 0.24, blue: 0.36), Color(red: 0.31, green: 0.57, blue: 0.68), Color(red: 0.83, green: 0.72, blue: 0.52)]
        case .honeymoon: [Color(red: 0.08, green: 0.34, blue: 0.50), Color(red: 0.31, green: 0.69, blue: 0.72), Color(red: 0.96, green: 0.69, blue: 0.45)]
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

private struct DefaultIdeaArtworkPreview: View {
    private let columns = [
        GridItem(.adaptive(minimum: 150), spacing: AppTheme.Spacing.standard)
    ]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: AppTheme.Spacing.standard) {
                ForEach(IdeaCategory.allCases) { category in
                    ZStack(alignment: .bottomLeading) {
                        ProgressiveArtwork(
                            symbol: category.symbol,
                            colors: category.artworkColors,
                            accent: category.artworkAccent,
                            ambientBlurRadius: 14,
                            progressiveBlurRadius: 0
                        )

                        Text(category.title)
                            .font(.headline)
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.45), radius: 4, y: 2)
                            .padding(AppTheme.Spacing.standard)
                    }
                    .aspectRatio(0.86, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous))
                }
            }
            .padding(AppTheme.Spacing.standard)
        }
        .background(AppTheme.ColorToken.background)
    }
}

private struct DefaultEventArtworkPreview: View {
    private let columns = [
        GridItem(.adaptive(minimum: 150), spacing: AppTheme.Spacing.standard)
    ]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: AppTheme.Spacing.standard) {
                ForEach(TimelineCategory.allCases) { category in
                    ZStack(alignment: .bottomLeading) {
                        ProgressiveArtwork(
                            symbol: category.symbol,
                            colors: category.artworkColors,
                            accent: category.artworkAccent,
                            ambientBlurRadius: 14,
                            progressiveBlurRadius: 0
                        )

                        Text(category.title)
                            .font(.headline)
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.45), radius: 4, y: 2)
                            .padding(AppTheme.Spacing.standard)
                    }
                    .aspectRatio(0.86, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous))
                }
            }
            .padding(AppTheme.Spacing.standard)
        }
        .background(AppTheme.ColorToken.background)
    }
}

#Preview("Idea Default Artwork") {
    DefaultIdeaArtworkPreview()
}

#Preview("Event Default Artwork") {
    DefaultEventArtworkPreview()
}
