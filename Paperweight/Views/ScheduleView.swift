import SwiftUI

struct ScheduleView: View {
    @ObservedObject var vm: HomeViewModel
    @State private var scheduleEnabled: Bool
    @State private var startHour: Int
    @State private var startMinute: Int
    @State private var endHour: Int
    @State private var endMinute: Int
    @State private var weekdays: Set<Int>

    init(vm: HomeViewModel) {
        self.vm = vm
        let s = vm.config.schedule
        _scheduleEnabled = State(initialValue: s != nil)
        _startHour = State(initialValue: s?.startHour ?? 9)
        _startMinute = State(initialValue: s?.startMinute ?? 0)
        _endHour = State(initialValue: s?.endHour ?? 22)
        _endMinute = State(initialValue: s?.endMinute ?? 0)
        _weekdays = State(initialValue: s?.weekdays ?? Set(1...7))
    }

    var body: some View {
        Form {
            Section {
                Toggle("Use a schedule", isOn: $scheduleEnabled)
            } footer: {
                Text(scheduleEnabled
                     ? "Apps are free during the window below. Restricted all other times."
                     : "No schedule — apps are always restricted while Paperweight is on.")
            }

            if scheduleEnabled {
                Section("Free Window") {
                    TimePicker(label: "Start", hour: $startHour, minute: $startMinute)
                    TimePicker(label: "End", hour: $endHour, minute: $endMinute)
                }

                Section("Days") {
                    WeekdayPicker(selection: $weekdays)
                }

                if !currentSchedule.isValid {
                    Section {
                        Label("End time must be after start time.", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                }
            }
        }
        .navigationTitle("Schedule")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
                    .disabled(scheduleEnabled && !currentSchedule.isValid)
            }
        }
    }

    private var currentSchedule: AllowSchedule {
        AllowSchedule(startHour: startHour, startMinute: startMinute,
                      endHour: endHour, endMinute: endMinute, weekdays: weekdays)
    }

    private func save() {
        vm.config.schedule = scheduleEnabled ? currentSchedule : nil
        vm.saveSelection()
        ScheduleService.shared.updateSchedule(vm.config.schedule)
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
            Picker("Hour", selection: $hour) {
                ForEach(0..<24, id: \.self) { h in
                    Text(String(format: "%02d", h)).tag(h)
                }
            }
            .pickerStyle(.wheel)
            .frame(width: 60)
            Text(":")
            Picker("Minute", selection: $minute) {
                ForEach([0, 15, 30, 45], id: \.self) { m in
                    Text(String(format: "%02d", m)).tag(m)
                }
            }
            .pickerStyle(.wheel)
            .frame(width: 60)
        }
    }
}

struct WeekdayPicker: View {
    @Binding var selection: Set<Int>
    private let days = [(1,"Su"),(2,"Mo"),(3,"Tu"),(4,"We"),(5,"Th"),(6,"Fr"),(7,"Sa")]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(days, id: \.0) { (num, label) in
                let selected = selection.contains(num)
                Button(label) {
                    if selected { selection.remove(num) } else { selection.insert(num) }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(selected ? Color.orange : Color(.systemGray5))
                .foregroundStyle(selected ? .white : .primary)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .font(.caption.bold())
            }
        }
    }
}
