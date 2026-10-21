//
//  ContentView.swift
//  Gatherory
//
//  Created by Julio C on 10/7/26.
//

import SwiftUI

private enum LibraryTab: Hashable { case workspaces, blueprints, explore }

struct AppRootView: View {
    @Environment(AuthenticationSession.self) private var authentication
    @State private var selectedTab = LibraryTab.workspaces
    @State private var isPreviewingBlueprint = false
    @Environment(WorkspaceLibrary.self) private var workspaceLibrary
    @Environment(\.currentUserAccount) private var currentUserAccount
    @Environment(GuestInvitationStore.self) private var guests

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

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Workspaces", systemImage: "rectangle.stack.fill", value: .workspaces) {
                NavigationStack {
                    WorkspaceBrowserView(onExplore: { selectedTab = .explore })
                }
            }
            Tab(BlueprintCopy.libraryTitle, systemImage: "square.stack.3d.up.fill", value: .blueprints) {
                NavigationStack {
                    if authentication.isGuestMode {
                        LocalGuestSignInGate(message: GuestCopy.blueprintHelp)
                    } else {
                        BlueprintLibraryView(
                            ownerID: currentUserAccount?.id ?? "",
                            isActive: selectedTab == .blueprints
                        )
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
                            isActive: selectedTab == .explore
                        )
                    }
                }
                .id(currentUserAccount?.id)
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .tabBarMinimizeBehavior(.onScrollDown)
        .tint(AppTheme.ColorToken.accent)
        .environment(\.blueprintPreviewPresented, $isPreviewingBlueprint)
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
        .onChange(of: currentUserAccount?.id) { _, _ in
            selectedTab = .workspaces
            isPreviewingBlueprint = false
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
    @State private var selectedTab = WorkspaceTab.home
    @State private var homeReselectionTrigger = 0
    @State private var notificationTodoDestination: NotificationPlanningDestination?
    @State private var notificationAnnouncementDestination: NotificationPlanningDestination?

    init(onExitWorkspace: (() -> Void)? = nil) {
        self.onExitWorkspace = onExitWorkspace
    }

    private var tabSelection: Binding<WorkspaceTab> {
        Binding(
            get: { selectedTab },
            set: { newValue in
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
                }
            }
        }
        .tint(AppTheme.ColorToken.accent)
        .task(id: notificationNavigation?.destination?.id) {
            guard let destination = notificationNavigation?.destination,
                  destination.workspaceID == workspace.mainEventID else { return }
            selectedTab = destination.todoID == nil ? .home : .manage
            notificationTodoDestination = destination.todoID == nil ? nil : destination
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
        .onChange(of: currentUserAccount?.id) { _, _ in
            notificationTodoDestination = nil
            notificationAnnouncementDestination = nil
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
        WorkspaceTabShell(selection: tabSelection, showsManage: true, showsIdeasEventFilter: true, showsManageEventFilter: true) {
            NavigationStack {
                HomeView(
                    homeReselectionTrigger: homeReselectionTrigger,
                    onExitWorkspace: onExitWorkspace
                )
            }
        } ideas: { scope in
            NavigationStack {
                IdeasView(scope: scope, onExitWorkspace: onExitWorkspace)
            }
        } decide: {
            NavigationStack {
                DecisionDeckView(
                    isActive: selectedTab == .decide,
                    onExitWorkspace: onExitWorkspace
                )
            }
        } manage: { eventSelection in
            NavigationStack {
                ManageView(selection: eventSelection, isActive: selectedTab == .manage, onExitWorkspace: onExitWorkspace)
                    .navigationDestination(item: $notificationTodoDestination) { destination in
                        ManageTodosView(reference: destination.reference)
                    }
            }
            .id("\(workspace.mainEventID)|\(currentUserAccount?.id ?? "")")
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
