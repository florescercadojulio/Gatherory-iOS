//
//  ContentView.swift
//  isaidyes
//
//  Created by Julio C on 10/7/26.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            Tab("Home", systemImage: "house.fill") {
                NavigationStack {
                    HomeView()
                }
            }

            Tab("Ideas", systemImage: "sparkles.rectangle.stack.fill") {
                NavigationStack {
                    IdeasView()
                }
            }

            Tab("Decide", systemImage: "rectangle.on.rectangle.angled") {
                NavigationStack {
                    DecisionDeckView()
                }
            }

            Tab("Timeline", systemImage: "calendar") {
                NavigationStack {
                    TimelineView()
                }
            }
        }
        .tint(AppTheme.ColorToken.accent)
    }
}

#Preview {
    ContentView()
        .environment(WeddingWorkspace.sample)
}
