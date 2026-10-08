import Glur
import SwiftUI

struct MediaArtwork: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    let imageData: Data?
    var assetName: String? = nil
    var remoteURL: URL? = nil
    let symbol: String
    let colors: [Color]
    let accent: Color
    var ambientBlurRadius: CGFloat = 36
    var progressiveBlurRadius: CGFloat = 22
    var blurStart: CGFloat = 0.38

    var body: some View {
        if let imageData, let image = UIImage(data: imageData) {
            photo(Image(uiImage: image))
        } else if let assetName {
            photo(Image(assetName))
        } else if let remoteURL {
            AsyncImage(url: remoteURL) { phase in
                switch phase {
                case .success(let image):
                    photo(image)
                default:
                    fallbackArtwork
                }
            }
        } else {
            fallbackArtwork
        }
    }

    @ViewBuilder
    private func photo(_ image: Image) -> some View {
        GeometryReader { proxy in
            let artwork = image
                .resizable()
                .scaledToFill()
                .frame(width: proxy.size.width, height: proxy.size.height)

            if reduceTransparency || progressiveBlurRadius == 0 {
                artwork
                    .clipped()
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
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()
            }
        }
    }

    private var fallbackArtwork: some View {
        ProgressiveArtwork(
            symbol: symbol,
            colors: colors,
            accent: accent,
            ambientBlurRadius: ambientBlurRadius,
            progressiveBlurRadius: progressiveBlurRadius,
            blurStart: blurStart
        )
    }
}
