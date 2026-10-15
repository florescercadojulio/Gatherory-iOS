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
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var systemColorScheme
    @State private var authentication: AuthenticationSession
    @State private var workspaceLibrary: WorkspaceLibrary
    @State private var cloudSync: WorkspaceCloudSyncController
    @State private var invitations = InvitationRouter(baseURL: AppRuntimeConfiguration.authenticationBaseURL)
    @State private var sharedBlueprintLinks = BlueprintSharedTemplateRouter(baseURL: AppRuntimeConfiguration.authenticationBaseURL)
    @State private var guestInvitations = GuestInvitationStore(baseURL: AppRuntimeConfiguration.authenticationBaseURL)
    @State private var musicCatalog = MusicCatalog()
    @State private var musicPreviewPlayer = MusicPreviewPlayer()
    @State private var imageSafety = ImageSafetyStore()
    @AppStorage(AppAppearance.storageKey) private var appearance = AppAppearance.system.rawValue
    @AppStorage(AppColorThemeChoice.storageKey) private var colorTheme = AppColorThemeChoice.gatheroryBlue.rawValue

    private let persistence: WorkspacePersistenceController

    init() {
        Self.configurePostHog()

        let authentication = AuthenticationSession.bootstrap()
        let persistence = WorkspacePersistenceController.bootstrap(
            isStoredInMemoryOnly: AppRuntimeConfiguration.usesEphemeralDataStore
        )
        let library = persistence.restoreLibrary(
            seedData: AppRuntimeConfiguration.seedsDevelopmentData,
            ownerUserID: authentication.currentUser?.id
        )

        _authentication = State(initialValue: authentication)
        self.persistence = persistence
        _workspaceLibrary = State(initialValue: library)
        _cloudSync = State(
            initialValue: WorkspaceCloudSyncController(
                persistence: persistence,
                library: library,
                baseURL: AppRuntimeConfiguration.authenticationBaseURL
            )
        )
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
                if persistence.lastError == nil {
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
            .environment(invitations)
            .environment(sharedBlueprintLinks)
            .environment(guestInvitations)
            .environment(imageSafety)
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
