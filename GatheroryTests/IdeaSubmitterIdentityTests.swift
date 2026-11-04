import Foundation
import Testing
@testable import Gatherory

@MainActor
struct IdeaSubmitterIdentityTests {
    @Test("An idea authored by the signed-in account resolves to that account and its photo")
    func currentAccountAuthorUsesAccountPhoto() throws {
        let account = makeAccount(id: "author", asset: "AuthorPortrait")
        let idea = makeIdea(authorID: account.id)

        guard case .account(let resolved) = IdeaSubmitterIdentity.resolve(
            idea: idea, members: [], currentAccount: account
        ) else {
            Issue.record("Expected the matching current account to be the author")
            return
        }

        #expect(resolved.id == account.id)
        #expect(resolved.profileImageAssetName == "AuthorPortrait")
    }

    @Test("A linked collaborator resolves to their saved asset or profile URL")
    func collaboratorAuthorUsesMemberPhoto() throws {
        let idea = makeIdea(authorID: "collaborator")
        let assetMember = makeMember(userID: "collaborator", asset: "CollaboratorPortrait")
        let url = try #require(URL(string: "https://images.example.test/collaborator.jpg"))
        let urlMember = makeMember(userID: "collaborator", url: url)

        guard case .member(let resolvedAsset) = IdeaSubmitterIdentity.resolve(
            idea: idea, members: [assetMember], currentAccount: makeAccount(id: "viewer")
        ) else {
            Issue.record("Expected the linked collaborator to resolve as a workspace member")
            return
        }
        #expect(resolvedAsset.profileImageAssetName == "CollaboratorPortrait")

        guard case .member(let resolvedURL) = IdeaSubmitterIdentity.resolve(
            idea: idea, members: [urlMember], currentAccount: makeAccount(id: "viewer")
        ) else {
            Issue.record("Expected the linked collaborator to resolve as a workspace member")
            return
        }
        #expect(resolvedURL.profileImageURL == url)
    }

    @Test("An unrelated signed-in account never replaces the identified author")
    func unrelatedCurrentAccountDoesNotOverrideAuthor() {
        let account = makeAccount(id: "viewer", asset: "ViewerPortrait")
        let member = makeMember(userID: "author", asset: "AuthorPortrait")

        guard case .member(let resolved) = IdeaSubmitterIdentity.resolve(
            idea: makeIdea(authorID: "author"), members: [member], currentAccount: account
        ) else {
            Issue.record("Expected the author member, not the signed-in viewer")
            return
        }

        #expect(resolved.userID == "author")
        #expect(resolved.profileImageAssetName == "AuthorPortrait")
    }

    @Test("Legacy ideas and duplicate names do not infer an author identity")
    func namesNeverResolveIdentity() {
        let duplicateNames = [
            makeMember(userID: "first", name: "Alex Morgan", asset: "FirstPortrait"),
            makeMember(userID: "second", name: "Alex Morgan", asset: "SecondPortrait")
        ]
        let account = makeAccount(id: "first", name: "Alex Morgan", asset: "AccountPortrait")

        for idea in [makeIdea(authorID: nil), makeIdea(authorID: "")] {
            guard case .unknown = IdeaSubmitterIdentity.resolve(
                idea: idea, members: duplicateNames, currentAccount: account
            ) else {
                Issue.record("An idea without a stable author ID must remain unknown")
                return
            }
        }
    }

    @Test("A missing or removed author falls back to unknown identity")
    func missingAuthorFallsBackToUnknown() {
        let account = makeAccount(id: "viewer", name: "Alex Morgan", asset: "ViewerPortrait")
        let idea = makeIdea(authorID: "removed-author", name: "Alex Morgan")

        guard case .unknown = IdeaSubmitterIdentity.resolve(
            idea: idea, members: [], currentAccount: account
        ) else {
            Issue.record("A display-name match must not restore a removed author")
            return
        }
    }

    @Test("Resolving again after an account change follows the same stored author ID")
    func accountChangeResolvesFromCurrentIdentity() {
        let idea = makeIdea(authorID: "former-viewer")
        let formerViewer = makeAccount(id: "former-viewer", asset: "FormerPortrait")
        let newViewer = makeAccount(id: "new-viewer", asset: "NewPortrait")

        guard case .account(let firstResolution) = IdeaSubmitterIdentity.resolve(
            idea: idea, members: [], currentAccount: formerViewer
        ), case .unknown = IdeaSubmitterIdentity.resolve(
            idea: idea, members: [], currentAccount: newViewer
        ) else {
            Issue.record("A new account must not inherit the previous account's author identity")
            return
        }

        #expect(firstResolution.profileImageAssetName == "FormerPortrait")
    }

    @Test("A linked author without a photo still resolves to the member fallback")
    func linkedMemberWithoutPhotoResolvesForInitialsFallback() {
        let member = makeMember(userID: "author")

        guard case .member(let resolved) = IdeaSubmitterIdentity.resolve(
            idea: makeIdea(authorID: "author"), members: [member], currentAccount: nil
        ) else {
            Issue.record("A linked member without photo metadata should retain member identity")
            return
        }

        #expect(resolved.profileImageAssetName == nil)
        #expect(resolved.profileImageURL == nil)
        #expect(resolved.initials == "AM")
    }

    private func makeIdea(authorID: String?, name: String = "Alex Morgan") -> PlanningIdea {
        PlanningIdea(title: "Idea", note: "", category: .other, submittedBy: name,
            submittedByUserID: authorID)
    }

    private func makeAccount(
        id: String,
        name: String = "Author",
        asset: String? = nil
    ) -> UserAccount {
        UserAccount(id: id, email: "\(id)@example.test", displayName: name, role: .planner,
            authenticationProvider: .password, createdAt: Date(timeIntervalSince1970: 0),
            profileImageAssetName: asset)
    }

    private func makeMember(
        userID: String?,
        name: String = "Alex Morgan",
        asset: String? = nil,
        url: URL? = nil
    ) -> WorkspaceMember {
        WorkspaceMember(userID: userID, name: name, participantRole: .collaborator, initials: "AM",
            profileImageAssetName: asset, profileImageURL: url)
    }
}
