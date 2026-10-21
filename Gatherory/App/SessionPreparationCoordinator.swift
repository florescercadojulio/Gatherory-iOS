import Foundation
import Observation

enum SessionPreparationIdentity: Equatable, Sendable {
    case signedOut
    case guest(UUID)
    case account(String)
}

struct SessionPreparationRequest: Equatable, Sendable {
    let account: UserAccount?
    let guestProfile: LocalGuestProfile?

    var identity: SessionPreparationIdentity {
        if let account { return .account(account.id) }
        if let guestProfile { return .guest(guestProfile.id) }
        return .signedOut
    }

}

enum SessionPreparationRecovery: Equatable, Sendable {
    case retry
    case originalAccountRequired
}

enum SessionPreparationPhase: Equatable, Sendable {
    case idle
    case preparing(SessionPreparationIdentity)
    case ready(SessionPreparationIdentity)
    case recovery(SessionPreparationIdentity, SessionPreparationRecovery)
}

/// Effects run in order, separately from the pure screen-routing chain. The
/// guest transfer keeps its own durable import/claim/cleanup boundaries.
@MainActor protocol SessionPreparationServices {
    func detachNotifications() async
    func activatePlanning(for request: SessionPreparationRequest) async
    func finishPlanningActivation(for request: SessionPreparationRequest) throws
    func activateGuest(_ profile: LocalGuestProfile) async throws
    func transferGuest(_ profile: LocalGuestProfile, into account: UserAccount,
                       validate: @MainActor () throws -> Void) async throws
    func activateAccountInvitations(_ account: UserAccount?) async
    func bindNotifications() async
}

@Observable @MainActor
final class SessionPreparationCoordinator {
    private(set) var phase: SessionPreparationPhase = .idle
    @ObservationIgnored private var generation: UInt64 = 0

    func isReady(for identity: SessionPreparationIdentity) -> Bool { phase == .ready(identity) }

    func recovery(for identity: SessionPreparationIdentity) -> SessionPreparationRecovery? {
        guard case .recovery(let failedIdentity, let reason) = phase, failedIdentity == identity else { return nil }
        return reason
    }

    func prepare(_ request: SessionPreparationRequest, using services: any SessionPreparationServices,
                 isCurrent: @escaping @MainActor () -> Bool) async {
        guard !Task.isCancelled, isCurrent() else { return }
        generation &+= 1
        let expected = generation
        phase = .preparing(request.identity)
        let validate: @MainActor () throws -> Void = { [self] in
            try Task.checkCancellation()
            guard generation == expected, isCurrent() else { throw CancellationError() }
        }
        do {
            await services.detachNotifications()
            try validate()
            await services.activatePlanning(for: request)
            try validate()
            try services.finishPlanningActivation(for: request)
            if let profile = request.guestProfile {
                if let account = request.account {
                    try await services.transferGuest(profile, into: account, validate: validate)
                } else {
                    try await services.activateGuest(profile)
                }
                try validate()
            }
            if request.account != nil || request.guestProfile == nil {
                await services.activateAccountInvitations(request.account)
                try validate()
            }
            // Notification activation can deliver a pending tap. Mark the
            // fully prepared scope ready before enabling that callback.
            phase = .ready(request.identity)
            await services.bindNotifications()
            try validate()
        } catch is CancellationError {
            // A newer preparation owns its phase; an older completion must
            // never overwrite readiness or recovery for that generation.
            if generation == expected { phase = .idle }
        } catch {
            guard generation == expected, isCurrent(), !Task.isCancelled else { return }
            let reason: SessionPreparationRecovery =
                error as? LocalGuestWorkspacePersistenceError == .guestAlreadyImportedIntoDifferentAccount
                ? .originalAccountRequired : .retry
            phase = .recovery(request.identity, reason)
        }
    }
}

@MainActor struct LiveSessionPreparationServices: SessionPreparationServices {
    let authentication: AuthenticationSession
    let library: WorkspaceLibrary
    let cloudSync: WorkspaceCloudSyncController
    let persistence: WorkspacePersistenceController
    let guestInvitations: GuestInvitationStore
    let notifications: NotificationController
    var usesRemoteAccountState = AppRuntimeConfiguration.usesRemoteAccountState
    var seedsDevelopmentData = AppRuntimeConfiguration.seedsDevelopmentData
    var baseURL = AppRuntimeConfiguration.authenticationBaseURL
    var claimGuestAttendance: ((LocalGuestProfile) async throws -> Void)? = nil

    func detachNotifications() async { await notifications.activate(identity: nil) }

    func activatePlanning(for request: SessionPreparationRequest) async {
        await cloudSync.activate(userID: request.account?.id, seedData: seedsDevelopmentData && request.guestProfile == nil)
    }

    func finishPlanningActivation(for request: SessionPreparationRequest) throws {
        // Guest activation retries its own durable flush/reload below. A prior
        // guest storage failure must not prevent that retry from running.
        if request.account != nil, let error = persistence.lastError { throw error }
        library.configureViewer(request.account)
        if request.account == nil, request.guestProfile == nil {
            persistence.activate(userID: nil, in: library, seedData: false)
        }
    }

    func activateGuest(_ profile: LocalGuestProfile) async throws {
        let hasImportReceipt = try persistence.guestImportAccountID(profile) != nil
        if profile.handoverCleanupAccountID != nil || hasImportReceipt {
            // The retained source must not diverge from its account-owned copy.
            throw LocalGuestWorkspacePersistenceError.guestAlreadyImportedIntoDifferentAccount
        }
        try persistence.activateLocalGuest(profile, in: library)
        await guestInvitations.activate(localGuest: profile)
    }

    func transferGuest(_ profile: LocalGuestProfile, into account: UserAccount,
                       validate: @MainActor () throws -> Void) async throws {
        try validate()
        let cleanupAlreadyAuthorized: Bool
        if profile.handoverCleanupAccountID != nil {
            guard profile.handoverCleanupAccountID == account.id,
                  authentication.guestHandoverIsReadyForCleanup(profileID: profile.id, accountID: account.id) else {
                throw LocalGuestWorkspacePersistenceError.guestAlreadyImportedIntoDifferentAccount
            }
            cleanupAlreadyAuthorized = true
        } else {
            cleanupAlreadyAuthorized = false
        }
        if !cleanupAlreadyAuthorized {
            try validate()
            if usesRemoteAccountState {
                switch cloudSync.accountOnboardingState {
                case .complete, .needsOnboarding: break
                default: throw AuthenticationFailure.guestDataUnavailable
                }
            }
            _ = try persistence.importLocalGuest(profile, into: account, in: library)
            if usesRemoteAccountState {
                try validate()
                if let claimGuestAttendance {
                    try await claimGuestAttendance(profile)
                } else {
                    guard let baseURL else { throw AuthenticationFailure.guestDataUnavailable }
                    _ = try await DeviceGuestInvitationClient(baseURL: baseURL, profile: profile).claim()
                }
            }
            try validate()
            try authentication.markGuestHandoverReadyForCleanup(profileID: profile.id, accountID: account.id)
        }
        try validate()
        try guestInvitations.purgeCache(profileID: profile.id)
        try persistence.discardLocalGuest(profile, in: library)
        try authentication.completeGuestImport()
        if !library.workspaces.isEmpty { cloudSync.markOnboardingCompletedLocally() }
        cloudSync.schedule(trigger: .mutationCreated)
    }

    func activateAccountInvitations(_ account: UserAccount?) async {
        await guestInvitations.activate(account: usesRemoteAccountState ? account : nil)
    }

    func bindNotifications() async {
        await notifications.activate(identity: authentication.notificationPrincipal)
    }
}
