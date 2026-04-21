import SwiftUI

@main
struct PocketLuCIApp: App {
    @State private var appState = AppState()
    @State private var isLocked = false
    @State private var backgroundedAt: Date?
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("appLockEnabled") private var appLockEnabled = false

    private let gracePeriod: TimeInterval = 5

    var body: some Scene {
        WindowGroup {
            ZStack {
                MainTabView()
                    .environment(appState)
                if isLocked {
                    LockScreenView {
                        isLocked = false
                        autoConnectIfNeeded()
                    }
                }
            }
            .task {
                if appLockEnabled {
                    isLocked = true
                } else {
                    autoConnectIfNeeded()
                }
            }
            .onChange(of: scenePhase) { _, phase in
                switch phase {
                case .background:
                    backgroundedAt = Date()
                case .active:
                    if appLockEnabled, let bg = backgroundedAt {
                        if Date().timeIntervalSince(bg) > gracePeriod { isLocked = true }
                    }
                    backgroundedAt = nil
                default:
                    break
                }
            }
        }
    }

    private func autoConnectIfNeeded() {
        guard appState.wasConnected, !appState.isConnected, !appState.routerHost.isEmpty else { return }
        Task { await appState.connect() }
    }
}
