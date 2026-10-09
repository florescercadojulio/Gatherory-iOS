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

struct ContentView: View {
    @Environment(WeddingWorkspace.self) private var workspace
    @State private var selectedTab = AppTab.home
    @State private var homeReselectionTrigger = 0

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
                    HomeView(homeReselectionTrigger: homeReselectionTrigger)
                }
            }

            Tab("Ideas", systemImage: "sparkles.rectangle.stack.fill", value: .ideas) {
                NavigationStack {
                    IdeasView()
                }
            }

            Tab("Decide", systemImage: "rectangle.on.rectangle.angled", value: .decide) {
                NavigationStack {
                    DecisionDeckView()
                }
            }

            Tab("Timeline", systemImage: "calendar", value: .timeline) {
                NavigationStack {
                    TimelineView()
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
