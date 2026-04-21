import Foundation

struct FirewallRule: Identifiable, Hashable {
    var id: String // UCI section ID
    var name: String
    var src: String
    var dest: String
    var srcMac: String?
    var target: String
    var isEnabled: Bool

    var targetColor: String {
        switch target {
        case "ACCEPT": return "green"
        case "REJECT", "DROP": return "red"
        default: return "orange"
        }
    }
}
