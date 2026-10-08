//
//  isaidyesApp.swift
//  isaidyes
//
//  Created by Julio C on 10/7/26.
//

import SwiftUI

@main
struct isaidyesApp: App {
    @State private var workspace = WeddingWorkspace.sample
    @State private var musicCatalog = MusicCatalog()
    @AppStorage("appAppearance") private var appearance = AppAppearance.system.rawValue

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(workspace)
                .environment(musicCatalog)
                .preferredColorScheme(AppAppearance(rawValue: appearance)?.colorScheme)
        }
    }
}
