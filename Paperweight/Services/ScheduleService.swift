import DeviceActivity
import Foundation

final class ScheduleService {
    static let shared = ScheduleService()
    private let center = DeviceActivityCenter()

    /// DeviceActivity caps the number of simultaneously monitored activities.
    /// We stay well under it; complex schedules are merged into distinct windows.
    private let maxActivities = 18

    /// Registers a repeating DeviceActivity schedule for each distinct free
    /// window. Each window repeats *daily*; the monitor re-checks the actual
    /// weekday via `PaperweightSchedule.isFree(at:)` so weekday filtering is
    /// handled there. Passing `nil` stops all monitoring.
    func updateSchedule(_ schedule: PaperweightSchedule?) {
        center.stopMonitoring(center.activities)
        guard let schedule, !schedule.isEmpty else { return }

        let windows = schedule.freeWindows().prefix(maxActivities)
        for (index, window) in windows.enumerated() {
            let name = DeviceActivityName("\(Paperweight.activityName).\(index)")
            let deviceSchedule = DeviceActivitySchedule(
                intervalStart: window.startComponents,
                intervalEnd: window.endComponents,
                repeats: true
            )
            do {
                try center.startMonitoring(name, during: deviceSchedule)
            } catch {
                print("ScheduleService: startMonitoring failed for \(name): \(error)")
            }
        }
    }
}
