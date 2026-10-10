//
//  GatheroryApp.swift
//  Gatherory
//
//  Created by Julio C on 10/7/26.
//

import SwiftUI

@main
struct GatheroryApp: App {
    @State private var authentication = AuthenticationSession.bootstrap()
    @State private var workspaceLibrary = WorkspaceLibrary.bootstrap()
    @State private var musicCatalog = MusicCatalog()
    @AppStorage(AppAppearance.storageKey) private var appearance = AppAppearance.system.rawValue

    var body: some Scene {
        WindowGroup {
            GatheroryLaunchContainer()
                .environment(authentication)
                .environment(workspaceLibrary)
                .environment(musicCatalog)
                .appUserAppearance(AppAppearance(rawValue: appearance) ?? .system)
        }
    }
}
