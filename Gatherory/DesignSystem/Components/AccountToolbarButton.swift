import SwiftUI

struct AccountToolbarButton: View {
    var monochrome = false
    @State private var isPresentingAccount = false

    var body: some View {
        Button {
            isPresentingAccount = true
        } label: {
            if monochrome {
                Image(systemName: "person.crop.circle.fill")
                    .font(.title3)
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(.primary)
            } else {
                Image(systemName: "person.crop.circle.fill")
                    .font(.title3)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(AppTheme.ColorToken.accent, AppTheme.ColorToken.lilac)
            }
        }
        .tint(monochrome ? Color.primary : AppTheme.ColorToken.accent)
        .accessibilityLabel("Account and settings")
        .sheet(isPresented: $isPresentingAccount) {
            NavigationStack {
                AccountView()
            }
        }
    }
}
