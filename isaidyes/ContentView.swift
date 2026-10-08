//
//  ContentView.swift
//  isaidyes
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
    case pass
    case maybe
    case love
}

struct ContentView: View {
    @Environment(WeddingWorkspace.self) private var workspace
    @State private var selectedTab = AppTab.home
    @State private var isDecisionModeFocused = false

    var body: some View {
        TabView(selection: tabSelection) {
            Tab("Decide", systemImage: "rectangle.on.rectangle.angled", value: .decide) {
                NavigationStack {
                    DecisionDeckView()
                }
            }

            if isDecisionModeFocused {
                Tab("Pass", systemImage: "xmark", value: .pass) {
                    Color.clear
                }

                Tab("Maybe", systemImage: "bookmark.fill", value: .maybe) {
                    Color.clear
                }

                Tab("Love It", systemImage: "heart.fill", value: .love) {
                    Color.clear
                }
            } else {
                Tab("Ideas", systemImage: "sparkles.rectangle.stack.fill", value: .ideas) {
                    NavigationStack {
                        IdeasView()
                    }
                }

                Tab("Home", systemImage: "house.fill", value: .home) {
                    NavigationStack {
                        HomeView()
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
        }
        .tabViewStyle(.sidebarAdaptable)
        .tabBarMinimizeBehavior(.onScrollDown)
        .tint(AppTheme.ColorToken.accent)
        .onChange(of: workspace.decisionQueue.count) { _, count in
            if count == 0 {
                withAnimation(.snappy) {
                    isDecisionModeFocused = false
                }
            }
        }
    }

    private var tabSelection: Binding<AppTab> {
        Binding(
            get: { selectedTab },
            set: { newTab in
                switch newTab {
                case .decide:
                    withAnimation(.snappy) {
                        selectedTab = .decide
                        isDecisionModeFocused.toggle()
                    }
                case .pass:
                    decide(.pass)
                case .maybe:
                    decide(.maybe)
                case .love:
                    decide(.love)
                case .home, .ideas, .timeline, .registry:
                    withAnimation(.snappy) {
                        selectedTab = newTab
                        isDecisionModeFocused = false
                    }
                }
            }
        )
    }

    private func decide(_ choice: DecisionChoice) {
        guard let currentIdea = workspace.decisionQueue.first else { return }
        withAnimation(.snappy) {
            workspace.decide(choice, on: currentIdea)
            selectedTab = .decide
        }
    }
}

#Preview {
    ContentView()
        .environment(WeddingWorkspace.sample)
}
