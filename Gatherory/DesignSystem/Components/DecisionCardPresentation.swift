import SwiftUI

/// Shared vertical composition for live Decide cards and read-only previews.
/// Each surface supplies its own artwork, guidance, feedback, and summary.
struct DecisionCardPresentation<Artwork: View, Guide: View, Feedback: View, Summary: View>: View {
    @ViewBuilder var artwork: () -> Artwork
    @ViewBuilder var guide: () -> Guide
    @ViewBuilder var feedback: () -> Feedback
    @ViewBuilder var summary: () -> Summary

    var body: some View {
        // The deck supplies the bounds; artwork and long summaries must not
        // grow the resting card underneath navigation or the tab bar.
        GeometryReader { geometry in
            AdaptiveArtworkPresentation {
                VStack(spacing: 0) {
                    guide()

                    Spacer(minLength: AppTheme.Spacing.section)

                    feedback()

                    Spacer(minLength: AppTheme.Spacing.standard)

                    summary()
                }
                .padding(AppTheme.Spacing.standard)
                .frame(width: geometry.size.width, height: geometry.size.height)
            } artwork: {
                artwork()
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .background(AppTheme.ColorToken.background)
    }
}
