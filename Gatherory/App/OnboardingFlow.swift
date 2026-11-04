import Foundation

/// Selects the onboarding presentation only after the authentication chain has
/// resolved all recovery, invitation, and account preparation destinations.
enum OnboardingExperience: String, CaseIterable, Sendable {
    case classic
    case movieNight
}

enum OnboardingExperienceSelection {
    static func resolve(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        catalogAvailable: Bool = true
    ) -> OnboardingExperience {
        // QA can always compare the preserved onboarding flow.
        if arguments.contains("-ClassicOnboarding") { return .classic }
        // The lesson is bundled; catalog/network availability never changes
        // which first-run experience the account is offered.
        return .movieNight
    }
}

/// A transient request to replay the real launch onboarding from Account.
/// This is deliberately separate from account onboarding completion state.
enum DeveloperOnboardingReplayPolicy {
    static let accessibilityIdentifier = "account.developer.redoOnboarding"

    enum Destination {
        case app
        case completeRemoteAccount
        case unresolvedRemoteAccount
        case unsafe
    }

    static func isAvailable(
        isDebugBuild: Bool,
        environment: AppRuntimeConfiguration.Environment
    ) -> Bool {
        isDebugBuild && environment == .development
    }

    static func shouldAccept(
        requestedAccountID: String?,
        currentAccountID: String?,
        isAuthenticated: Bool,
        isGuest: Bool,
        isSessionReady: Bool,
        hasBlockingRecovery: Bool,
        hasPendingGuestImport: Bool,
        hasPendingInvitation: Bool,
        invitationRequiresAuthentication: Bool,
        hasPendingSharedBlueprint: Bool,
        destination: Destination,
        isDebugBuild: Bool,
        environment: AppRuntimeConfiguration.Environment
    ) -> Bool {
        guard isAvailable(isDebugBuild: isDebugBuild, environment: environment),
              let requestedAccountID, !requestedAccountID.isEmpty,
              let currentAccountID, !currentAccountID.isEmpty,
              requestedAccountID == currentAccountID,
              isAuthenticated, !isGuest, isSessionReady,
              !hasBlockingRecovery, !hasPendingGuestImport,
              !hasPendingInvitation, !invitationRequiresAuthentication,
              !hasPendingSharedBlueprint else { return false }

        switch destination {
        case .app, .completeRemoteAccount:
            return true
        case .unresolvedRemoteAccount, .unsafe:
            return false
        }
    }

    static func isActive(
        requestedAccountID: String?,
        currentAccountID: String?,
        isAuthenticated: Bool,
        isGuest: Bool,
        isSessionReady: Bool,
        isDebugBuild: Bool,
        environment: AppRuntimeConfiguration.Environment
    ) -> Bool {
        guard isAvailable(isDebugBuild: isDebugBuild, environment: environment),
              let requestedAccountID, !requestedAccountID.isEmpty,
              let currentAccountID, !currentAccountID.isEmpty,
              isAuthenticated, !isGuest, isSessionReady else { return false }
        return requestedAccountID == currentAccountID
    }
}

enum DeveloperOnboardingReplayRequest {
    static let notificationName = Notification.Name("developerOnboardingReplayRequested")

    static func post(
        accountID: String,
        environment: AppRuntimeConfiguration.Environment,
        center: NotificationCenter = .default
    ) {
#if DEBUG
        guard DeveloperOnboardingReplayPolicy.isAvailable(isDebugBuild: true, environment: environment),
              !accountID.isEmpty else { return }
        center.post(name: notificationName, object: nil, userInfo: ["accountID": accountID])
#endif
    }
}

enum MovieNightTourStep: String, Codable, Sendable {
    case previewUsed
    case ideas
    case loveIt
    case approve
    case schedule
    case completed
}

/// Durable, account-bound progress for the Movie Night tour. It intentionally
/// stores no event, decision, vote, or blueprint content.
struct MovieNightTourProgress: Codable, Equatable, Sendable {
    var installedWorkspaceID: UUID
    var step: MovieNightTourStep
    var snackIdeaID: UUID? = nil
    var eventIdeaID: UUID? = nil
}

struct MovieNightTourStore {
    private let defaults: UserDefaults
    private let keyPrefix = "movieNightTourProgress."

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func progress(accountID: String) -> MovieNightTourProgress? {
        guard !accountID.isEmpty,
              let data = defaults.data(forKey: key(for: accountID)) else { return nil }
        return try? JSONDecoder().decode(MovieNightTourProgress.self, from: data)
    }

    func recordPreviewUsed(
        accountID: String,
        installedWorkspaceID: UUID,
        snackIdeaID: UUID? = nil,
        eventIdeaID: UUID? = nil
    ) {
        guard !accountID.isEmpty else { return }
        // A later callback cannot silently retarget a tutorial that was
        // already bound to another installed workspace (or reset completion).
        guard progress(accountID: accountID) == nil else { return }
        save(MovieNightTourProgress(
            installedWorkspaceID: installedWorkspaceID,
            step: .previewUsed,
            snackIdeaID: snackIdeaID,
            eventIdeaID: eventIdeaID
        ), accountID: accountID)
    }

    func advance(accountID: String, to step: MovieNightTourStep) {
        guard !accountID.isEmpty,
              var current = progress(accountID: accountID),
              current.step != .completed else { return }
        current.step = step
        save(current, accountID: accountID)
    }

    /// Only an explicit Start/Redo action may replace or restart a lesson.
    func restart(accountID: String, installedWorkspaceID: UUID, snackIdeaID: UUID, eventIdeaID: UUID) {
        guard !accountID.isEmpty else { return }
        save(MovieNightTourProgress(installedWorkspaceID: installedWorkspaceID, step: .previewUsed,
                                   snackIdeaID: snackIdeaID, eventIdeaID: eventIdeaID), accountID: accountID)
        NotificationCenter.default.post(name: .movieNightTourDidRestart, object: nil,
                                        userInfo: ["accountID": accountID, "workspaceID": installedWorkspaceID])
    }

    func clear(accountID: String) {
        guard !accountID.isEmpty else { return }
        defaults.removeObject(forKey: key(for: accountID))
    }

    private func save(_ progress: MovieNightTourProgress, accountID: String) {
        guard let data = try? JSONEncoder().encode(progress) else { return }
        defaults.set(data, forKey: key(for: accountID))
    }

    private func key(for accountID: String) -> String { keyPrefix + accountID }
}

extension Notification.Name {
    static let movieNightTourDidRestart = Notification.Name("movieNightTourDidRestart")
}
