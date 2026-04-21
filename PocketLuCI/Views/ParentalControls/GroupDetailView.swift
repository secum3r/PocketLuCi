import SwiftUI

struct GroupDetailView: View {
    var group: DeviceGroup
    var vm: ParentalControlsViewModel

    @Environment(AppState.self) private var appState
    @State private var editedGroup: DeviceGroup
    @State private var showAddMAC = false
    @State private var newMAC = ""
    @State private var showAddSchedule = false
    @State private var showColorPicker = false

    init(group: DeviceGroup, vm: ParentalControlsViewModel) {
        self.group = group
        self.vm = vm
        _editedGroup = State(initialValue: group)
    }

    var schedules: [AccessSchedule] { vm.schedulesFor(group: editedGroup) }

    var body: some View {
        List {
            // Name & color
            Section("Group") {
                HStack {
                    Text("Name")
                    Spacer()
                    TextField("Group name", text: $editedGroup.name)
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(.secondary)
                        .onSubmit { vm.updateGroup(editedGroup) }
                }
                HStack {
                    Text("Color")
                    Spacer()
                    HStack(spacing: 8) {
                        ForEach(DeviceGroup.colorOptions, id: \.self) { name in
                            Circle()
                                .fill(colorFromName(name))
                                .frame(width: 22, height: 22)
                                .overlay {
                                    if editedGroup.colorName == name {
                                        Circle().stroke(Color.primary, lineWidth: 2)
                                    }
                                }
                                .onTapGesture {
                                    editedGroup.colorName = name
                                    vm.updateGroup(editedGroup)
                                }
                        }
                    }
                }
            }

            // Access control
            Section("Access") {
                HStack {
                    Label(editedGroup.isBlocked ? "Blocked" : "Allowed", systemImage: editedGroup.isBlocked ? "wifi.slash" : "wifi")
                        .foregroundStyle(editedGroup.isBlocked ? .red : .green)
                    Spacer()
                    Button(editedGroup.isBlocked ? "Unblock" : "Block") {
                        let g = editedGroup
                        Task {
                            await vm.toggleBlock(g)
                            if let updated = vm.groups.first(where: { $0.id == g.id }) {
                                editedGroup = updated
                            }
                        }
                    }
                    .buttonStyle(.bordered)
                    .tint(editedGroup.isBlocked ? .green : .red)
                }
            }

            // Devices
            Section {
                ForEach(editedGroup.deviceMACs, id: \.self) { mac in
                    HStack {
                        Image(systemName: "laptopcomputer")
                            .foregroundStyle(.secondary)
                        Text(mac.uppercased())
                            .font(.subheadline)
                            .monospaced()
                    }
                }
                .onDelete { indexSet in
                    editedGroup.deviceMACs.remove(atOffsets: indexSet)
                    vm.updateGroup(editedGroup)
                }

                Button {
                    showAddMAC = true
                } label: {
                    Label("Add Device", systemImage: "plus.circle")
                }
            } header: {
                Text("Devices (\(editedGroup.deviceMACs.count))")
            }

            // Schedules
            Section {
                ForEach(schedules) { schedule in
                    ScheduleRow(schedule: schedule) {
                        Task { await vm.toggleSchedule(schedule) }
                    }
                }
                .onDelete { indexSet in
                    Task {
                        for i in indexSet { await vm.deleteSchedule(schedules[i]) }
                    }
                }

                Button {
                    showAddSchedule = true
                } label: {
                    Label("Add Schedule", systemImage: "clock.badge.plus")
                }
            } header: {
                Text("Schedules")
            } footer: {
                Text("Schedules block internet access at the specified times using cron jobs on the router.")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(editedGroup.name)
        .navigationBarTitleDisplayMode(.large)
        .alert("Add Device by MAC", isPresented: $showAddMAC) {
            TextField("AA:BB:CC:DD:EE:FF", text: $newMAC)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.characters)
            Button("Add") {
                let mac = newMAC.trimmingCharacters(in: .whitespaces).lowercased()
                if !mac.isEmpty && !editedGroup.deviceMACs.contains(mac) {
                    editedGroup.deviceMACs.append(mac)
                    vm.updateGroup(editedGroup)
                }
                newMAC = ""
            }
            Button("Cancel", role: .cancel) { newMAC = "" }
        } message: {
            Text("Enter the MAC address of the device.")
        }
        .sheet(isPresented: $showAddSchedule) {
            ScheduleEditorView(groupID: editedGroup.id) { schedule in
                Task { await vm.addSchedule(schedule) }
            }
        }
    }

    private func colorFromName(_ name: String) -> Color {
        switch name {
        case "green": return .green
        case "orange": return .orange
        case "purple": return .purple
        case "red": return .red
        case "teal": return .teal
        default: return .blue
        }
    }
}

struct ScheduleRow: View {
    let schedule: AccessSchedule
    let onToggle: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(schedule.name)
                    .font(.body)
                    .fontWeight(.medium)
                Text("\(schedule.startTimeDisplay) – \(schedule.endTimeDisplay)  ·  \(schedule.daysDisplay)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if schedule.isActiveNow {
                    Text("Active now")
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .fontWeight(.semibold)
                }
            }
            Spacer()
            Toggle("", isOn: Binding(get: { schedule.isEnabled }, set: { _ in onToggle() }))
                .labelsHidden()
        }
        .padding(.vertical, 2)
        .opacity(schedule.isEnabled ? 1 : 0.5)
    }
}
