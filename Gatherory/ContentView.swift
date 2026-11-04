//
//  ContentView.swift
//  Gatherory
//
//  Created by Julio C on 10/7/26.
//

import SwiftUI

private enum LibraryTab: Hashable { case workspaces, blueprints, explore }

private struct BlueprintLibraryCreationRoute: Identifiable {
    let ownerID: String
    var id: String { ownerID }
}

struct AppRootView: View {
    @Environment(AuthenticationSession.self) private var authentication
    @State private var selectedTab = LibraryTab.workspaces
    @State private var isPreviewingBlueprint = false
    @Environment(WorkspaceLibrary.self) private var workspaceLibrary
    @Environment(WorkspacePersistenceController.self) private var persistence
    @Environment(WorkspaceCloudSyncController.self) private var cloudSync
    @Environment(\.currentUserAccount) private var currentUserAccount
    @Environment(GuestInvitationStore.self) private var guests
    @State private var blueprintActions: BlueprintActionStore?
    @State private var blueprintCreation: BlueprintLibraryCreationRoute?
    @State private var blueprintLibraryRefreshID = UUID()
    @State private var resumedTourAccountID: String?
    @State private var discoveryPhase: MovieNightTourDiscoveryPhase?
    @State private var discoveryRevision = 0
    @State private var discoverySaveFailed = false
    @State private var discoveryGeometry = MovieNightTourWindowGeometry()
    private let discoveryStore = MovieNightTourDiscoveryStore()

    private var isPresentingWorkspace: Binding<Bool> {
        Binding(
            get: { !isPreviewingBlueprint && (workspaceLibrary.selectedWorkspace != nil || guests.selectedPresentation != nil) },
            set: { isPresented in
                if !isPresented && !isPreviewingBlueprint {
                    workspaceLibrary.closeWorkspace()
                    guests.selectedEventID = nil
                }
            }
        )
    }

    private var tabSelection: Binding<LibraryTab> {
        Binding(get: { selectedTab }, set: { tab in
            guard selectedTab != tab else { return }
            if discoveryPhase != nil {
                guard tab == .explore else { return }
                discoveryStore.openExplore(accountID: currentUserAccount?.id ?? "")
                discoveryPhase = .chooseMovieNight
            }
            AppHaptics.play(.selection)
            selectedTab = tab
        })
    }

    private var libraryTabs: some View {
        TabView(selection: tabSelection) {
            Tab("Workspaces", systemImage: "rectangle.stack.fill", value: .workspaces) {
                NavigationStack {
                    WorkspaceBrowserView(onExplore: { selectedTab = .explore })
                        .disabled(discoveryPhase != nil)
                        .allowsHitTesting(discoveryPhase == nil)
                        .accessibilityHidden(discoveryPhase != nil)
                        .overlay(alignment: .bottom) { discoveryDialog.padding(16) }
                }
            }
            Tab(BlueprintCopy.libraryTitle, systemImage: "square.stack.3d.up.fill", value: .blueprints) {
                NavigationStack {
                    if authentication.isGuestMode {
                        LocalGuestSignInGate(message: GuestCopy.blueprintHelp)
                    } else {
                        BlueprintLibraryView(
                            ownerID: currentUserAccount?.id ?? "",
                            isActive: selectedTab == .blueprints,
                            actionStore: blueprintActions?.ownerID == currentUserAccount?.id ? blueprintActions : nil,
                            onExplore: { selectedTab = .explore },
                            onCreate: {
                                guard let account = currentUserAccount, !authentication.isGuestMode else { return }
                                blueprintCreation = BlueprintLibraryCreationRoute(ownerID: account.id)
                            }
                        )
                        .id(blueprintLibraryRefreshID)
                    }
                }
                .id(currentUserAccount?.id)
            }
            Tab(ExploreCopy.title, systemImage: "magnifyingglass", value: .explore) {
                NavigationStack {
                    if authentication.isGuestMode {
                        LocalGuestSignInGate(message: GuestCopy.blueprintHelp)
                    } else {
                        BlueprintExploreView(
                            ownerID: currentUserAccount?.id ?? "",
                            isActive: selectedTab == .explore && workspaceLibrary.selectedWorkspace == nil
                                && guests.selectedPresentation == nil,
                            tourSelection: guidedMovieNightSelection
                        )
                        .overlay(alignment: .bottom) { discoveryDialog.padding(16) }
                    }
                }
                .id(currentUserAccount?.id)
            }
        }
    }

    private var guidedMovieNightSelection: (() -> Void)? {
        guard discoveryPhase != nil else { return nil }
        return { selectTourMovieNight() }
    }

    var body: some View {
        libraryTabs
        .environment(\.movieNightTourWindowGeometry, discoveryGeometry)
        .movieNightDiscoveryOverlay(phase: discoveryPhase, windowGeometry: discoveryGeometry)
        .tabViewStyle(.sidebarAdaptable)
        .tabBarMinimizeBehavior(selectedTab == .workspaces || discoveryPhase != nil ? .never : .onScrollDown)
        .tint(AppTheme.ColorToken.accent)
        .environment(\.blueprintPreviewPresented, $isPreviewingBlueprint)
        .sheet(item: $blueprintCreation, onDismiss: { blueprintLibraryRefreshID = UUID() }) { route in
            if currentUserAccount?.id == route.ownerID, !authentication.isGuestMode {
                BlueprintLibraryCreationView(ownerID: route.ownerID) { selectedTab = .workspaces }
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
        }
        .fullScreenCover(isPresented: isPresentingWorkspace) {
            if let eventID = guests.selectedEventID {
                GuestEventInvitationView(eventID: eventID)
            } else if let workspace = workspaceLibrary.selectedWorkspace {
                WorkspaceSessionView(
                    workspace: workspace,
                    account: currentUserAccount,
                    localGuest: authentication.isGuestMode ? authentication.localGuestProfile : nil
                )
            }
        }
        .task(id: currentUserAccount?.id ?? authentication.localGuestProfile?.storageID) {
            if authentication.isGuestMode, let profile = authentication.localGuestProfile {
                workspaceLibrary.configureLocalGuest(profile)
            } else {
                workspaceLibrary.configureViewer(currentUserAccount)
            }
        }
        .task(id: "\(currentUserAccount?.id ?? "")|\(String(describing: cloudSync.accountOnboardingState))") {
#if DEBUG
            if let fixture = BlueprintPreviewActionsVisualFixture.load(ownerID: currentUserAccount?.id ?? "") {
                blueprintActions = fixture.actionStore
                await fixture.prepareActions()
                return
            }
            if BlueprintLibraryVisualFixture.load(ownerID: currentUserAccount?.id ?? "") != nil { return }
#endif
            if let currentUserAccount {
                if let blueprintActions, blueprintActions.ownerID != currentUserAccount.id {
                    blueprintActions.resetForAccountChange()
                    self.blueprintActions = nil
                }
                if self.blueprintActions?.ownerID != currentUserAccount.id,
                   let coordinator = cloudSync.makeBlueprintInstallationCoordinator() {
                    let store = BlueprintActionStore(ownerID: currentUserAccount.id, transport: coordinator)
                    self.blueprintActions = store
                    await store.loadPreferences()
                }
            } else {
                blueprintActions?.resetForAccountChange()
                blueprintActions = nil
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .movieNightTourDiscoveryDidChange)) { notification in
            guard notification.userInfo?["accountID"] as? String == currentUserAccount?.id else { return }
            discoveryRevision += 1
        }
        .task(id: "discovery:\(currentUserAccount?.id ?? ""):\(discoveryRevision)") {
            await Task.yield()
            guard !Task.isCancelled else { return }
            discoveryPhase = discoveryStore.phase(accountID: currentUserAccount?.id ?? "")
            guard let discoveryPhase else { return }
            // Explicit Start/Redo exits an existing event before guiding the
            // person through the actual library tabs.
            workspaceLibrary.closeWorkspace()
            guests.selectedEventID = nil
            selectedTab = discoveryPhase == .chooseExplore ? .workspaces : .explore
        }
        .onChange(of: currentUserAccount?.id) { _, _ in
            discoveryPhase = nil
            discoverySaveFailed = false
            selectedTab = .workspaces
            isPreviewingBlueprint = false
            blueprintCreation = nil
            resumedTourAccountID = nil
        }
        .task(id: "tour:\(currentUserAccount?.id ?? ""):\(workspaceLibrary.workspaces.map { $0.mainEventID.uuidString }.joined(separator: ","))") {
            guard let account = currentUserAccount,
                  resumedTourAccountID != account.id,
                  discoveryStore.phase(accountID: account.id) == nil,
                  !authentication.isGuestMode,
                  let progress = MovieNightTourStore().progress(accountID: account.id),
                  progress.step != .completed,
                  let workspace = workspaceLibrary.workspaces.first(where: { $0.mainEventID == progress.installedWorkspaceID }),
                  !workspace.isMainEventDeleted, !workspace.currentMainEventStatus.isReadOnly,
                  workspace.participants(for: .main).contains(where: {
                      $0.userID == account.id && $0.participantRole == .host && $0.invitationStatus == .active
                  }) else { return }
            resumedTourAccountID = account.id
            guard selectedTab == .workspaces,
                  workspaceLibrary.selectedWorkspace == nil,
                  guests.selectedEventID == nil else { return }
            workspaceLibrary.open(workspace)
        }
    }

    @ViewBuilder
    private var discoveryDialog: some View {
        if let discoveryPhase,
           (selectedTab == .workspaces && discoveryPhase == .chooseExplore)
            || (selectedTab == .explore && discoveryPhase == .chooseMovieNight) {
            MovieNightTourDiscoveryCoach(phase: discoveryPhase, saveFailed: discoverySaveFailed,
                windowGeometry: discoveryGeometry,
                onPrevious: previousDiscoveryStep, onSkip: skipDiscoveryTour)
        }
    }

    private func previousDiscoveryStep() {
        discoveryStore.previous(accountID: currentUserAccount?.id ?? "")
        discoveryPhase = .chooseExplore
        selectedTab = .workspaces
    }

    private func skipDiscoveryTour() {
        guard let accountID = currentUserAccount?.id else { return }
        discoveryStore.clear(accountID: accountID)
        MovieNightTourStore().advance(accountID: accountID, to: .completed)
        discoveryPhase = nil
        discoverySaveFailed = false
        ContextualPrimerStore.announceTourFinished(accountID: accountID)
    }

    private func selectTourMovieNight() {
        guard let account = currentUserAccount, discoveryPhase == .chooseMovieNight else { return }
        do {
            _ = try MovieNightTourDiscoveryCoordinator.selectMovieNight(
                account: account, library: workspaceLibrary, persistence: persistence)
            discoveryPhase = nil
            discoverySaveFailed = false
            selectedTab = .workspaces
        } catch {
            discoverySaveFailed = true
        }
    }

}

private struct WorkspaceSessionView: View {
    @Environment(\.dismiss) private var dismiss
    let workspace: PlanningWorkspace

    init(workspace: PlanningWorkspace, account: UserAccount?, localGuest: LocalGuestProfile?) {
        self.workspace = workspace
        if let localGuest { workspace.configureLocalGuestViewer(localGuest) }
        else { workspace.configureViewer(account) }
    }

    var body: some View {
        ContentView {
            dismiss()
        }
        .environment(workspace)
    }
}

struct ContentView: View {
    @Environment(PlanningWorkspace.self) private var workspace
    @Environment(\.currentUserAccount) private var currentUserAccount
    @Environment(WorkspaceCloudSyncController.self) private var cloudSync: WorkspaceCloudSyncController?
    @Environment(NotificationNavigationState.self) private var notificationNavigation: NotificationNavigationState?
    @Environment(\.scenePhase) private var scenePhase
    var onExitWorkspace: (() -> Void)?
    @State private var selectedTab: WorkspaceTab
    @State private var homeReselectionTrigger = 0
    @State private var notificationTodoDestination: NotificationPlanningDestination?
    @State private var notificationAnnouncementDestination: NotificationPlanningDestination?
    @State private var hasPresentedManagePreview = false
    @State private var ideasTourWindowGeometry = MovieNightTourWindowGeometry()

    init(onExitWorkspace: (() -> Void)? = nil) {
        self.onExitWorkspace = onExitWorkspace
        _selectedTab = State(initialValue: .home)
    }

    private var tabSelection: Binding<WorkspaceTab> {
        Binding(
            get: { selectedTab },
            set: { newValue in
                if newValue != selectedTab { AppHaptics.play(.selection) }
                if newValue == .home, selectedTab == .home {
                    homeReselectionTrigger += 1
                }
                selectedTab = newValue
            }
        )
    }

    var body: some View {
        Group {
            if workspace.showsPlanningInterface {
                planningTabs
            } else {
                NavigationStack {
                    HomeView(onExitWorkspace: onExitWorkspace)
                        .navigationDestination(item: $notificationTodoDestination) { destination in
                            EventManagementView(reference: destination.reference, initialDestination: .tasks)
                                .environment(workspace)
                        }
                }
            }
        }
        .tint(AppTheme.ColorToken.accent)
        .task(id: notificationNavigation?.destination?.id) {
            guard let destination = notificationNavigation?.destination,
                  destination.workspaceID == workspace.mainEventID else { return }
            selectedTab = .home
            notificationTodoDestination = destination.todoID != nil
                && EventManagementAccess.canOpen(reference: destination.reference, in: workspace)
                ? destination : nil
            notificationAnnouncementDestination = destination.announcementID == nil ? nil : destination
            notificationNavigation?.destination = nil
        }
        .sheet(item: $notificationAnnouncementDestination) { destination in
            NavigationStack {
                EventAnnouncementsView(eventID: announcementEventID(for: destination.reference), announcementID: destination.announcementID)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button(AppCopy.Common.close) { notificationAnnouncementDestination = nil }
                        }
                    }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .movieNightTourDidRestart)) { notification in
            guard notification.userInfo?["accountID"] as? String == currentUserAccount?.id,
                  notification.userInfo?["workspaceID"] as? UUID == workspace.mainEventID else { return }
            selectedTab = .home
        }
        .onChange(of: currentUserAccount?.id) { _, _ in
            notificationTodoDestination = nil
            notificationAnnouncementDestination = nil
        }
        .onChange(of: workspace.mainEventID) { _, _ in
            notificationTodoDestination = nil
            notificationAnnouncementDestination = nil
        }
        .onAppear {
#if DEBUG
            guard !hasPresentedManagePreview, BirthdayMarketingFixtures.startsOnManagePreview,
                  EventManagementAccess.canOpen(reference: .main, in: workspace) else { return }
            hasPresentedManagePreview = true
            notificationTodoDestination = NotificationPlanningDestination(
                workspaceID: workspace.mainEventID,
                reference: .main,
                todoID: UUID()
            )
#endif
        }
        .task(id: "\(workspace.mainEventID)|\(scenePhase)") {
            guard scenePhase == .active, workspace.showsPlanningInterface,
                  let cloudSync else { return }
            // Navigation reads local state immediately. Foreground activation and
            // local edits already schedule sync; passive polling waits first and
            // is independent of tab selection.
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(60)) } catch { return }
                await cloudSync.refreshCollaboration(passively: true)
            }
        }
    }

    private var planningTabs: some View {
        WorkspaceTabShell(selection: tabSelection, showsIdeasEventFilter: true) {
            NavigationStack {
                HomeView(
                    homeReselectionTrigger: homeReselectionTrigger,
                    onExitWorkspace: onExitWorkspace
                )
                .movieNightTourOverlay(selectedTab: $selectedTab)
                .navigationDestination(item: $notificationTodoDestination) { destination in
                    EventManagementView(reference: destination.reference, initialDestination: .tasks)
                        .environment(workspace)
                }
            }
        } ideas: { scope in
            NavigationStack {
                IdeasView(scope: scope, onExitWorkspace: onExitWorkspace, tourWindowGeometry: ideasTourWindowGeometry)
            }
            .movieNightTourOverlay(selectedTab: $selectedTab, windowGeometry: ideasTourWindowGeometry)
        } decide: {
            NavigationStack {
                DecisionDeckView(
                    isActive: selectedTab == .decide,
                    onExitWorkspace: onExitWorkspace
                )
                .movieNightTourOverlay(selectedTab: $selectedTab)
            }
        }
    }

    private func announcementEventID(for reference: EventReference) -> UUID {
        if case .subevent(let id) = reference { return id }
        return workspace.mainEventID
    }
}

#Preview {
    ContentView()
        .environment(PlanningWorkspace.sample)
}
