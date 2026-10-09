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
    case timeline
}

struct AppRootView: View {
    @Environment(WorkspaceLibrary.self) private var workspaceLibrary

    private var isPresentingWorkspace: Binding<Bool> {
        Binding(
            get: { workspaceLibrary.selectedWorkspace != nil },
            set: { isPresented in
                if !isPresented {
                    workspaceLibrary.closeWorkspace()
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
            if let workspace = workspaceLibrary.selectedWorkspace {
                WorkspaceSessionView(workspace: workspace)
            }
        }
    }
}

private struct WorkspaceSessionView: View {
    @Environment(\.dismiss) private var dismiss
    let workspace: WeddingWorkspace

    var body: some View {
        ContentView {
            dismiss()
        }
        .environment(workspace)
    }
}

struct ContentView: View {
    @Environment(WeddingWorkspace.self) private var workspace
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
        TabView(selection: tabSelection) {
            Tab("Home", systemImage: "house.fill", value: .home) {
                NavigationStack {
                    HomeView(
                        homeReselectionTrigger: homeReselectionTrigger,
                        onExitWorkspace: onExitWorkspace
                    )
                }
            }

            Tab("Ideas", systemImage: "sparkles.rectangle.stack.fill", value: .ideas) {
                NavigationStack {
                    IdeasView(onExitWorkspace: onExitWorkspace)
                }
            }

            Tab("Decide", systemImage: "rectangle.on.rectangle.angled", value: .decide) {
                NavigationStack {
                    DecisionDeckView(onExitWorkspace: onExitWorkspace)
                }
            }

            Tab("Timeline", systemImage: "calendar", value: .timeline) {
                NavigationStack {
                    TimelineView(onExitWorkspace: onExitWorkspace)
                }
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .tabBarMinimizeBehavior(
            selectedTab == .home || selectedTab == .decide
                ? .never
                : .onScrollDown
        )
        .tint(AppTheme.ColorToken.accent)
    }
}

#Preview {
    ContentView()
        .environment(WeddingWorkspace.sample)
}
