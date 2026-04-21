import Foundation
import SwiftUI

@Observable
final class DevicesViewModel {
    var devices: [Device] = []
    var isLoading = false
    var error: String?

    func load() async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            let (arp, dhcp) = try await LuCIClient.shared.getDevices()
            let firewallConfig = (try? await LuCIClient.shared.getFirewallConfig()) ?? [:]

            var hostnameMap = [String: String]()
            var dhcpIPMap = [String: String]()
            for lease in dhcp {
                dhcpIPMap[lease.mac] = lease.ip
                if let h = lease.hostname { hostnameMap[lease.mac] = h }
            }

            var blockedMACs = [String: String]()
            for (sectionID, section) in firewallConfig where section.type == "rule" {
                if let mac = section.options["src_mac"],
                   (section.options["target"] == "REJECT" || section.options["target"] == "DROP"),
                   section.options["enabled"] != "0" {
                    blockedMACs[mac.lowercased()] = sectionID
                }
            }

            devices = arp
                .filter { !$0.mac.isEmpty && $0.mac != "00:00:00:00:00:00" && $0.mac != "ff:ff:ff:ff:ff:ff" }
                .map { entry in
                    let mac = entry.mac.lowercased()
                    return Device(
                        ip: dhcpIPMap[mac] ?? entry.ip,
                        mac: mac,
                        hostname: hostnameMap[mac] ?? entry.ip,
                        isBlocked: blockedMACs[mac] != nil,
                        blockRuleSectionID: blockedMACs[mac]
                    )
                }
                .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        } catch {
            self.error = error.localizedDescription
        }
    }

    func toggleBlock(_ device: Device) async {
        do {
            if device.isBlocked, let sectionID = device.blockRuleSectionID {
                try await LuCIClient.shared.deleteRule(section: sectionID)
            } else {
                _ = try await LuCIClient.shared.addBlockRule(
                    name: "Block \(device.displayName)", srcMac: device.mac
                )
            }
            await load()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
