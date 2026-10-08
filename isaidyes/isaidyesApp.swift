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
    @AppStorage("appAppearance") private var appearance = AppAppearance.system.rawValue

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(workspace)
                .preferredColorScheme(AppAppearance(rawValue: appearance)?.colorScheme)
        }
    }
}
