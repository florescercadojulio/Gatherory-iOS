//
//  GatheroryApp.swift
//  Gatherory
//
//  Created by Julio C on 10/7/26.
//

import SwiftUI

@main
struct GatheroryApp: App {
    @State private var workspaceLibrary = WorkspaceLibrary.sample
    @State private var musicCatalog = MusicCatalog()
    @AppStorage("appAppearance") private var appearance = AppAppearance.system.rawValue

    var body: some Scene {
        WindowGroup {
            AppRootView()
                .environment(workspaceLibrary)
                .environment(musicCatalog)
                .preferredColorScheme(AppAppearance(rawValue: appearance)?.colorScheme)
        }
    }
}
