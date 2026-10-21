import Foundation
import Testing
@testable import Gatherory

@MainActor
struct AccountDeletionRoutingTests {
    @Test("Pending account deletion cleanup takes priority over every launch destination")
    func cleanupOwnsLaunchRouting() {
        let invitation = UUID()
        let cases: [(String, AuthenticationFlowContext, AuthenticationFlowDestination)] = [
            ("signed out", .init(), .authentication),
            ("signed in", .init(isAuthenticated: true, preparedIdentityMatches: true), .app),
            ("account loading", .init(isAuthenticated: true), .accountLoading),
            ("guest", .init(isGuestMode: true, preparedIdentityMatches: true), .app),
            ("guest loading", .init(isGuestMode: true), .guestLoading),
            ("guest sign in", .init(guestSignInRequested: true, isGuestMode: true), .guestSignIn),
            ("guest import", .init(hasPendingGuestImport: true, isAuthenticated: true), .guestImporting),
            ("guest import recovery", .init(guestImportNeedsSignIn: true, hasPendingGuestImport: true,
                isAuthenticated: true), .guestRecovery(needsSignIn: true)),
            ("shared link authentication", .init(pendingSharedBlueprintToken: "shared-token"),
                .sharedBlueprintAuthentication),
            ("shared preview", .init(pendingSharedBlueprintToken: "shared-token", isAuthenticated: true,
                preparedIdentityMatches: true), .sharedBlueprintPreview(token: "shared-token")),
            ("invitation authentication", .init(pendingInvitationToken: invitation,
                invitationRequiresAuthentication: true), .invitationAuthentication),
            ("invitation preview", .init(pendingInvitationToken: invitation), .invitation(token: invitation)),
            ("invitation loading", .init(pendingInvitationToken: invitation, isAuthenticated: true), .invitationLoading),
            ("onboarding", .init(isAuthenticated: true, preparedIdentityMatches: true,
                accountOnboardingState: .needsOnboarding), .onboarding),
            ("forced onboarding", .init(isAuthenticated: true, preparedIdentityMatches: true,
                alwaysShowsOnboarding: true, usesRemoteAccountState: true,
                accountOnboardingState: .complete), .onboarding),
            ("completed onboarding", .init(isAuthenticated: true, preparedIdentityMatches: true,
                completedOnboardingThisSession: true), .app),
            ("remote account", .init(isAuthenticated: true, preparedIdentityMatches: true,
                usesRemoteAccountState: true, accountOnboardingState: .complete), .remoteAccount),
            ("attendance arrival", .init(isAuthenticated: true, preparedIdentityMatches: true,
                hasGuestInvitations: true, didJoinInvitationThisSession: true), .app),
            ("restoration recovery", .init(sessionRestorationUnavailable: true), .sessionRestorationRecovery),
            ("explicit restoration sign in", .init(sessionRestorationUnavailable: true,
                restorationSignInRequested: true), .authentication),
            ("guest discard recovery", .init(isGuestMode: true, guestDiscardNeedsAttention: true), .guestDiscardRecovery),
            ("account preparation recovery", .init(isAuthenticated: true,
                accountPreparationFailed: true), .accountRecovery)
        ]

        for (name, original, expected) in cases {
            var context = original
            #expect(AuthenticationFlowChain.default.destination(for: context) == expected, "\(name)")
            context.accountDeletionCleanupPending = true
            #expect(AuthenticationFlowChain.default.destination(for: context) == .accountDeletionCleanup, "\(name)")
            context.accountDeletionCleanupPending = false
            #expect(AuthenticationFlowChain.default.destination(for: context) == expected, "\(name)")
        }
    }

    @Test("Account cleanup blocks notification principals for both signed-in accounts and retained guests",
        arguments: [false, true])
    func cleanupBlocksNotificationEntry(signedIn: Bool) throws {
        let cleanup = AccountDeletionCleanupCoordinator(journal: MemoryAccountDeletionCleanupJournal())
        let profiles = MemoryLocalGuestProfileStore()
        if !signedIn { try profiles.save(LocalGuestProfile(displayName: "Retained guest")) }
        let authentication = AuthenticationSession(environment: .development, skipsAuthentication: signedIn,
            guestProfileStore: profiles, guestCredentialStore: MemoryLocalGuestCredentialStore(),
            deletionCleanup: cleanup)
        let originalPrincipal = try #require(authentication.notificationPrincipal)
        let deletedAccountID = authentication.currentUser?.id ?? "previously-deleted-account"

        try cleanup.begin(accountID: deletedAccountID)
        #expect(authentication.notificationPrincipal == nil)
        #expect(AuthenticationFlowChain.default.destination(for: AuthenticationFlowContext(
            isGuestMode: authentication.isGuestMode, isAuthenticated: authentication.isAuthenticated,
            preparedIdentityMatches: true, hasGuestInvitations: true,
            accountDeletionCleanupPending: cleanup.blocksEntry)) == .accountDeletionCleanup)

        cleanup.cancelUnconfirmedRequest()
        #expect(authentication.notificationPrincipal == originalPrincipal)
    }
}
