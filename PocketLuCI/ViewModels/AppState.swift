import Foundation
import SwiftUI

@Observable
final class AppState {
    var routerHost: String
    var username: String
    var password: String
    var useHTTPS: Bool
    var isConnected = false
    var isConnecting = false
    var connectionError: String?
    var selectedTab: Int = 0

    private let defaults = UserDefaults.standard

    var rpcBaseURL: String {
        let scheme = useHTTPS ? "https" : "http"
        return "\(scheme)://\(routerHost)/cgi-bin/luci/rpc"
    }

    init() {
        routerHost = defaults.string(forKey: "routerHost") ?? ""
        username = defaults.string(forKey: "username") ?? "root"
        password = defaults.string(forKey: "password") ?? ""
        useHTTPS = defaults.bool(forKey: "useHTTPS")
    }

    func saveSettings() {
        defaults.set(routerHost, forKey: "routerHost")
        defaults.set(username, forKey: "username")
        defaults.set(password, forKey: "password")
        defaults.set(useHTTPS, forKey: "useHTTPS")
    }

    func connect() async {
        guard !routerHost.isEmpty else {
            connectionError = "Enter the router IP address first."
            return
        }
        isConnecting = true
        connectionError = nil
        LuCIClient.shared.configure(host: routerHost, useHTTPS: useHTTPS)
        do {
            try await LuCIClient.shared.authenticate(username: username, password: password)
            isConnected = true
        } catch {
            isConnected = false
            connectionError = error.localizedDescription
        }
        isConnecting = false
    }

    func disconnect() {
        isConnected = false
        LuCIClient.shared.invalidateSession()
        LuCIClient.shared.configure(host: "", useHTTPS: false)
    }
}
