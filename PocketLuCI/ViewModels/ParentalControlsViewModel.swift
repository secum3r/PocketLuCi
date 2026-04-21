import Foundation
import SwiftUI

@Observable
final class ParentalControlsViewModel {
    var groups: [DeviceGroup] = []
    var schedules: [AccessSchedule] = []
    var error: String?

    private let groupsKey = "pocketluci_groups"
    private let schedulesKey = "pocketluci_schedules"

    init() { loadLocal() }

    // MARK: Local persistence

    func loadLocal() {
        if let data = UserDefaults.standard.data(forKey: groupsKey),
           let decoded = try? JSONDecoder().decode([DeviceGroup].self, from: data) {
            groups = decoded
        }
        if let data = UserDefaults.standard.data(forKey: schedulesKey),
           let decoded = try? JSONDecoder().decode([AccessSchedule].self, from: data) {
            schedules = decoded
        }
    }

    private func saveLocal() {
        if let data = try? JSONEncoder().encode(groups) {
            UserDefaults.standard.set(data, forKey: groupsKey)
        }
        if let data = try? JSONEncoder().encode(schedules) {
            UserDefaults.standard.set(data, forKey: schedulesKey)
        }
    }

    // MARK: Router sync

    func syncBlockedState() async {
        let blockedGroups = groups.filter { $0.isBlocked }
        guard !blockedGroups.isEmpty else { return }
        guard let config = try? await LuCIClient.shared.getFirewallConfig() else { return }
        let existingSectionIDs = Set(config.keys)
        var changed = false
        for group in blockedGroups {
            let stillExists = group.blockRuleSectionIDs.contains { existingSectionIDs.contains($0) }
            if !stillExists {
                if let idx = groups.firstIndex(where: { $0.id == group.id }) {
                    groups[idx].isBlocked = false
                    groups[idx].blockRuleSectionIDs = []
                    changed = true
                }
            }
        }
        if changed { saveLocal() }
    }

    // MARK: Group management

    func addGroup(name: String) {
        groups.append(DeviceGroup(name: name))
        saveLocal()
    }

    func updateGroup(_ group: DeviceGroup) {
        if let idx = groups.firstIndex(where: { $0.id == group.id }) {
            groups[idx] = group
        }
        saveLocal()
    }

    func deleteGroup(_ group: DeviceGroup) async {
        if group.isBlocked {
            await unblockGroup(group)
        }
        groups.removeAll { $0.id == group.id }
        schedules.removeAll { $0.groupID == group.id }
        saveLocal()
    }

    func schedulesFor(group: DeviceGroup) -> [AccessSchedule] {
        schedules.filter { $0.groupID == group.id }
    }

    // MARK: Block / unblock

    func toggleBlock(_ group: DeviceGroup) async {
        if group.isBlocked {
            await unblockGroup(group)
        } else {
            await blockGroup(group)
        }
    }

    private func blockGroup(_ group: DeviceGroup) async {
        var updated = group
        updated.blockRuleSectionIDs = []
        error = nil
        do {
            for mac in group.deviceMACs {
                let sid = try await LuCIClient.shared.addBlockRule(
                    name: "PC_\(group.name)", srcMac: mac
                )
                updated.blockRuleSectionIDs.append(sid)
            }
            updated.isBlocked = true
        } catch {
            self.error = error.localizedDescription
        }
        updateGroup(updated)
    }

    private func unblockGroup(_ group: DeviceGroup) async {
        var updated = group
        error = nil
        do {
            for sid in group.blockRuleSectionIDs {
                try await LuCIClient.shared.deleteRule(section: sid)
            }
            updated.isBlocked = false
            updated.blockRuleSectionIDs = []
        } catch {
            self.error = error.localizedDescription
        }
        updateGroup(updated)
    }

    // MARK: Schedules

    func addSchedule(_ schedule: AccessSchedule) async {
        schedules.append(schedule)
        saveLocal()
        if schedule.isEnabled {
            await applyScheduleToRouter(schedule)
        }
    }

    func toggleSchedule(_ schedule: AccessSchedule) async {
        guard let idx = schedules.firstIndex(where: { $0.id == schedule.id }) else { return }
        schedules[idx].isEnabled.toggle()
        saveLocal()
        let updated = schedules[idx]
        if updated.isEnabled {
            await applyScheduleToRouter(updated)
        } else {
            await removeScheduleFromRouter(updated)
        }
    }

    func deleteSchedule(_ schedule: AccessSchedule) async {
        schedules.removeAll { $0.id == schedule.id }
        saveLocal()
        await removeScheduleFromRouter(schedule)
    }

    private func applyScheduleToRouter(_ schedule: AccessSchedule) async {
        guard let group = groups.first(where: { $0.id == schedule.groupID }) else { return }
        for mac in group.deviceMACs {
            try? await LuCIClient.shared.applyScheduleCron(
                mac: mac,
                blockHour: schedule.startHour, blockMinute: schedule.startMinute,
                unblockHour: schedule.endHour, unblockMinute: schedule.endMinute,
                days: schedule.daysOfWeek
            )
        }
    }

    private func removeScheduleFromRouter(_ schedule: AccessSchedule) async {
        guard let group = groups.first(where: { $0.id == schedule.groupID }) else { return }
        for mac in group.deviceMACs {
            try? await LuCIClient.shared.removeScheduleCron(mac: mac)
        }
    }
}
