import SwiftUI

struct ScheduleEditorView: View {
    let groupID: UUID
    let onSave: (AccessSchedule) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var name = "Bedtime"
    @State private var selectedDays: Set<Int> = [1, 2, 3, 4, 5]
    @State private var startHour = 22
    @State private var startMinute = 0
    @State private var endHour = 7
    @State private var endMinute = 0

    private let dayNames = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    var body: some View {
        NavigationStack {
            Form {
                Section("Schedule Name") {
                    TextField("e.g. Bedtime, School hours", text: $name)
                }

                Section("Days") {
                    HStack(spacing: 8) {
                        ForEach(0..<7, id: \.self) { day in
                            DayToggle(label: dayNames[day], isSelected: selectedDays.contains(day)) {
                                if selectedDays.contains(day) {
                                    selectedDays.remove(day)
                                } else {
                                    selectedDays.insert(day)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)

                    HStack {
                        quickButton("Weekdays") { selectedDays = [1, 2, 3, 4, 5] }
                        quickButton("Weekends") { selectedDays = [0, 6] }
                        quickButton("Every day") { selectedDays = Set(0...6) }
                    }
                }

                Section("Block Internet From") {
                    TimePicker(label: "Start", hour: $startHour, minute: $startMinute)
                }

                Section("Until") {
                    TimePicker(label: "End", hour: $endHour, minute: $endMinute)
                }

                Section {
                    HStack {
                        Image(systemName: "info.circle")
                            .foregroundStyle(.secondary)
                        Text("Schedules are enforced on the router via cron jobs. Changes apply immediately if the router is reachable.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("New Schedule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        let schedule = AccessSchedule(
                            name: name.trimmingCharacters(in: .whitespaces).isEmpty ? "Schedule" : name,
                            groupID: groupID,
                            daysOfWeek: selectedDays.sorted(),
                            startHour: startHour,
                            startMinute: startMinute,
                            endHour: endHour,
                            endMinute: endMinute
                        )
                        onSave(schedule)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(selectedDays.isEmpty)
                }
            }
        }
    }

    private func quickButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .font(.caption)
            .buttonStyle(.bordered)
            .controlSize(.small)
    }
}

struct DayToggle: View {
    let label: String
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Text(label)
            .font(.caption2)
            .fontWeight(.semibold)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(isSelected ? Color.accentColor : Color.secondary.opacity(0.15))
            .foregroundStyle(isSelected ? .white : .primary)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .onTapGesture(perform: onTap)
    }
}

struct TimePicker: View {
    let label: String
    @Binding var hour: Int
    @Binding var minute: Int

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            HStack(spacing: 4) {
                Picker("Hour", selection: $hour) {
                    ForEach(0..<24, id: \.self) { h in
                        Text(String(format: "%02d", h)).tag(h)
                    }
                }
                .pickerStyle(.wheel)
                .frame(width: 60, height: 100)
                .clipped()

                Text(":")
                    .font(.title2)
                    .fontWeight(.bold)

                Picker("Minute", selection: $minute) {
                    ForEach([0, 15, 30, 45], id: \.self) { m in
                        Text(String(format: "%02d", m)).tag(m)
                    }
                }
                .pickerStyle(.wheel)
                .frame(width: 60, height: 100)
                .clipped()
            }
        }
    }
}

#Preview {
    ScheduleEditorView(groupID: UUID()) { _ in }
}
