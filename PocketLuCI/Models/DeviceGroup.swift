import Foundation
import SwiftUI

struct DeviceGroup: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var deviceMACs: [String] = []
    var isBlocked: Bool = false
    var blockRuleSectionIDs: [String] = []
    var colorName: String = "blue"

    var color: Color {
        switch colorName {
        case "green": return .green
        case "orange": return .orange
        case "purple": return .purple
        case "red": return .red
        case "teal": return .teal
        default: return .blue
        }
    }

    static let colorOptions = ["blue", "green", "orange", "purple", "red", "teal"]
}
