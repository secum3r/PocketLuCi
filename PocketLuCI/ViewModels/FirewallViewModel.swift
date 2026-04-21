import Foundation
import SwiftUI

@Observable
final class FirewallViewModel {
    var rules: [FirewallRule] = []
    var isLoading = false
    var error: String?

    func load() async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            let config = try await LuCIClient.shared.getFirewallConfig()
            rules = config.compactMap { (sectionID, section) in
                guard section.type == "rule" else { return nil }
                return FirewallRule(
                    id: sectionID,
                    name: section.options["name"] ?? sectionID,
                    src: section.options["src"] ?? "*",
                    dest: section.options["dest"] ?? "*",
                    srcMac: section.options["src_mac"],
                    target: section.options["target"] ?? "ACCEPT",
                    isEnabled: section.options["enabled"] != "0"
                )
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        } catch {
            self.error = error.localizedDescription
        }
    }

    func toggleRule(_ rule: FirewallRule) async {
        do {
            try await LuCIClient.shared.setRuleEnabled(section: rule.id, enabled: !rule.isEnabled)
            await load()
        } catch {
            self.error = error.localizedDescription
        }
    }

    func deleteRule(_ rule: FirewallRule) async {
        do {
            try await LuCIClient.shared.deleteRule(section: rule.id)
            rules.removeAll { $0.id == rule.id }
        } catch {
            self.error = error.localizedDescription
        }
    }
}
