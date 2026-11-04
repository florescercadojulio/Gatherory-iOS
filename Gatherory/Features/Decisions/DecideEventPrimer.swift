import SwiftUI

struct DecideEventPrimer: View {
    let continueAction: () -> Void

    var body: some View {
        FeaturePrimerView(
            title: AppCopy.Primer.Decide.title,
            continueIdentifier: "decide-primer-continue",
            continueAction: continueAction
        ) {
            FeaturePrimerRow(symbol: "arrow.left", title: AppCopy.Primer.Decide.pass,
                             detail: AppCopy.Primer.Decide.passDetail)
                .accessibilityIdentifier("decide.primer.feature.pass")
            FeaturePrimerRow(symbol: "arrow.up", title: AppCopy.Primer.Decide.maybe,
                             detail: AppCopy.Primer.Decide.maybeDetail)
                .accessibilityIdentifier("decide.primer.feature.maybe")
            FeaturePrimerRow(symbol: "arrow.right", title: AppCopy.Primer.Decide.love,
                             detail: AppCopy.Primer.Decide.loveDetail)
                .accessibilityIdentifier("decide.primer.feature.love")
        }
    }
}

#Preview {
    DecideEventPrimer(continueAction: {})
}
