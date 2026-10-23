import SwiftUI

#if DEBUG
#Preview("Explore ad · Light") {
    ExploreNativeAdPreviewFixture()
        .padding()
        .preferredColorScheme(.light)
}

#Preview("Explore ad · Dark") {
    ExploreNativeAdPreviewFixture()
        .padding()
        .preferredColorScheme(.dark)
}

#Preview("Explore ad · Large text") {
    ExploreNativeAdPreviewFixture()
        .padding()
        .environment(\.dynamicTypeSize, .accessibility3)
}

#Preview("Explore ad · Narrow 180pt") {
    ExploreNativeAdPreviewFixture()
        .frame(width: 180)
        .padding()
}
#endif
