import DeviceActivity
import Foundation

final class ScheduleService {
    static let shared = ScheduleService()
    private let center = DeviceActivityCenter()
    private let activityName = DeviceActivityName(Paperweight.activityName)

    static func dateComponents(from schedule: AllowSchedule) -> (start: DateComponents, end: DateComponents) {
        schedule.dateComponents()
    }

    func updateSchedule(_ schedule: AllowSchedule?) {
        center.stopMonitoring([activityName])
        guard let schedule, schedule.isValid else { return }

        let (start, end) = schedule.dateComponents()
        let deviceSchedule = DeviceActivitySchedule(
            intervalStart: start,
            intervalEnd: end,
            repeats: true
        )
        do {
            try center.startMonitoring(activityName, during: deviceSchedule)
        } catch {
            print("ScheduleService: startMonitoring failed: \(error)")
        }
    }
}
