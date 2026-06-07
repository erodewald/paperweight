import DeviceActivity
import Foundation

final class ScheduleService {
    static let shared = ScheduleService()

    static func dateComponents(from schedule: AllowSchedule) -> (start: DateComponents, end: DateComponents) {
        var start = DateComponents()
        start.hour = schedule.startHour
        start.minute = schedule.startMinute
        var end = DateComponents()
        end.hour = schedule.endHour
        end.minute = schedule.endMinute
        return (start, end)
    }

    func updateSchedule(_ schedule: AllowSchedule?) {
        // Implemented in Task 11
    }
}
