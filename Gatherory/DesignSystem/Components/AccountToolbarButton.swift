import SwiftUI

private struct CurrentUserAccountKey: EnvironmentKey {
    static let defaultValue: UserAccount? = nil
}

extension EnvironmentValues {
    var currentUserAccount: UserAccount? {
        get { self[CurrentUserAccountKey.self] }
        set { self[CurrentUserAccountKey.self] = newValue }
    }
}

struct AccountToolbarButton: View {
    var monochrome = false
    var avatarSize: CGFloat = 28
    @Environment(\.currentUserAccount) private var currentUserAccount
    @State private var isPresentingAccount = false

    var body: some View {
        Button {
            isPresentingAccount = true
        } label: {
            UserAvatarView(
                account: currentUserAccount,
                size: avatarSize,
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

/// Groups trailing toolbar actions into the same compact Liquid Glass capsule
/// used by the workspace browser.
struct ToolbarGlassActionGroup<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        HStack(spacing: 6, content: content)
            .frame(minHeight: 44)
            .glassEffect(.regular.interactive(), in: Capsule())
    }
}

struct UserAvatarView: View {
    let account: UserAccount?
    var size: CGFloat
    var fallbackIsMonochrome = false
    var showsBorder = true

    var body: some View {
        Group {
            if let assetName = account?.profileImageAssetName {
                Image(assetName)
                    .resizable()
                    .scaledToFill()
            } else if let imageURL = account?.profileImageURL {
                AsyncImage(url: imageURL, transaction: .init(animation: .easeOut(duration: 0.2))) { phase in
                    if let image = phase.image {
                        image
                            .resizable()
                            .scaledToFill()
                    } else {
                        initialsFallback
                    }
                }
            } else {
                initialsFallback
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay {
            if showsBorder {
                Circle()
                    .stroke(.white.opacity(0.72), lineWidth: size >= 44 ? 1.5 : 1)
            }
        }
        .contentShape(Circle())
        .accessibilityHidden(true)
    }

    private var initialsFallback: some View {
        ZStack {
            Circle()
                .fill(
                    fallbackIsMonochrome
                        ? AnyShapeStyle(Color.primary.opacity(0.12))
                        : AnyShapeStyle(
                            LinearGradient(
                                colors: [
                                    AppTheme.ColorToken.accent,
                                    AppTheme.ColorToken.accentSecondary
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )

            Text(initials)
                .font(.system(size: max(size * 0.34, 11), weight: .semibold, design: .rounded))
                .foregroundStyle(fallbackIsMonochrome ? Color.primary : AppTheme.ColorToken.onAccent)
                .minimumScaleFactor(0.7)
        }
    }

    private var initials: String {
        account.map(accountInitials) ?? "G"
    }
}

enum ParticipantAvatarStyle: Equatable {
    case hero
    case toolbar
    case accent
}

/// Resolves an event participant back to the signed-in account when possible,
/// so every representation of that person uses the same profile image. People
/// without a linked account intentionally continue to use their initials.
struct ParticipantAvatarView: View {
    let member: WorkspaceMember
    var size: CGFloat
    var style: ParticipantAvatarStyle = .accent

    @Environment(\.currentUserAccount) private var currentUserAccount

    var body: some View {
        Group {
            if let linkedAccount {
                UserAvatarView(
                    account: linkedAccount,
                    size: size,
                    fallbackIsMonochrome: style == .toolbar,
                    showsBorder: false
                )
            } else if let assetName = member.profileImageAssetName {
                Image(assetName)
                    .resizable()
                    .scaledToFill()
            } else if let imageURL = member.profileImageURL {
                AsyncImage(
                    url: imageURL,
                    transaction: .init(animation: .easeOut(duration: 0.2))
                ) { phase in
                    if let image = phase.image {
                        image
                            .resizable()
                            .scaledToFill()
                    } else {
                        initialsFallback
                    }
                }
            } else {
                initialsFallback
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay {
            Circle().stroke(strokeColor, lineWidth: strokeWidth)
        }
        .contentShape(Circle())
        .accessibilityHidden(true)
    }

    private var linkedAccount: UserAccount? {
        guard let account = currentUserAccount else { return nil }

        if member.userID == account.id {
            return account
        }

        if let email = member.email,
           email.caseInsensitiveCompare(account.email) == .orderedSame {
            return account
        }

        // Workspaces saved before participants carried account identifiers
        // still placed the current managing host first and stored their
        // initials. Keep those archives visually linked without mistaking an
        // ordinary guest with the same initials for the signed-in person.
        if member.userID == nil,
           member.email == nil,
           member.planningPermission == .manage,
           member.initials.caseInsensitiveCompare(accountInitials(account)) == .orderedSame {
            return account
        }

        return nil
    }

    @ViewBuilder
    private var initialsFallback: some View {
        switch style {
        case .hero:
            Text(member.initials)
                .font(.caption.bold())
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.regularMaterial, in: Circle())
        case .toolbar:
            Text(member.initials)
                .font(.caption2.bold())
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.thinMaterial, in: Circle())
        case .accent:
            Text(member.initials)
                .font(.system(size: max(size * 0.32, 11), weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.ColorToken.onAccent)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(AppTheme.ColorToken.accent, in: Circle())
        }
    }

    private var strokeColor: Color {
        switch style {
        case .hero:
            .white.opacity(0.72)
        case .toolbar:
            .primary.opacity(0.24)
        case .accent:
            .white.opacity(0.72)
        }
    }

    private var strokeWidth: CGFloat {
        switch style {
        case .hero:
            2
        case .toolbar:
            0.5
        case .accent:
            size >= 44 ? 1.5 : 1
        }
    }
}

private func accountInitials(_ account: UserAccount) -> String {
    let displayName = account.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
    let source = displayName.isEmpty || displayName.caseInsensitiveCompare(account.email) == .orderedSame
        ? account.email.split(separator: "@").first.map(String.init) ?? "G"
        : displayName
    let parts = source
        .split(whereSeparator: { $0.isWhitespace || $0 == "-" || $0 == "_" || $0 == "." })
    let characters = parts.prefix(2).compactMap(\.first)
    return characters.isEmpty ? "G" : String(characters).uppercased()
}
