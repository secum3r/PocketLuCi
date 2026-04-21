import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("appColorScheme") private var preferredScheme: String = "system"
    @AppStorage("appLockEnabled") private var appLockEnabled = false
    @State private var showPassword = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    connectionStatusBanner
                }

                Section {
                    HStack {
                        Label("IP / Host", systemImage: "network")
                        Spacer()
                        TextField("192.168.1.1", text: Bindable(appState).routerHost)
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.URL)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .foregroundStyle(.secondary)
                    }

                    Toggle(isOn: Bindable(appState).useHTTPS) {
                        Label("Use HTTPS", systemImage: "lock.shield")
                    }

                    HStack {
                        Label("Username", systemImage: "person")
                        Spacer()
                        TextField("root", text: Bindable(appState).username)
                            .multilineTextAlignment(.trailing)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Label("Password", systemImage: "lock")
                        Spacer()
                        Group {
                            if showPassword {
                                TextField("Password", text: Bindable(appState).password)
                            } else {
                                SecureField("Password", text: Bindable(appState).password)
                            }
                        }
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(.secondary)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)

                        Button { showPassword.toggle() } label: {
                            Image(systemName: showPassword ? "eye.slash" : "eye")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }

                    if !appState.routerHost.isEmpty {
                        HStack {
                            Image(systemName: "link")
                                .foregroundStyle(.secondary)
                                .font(.caption)
                            Text(appState.rpcBaseURL)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                } header: {
                    Text("Router")
                } footer: {
                    Text("Requires luci-mod-rpc on the router. If you get a 404 error, run: opkg update && opkg install luci-mod-rpc")
                }

                Section {
                    if appState.isConnected {
                        Button(role: .destructive) {
                            appState.disconnect()
                        } label: {
                            HStack {
                                Spacer()
                                Text("Disconnect")
                                    .fontWeight(.semibold)
                                Spacer()
                            }
                        }
                    } else {
                        Button {
                            appState.saveSettings()
                            Task { await appState.connect() }
                        } label: {
                            HStack {
                                Spacer()
                                if appState.isConnecting {
                                    ProgressView()
                                        .padding(.trailing, 6)
                                }
                                Text(appState.isConnecting ? "Connecting…" : "Connect")
                                    .fontWeight(.semibold)
                                Spacer()
                            }
                        }
                        .disabled(appState.isConnecting || appState.routerHost.isEmpty)
                    }

                    if let err = appState.connectionError {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            Text(err)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Appearance") {
                    Toggle(isOn: $appLockEnabled) {
                        Label("Require Face ID / Passcode", systemImage: "faceid")
                    }

                    Picker(selection: $preferredScheme) {
                        Text("System").tag("system")
                        Text("Light").tag("light")
                        Text("Dark").tag("dark")
                    } label: {
                        Label("Theme", systemImage: "paintbrush")
                    }
                }

                Section("About") {
                    LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                    LabeledContent("Protocol", value: "OpenWRT LuCI RPC")
                    Link(destination: URL(string: "https://openwrt.org/docs/techref/luci")!) {
                        Label("OpenWRT Documentation", systemImage: "safari")
                    }
                }
            }
            .navigationTitle("Settings")
        }
        .preferredColorScheme(schemeFromString(preferredScheme))
    }

    private var connectionStatusBanner: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(appState.isConnected ? Color.green.opacity(0.12) : Color.secondary.opacity(0.1))
                    .frame(width: 44, height: 44)
                Image(systemName: appState.isConnected ? "wifi" : "wifi.slash")
                    .foregroundStyle(appState.isConnected ? .green : .secondary)
                    .font(.title3)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(appState.isConnected ? "Connected to Router" : "Not Connected")
                    .font(.headline)
                    .foregroundStyle(appState.isConnected ? .green : .primary)
                if appState.isConnected {
                    Text(appState.routerHost)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Enter router details below to connect")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 6)
    }

    private func schemeFromString(_ s: String) -> ColorScheme? {
        switch s {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }
}

#Preview {
    SettingsView()
        .environment(AppState())
}
