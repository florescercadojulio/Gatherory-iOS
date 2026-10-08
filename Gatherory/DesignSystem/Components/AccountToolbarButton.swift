import SwiftUI

struct AccountToolbarButton: View {
    @State private var isPresentingAccount = false

    var body: some View {
        Button {
            isPresentingAccount = true
        } label: {
            Image(systemName: "person.crop.circle.fill")
                .font(.title3)
                .symbolRenderingMode(.palette)
                .foregroundStyle(AppTheme.ColorToken.accent, AppTheme.ColorToken.lilac)
        }
        .accessibilityLabel("Account and settings")
        .sheet(isPresented: $isPresentingAccount) {
            NavigationStack {
                AccountView()
            }
        }
    }
}
