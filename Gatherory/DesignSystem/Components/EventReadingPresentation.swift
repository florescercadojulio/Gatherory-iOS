import SwiftUI

/// The shared title and context layout used by live event invitations and
/// authored blueprint event previews.
struct EventReadingHero<EyebrowStatus: View, TimingLocation: View, Response: View>: View {
    let title: String
    let height: CGFloat
    let topSpacer: CGFloat
    @ViewBuilder let eyebrowStatus: () -> EyebrowStatus
    @ViewBuilder let timingLocation: () -> TimingLocation
    @ViewBuilder let response: () -> Response

    init(
        title: String,
        height: CGFloat,
        topSpacer: CGFloat,
        @ViewBuilder eyebrowStatus: @escaping () -> EyebrowStatus,
        @ViewBuilder timingLocation: @escaping () -> TimingLocation,
        @ViewBuilder response: @escaping () -> Response
    ) {
        self.title = title
        self.height = height
        self.topSpacer = topSpacer
        self.eyebrowStatus = eyebrowStatus
        self.timingLocation = timingLocation
        self.response = response
    }

    var body: some View {
        VStack(spacing: AppTheme.Spacing.standard) {
            Spacer(minLength: topSpacer)

            VStack(spacing: AppTheme.Spacing.standard) {
                eyebrowStatus()

                Text(title)
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                timingLocation()
                    .multilineTextAlignment(.center)
            }
            .accessibilityElement(children: .combine)

            response()
        }
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(0.34), radius: 10, y: 4)
        .padding(AppTheme.Spacing.spacious)
        .frame(maxWidth: .infinity)
        .frame(height: LayoutDimensions.nonnegative(height))
    }
}
