import SwiftUI

enum IdeaSubmitterIdentity {
    case account(UserAccount)
    case member(WorkspaceMember)
    case unknown

    /// Resolves only by the stable account identifier stored with the idea.
    /// Names and email addresses are intentionally never used as identity clues.
    static func resolve(
        idea: PlanningIdea,
        members: [WorkspaceMember],
        currentAccount: UserAccount?
    ) -> IdeaSubmitterIdentity {
        guard let userID = idea.submittedByUserID, !userID.isEmpty else { return .unknown }
        if let currentAccount, currentAccount.id == userID {
            return .account(currentAccount)
        }
        if let member = members.first(where: { $0.userID == userID }) {
            return .member(member)
        }
        return .unknown
    }
}

struct IdeaSubmitterAttribution: View {
    let idea: PlanningIdea
    let members: [WorkspaceMember]
    var showsName = true

    @Environment(\.currentUserAccount) private var currentAccount

    var body: some View {
        HStack(spacing: 8) {
            avatar
                .frame(width: 26, height: 26)
            if showsName {
                Text(idea.submittedBy)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("Suggested by \(idea.submittedBy)")
            }
        }
    }

    @ViewBuilder
    private var avatar: some View {
        switch IdeaSubmitterIdentity.resolve(
            idea: idea,
            members: members,
            currentAccount: currentAccount
        ) {
        case .account(let account):
            UserAvatarView(account: account, size: 26, showsBorder: false)
        case .member(let member):
            memberAvatar(member)
        case .unknown:
            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: 26))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private func memberAvatar(_ member: WorkspaceMember) -> some View {
        Group {
            if let assetName = member.profileImageAssetName {
                Image(assetName).resizable().scaledToFill()
            } else if let imageURL = member.profileImageURL {
                AsyncImage(url: imageURL, transaction: .init(animation: .easeOut(duration: 0.2))) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        memberFallback(member)
                    }
                }
            } else {
                memberFallback(member)
            }
        }
        .frame(width: 26, height: 26)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }

    private func memberFallback(_ member: WorkspaceMember) -> some View {
        Text(member.initials)
            .font(.system(size: 9, weight: .bold, design: .rounded))
            .foregroundStyle(AppTheme.ColorToken.onAccent)
            .frame(width: 26, height: 26)
            .background(AppTheme.ColorToken.accent, in: Circle())
    }
}
