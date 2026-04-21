//
//  PocketLuCIApp.swift
//  PocketLuCI
//
//  Created by uq on 18/4/2026.
//

import SwiftUI

@main
struct PocketLuCIApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .environment(appState)
        }
    }
}
