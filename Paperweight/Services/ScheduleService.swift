import DeviceActivity
import Foundation

final class ScheduleService {
    static let shared = ScheduleService()
    private let center = DeviceActivityCenter()

    /// DeviceActivity caps the number of simultaneously monitored activities.
    /// We stay well under it; complex schedules are merged into distinct windows.
    private let maxActivities = 18

    /// Registers monitoring for the given schedule when Paperweight is enabled.
    ///
    /// - A repeating DeviceActivity schedule is registered for each distinct free
    ///   window (the monitor re-checks the actual weekday via `isFree(at:)`).
    /// - A daily "heartbeat" window is always registered while enabled, even with
    ///   no free windows, so the monitor runs at least once a day and can enforce
    ///   the auto-unlock failsafe — the escape hatch against a permanent lockout.
    ///
    /// Passing `enabled: false` stops all monitoring.
    func updateSchedule(_ schedule: PaperweightSchedule?, enabled: Bool) {
        center.stopMonitoring(center.activities)
        guard enabled else { return }

        registerHeartbeat()

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

    private func registerHeartbeat() {
        let name = DeviceActivityName("\(Paperweight.activityName).heartbeat")
        let schedule = DeviceActivitySchedule(
            intervalStart: DateComponents(hour: 4, minute: 0),
            intervalEnd: DateComponents(hour: 4, minute: 15),
            repeats: true
        )
        try? center.startMonitoring(name, during: schedule)
    }
}
