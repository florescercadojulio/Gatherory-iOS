import SwiftUI

struct SearchPrimer: View {
    let continueAction: () -> Void

    var body: some View {
        FeaturePrimerView(
            title: String(localized: "primer.search.title", defaultValue: "Find ideas for your event"),
            continueIdentifier: "search.primer.continue",
            continueAction: continueAction
        ) {
            FeaturePrimerRow(symbol: "magnifyingglass", title: String(localized: "primer.search.search.title", defaultValue: "Search blueprints and ideas"), detail: String(localized: "primer.search.search.detail", defaultValue: "Find a complete plan or a little inspiration."))
                .accessibilityIdentifier("search.primer.feature.search")
            FeaturePrimerRow(symbol: "line.3.horizontal.decrease", title: String(localized: "primer.search.filter.title", defaultValue: "Choose what to browse"), detail: String(localized: "primer.search.filter.detail", defaultValue: "Browse All, Blueprints, or Ideas."))
                .accessibilityIdentifier("search.primer.feature.filter")
            FeaturePrimerRow(symbol: "plus.circle", title: String(localized: "primer.search.add.title", defaultValue: "Add an idea to your event"), detail: String(localized: "primer.search.add.detail", defaultValue: "Keep an idea with an event you’re planning."))
                .accessibilityIdentifier("search.primer.feature.add")
        }
    }
}
