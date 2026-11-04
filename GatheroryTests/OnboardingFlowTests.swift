import Foundation
import Testing
@testable import Gatherory

private final class OnboardingReplayNotificationRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var accountIDs: [String] = []

    func append(_ accountID: String) {
        lock.lock()
        accountIDs.append(accountID)
        lock.unlock()
    }

    func recordedAccountIDs() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return accountIDs
    }
}

@MainActor
struct OnboardingFlowTests {
    @Test("Movie Night is the default, with a classic QA override and no catalog dependency")
    func selectionPolicy() {
        #expect(OnboardingExperienceSelection.resolve(arguments: []) == .movieNight)
        #expect(OnboardingExperienceSelection.resolve(arguments: ["-ClassicOnboarding"]) == .classic)
        #expect(OnboardingExperienceSelection.resolve(arguments: [], catalogAvailable: false) == .movieNight)
        #expect(OnboardingExperienceSelection.resolve(
            arguments: ["-ClassicOnboarding"], catalogAvailable: false
        ) == .classic)
    }

    @Test("Developer onboarding replay is available only in Debug development builds")
    func developerReplayAvailability() {
        #expect(DeveloperOnboardingReplayPolicy.isAvailable(isDebugBuild: true, environment: .development))
        #expect(!DeveloperOnboardingReplayPolicy.isAvailable(isDebugBuild: false, environment: .development))
        #expect(!DeveloperOnboardingReplayPolicy.isAvailable(isDebugBuild: true, environment: .staging))
        #expect(!DeveloperOnboardingReplayPolicy.isAvailable(isDebugBuild: true, environment: .production))
        #expect(DeveloperOnboardingReplayPolicy.accessibilityIdentifier == "account.developer.redoOnboarding")
    }

    @Test("Developer tools follow configured APP_ENVIRONMENT even when auth flow is simulated as production")
    func developerToolsEnvironmentUsesConfiguredValue() {
        // Simulated production affects runtime routing, but is not consulted by this parser.
        let configuredDevelopment = AppRuntimeConfiguration.developerToolsEnvironment(configuredValue: "development")
        #expect(configuredDevelopment == .development)
        #expect(DeveloperOnboardingReplayPolicy.isAvailable(
            isDebugBuild: true,
            environment: configuredDevelopment
        ))

        #expect(AppRuntimeConfiguration.developerToolsEnvironment(configuredValue: "staging") == .staging)
        #expect(!DeveloperOnboardingReplayPolicy.isAvailable(
            isDebugBuild: true,
            environment: AppRuntimeConfiguration.developerToolsEnvironment(configuredValue: "staging")
        ))
        #expect(AppRuntimeConfiguration.developerToolsEnvironment(configuredValue: "production") == .production)
        #expect(!DeveloperOnboardingReplayPolicy.isAvailable(
            isDebugBuild: true,
            environment: AppRuntimeConfiguration.developerToolsEnvironment(configuredValue: "production")
        ))
        #expect(AppRuntimeConfiguration.developerToolsEnvironment(configuredValue: "unknown") == .production)
        #expect(!DeveloperOnboardingReplayPolicy.isAvailable(
            isDebugBuild: true,
            environment: AppRuntimeConfiguration.developerToolsEnvironment(configuredValue: "unknown")
        ))
    }

    @Test("Replay activation requires the same prepared authenticated account")
    func developerReplayActivationRequiresCurrentReadyAccount() {
        #expect(activeReplay())
        #expect(!activeReplay(requestedAccountID: nil, currentAccountID: nil))
        #expect(!activeReplay(requestedAccountID: "", currentAccountID: ""))
        #expect(!activeReplay(requestedAccountID: "account-a", currentAccountID: "account-b"))
        #expect(!activeReplay(isAuthenticated: false))
        #expect(!activeReplay(isGuest: true))
        #expect(!activeReplay(isSessionReady: false))
        #expect(!activeReplay(isDebugBuild: false))
        #expect(!activeReplay(environment: .staging))
        #expect(!activeReplay(environment: .production))
    }

    @Test("Replay accepts only safe completed destinations with no pending recovery or invitation work")
    func developerReplayAcceptancePreservesPrecedence() {
        #expect(acceptedReplay(destination: .app))
        #expect(acceptedReplay(destination: .completeRemoteAccount))
        #expect(!acceptedReplay(destination: .unresolvedRemoteAccount))
        #expect(!acceptedReplay(destination: .unsafe))
        #expect(!acceptedReplay(requestedAccountID: nil, currentAccountID: nil))
        #expect(!acceptedReplay(requestedAccountID: "account-a", currentAccountID: "account-b"))
        #expect(!acceptedReplay(isAuthenticated: false))
        #expect(!acceptedReplay(isGuest: true))
        #expect(!acceptedReplay(isSessionReady: false))
        #expect(!acceptedReplay(hasBlockingRecovery: true))
        #expect(!acceptedReplay(hasPendingGuestImport: true))
        #expect(!acceptedReplay(hasPendingInvitation: true))
        #expect(!acceptedReplay(invitationRequiresAuthentication: true))
        #expect(!acceptedReplay(hasPendingSharedBlueprint: true))
        #expect(!acceptedReplay(isDebugBuild: false))
        #expect(!acceptedReplay(environment: .staging))
        #expect(!acceptedReplay(environment: .production))
    }

    @Test("Developer replay request is development-only and targets one nonempty account")
    func developerReplayRequestIsGatedAndAccountScoped() {
        let center = NotificationCenter()
        let recorder = OnboardingReplayNotificationRecorder()
        let observer = center.addObserver(
            forName: DeveloperOnboardingReplayRequest.notificationName,
            object: nil,
            queue: nil
        ) { notification in
            if let accountID = notification.userInfo?["accountID"] as? String {
                recorder.append(accountID)
            }
        }
        defer { center.removeObserver(observer) }

        DeveloperOnboardingReplayRequest.post(accountID: "account-a", environment: .development, center: center)
        DeveloperOnboardingReplayRequest.post(accountID: "account-b", environment: .development, center: center)
        DeveloperOnboardingReplayRequest.post(accountID: "account-c", environment: .production, center: center)
        DeveloperOnboardingReplayRequest.post(accountID: "", environment: .development, center: center)

#if DEBUG
        #expect(recorder.recordedAccountIDs() == ["account-a", "account-b"])
#else
        #expect(recorder.recordedAccountIDs().isEmpty)
#endif
    }

    private func activeReplay(
        requestedAccountID: String? = "account-a",
        currentAccountID: String? = "account-a",
        isAuthenticated: Bool = true,
        isGuest: Bool = false,
        isSessionReady: Bool = true,
        isDebugBuild: Bool = true,
        environment: AppRuntimeConfiguration.Environment = .development
    ) -> Bool {
        DeveloperOnboardingReplayPolicy.isActive(
            requestedAccountID: requestedAccountID,
            currentAccountID: currentAccountID,
            isAuthenticated: isAuthenticated,
            isGuest: isGuest,
            isSessionReady: isSessionReady,
            isDebugBuild: isDebugBuild,
            environment: environment
        )
    }

    private func acceptedReplay(
        requestedAccountID: String? = "account-a",
        currentAccountID: String? = "account-a",
        isAuthenticated: Bool = true,
        isGuest: Bool = false,
        isSessionReady: Bool = true,
        hasBlockingRecovery: Bool = false,
        hasPendingGuestImport: Bool = false,
        hasPendingInvitation: Bool = false,
        invitationRequiresAuthentication: Bool = false,
        hasPendingSharedBlueprint: Bool = false,
        destination: DeveloperOnboardingReplayPolicy.Destination = .app,
        isDebugBuild: Bool = true,
        environment: AppRuntimeConfiguration.Environment = .development
    ) -> Bool {
        DeveloperOnboardingReplayPolicy.shouldAccept(
            requestedAccountID: requestedAccountID,
            currentAccountID: currentAccountID,
            isAuthenticated: isAuthenticated,
            isGuest: isGuest,
            isSessionReady: isSessionReady,
            hasBlockingRecovery: hasBlockingRecovery,
            hasPendingGuestImport: hasPendingGuestImport,
            hasPendingInvitation: hasPendingInvitation,
            invitationRequiresAuthentication: invitationRequiresAuthentication,
            hasPendingSharedBlueprint: hasPendingSharedBlueprint,
            destination: destination,
            isDebugBuild: isDebugBuild,
            environment: environment
        )
    }

    @Test("Movie Night progress resumes per account with the installed workspace")
    func accountBoundProgress() throws {
        let suiteName = "MovieNightTourStoreTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = MovieNightTourStore(defaults: defaults)
        let workspaceID = UUID()
        let snackIdeaID = UUID()
        let eventIdeaID = UUID()

        #expect(store.progress(accountID: "account-a") == nil)
        store.recordPreviewUsed(
            accountID: "account-a",
            installedWorkspaceID: workspaceID,
            snackIdeaID: snackIdeaID,
            eventIdeaID: eventIdeaID
        )
        #expect(store.progress(accountID: "account-a") == MovieNightTourProgress(
            installedWorkspaceID: workspaceID,
            step: .previewUsed,
            snackIdeaID: snackIdeaID,
            eventIdeaID: eventIdeaID
        ))
        #expect(store.progress(accountID: "account-b") == nil)
        store.recordPreviewUsed(accountID: "account-a", installedWorkspaceID: UUID())
        #expect(store.progress(accountID: "account-a")?.installedWorkspaceID == workspaceID)

        // Recreating the store models an app relaunch after onboarding completed.
        let relaunchedStore = MovieNightTourStore(defaults: defaults)
        #expect(relaunchedStore.progress(accountID: "account-a")?.installedWorkspaceID == workspaceID)
        #expect(relaunchedStore.progress(accountID: "account-a")?.snackIdeaID == snackIdeaID)
        #expect(relaunchedStore.progress(accountID: "account-a")?.eventIdeaID == eventIdeaID)
        relaunchedStore.advance(accountID: "account-a", to: .ideas)
        #expect(relaunchedStore.progress(accountID: "account-a")?.step == .ideas)
        relaunchedStore.advance(accountID: "account-a", to: .completed)
        relaunchedStore.recordPreviewUsed(accountID: "account-a", installedWorkspaceID: UUID())
        #expect(relaunchedStore.progress(accountID: "account-a")?.step == .completed)
        #expect(relaunchedStore.progress(accountID: "account-a")?.installedWorkspaceID == workspaceID)
        relaunchedStore.advance(accountID: "account-a", to: .ideas)
        #expect(relaunchedStore.progress(accountID: "account-a")?.step == .completed)
        #expect(relaunchedStore.progress(accountID: "account-a")?.snackIdeaID == snackIdeaID)

        relaunchedStore.clear(accountID: "account-a")
        #expect(relaunchedStore.progress(accountID: "account-a") == nil)
        #expect(relaunchedStore.progress(accountID: "account-b") == nil)
    }

    @Test("Only an explicit replay resets completed progress and leaves other accounts alone")
    func explicitReplay() throws {
        let suite = "MovieNightReplay-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = MovieNightTourStore(defaults: defaults)
        store.recordPreviewUsed(accountID: "a", installedWorkspaceID: UUID())
        store.recordPreviewUsed(accountID: "b", installedWorkspaceID: UUID())
        store.advance(accountID: "a", to: .completed)
        let other = store.progress(accountID: "b")
        let replacement = UUID(), snack = UUID(), event = UUID()
        store.restart(accountID: "a", installedWorkspaceID: replacement, snackIdeaID: snack, eventIdeaID: event)
        #expect(store.progress(accountID: "a") == MovieNightTourProgress(
            installedWorkspaceID: replacement, step: .previewUsed, snackIdeaID: snack, eventIdeaID: event))
        #expect(store.progress(accountID: "b") == other)
    }

    @Test("An invalid persisted tour value fails closed")
    func invalidProgressFailsClosed() throws {
        let suiteName = "MovieNightTourStoreInvalidTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(Data("invalid".utf8), forKey: "movieNightTourProgress.account-a")

        #expect(MovieNightTourStore(defaults: defaults).progress(accountID: "account-a") == nil)
    }

    @Test("Older tour progress without target idea IDs still decodes")
    func backwardCompatibleProgressDecoding() throws {
        let workspaceID = UUID()
        let legacy = "{\"installedWorkspaceID\":\"\(workspaceID.uuidString)\",\"step\":\"previewUsed\"}"
        let decoded = try JSONDecoder().decode(MovieNightTourProgress.self, from: Data(legacy.utf8))

        #expect(decoded.installedWorkspaceID == workspaceID)
        #expect(decoded.step == .previewUsed)
        #expect(decoded.snackIdeaID == nil)
        #expect(decoded.eventIdeaID == nil)
    }
}
