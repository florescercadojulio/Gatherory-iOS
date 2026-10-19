import SwiftUI

/// Shared vertical composition for live Decide cards and read-only previews.
/// Each surface supplies its own artwork, guidance, feedback, and summary.
struct DecisionCardPresentation<Artwork: View, Guide: View, Feedback: View, Summary: View>: View {
    @ViewBuilder var artwork: () -> Artwork
    @ViewBuilder var guide: () -> Guide
    @ViewBuilder var feedback: () -> Feedback
    @ViewBuilder var summary: () -> Summary

    var body: some View {
        ZStack {
            artwork()

            VStack(spacing: 0) {
                guide()

                Spacer(minLength: AppTheme.Spacing.section)

                feedback()

                Spacer(minLength: AppTheme.Spacing.standard)

                summary()
            }
            .padding(AppTheme.Spacing.standard)
        }
    }
}
