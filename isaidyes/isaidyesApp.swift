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

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(workspace)
        }
    }
}
