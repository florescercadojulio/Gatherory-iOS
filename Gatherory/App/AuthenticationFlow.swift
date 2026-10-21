import Foundation

/// The inputs needed to choose the first screen after authentication and
/// account preparation. This value is deliberately side-effect free so the
/// priority rules can be tested without SwiftUI, networking, or persistence.
struct AuthenticationFlowContext: Equatable, Sendable {
    var guestSignInRequested: Bool = false
    var guestImportNeedsSignIn: Bool = false
    var hasPendingGuestImport: Bool = false
    var pendingSharedBlueprintToken: String?
    var pendingInvitationToken: UUID?
    var invitationRequiresAuthentication: Bool = false
    var isGuestMode: Bool = false
    var isAuthenticated: Bool = false
    var guestPreparationFailed: Bool = false
    var preparedIdentityMatches: Bool = false
    var hasGuestInvitations: Bool = false
    var didJoinInvitationThisSession: Bool = false
    var alwaysShowsOnboarding: Bool = false
    var completedOnboardingThisSession: Bool = false
    var usesRemoteAccountState: Bool = false
    var accountOnboardingState: AccountOnboardingState = .signedOut
    var sessionRestorationUnavailable = false
    var restorationSignInRequested = false
    var guestDiscardNeedsAttention = false
    var accountPreparationFailed = false
    var accountDeletionCleanupPending = false
}

enum AuthenticationFlowDestination: Equatable, Sendable {
    case guestSignIn
    case guestRecovery(needsSignIn: Bool)
    case guestImporting
    case sharedBlueprintAuthentication
    case sharedBlueprintLoading
    case sharedBlueprintPreview(token: String)
    case invitationAuthentication
    case invitationLoading
    case invitationRecovery(needsSignIn: Bool)
    case invitation(token: UUID)
    case guestLoading
    case authentication
    case accountLoading
    case app
    case onboarding
    case remoteAccount
    case sessionRestorationRecovery
    case guestDiscardRecovery
    case accountRecovery
    case accountDeletionCleanup
}

/// A small Chain of Responsibility for launch routing. Each handler owns one
/// reason to stop evaluating the chain; adding a new authentication or data
/// retention state does not require editing a nested view conditional.
protocol AuthenticationFlowHandler: Sendable {
    func destination(for context: AuthenticationFlowContext) -> AuthenticationFlowDestination?
}

struct AuthenticationFlowChain: Sendable {
    private let handlers: [any AuthenticationFlowHandler]

    init(handlers: [any AuthenticationFlowHandler] = AuthenticationFlowChain.defaultHandlers) {
        self.handlers = handlers
    }

    func destination(for context: AuthenticationFlowContext) -> AuthenticationFlowDestination {
        for handler in handlers {
            if let destination = handler.destination(for: context) { return destination }
        }
        // An incomplete chain must never open a data scope by accident.
        if context.isAuthenticated { return .accountLoading }
        if context.isGuestMode { return .guestLoading }
        return .authentication
    }

    static let `default` = AuthenticationFlowChain()

    private static let defaultHandlers: [any AuthenticationFlowHandler] = [
        AccountDeletionCleanupHandler(),
        SessionRestorationHandler(),
        GuestDiscardHandler(),
        GuestSignInRequestHandler(),
        GuestRecoveryHandler(),
        GuestImportHandler(),
        AccountRecoveryHandler(),
        SharedBlueprintHandler(),
        InvitationHandler(),
        GuestModeHandler(),
        SignedOutHandler(),
        AccountPreparationHandler(),
        InvitationArrivalHandler(),
        OnboardingHandler(),
        RemoteAccountHandler(),
        AppHandler()
    ]
}

private struct AccountDeletionCleanupHandler: AuthenticationFlowHandler {
    func destination(for context: AuthenticationFlowContext) -> AuthenticationFlowDestination? {
        context.accountDeletionCleanupPending ? .accountDeletionCleanup : nil
    }
}

private struct SessionRestorationHandler: AuthenticationFlowHandler {
    func destination(for context: AuthenticationFlowContext) -> AuthenticationFlowDestination? {
        guard context.sessionRestorationUnavailable, !context.isAuthenticated else { return nil }
        return context.restorationSignInRequested ? .authentication : .sessionRestorationRecovery
    }
}

private struct GuestDiscardHandler: AuthenticationFlowHandler {
    func destination(for context: AuthenticationFlowContext) -> AuthenticationFlowDestination? {
        context.isGuestMode && context.guestDiscardNeedsAttention ? .guestDiscardRecovery : nil
    }
}

private struct AccountRecoveryHandler: AuthenticationFlowHandler {
    func destination(for context: AuthenticationFlowContext) -> AuthenticationFlowDestination? {
        context.isAuthenticated && context.accountPreparationFailed ? .accountRecovery : nil
    }
}

private struct GuestSignInRequestHandler: AuthenticationFlowHandler {
    func destination(for context: AuthenticationFlowContext) -> AuthenticationFlowDestination? {
        context.guestSignInRequested && !context.isAuthenticated ? .guestSignIn : nil
    }
}

private struct GuestRecoveryHandler: AuthenticationFlowHandler {
    func destination(for context: AuthenticationFlowContext) -> AuthenticationFlowDestination? {
        guard context.isGuestMode, context.guestImportNeedsSignIn else { return nil }
        return .guestRecovery(needsSignIn: true)
    }
}

private struct GuestImportHandler: AuthenticationFlowHandler {
    func destination(for context: AuthenticationFlowContext) -> AuthenticationFlowDestination? {
        guard context.hasPendingGuestImport else { return nil }
        guard context.isAuthenticated, !context.guestImportNeedsSignIn else {
            return .guestRecovery(needsSignIn: true)
        }
        return context.guestPreparationFailed
            ? .guestRecovery(needsSignIn: false)
            : .guestImporting
    }
}

private struct SharedBlueprintHandler: AuthenticationFlowHandler {
    func destination(for context: AuthenticationFlowContext) -> AuthenticationFlowDestination? {
        guard let token = context.pendingSharedBlueprintToken else { return nil }
        guard context.isAuthenticated else { return .sharedBlueprintAuthentication }
        guard context.preparedIdentityMatches else { return .sharedBlueprintLoading }
        return .sharedBlueprintPreview(token: token)
    }
}

private struct InvitationHandler: AuthenticationFlowHandler {
    func destination(for context: AuthenticationFlowContext) -> AuthenticationFlowDestination? {
        guard let token = context.pendingInvitationToken else { return nil }
        if context.invitationRequiresAuthentication && !context.isAuthenticated {
            return .invitationAuthentication
        }
        if context.isGuestMode, !context.preparedIdentityMatches {
            return context.guestPreparationFailed
                ? .invitationRecovery(needsSignIn: false)
                : .invitationLoading
        }
        if context.isAuthenticated, !context.preparedIdentityMatches {
            return .invitationLoading
        }
        return .invitation(token: token)
    }
}

private struct GuestModeHandler: AuthenticationFlowHandler {
    func destination(for context: AuthenticationFlowContext) -> AuthenticationFlowDestination? {
        guard context.isGuestMode else { return nil }
        guard context.preparedIdentityMatches else {
            return context.guestPreparationFailed
                ? .guestRecovery(needsSignIn: false)
                : .guestLoading
        }
        return .app
    }
}

private struct SignedOutHandler: AuthenticationFlowHandler {
    func destination(for context: AuthenticationFlowContext) -> AuthenticationFlowDestination? {
        context.isAuthenticated || context.isGuestMode ? nil : .authentication
    }
}

private struct AccountPreparationHandler: AuthenticationFlowHandler {
    func destination(for context: AuthenticationFlowContext) -> AuthenticationFlowDestination? {
        context.isAuthenticated && !context.preparedIdentityMatches ? .accountLoading : nil
    }
}

private struct InvitationArrivalHandler: AuthenticationFlowHandler {
    func destination(for context: AuthenticationFlowContext) -> AuthenticationFlowDestination? {
        guard context.hasGuestInvitations || context.didJoinInvitationThisSession else { return nil }
        return .app
    }
}

private struct OnboardingHandler: AuthenticationFlowHandler {
    func destination(for context: AuthenticationFlowContext) -> AuthenticationFlowDestination? {
        // The remote experience checks attendance loading/failure before
        // deciding onboarding from the current account's bootstrap. Keep the
        // explicit QA override, but do not bypass those checks in normal use.
        guard !context.usesRemoteAccountState || context.alwaysShowsOnboarding else { return nil }
        guard !context.completedOnboardingThisSession,
              context.alwaysShowsOnboarding || context.accountOnboardingState == .needsOnboarding else {
            return nil
        }
        return .onboarding
    }
}

private struct RemoteAccountHandler: AuthenticationFlowHandler {
    func destination(for context: AuthenticationFlowContext) -> AuthenticationFlowDestination? {
        context.usesRemoteAccountState ? .remoteAccount : nil
    }
}

private struct AppHandler: AuthenticationFlowHandler {
    func destination(for context: AuthenticationFlowContext) -> AuthenticationFlowDestination? {
        guard context.preparedIdentityMatches,
              context.isAuthenticated || context.isGuestMode else { return nil }
        return .app
    }
}
