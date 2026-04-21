import Foundation

struct Device: Identifiable, Hashable {
    var id: String { mac.lowercased() }
    var ip: String
    var mac: String
    var hostname: String
    var isBlocked: Bool = false
    var blockRuleSectionID: String?

    var displayName: String { hostname.isEmpty ? ip : hostname }
}
