import SwiftUI

struct FirewallView: View {
    @Environment(AppState.self) private var appState
    @State private var vm = FirewallViewModel()

    var body: some View {
        NavigationStack {
            Group {
                if !appState.isConnected {
                    ContentUnavailableView(
                        "Not Connected",
                        systemImage: "shield.slash",
                        description: Text("Connect to your router in Settings.")
                    )
                } else if vm.isLoading && vm.rules.isEmpty {
                    ProgressView("Loading rules…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if vm.rules.isEmpty {
                    ContentUnavailableView(
                        "No Firewall Rules",
                        systemImage: "shield",
                        description: Text("No custom firewall rules found.")
                    )
                } else {
                    List {
                        ForEach(vm.rules) { rule in
                            FirewallRuleRow(rule: rule,
                                onToggle: { Task { await vm.toggleRule(rule) } }
                            )
                        }
                        .onDelete { indexSet in
                            Task {
                                for i in indexSet {
                                    await vm.deleteRule(vm.rules[i])
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .refreshable { await vm.load() }
                }
            }
            .navigationTitle("Firewall")
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
}

struct FirewallRuleRow: View {
    let rule: FirewallRule
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(targetColor.opacity(0.12))
                    .frame(width: 36, height: 36)
                Image(systemName: targetIcon)
                    .foregroundStyle(targetColor)
                    .font(.system(size: 15))
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(rule.name)
                    .font(.body)
                    .fontWeight(.medium)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text("\(rule.src) → \(rule.dest)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(rule.target)
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(targetColor.opacity(0.15))
                        .foregroundStyle(targetColor)
                        .clipShape(Capsule())
                }
                if let mac = rule.srcMac {
                    Text(mac.uppercased())
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .monospaced()
                }
            }

            Spacer()

            Toggle("", isOn: Binding(get: { rule.isEnabled }, set: { _ in onToggle() }))
                .labelsHidden()
        }
        .padding(.vertical, 4)
        .opacity(rule.isEnabled ? 1 : 0.5)
    }

    private var targetColor: Color {
        switch rule.target {
        case "ACCEPT": return .green
        case "REJECT", "DROP": return .red
        default: return .orange
        }
    }

    private var targetIcon: String {
        switch rule.target {
        case "ACCEPT": return "checkmark.shield"
        case "REJECT", "DROP": return "xmark.shield"
        default: return "shield"
        }
    }
}

#Preview {
    FirewallView()
        .environment(AppState())
}
