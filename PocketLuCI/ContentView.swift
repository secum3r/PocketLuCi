//
//  ContentView.swift
//  PocketLuCI
//
//  Created by uq on 18/4/2026.
//

import SwiftUI

// Retained for compatibility; app entry is PocketLuCIApp → MainTabView.
struct ContentView: View {
    @State private var appState = AppState()

    var body: some View {
        MainTabView()
            .environment(appState)
    }
}

#Preview {
    ContentView()
}
