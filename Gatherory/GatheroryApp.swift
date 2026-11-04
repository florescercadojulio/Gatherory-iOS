//
//  GatheroryApp.swift
//  Gatherory
//
//  Created by Julio C on 10/7/26.
//

import GoogleSignIn
import PostHog
import SwiftUI
import SwiftData

@main
@MainActor
struct GatheroryApp: App {
    @UIApplicationDelegateAdaptor(GatheroryNotificationAppDelegate.self) private var notificationAppDelegate
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var systemColorScheme
    @State private var authentication: AuthenticationSession
    @State private var workspaceLibrary: WorkspaceLibrary
    @State private var cloudSync: WorkspaceCloudSyncController
    @State private var connectionStatus: AppConnectionStatus
    @State private var invitations = InvitationRouter(baseURL: AppRuntimeConfiguration.authenticationBaseURL)
    @State private var sharedBlueprintLinks = BlueprintSharedTemplateRouter(baseURL: AppRuntimeConfiguration.authenticationBaseURL)
    @State private var guestInvitations = GuestInvitationStore(baseURL: AppRuntimeConfiguration.authenticationBaseURL)
    @State private var musicCatalog = MusicCatalog()
    @State private var musicPreviewPlayer = MusicPreviewPlayer()
    @State private var imageSafety = ImageSafetyStore()
    @State private var notifications: NotificationController
    @AppStorage(AppAppearance.storageKey) private var appearance = AppAppearance.system.rawValue
    @AppStorage(AppColorThemeChoice.storageKey) private var colorTheme = AppColorThemeChoice.gatheroryBlue.rawValue

    private let persistence: WorkspacePersistenceController

    init() {
        Self.configurePostHog()

        let authentication = AuthenticationSession.bootstrap()
        let notifications = NotificationController(baseURL: AppRuntimeConfiguration.authenticationBaseURL)
        let persistence = WorkspacePersistenceController.bootstrap(
            isStoredInMemoryOnly: AppRuntimeConfiguration.usesEphemeralDataStore
        )
        #if DEBUG
        let usesBudgetConflictUITestFixture = BudgetConflictUITestFixtures.isEnabled
        #else
        let usesBudgetConflictUITestFixture = false
        #endif
        let library = persistence.restoreLibrary(
            seedData: AppRuntimeConfiguration.seedsDevelopmentData
                && !authentication.deletionCleanup.blocksEntry
                && !usesBudgetConflictUITestFixture,
            ownerUserID: authentication.deletionCleanup.blocksEntry ? nil : authentication.currentUser?.id
        )
        #if DEBUG
        if usesBudgetConflictUITestFixture {
            guard let owner = authentication.currentUser else {
                fatalError("Budget conflict UI fixture requires -SkipAuthentication.")
            }
            do {
                try BudgetConflictUITestFixtures.install(
                    persistence: persistence, library: library, owner: owner
                )
            } catch {
                fatalError("Could not install budget conflict UI fixture: \(error)")
            }
        }
        #endif
        #if DEBUG
        // Explicit, isolated UI harness only. Never reset a real account's tour.
        if ProcessInfo.processInfo.arguments.contains("-ResetMovieNightTourUITestState"),
           AppRuntimeConfiguration.environment == .development,
           AppRuntimeConfiguration.skipsAuthentication,
           AppRuntimeConfiguration.usesEphemeralDataStore,
           let accountID = authentication.currentUser?.id {
            MovieNightTourStore().clear(accountID: accountID)
            MovieNightTourDiscoveryStore().clear(accountID: accountID)
            ContextualPrimerStore().reset(accountID: accountID)
        }
        #endif
        let syncBaseURL = usesBudgetConflictUITestFixture ? nil : AppRuntimeConfiguration.authenticationBaseURL

        _authentication = State(initialValue: authentication)
        _notifications = State(initialValue: notifications)
        GatheroryNotificationAppDelegate.controller = notifications
        self.persistence = persistence
        _workspaceLibrary = State(initialValue: library)
        _cloudSync = State(
            initialValue: WorkspaceCloudSyncController(
                persistence: persistence,
                library: library,
                baseURL: syncBaseURL
            )
        )
        _connectionStatus = State(initialValue: AppConnectionStatus.bootstrap())
    }

    private static func configurePostHog() {
        guard AppRuntimeConfiguration.postHogEnabled else { return }
        guard let projectToken = AppRuntimeConfiguration.postHogProjectToken else {
#if DEBUG
            assertionFailure("POSTHOG_PROJECT_TOKEN variable required by PostHog is missing or un-configured, this causes events to be silently missed. This error stops appearing once POSTHOG_PROJECT_TOKEN is configured")
#endif
            return
        }

        guard let host = AppRuntimeConfiguration.postHogHost else {
#if DEBUG
            assertionFailure("POSTHOG_HOST variable required by PostHog is missing or un-configured, this causes events to be silently missed. This error stops appearing once POSTHOG_HOST is configured")
#endif
            return
        }

        let config = PostHogConfig(projectToken: projectToken, host: host)
        config.errorTrackingConfig.autoCapture = true
        config.logs.serviceName = "gatherory-ios"
        config.logs.environment = AppRuntimeConfiguration.environment.rawValue
        PostHogSDK.shared.setup(config)
    }

    private var selectedColorTheme: AppColorThemeChoice {
        AppColorThemeChoice(rawValue: colorTheme) ?? .gatheroryBlue
    }

    private var selectedAppearance: AppAppearance {
        AppAppearance(rawValue: appearance) ?? .system
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if persistence.lastError == nil || authentication.deletionCleanup.blocksEntry {
                    GatheroryLaunchContainer()
                } else {
                    LocalDataStoreFailureView()
                }
            }
            .environment(authentication)
            .environment(\.currentUserAccount, authentication.currentUser)
            .environment(workspaceLibrary)
            .environment(musicCatalog)
            .environment(musicPreviewPlayer)
            .environment(persistence)
            .environment(cloudSync)
            .environment(connectionStatus)
            .environment(invitations)
            .environment(sharedBlueprintLinks)
            .environment(guestInvitations)
            .environment(imageSafety)
            .environment(notifications)
            .appUserAppearance(selectedAppearance)
            .environment(
                \.appContentColorScheme,
                selectedAppearance.resolvedColorScheme(systemColorScheme: systemColorScheme)
            )
            .appColorTheme(selectedColorTheme)
            .modelContainer(persistence.container)
            .task {
                persistence.startObserving(workspaceLibrary)
            }
            .task(id: authentication.currentUser?.id) {
                imageSafety.configure(accountID: authentication.currentUser?.id)
                await imageSafety.refresh()
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    Task { await imageSafety.refresh() }
                    cloudSync.schedule(trigger: .appBecameActive)
                    Task { await guestInvitations.refresh() }
                    Task {
                        await musicCatalog.refreshAuthorizationStates()
                    }
                } else {
                    musicPreviewPlayer.pause()
                    persistence.flush(workspaceLibrary)
                }
            }
            .onOpenURL { url in
                if !invitations.receive(url), !sharedBlueprintLinks.receive(url) {
                    GIDSignIn.sharedInstance.handle(url)
                }
            }
            .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                if let url = activity.webpageURL,
                   !invitations.receive(url) {
                    _ = sharedBlueprintLinks.receive(url)
                }
            }
        }
    }
}

private struct LocalDataStoreFailureView: View {
    var body: some View {
        ContentUnavailableView {
            Label("Local Data Unavailable", systemImage: "externaldrive.badge.exclamationmark")
        } description: {
            Text(
                "Gatherory couldn’t safely open its local data. Your existing data hasn’t been replaced. Close and reopen the app. If this continues, contact support."
            )
        }
        .padding()
        .accessibilityElement(children: .combine)
    }
}
