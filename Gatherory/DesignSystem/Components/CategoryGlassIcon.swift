import SwiftUI

/// Category artwork used in compact category controls.
///
/// Icon Composer artwork used in compact category controls.
struct CategoryGlassIcon: View {
    let category: IdeaCategory
    var size: CGFloat

    var body: some View {
        Image(category.glassIconAssetName)
            .resizable()
            .interpolation(.high)
            .scaledToFit()
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .stroke(.white.opacity(0.18), lineWidth: 0.75)
        }
        .accessibilityHidden(true)
    }
}

extension IdeaCategory {
    var glassIconAssetName: String {
        "IdeaCategoryGlass\(rawValue.prefix(1).uppercased())\(rawValue.dropFirst())"
    }
}
