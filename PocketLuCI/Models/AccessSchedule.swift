import Foundation

struct AccessSchedule: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var groupID: UUID
    var daysOfWeek: [Int] = []
    var startHour: Int = 22
    var startMinute: Int = 0
    var endHour: Int = 7
    var endMinute: Int = 0
    var isEnabled: Bool = true

    var startTimeDisplay: String { String(format: "%02d:%02d", startHour, startMinute) }
    var endTimeDisplay: String { String(format: "%02d:%02d", endHour, endMinute) }

    var daysDisplay: String {
        let names = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        let sorted = daysOfWeek.sorted()
        if sorted.count == 7 { return "Every day" }
        if sorted == [1, 2, 3, 4, 5] { return "Weekdays" }
        if sorted == [0, 6] { return "Weekends" }
        return sorted.map { names[$0] }.joined(separator: ", ")
    }

    var isActiveNow: Bool {
        let cal = Calendar.current
        let now = Date()
        let weekday = cal.component(.weekday, from: now) - 1
        guard daysOfWeek.contains(weekday) else { return false }
        let h = cal.component(.hour, from: now)
        let m = cal.component(.minute, from: now)
        let cur = h * 60 + m
        let start = startHour * 60 + startMinute
        let end = endHour * 60 + endMinute
        return start < end ? (cur >= start && cur < end) : (cur >= start || cur < end)
    }
}
