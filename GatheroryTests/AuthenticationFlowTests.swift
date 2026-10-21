import Foundation
import Testing
@testable import Gatherory

struct AuthenticationFlowTests {
    @Test("A requested guest sign-in takes priority over guest recovery")
    func guestSignInWins() {
        var context = AuthenticationFlowContext(
            guestSignInRequested: true,
            guestImportNeedsSignIn: true,
            isGuestMode: true
        )
        #expect(AuthenticationFlowChain.default.destination(for: context) == .guestSignIn)

        context.guestSignInRequested = false
        #expect(AuthenticationFlowChain.default.destination(for: context) == .guestRecovery(needsSignIn: true))
    }

    @Test("Guest data is prepared before a pending share or invitation is opened")
    func guestPreparationWins() {
        let sharedBlueprint = AuthenticationFlowContext(
            hasPendingGuestImport: true,
            pendingSharedBlueprintToken: "share-token",
            isAuthenticated: true,
            preparedIdentityMatches: false
        )
        #expect(AuthenticationFlowChain.default.destination(for: sharedBlueprint) == .guestImporting)

        let failedImport = AuthenticationFlowContext(
            hasPendingGuestImport: true,
            pendingInvitationToken: UUID(),
            isAuthenticated: true,
            guestPreparationFailed: true,
            preparedIdentityMatches: false
        )
        #expect(AuthenticationFlowChain.default.destination(for: failedImport) == .guestRecovery(needsSignIn: false))
    }

    @Test("Shared blueprint access separates authentication, preparation, and preview")
    func sharedBlueprintStages() {
        let token = "share-token"
        #expect(AuthenticationFlowChain.default.destination(for: AuthenticationFlowContext(
            pendingSharedBlueprintToken: token
        )) == .sharedBlueprintAuthentication)
        #expect(AuthenticationFlowChain.default.destination(for: AuthenticationFlowContext(
            pendingSharedBlueprintToken: token,
            isAuthenticated: true,
            preparedIdentityMatches: false
        )) == .sharedBlueprintLoading)
        #expect(AuthenticationFlowChain.default.destination(for: AuthenticationFlowContext(
            pendingSharedBlueprintToken: token,
            isAuthenticated: true,
            preparedIdentityMatches: true
        )) == .sharedBlueprintPreview(token: token))
    }

    @Test("Invitations keep guest attendance and signed-in planning states explicit")
    func invitationStages() {
        let token = UUID()
        #expect(AuthenticationFlowChain.default.destination(for: AuthenticationFlowContext(
            pendingInvitationToken: token,
            invitationRequiresAuthentication: true
        )) == .invitationAuthentication)
        #expect(AuthenticationFlowChain.default.destination(for: AuthenticationFlowContext(
            pendingInvitationToken: token,
            isGuestMode: true,
            preparedIdentityMatches: false
        )) == .invitationLoading)
        #expect(AuthenticationFlowChain.default.destination(for: AuthenticationFlowContext(
            pendingInvitationToken: token,
            isAuthenticated: true,
            preparedIdentityMatches: true
        )) == .invitation(token: token))
    }

    @Test("Onboarding is account-scoped and does not interrupt guest attendance")
    func onboardingAndGuestStates() {
        #expect(AuthenticationFlowChain.default.destination(for: AuthenticationFlowContext(
            isAuthenticated: true,
            preparedIdentityMatches: true,
            accountOnboardingState: .needsOnboarding
        )) == .onboarding)
        #expect(AuthenticationFlowChain.default.destination(for: AuthenticationFlowContext(
            isGuestMode: true,
            preparedIdentityMatches: true,
            accountOnboardingState: .needsOnboarding
        )) == .app)
        #expect(AuthenticationFlowChain.default.destination(for: AuthenticationFlowContext(
            isAuthenticated: true,
            preparedIdentityMatches: true,
            accountOnboardingState: .complete
        )) == .app)
    }

    @Test("Remote account availability is resolved before normal onboarding", arguments: [
        AccountOnboardingState.signedOut, .resolving, .needsOnboarding, .complete, .unavailable
    ])
    func remoteAccountOwnsOnboarding(state: AccountOnboardingState) {
        #expect(AuthenticationFlowChain.default.destination(for: AuthenticationFlowContext(
            isAuthenticated: true,
            preparedIdentityMatches: true,
            usesRemoteAccountState: true,
            accountOnboardingState: state
        )) == .remoteAccount)
    }

    @Test("Changing accounts waits for preparation even when the previous account completed onboarding")
    func accountPreparationPrecedesPriorOnboardingCompletion() {
        #expect(AuthenticationFlowChain.default.destination(for: AuthenticationFlowContext(
            isAuthenticated: true,
            preparedIdentityMatches: false,
            completedOnboardingThisSession: true,
            usesRemoteAccountState: true,
            accountOnboardingState: .complete
        )) == .accountLoading)
    }

    @Test("An import bound to a different account offers sign-in recovery before opening links")
    func wrongImportAccountKeepsRecoveryReason() {
        #expect(AuthenticationFlowChain.default.destination(for: AuthenticationFlowContext(
            guestImportNeedsSignIn: true,
            hasPendingGuestImport: true,
            pendingSharedBlueprintToken: "share-token",
            pendingInvitationToken: UUID(),
            isAuthenticated: true,
            guestPreparationFailed: true
        )) == .guestRecovery(needsSignIn: true))
    }

    @Test("A pending import cannot run without an authenticated account")
    func importRequiresAccount() {
        #expect(AuthenticationFlowChain.default.destination(for: AuthenticationFlowContext(
            hasPendingGuestImport: true
        )) == .guestRecovery(needsSignIn: true))
    }

    @Test("Guest preparation failure blocks attendance and the workspace browser")
    func guestFailureKeepsRecovery() {
        var context = AuthenticationFlowContext(
            isGuestMode: true,
            guestPreparationFailed: true,
            hasGuestInvitations: true,
            didJoinInvitationThisSession: true
        )
        #expect(AuthenticationFlowChain.default.destination(for: context) == .guestRecovery(needsSignIn: false))
        context.pendingInvitationToken = UUID()
        #expect(AuthenticationFlowChain.default.destination(for: context) == .invitationRecovery(needsSignIn: false))
        context.invitationRequiresAuthentication = true
        #expect(AuthenticationFlowChain.default.destination(for: context) == .invitationAuthentication)
    }

    @Test("An invitation can be previewed before sign-in when attendance does not require it")
    func publicInvitationPreview() {
        let token = UUID()
        #expect(AuthenticationFlowChain.default.destination(for: AuthenticationFlowContext(
            pendingInvitationToken: token
        )) == .invitation(token: token))
    }

    @Test("An explicit shared blueprint link takes precedence over an invitation")
    func linkPrecedence() {
        #expect(AuthenticationFlowChain.default.destination(for: AuthenticationFlowContext(
            pendingSharedBlueprintToken: "share-token",
            pendingInvitationToken: UUID(),
            isAuthenticated: true,
            preparedIdentityMatches: true
        )) == .sharedBlueprintPreview(token: "share-token"))
    }

    @Test("The QA onboarding override remains explicit and ends after completion")
    func onboardingOverride() {
        var context = AuthenticationFlowContext(
            isAuthenticated: true,
            preparedIdentityMatches: true,
            alwaysShowsOnboarding: true,
            usesRemoteAccountState: true,
            accountOnboardingState: .complete
        )
        #expect(AuthenticationFlowChain.default.destination(for: context) == .onboarding)
        context.completedOnboardingThisSession = true
        #expect(AuthenticationFlowChain.default.destination(for: context) == .remoteAccount)
    }

    @Test("An incomplete custom chain fails closed for every identity")
    func missingHandlerDoesNotOpenApp() {
        let chain = AuthenticationFlowChain(handlers: [])
        #expect(chain.destination(for: AuthenticationFlowContext()) == .authentication)
        #expect(chain.destination(for: AuthenticationFlowContext(
            isAuthenticated: true,
            preparedIdentityMatches: true
        )) == .accountLoading)
        #expect(chain.destination(for: AuthenticationFlowContext(
            isGuestMode: true,
            preparedIdentityMatches: true
        )) == .guestLoading)
    }

    @Test("Attendance from a previous account never bypasses sign-in or preparation")
    func staleAttendanceDoesNotOpenApp() {
        var context = AuthenticationFlowContext(
            hasGuestInvitations: true,
            didJoinInvitationThisSession: true,
            completedOnboardingThisSession: true
        )
        #expect(AuthenticationFlowChain.default.destination(for: context) == .authentication)
        context.isAuthenticated = true
        #expect(AuthenticationFlowChain.default.destination(for: context) == .accountLoading)
        context.preparedIdentityMatches = true
        #expect(AuthenticationFlowChain.default.destination(for: context) == .app)
    }

    @Test("Unavailable session restoration blocks guest entry, invitations, and shared links")
    func restorationRecoveryHasPriority() {
        let contexts = [
            AuthenticationFlowContext(
                pendingInvitationToken: UUID(),
                sessionRestorationUnavailable: true
            ),
            AuthenticationFlowContext(
                pendingSharedBlueprintToken: "share-token",
                sessionRestorationUnavailable: true
            ),
            AuthenticationFlowContext(
                guestSignInRequested: true,
                isGuestMode: true,
                preparedIdentityMatches: true,
                sessionRestorationUnavailable: true
            )
        ]
        for context in contexts {
            #expect(AuthenticationFlowChain.default.destination(for: context) == .sessionRestorationRecovery)
        }
    }

    @Test("Explicit sign-in from restoration recovery only opens authentication")
    func restorationRecoveryAllowsExplicitSignIn() {
        #expect(AuthenticationFlowChain.default.destination(for: AuthenticationFlowContext(
            pendingSharedBlueprintToken: "share-token",
            pendingInvitationToken: UUID(),
            isGuestMode: true,
            preparedIdentityMatches: true,
            hasGuestInvitations: true,
            didJoinInvitationThisSession: true,
            completedOnboardingThisSession: true,
            sessionRestorationUnavailable: true,
            restorationSignInRequested: true
        )) == .authentication)
    }

    @Test("An incomplete guest discard blocks sign-in and all guest entry points")
    func incompleteDiscardHasPriority() {
        var context = AuthenticationFlowContext(
            guestSignInRequested: true,
            pendingSharedBlueprintToken: "share-token",
            pendingInvitationToken: UUID(),
            isGuestMode: true,
            preparedIdentityMatches: true,
            guestDiscardNeedsAttention: true
        )
        #expect(AuthenticationFlowChain.default.destination(for: context) == .guestDiscardRecovery)
        context.pendingSharedBlueprintToken = nil
        context.pendingInvitationToken = nil
        #expect(AuthenticationFlowChain.default.destination(for: context) == .guestDiscardRecovery)
        context.guestSignInRequested = false
        #expect(AuthenticationFlowChain.default.destination(for: context) == .guestDiscardRecovery)
    }

    @Test("Failed account preparation blocks shared previews, invitations, and onboarding")
    func accountPreparationFailureHasPriority() {
        var context = AuthenticationFlowContext(
            pendingSharedBlueprintToken: "share-token",
            pendingInvitationToken: UUID(),
            isAuthenticated: true,
            preparedIdentityMatches: true,
            alwaysShowsOnboarding: true,
            accountOnboardingState: .needsOnboarding,
            accountPreparationFailed: true
        )
        #expect(AuthenticationFlowChain.default.destination(for: context) == .accountRecovery)
        context.pendingSharedBlueprintToken = nil
        #expect(AuthenticationFlowChain.default.destination(for: context) == .accountRecovery)
        context.pendingInvitationToken = nil
        #expect(AuthenticationFlowChain.default.destination(for: context) == .accountRecovery)
    }

    @Test("A successfully authenticated current account ignores stale restoration failure flags")
    func successfulAuthenticationClearsRoutingBlock() {
        var context = AuthenticationFlowContext(
            isAuthenticated: true,
            preparedIdentityMatches: false,
            accountOnboardingState: .complete,
            sessionRestorationUnavailable: true,
            restorationSignInRequested: true
        )
        #expect(AuthenticationFlowChain.default.destination(for: context) == .accountLoading)
        context.preparedIdentityMatches = true
        #expect(AuthenticationFlowChain.default.destination(for: context) == .app)
    }
}
