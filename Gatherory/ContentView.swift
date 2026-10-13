//
//  ContentView.swift
//  Gatherory
//
//  Created by Julio C on 10/7/26.
//

import SwiftUI

private enum AppTab: Hashable {
    case home
    case ideas
    case decide
    case insights
}

struct AppRootView: View {
    @Environment(WorkspaceLibrary.self) private var workspaceLibrary
    @Environment(\.currentUserAccount) private var currentUserAccount
    @Environment(GuestInvitationStore.self) private var guests

    private var isPresentingWorkspace: Binding<Bool> {
        Binding(
            get: { workspaceLibrary.selectedWorkspace != nil || guests.selectedPresentation != nil },
            set: { isPresented in
                if !isPresented {
                    workspaceLibrary.closeWorkspace()
                    guests.selectedEventID = nil
                }
            }
        )
    }

    var body: some View {
        NavigationStack {
            WorkspaceBrowserView()
        }
        .tint(AppTheme.ColorToken.accent)
        .fullScreenCover(isPresented: isPresentingWorkspace) {
            if let eventID = guests.selectedEventID {
                GuestEventInvitationView(eventID: eventID)
            } else if let workspace = workspaceLibrary.selectedWorkspace {
                WorkspaceSessionView(
                    workspace: workspace,
                    account: currentUserAccount
                )
            }
        }
        .task(id: currentUserAccount) {
            workspaceLibrary.configureViewer(currentUserAccount)
        }
    }
}

private struct WorkspaceSessionView: View {
    @Environment(\.dismiss) private var dismiss
    let workspace: PlanningWorkspace

    init(workspace: PlanningWorkspace, account: UserAccount?) {
        self.workspace = workspace
        workspace.configureViewer(account)
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
    var onExitWorkspace: (() -> Void)?
    @State private var selectedTab = AppTab.home
    @State private var homeReselectionTrigger = 0

    init(onExitWorkspace: (() -> Void)? = nil) {
        self.onExitWorkspace = onExitWorkspace
    }

    private var tabSelection: Binding<AppTab> {
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
    }

    private var planningTabs: some View {
        TabView(selection: tabSelection) {
            Tab(AppCopy.Tab.home, systemImage: "house.fill", value: .home) {
                NavigationStack {
                    HomeView(
                        homeReselectionTrigger: homeReselectionTrigger,
                        onExitWorkspace: onExitWorkspace
                    )
                }
            }

            Tab(AppCopy.Tab.ideas, systemImage: "sparkles.rectangle.stack.fill", value: .ideas) {
                NavigationStack {
                    IdeasView(onExitWorkspace: onExitWorkspace)
                }
            }

            Tab(AppCopy.Tab.decide, systemImage: "rectangle.on.rectangle.angled", value: .decide) {
                NavigationStack {
                    DecisionDeckView(
                        isActive: selectedTab == .decide,
                        onExitWorkspace: onExitWorkspace
                    )
                }
            }

            Tab(AppCopy.Tab.insights, systemImage: "chart.bar.xaxis", value: .insights) {
                NavigationStack {
                    InsightsView(onExitWorkspace: onExitWorkspace)
                }
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .tabBarMinimizeBehavior(
            selectedTab == .home || selectedTab == .decide
                ? .never
                : .onScrollDown
        )
    }
}

#Preview {
    ContentView()
        .environment(PlanningWorkspace.sample)
}
