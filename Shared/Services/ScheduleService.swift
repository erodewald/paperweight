import DeviceActivity
import Foundation

/// The slice of `DeviceActivityCenter` the schedule service uses, so tests can
/// see what gets registered without touching the real Screen Time daemon.
protocol DeviceActivityMonitoring {
    var activities: [DeviceActivityName] { get }
    func startMonitoring(_ activity: DeviceActivityName, during schedule: DeviceActivitySchedule) throws
    func stopMonitoring(_ activities: [DeviceActivityName])
}

extension DeviceActivityCenter: DeviceActivityMonitoring {
    func startMonitoring(_ activity: DeviceActivityName, during schedule: DeviceActivitySchedule) throws {
        try startMonitoring(activity, during: schedule, events: [:])
    }
}

final class ScheduleService {
    static let shared = ScheduleService()
    private let center: DeviceActivityMonitoring

    /// DeviceActivity allows this many monitored activities in total and throws
    /// `MonitoringError.excessiveActivities` for any beyond it.
    static let activityCap = 20

    /// How many schedule windows fit once the heartbeats and a possible unlock
    /// expiry have taken their slots. Complex schedules are merged into distinct
    /// windows first, so a real schedule rarely comes near this.
    private var maxWindows: Int { Self.activityCap - Self.heartbeatHours.count - 1 }

    /// DeviceActivity refuses intervals shorter than this
    /// (`MonitoringError.intervalTooShort`).
    static let minimumInterval: TimeInterval = 15 * 60

    init(center: DeviceActivityMonitoring = DeviceActivityCenter()) {
        self.center = center
    }

    /// Brings DeviceActivity monitoring in line with `config`. Safe to call any
    /// time; it replaces whatever was registered before.
    ///
    /// While enabled, this registers:
    /// - A repeating schedule for each distinct free window of the active
    ///   schedule *and* of any pending (deferred-loosening) schedule. A pending
    ///   edit lands at the day boundary inside the monitor extension, which can't
    ///   register anything, so its boundaries have to be on the books up front.
    ///   Extra boundaries are harmless: the monitor re-derives the truth from
    ///   the saved config at every callback.
    /// - A few "heartbeat" windows a day, even with no free windows, so the
    ///   monitor runs regularly: it enforces the auto-unlock failsafe — the
    ///   escape hatch against a permanent lockout — and repairs the shield after
    ///   a dropped boundary callback.
    /// - While a timed NFC unlock is live, a one-shot activity at its expiry.
    ///   The app is suspended seconds after the user leaves it, so an
    ///   in-process timer can't be trusted to re-shield; the monitor extension
    ///   always runs.
    ///
    /// Passing a disabled config stops all monitoring.
    func sync(config: PaperweightConfig, now: Date = Date()) {
        center.stopMonitoring(center.activities)
        guard config.isEnabled else { return }

        registerHeartbeat()
        registerUnlockExpiry(config.unlockExpiresAt, now: now)

        var windows = Set<ScheduleWindow>()
        if let schedule = config.schedule { windows.formUnion(schedule.freeWindows()) }
        if let pending = config.pendingSchedule { windows.formUnion(pending.freeWindows()) }
        let ordered = windows.sorted {
            ($0.startHour, $0.startMinute, $0.endHour, $0.endMinute)
                < ($1.startHour, $1.startMinute, $1.endHour, $1.endMinute)
        }
        for (index, window) in ordered.prefix(maxWindows).enumerated() {
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

    /// Hours at which a heartbeat fires. DeviceActivity does drop boundary
    /// callbacks now and then, and a dropped one used to leave the wrong shield
    /// state for up to a day; four a day bounds that to six hours. Midnight is
    /// also the only boundary an open-all-day or quiet-all-day exception has.
    static let heartbeatHours = [0, 6, 12, 18]

    private func registerHeartbeat() {
        for hour in Self.heartbeatHours {
            let name = DeviceActivityName(String(format: "%@.heartbeat%02d", Paperweight.activityName, hour))
            let schedule = DeviceActivitySchedule(
                intervalStart: DateComponents(hour: hour, minute: 0),
                intervalEnd: DateComponents(hour: hour, minute: 15),
                repeats: true
            )
            try? center.startMonitoring(name, during: schedule)
        }
    }

    /// Registers a non-repeating activity whose start is the moment the monitor
    /// should re-apply the shield after a timed unlock.
    ///
    /// The start is the expiry rounded *up* to the next whole minute, plus one
    /// more minute of margin. DeviceActivity works at minute granularity, and a
    /// callback that runs even a second before `unlockExpiresAt` would find the
    /// unlock still live and lift the shield again. A minute or two late is the
    /// right side to err on.
    private func registerUnlockExpiry(_ expiry: Date?, now: Date, calendar: Calendar = .current) {
        guard let expiry, expiry > now else { return }
        let ceiled = expiry.timeIntervalSinceReferenceDate.rounded(.up) // whole second
        let wholeMinute = (ceiled / 60).rounded(.up) * 60
        let start = Date(timeIntervalSinceReferenceDate: wholeMinute + 60)
        let end = start.addingTimeInterval(Self.minimumInterval)
        let fields: Set<Calendar.Component> = [.year, .month, .day, .hour, .minute, .second]
        let schedule = DeviceActivitySchedule(
            intervalStart: calendar.dateComponents(fields, from: start),
            intervalEnd: calendar.dateComponents(fields, from: end),
            repeats: false
        )
        let name = DeviceActivityName("\(Paperweight.activityName).unlockExpiry")
        do {
            try center.startMonitoring(name, during: schedule)
        } catch {
            print("ScheduleService: startMonitoring failed for \(name): \(error)")
        }
    }
}
