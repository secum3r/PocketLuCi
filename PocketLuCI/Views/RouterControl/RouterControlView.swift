import SwiftUI

struct RouterControlView: View {
    @Environment(AppState.self) private var appState
    @State private var showRebootConfirm = false
    @State private var isRebooting = false
    @State private var rebootMessage: String?
    @State private var error: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    connectionStatusRow
                }

                if appState.isConnected {
                    Section {
                        Button(role: .destructive) {
                            showRebootConfirm = true
                        } label: {
                            HStack {
                                Label("Restart Router", systemImage: "arrow.clockwise")
                                Spacer()
                                if isRebooting {
                                    ProgressView()
                                }
                            }
                        }
                        .disabled(isRebooting)
                    } footer: {
                        Text("The router will restart and all connections will be temporarily interrupted.")
                    }

                    Section("Router Info") {
                        LabeledContent("Host", value: appState.routerHost)
                        LabeledContent("User", value: appState.username)
                        LabeledContent("Protocol", value: "HTTP (LuCI RPC)")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Router")
            .confirmationDialog("Restart Router?", isPresented: $showRebootConfirm, titleVisibility: .visible) {
                Button("Restart", role: .destructive) { Task { await reboot() } }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will interrupt all connections for 1–2 minutes.")
            }
            .alert("Router Restarting", isPresented: Binding(get: { rebootMessage != nil }, set: { _ in rebootMessage = nil })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(rebootMessage ?? "")
            }
            .alert("Error", isPresented: Binding(get: { error != nil }, set: { _ in error = nil })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(error ?? "")
            }
        }
    }

    private var connectionStatusRow: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(appState.isConnected ? Color.green.opacity(0.12) : Color.red.opacity(0.12))
                    .frame(width: 44, height: 44)
                Image(systemName: appState.isConnected ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(appState.isConnected ? .green : .red)
                    .font(.title2)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(appState.isConnected ? "Connected" : "Disconnected")
                    .font(.headline)
                Text(appState.isConnected ? appState.routerHost : "Go to Settings to connect")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func reboot() async {
        isRebooting = true
        do {
            try await LuCIClient.shared.reboot()
            rebootMessage = "The router is restarting. Reconnect in Settings after ~2 minutes."
            appState.disconnect()
        } catch {
            self.error = error.localizedDescription
        }
        isRebooting = false
    }
}

#Preview {
    RouterControlView()
        .environment(AppState())
}
