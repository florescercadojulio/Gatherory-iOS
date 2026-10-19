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
            let size = LayoutDimensions.size(proxy.size)
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
                    colors: [
                        AppTheme.ColorToken.onMedia.opacity(0.22),
                        .clear,
                        AppTheme.ColorToken.mediaScrim.opacity(0.18)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                decorativeShapes(in: size)

                artworkBadge(in: size)
                    .offset(
                        x: size.width * horizontalBadgeOffset,
                        y: -size.height * 0.12
                    )

                Ellipse()
                    .fill(AppTheme.ColorToken.onMedia.opacity(reduceTransparency ? 0 : 0.14))
                    .frame(width: size.width * 0.72, height: size.height * 0.16)
                    .blur(radius: ambientBlurRadius * 0.34)
                    .rotationEffect(.degrees(-12 + Double(signature % 18)))
                    .offset(x: -size.width * 0.25, y: size.height * 0.42)
            }
            .frame(width: size.width, height: size.height)
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
                        colors: [AppTheme.ColorToken.onMedia.opacity(0.22), .clear],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Image(systemName: symbol)
                .font(.system(size: diameter * 0.43, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(AppTheme.ColorToken.onMedia)
                .shadow(color: AppTheme.ColorToken.mediaScrim.opacity(0.16), radius: 10, y: 6)
        }
        .frame(width: diameter, height: diameter)
        .overlay {
            Circle()
                .stroke(AppTheme.ColorToken.onMedia.opacity(0.30), lineWidth: 1)
        }
        .shadow(color: AppTheme.ColorToken.mediaScrim.opacity(0.20), radius: 24, y: 16)
    }

    @ViewBuilder
    private func decorativeShapes(in size: CGSize) -> some View {
        let turn = Double(signature % 22) - 11

        RoundedRectangle(cornerRadius: min(size.width, size.height) * 0.09, style: .continuous)
            .fill(AppTheme.ColorToken.onMedia.opacity(reduceTransparency ? 0.10 : 0.19))
            .frame(width: size.width * 0.70, height: size.height * 0.18)
            .rotationEffect(.degrees(-31 + turn))
            .offset(x: size.width * 0.34, y: -size.height * 0.28)

        Circle()
            .fill(accent.opacity(0.62))
            .frame(width: min(size.width, size.height) * 0.24)
            .blur(radius: reduceTransparency ? 0 : ambientBlurRadius * 0.22)
            .offset(x: -size.width * 0.38, y: size.height * 0.19)

        Circle()
            .stroke(AppTheme.ColorToken.onMedia.opacity(0.30), lineWidth: max(2, size.width * 0.012))
            .frame(width: min(size.width, size.height) * 0.18)
            .offset(x: size.width * 0.34, y: size.height * 0.25)

        Image(systemName: "sparkle")
            .font(.system(size: min(size.width, size.height) * 0.11, weight: .bold))
            .foregroundStyle(AppTheme.ColorToken.onMedia.opacity(0.74))
            .rotationEffect(.degrees(turn))
            .offset(x: -size.width * 0.33, y: -size.height * 0.31)

        Image(systemName: "circle.fill")
            .font(.system(size: min(size.width, size.height) * 0.055))
            .foregroundStyle(AppTheme.ColorToken.onMedia.opacity(0.70))
            .offset(x: size.width * 0.38, y: -size.height * 0.17)
    }
}

extension IdeaCategory {
    var artworkColors: [Color] {
        AppTheme.Artwork.colors(for: self)
    }

    var artworkAccent: Color {
        artworkColors.last ?? tint
    }
}

extension RegistryCategory {
    var artworkColors: [Color] {
        AppTheme.Artwork.colors(for: self)
    }

    var artworkAccent: Color {
        artworkColors.last ?? tint
    }
}

extension TimelineCategory {
    var artworkColors: [Color] {
        AppTheme.Artwork.colors(for: self)
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
                            .foregroundStyle(AppTheme.ColorToken.onMedia)
                            .shadow(color: AppTheme.ColorToken.mediaScrim.opacity(0.45), radius: 4, y: 2)
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
                            .foregroundStyle(AppTheme.ColorToken.onMedia)
                            .shadow(color: AppTheme.ColorToken.mediaScrim.opacity(0.45), radius: 4, y: 2)
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
