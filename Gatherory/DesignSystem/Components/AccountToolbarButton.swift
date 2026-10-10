import SwiftUI

struct AccountToolbarButton: View {
    var monochrome = false
    @Environment(AuthenticationSession.self) private var authentication
    @State private var isPresentingAccount = false

    var body: some View {
        Button {
            isPresentingAccount = true
        } label: {
            UserAvatarView(
                account: authentication.currentUser,
                size: 28,
                fallbackIsMonochrome: monochrome
            )
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

struct UserAvatarView: View {
    let account: UserAccount?
    var size: CGFloat
    var fallbackIsMonochrome = false

    var body: some View {
        Group {
            if let assetName = account?.profileImageAssetName {
                Image(assetName)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "person.crop.circle.fill")
                    .resizable()
                    .scaledToFit()
                    .symbolRenderingMode(fallbackIsMonochrome ? .monochrome : .palette)
                    .foregroundStyle(
                        fallbackIsMonochrome ? Color.primary : AppTheme.ColorToken.accent,
                        AppTheme.ColorToken.lilac
                    )
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay {
            Circle()
                .stroke(.white.opacity(0.72), lineWidth: size >= 44 ? 1.5 : 1)
        }
        .contentShape(Circle())
        .accessibilityHidden(true)
    }
}
