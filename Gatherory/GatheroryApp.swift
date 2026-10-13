//
//  GatheroryApp.swift
//  Gatherory
//
//  Created by Julio C on 10/7/26.
//

import GoogleSignIn
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
    @State private var guestInvitations = GuestInvitationStore(baseURL: AppRuntimeConfiguration.authenticationBaseURL)
    @State private var musicCatalog = MusicCatalog()
    @State private var musicPreviewPlayer = MusicPreviewPlayer()
    @AppStorage(AppAppearance.storageKey) private var appearance = AppAppearance.system.rawValue
    @AppStorage(AppColorThemeChoice.storageKey) private var colorTheme = AppColorThemeChoice.gatheroryBlue.rawValue

    private let persistence: WorkspacePersistenceController

    init() {
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
            .environment(guestInvitations)
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
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
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
                if !invitations.receive(url) { GIDSignIn.sharedInstance.handle(url) }
            }
            .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                if let url = activity.webpageURL { _ = invitations.receive(url) }
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
