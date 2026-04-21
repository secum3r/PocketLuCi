import SwiftUI

struct ParentalControlsView: View {
    @Environment(AppState.self) private var appState
    @State private var vm = ParentalControlsViewModel()
    @State private var showAddGroup = false
    @State private var newGroupName = ""

    var body: some View {
        NavigationStack {
            Group {
                if vm.groups.isEmpty {
                    ContentUnavailableView {
                        Label("No Groups", systemImage: "person.2")
                    } description: {
                        Text("Create a group to manage devices together.")
                    } actions: {
                        Button("Add Group") { showAddGroup = true }
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    List {
                        ForEach(vm.groups) { group in
                            NavigationLink(destination: GroupDetailView(group: group, vm: vm)) {
                                GroupRow(group: group) {
                                    Task { await vm.toggleBlock(group) }
                                }
                            }
                        }
                        .onDelete { indexSet in
                            Task {
                                for i in indexSet { await vm.deleteGroup(vm.groups[i]) }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Parental Controls")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAddGroup = true } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .alert("New Group", isPresented: $showAddGroup) {
                TextField("Group name", text: $newGroupName)
                Button("Add") {
                    let name = newGroupName.trimmingCharacters(in: .whitespaces)
                    if !name.isEmpty { vm.addGroup(name: name) }
                    newGroupName = ""
                }
                Button("Cancel", role: .cancel) { newGroupName = "" }
            }
            .alert("Error", isPresented: Binding(get: { vm.error != nil }, set: { _ in vm.error = nil })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(vm.error ?? "")
            }
            .task(id: appState.isConnected) {
                guard appState.isConnected else { return }
                await vm.syncBlockedState()
            }
        }
    }
}

struct GroupRow: View {
    let group: DeviceGroup
    let onToggleBlock: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(group.color.opacity(0.2))
                    .frame(width: 40, height: 40)
                Image(systemName: "person.2.fill")
                    .foregroundStyle(group.color)
                    .font(.system(size: 16))
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(group.name)
                    .font(.body)
                    .fontWeight(.medium)
                Text("\(group.deviceMACs.count) device\(group.deviceMACs.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(action: onToggleBlock) {
                Text(group.isBlocked ? "Unblock" : "Block")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(group.isBlocked ? Color.green.opacity(0.15) : Color.red.opacity(0.15))
                    .foregroundStyle(group.isBlocked ? .green : .red)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    ParentalControlsView()
        .environment(AppState())
}
