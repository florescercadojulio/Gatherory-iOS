import SwiftUI

/// The shared title and context layout used by live event invitations and
/// authored blueprint event previews.
struct EventReadingHero<EyebrowStatus: View, TimingLocation: View, Response: View>: View {
    let title: String
    let height: CGFloat
    let topSpacer: CGFloat
    var bottomPadding: CGFloat
    var titleAction: AnyView?
    @ViewBuilder let eyebrowStatus: () -> EyebrowStatus
    @ViewBuilder let timingLocation: () -> TimingLocation
    @ViewBuilder let response: () -> Response

    init(
        title: String,
        height: CGFloat,
        topSpacer: CGFloat,
        bottomPadding: CGFloat = AppTheme.Spacing.spacious,
        titleAction: AnyView? = nil,
        @ViewBuilder eyebrowStatus: @escaping () -> EyebrowStatus,
        @ViewBuilder timingLocation: @escaping () -> TimingLocation,
        @ViewBuilder response: @escaping () -> Response
    ) {
        self.title = title
        self.height = height
        self.topSpacer = topSpacer
        self.bottomPadding = bottomPadding
        self.titleAction = titleAction
        self.eyebrowStatus = eyebrowStatus
        self.timingLocation = timingLocation
        self.response = response
    }

    var body: some View {
        VStack(spacing: AppTheme.Spacing.standard) {
            Spacer(minLength: min(topSpacer, height * 0.25))

            VStack(spacing: AppTheme.Spacing.standard) {
                eyebrowStatus()

                if let titleAction {
                    titleAction
                } else {
                    Text(title)
                        .font(.system(.largeTitle, design: .rounded, weight: .bold))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                timingLocation()
                    .multilineTextAlignment(.center)
            }
            .shadow(color: .black.opacity(0.34), radius: 10, y: 4)
            .accessibilityElement(children: titleAction.map { _ in AccessibilityChildBehavior.contain } ?? .combine)

            response()
        }
        .foregroundStyle(.white)
        .padding(.horizontal, AppTheme.Spacing.spacious)
        .padding(.top, AppTheme.Spacing.spacious)
        .padding(.bottom, bottomPadding)
        .adaptiveReadingWidth(680)
        .frame(minHeight: LayoutDimensions.nonnegative(height), alignment: .bottom)
    }
}
