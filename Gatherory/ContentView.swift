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
    case registry
}

struct ContentView: View {
    @State private var selectedTab = AppTab.home

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Home", systemImage: "house.fill", value: .home) {
                NavigationStack {
                    HomeView()
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

            Tab("Registry", systemImage: "gift.fill", value: .registry) {
                NavigationStack {
                    RegistryView()
                }
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .tabBarMinimizeBehavior(.onScrollDown)
        .tint(AppTheme.ColorToken.accent)
    }
}

#Preview {
    ContentView()
        .environment(WeddingWorkspace.sample)
}
