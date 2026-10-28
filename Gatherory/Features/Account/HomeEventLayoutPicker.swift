import SwiftUI

struct HomeEventLayoutPicker: View {
    @AppStorage(HomeEventLayout.preferenceKey) private var persistedLayout = HomeEventLayout.cards.rawValue

    private var selection: Binding<HomeEventLayout> {
        Binding(
            get: { HomeEventLayout(persistedValue: persistedLayout) },
            set: { persistedLayout = $0.rawValue }
        )
    }

    var body: some View {
        Picker(selection: selection) {
            ForEach(HomeEventLayout.allCases) { layout in
                Text(layout.title).tag(layout)
            }
        } label: {
            Label("Home view", systemImage: "rectangle.grid.1x2")
        }
        .pickerStyle(.navigationLink)
        .accessibilityIdentifier("account.home.layout")
    }
}
