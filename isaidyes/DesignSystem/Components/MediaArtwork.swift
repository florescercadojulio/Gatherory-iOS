import Glur
import SwiftUI

struct MediaArtwork: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    let imageData: Data?
    let symbol: String
    let colors: [Color]
    let accent: Color
    var ambientBlurRadius: CGFloat = 36
    var progressiveBlurRadius: CGFloat = 22
    var blurStart: CGFloat = 0.38

    var body: some View {
        if let imageData, let image = UIImage(data: imageData) {
            photo(image)
        } else {
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

    @ViewBuilder
    private func photo(_ image: UIImage) -> some View {
        let artwork = Image(uiImage: image)
            .resizable()
            .scaledToFill()

        if reduceTransparency || progressiveBlurRadius == 0 {
            artwork
        } else {
            artwork.glur(
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
}
