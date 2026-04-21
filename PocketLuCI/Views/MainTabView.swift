import SwiftUI

struct MainTabView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        TabView(selection: Bindable(appState).selectedTab) {
            ParentalControlsView()
                .tabItem { Label("Parental", systemImage: "person.2.fill") }
                .tag(0)

            DevicesView()
                .tabItem { Label("Devices", systemImage: "network") }
                .tag(1)

            FirewallView()
                .tabItem { Label("Firewall", systemImage: "shield") }
                .tag(2)

            RouterControlView()
                .tabItem { Label("Router", systemImage: "arrow.clockwise") }
                .tag(3)

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gear") }
                .tag(4)
        }
    }
}

#Preview {
    MainTabView()
        .environment(AppState())
}
