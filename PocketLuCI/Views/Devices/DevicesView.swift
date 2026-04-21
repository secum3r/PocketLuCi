import SwiftUI

struct DevicesView: View {
    @Environment(AppState.self) private var appState
    @State private var vm = DevicesViewModel()

    var body: some View {
        NavigationStack {
            Group {
                if !appState.isConnected {
                    notConnectedPlaceholder
                } else if vm.isLoading && vm.devices.isEmpty {
                    ProgressView("Loading devices…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if vm.devices.isEmpty {
                    ContentUnavailableView(
                        "No Devices",
                        systemImage: "network",
                        description: Text("No connected devices found on the network.")
                    )
                } else {
                    List(vm.devices) { device in
                        DeviceRow(device: device) {
                            Task { await vm.toggleBlock(device) }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .refreshable { await vm.load() }
                }
            }
            .navigationTitle("Devices")
            .toolbar {
                if vm.isLoading {
                    ToolbarItem(placement: .topBarTrailing) { ProgressView() }
                } else if appState.isConnected {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { Task { await vm.load() } } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                }
            }
            .task(id: appState.isConnected) {
                guard appState.isConnected else { return }
                await vm.load()
            }
            .alert("Error", isPresented: Binding(get: { vm.error != nil }, set: { _ in vm.error = nil })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(vm.error ?? "")
            }
        }
    }

    private var notConnectedPlaceholder: some View {
        ContentUnavailableView {
            Label("Not Connected", systemImage: "wifi.slash")
        } description: {
            Text("Connect to your router in Settings.")
        } actions: {
            Button("Open Settings") {
                appState.selectedTab = 4
            }
            .buttonStyle(.borderedProminent)
        }
    }
}

struct DeviceRow: View {
    let device: Device
    let onToggleBlock: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(device.isBlocked ? Color.red.opacity(0.12) : Color.green.opacity(0.12))
                    .frame(width: 40, height: 40)
                Image(systemName: device.isBlocked ? "wifi.slash" : "wifi")
                    .foregroundStyle(device.isBlocked ? .red : .green)
                    .font(.system(size: 17))
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(device.displayName)
                    .font(.body)
                    .fontWeight(.medium)
                    .lineLimit(1)
                Text(device.ip)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(device.mac.uppercased())
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .monospaced()
            }

            Spacer()

            Button(action: onToggleBlock) {
                Text(device.isBlocked ? "Unblock" : "Block")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(device.isBlocked ? Color.green.opacity(0.15) : Color.red.opacity(0.15))
                    .foregroundStyle(device.isBlocked ? .green : .red)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    DevicesView()
        .environment(AppState())
}
