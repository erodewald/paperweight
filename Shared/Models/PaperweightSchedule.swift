import Foundation

/// A weekly free-time schedule at 30-minute resolution.
///
/// The week is modeled as 7 days × 48 half-hours = 336 slots. A slot present in
/// `freeSlots` means apps are *free* (unrestricted) during that half-hour; every
/// other half-hour is restricted while Paperweight is enabled.
///
/// Day index is `weekday - 1` (0 = Sunday … 6 = Saturday) to match `Calendar`.
/// Half-hour index is `0…47` (0 = 00:00, 1 = 00:30, … 47 = 23:30).
/// Slot index is `day * 48 + halfHour`.
struct PaperweightSchedule: Codable, Equatable {
    var freeSlots: Set<Int> = []

    static let halfHoursPerDay = 48
    static let dayCount = 7
    static let slotCount = halfHoursPerDay * dayCount

    init(freeSlots: Set<Int> = []) {
        self.freeSlots = freeSlots
    }

    static func slot(day: Int, halfHour: Int) -> Int { day * halfHoursPerDay + halfHour }

    static func halfHour(hour: Int, minute: Int) -> Int { hour * 2 + (minute >= 30 ? 1 : 0) }

    func isFreeSlot(day: Int, halfHour: Int) -> Bool {
        freeSlots.contains(Self.slot(day: day, halfHour: halfHour))
    }

    mutating func setFree(day: Int, halfHour: Int, _ free: Bool) {
        let s = Self.slot(day: day, halfHour: halfHour)
        if free { freeSlots.insert(s) } else { freeSlots.remove(s) }
    }

    /// Convenience: mark a whole clock hour (both half-hours) free or blocked.
    mutating func setFree(day: Int, hour: Int, _ free: Bool) {
        setFree(day: day, halfHour: hour * 2, free)
        setFree(day: day, halfHour: hour * 2 + 1, free)
    }

    /// True when no free time is defined (apps restricted the entire week).
    var isEmpty: Bool { freeSlots.isEmpty }

    /// Number of free hours across the whole week.
    var freeHourCount: Double { Double(freeSlots.count) / 2.0 }

    /// Whether apps are free at the given instant.
    func isFree(at date: Date, calendar: Calendar = .current) -> Bool {
        let comps = calendar.dateComponents([.weekday, .hour, .minute], from: date)
        guard let weekday = comps.weekday, let hour = comps.hour else { return false }
        let half = Self.halfHour(hour: hour, minute: comps.minute ?? 0)
        return isFreeSlot(day: weekday - 1, halfHour: half)
    }

    /// Distinct daily time windows during which apps are free, derived from the
    /// grid. Each window is a contiguous run of free half-hours within a single
    /// day, de-duplicated across days (DeviceActivity schedules repeat daily and
    /// the monitor re-checks the actual weekday).
    func freeWindows() -> [ScheduleWindow] {
        var windows = Set<ScheduleWindow>()
        for day in 0..<Self.dayCount {
            var half = 0
            while half < Self.halfHoursPerDay {
                guard isFreeSlot(day: day, halfHour: half) else { half += 1; continue }
                let start = half
                var end = half
                while end < Self.halfHoursPerDay && isFreeSlot(day: day, halfHour: end) { end += 1 }
                // run is [start, end); DeviceActivity can't express 24:00, so a
                // run reaching end-of-day terminates at 23:59.
                let (endHour, endMinute) = end >= Self.halfHoursPerDay
                    ? (23, 59)
                    : (end / 2, (end % 2) * 30)
                windows.insert(ScheduleWindow(
                    startHour: start / 2, startMinute: (start % 2) * 30,
                    endHour: endHour, endMinute: endMinute))
                half = end
            }
        }
        return windows.sorted {
            ($0.startHour, $0.startMinute, $0.endHour) < ($1.startHour, $1.startMinute, $1.endHour)
        }
    }

    /// A human-readable summary of free windows for a given day index (0 = Sun).
    func summary(forDay day: Int) -> String {
        var parts: [String] = []
        var half = 0
        while half < Self.halfHoursPerDay {
            guard isFreeSlot(day: day, halfHour: half) else { half += 1; continue }
            let start = half
            var end = half
            while end < Self.halfHoursPerDay && isFreeSlot(day: day, halfHour: end) { end += 1 }
            parts.append("\(Self.timeLabel(halfHour: start))–\(Self.timeLabel(halfHour: end))")
            half = end
        }
        return parts.isEmpty ? "Blocked all day" : parts.joined(separator: ", ")
    }

    /// Compact label for the top of a clock hour, e.g. "6a", "12p".
    static func hourLabel(_ hour: Int) -> String {
        let h = hour % 24
        switch h {
        case 0: return "12a"
        case 12: return "12p"
        case let x where x < 12: return "\(x)a"
        default: return "\(h - 12)p"
        }
    }

    /// Compact label for a half-hour index, e.g. "6:30a".
    static func timeLabel(halfHour: Int) -> String {
        let hour = (halfHour / 2) % 24
        let minute = (halfHour % 2) * 30
        let suffix = hour < 12 ? "a" : "p"
        let h12 = hour % 12 == 0 ? 12 : hour % 12
        return minute == 0 ? "\(h12)\(suffix)" : "\(h12):30\(suffix)"
    }

    // MARK: Presets

    static func weekdayEvenings() -> PaperweightSchedule {
        var s = PaperweightSchedule()
        for day in 1...5 { for hour in 17..<21 { s.setFree(day: day, hour: hour, true) } }
        return s
    }

    static func alwaysFree() -> PaperweightSchedule {
        PaperweightSchedule(freeSlots: Set(0..<slotCount))
    }
}

/// A contiguous daily time window (does not cross midnight).
struct ScheduleWindow: Codable, Hashable {
    var startHour: Int
    var startMinute: Int
    var endHour: Int
    var endMinute: Int

    var startComponents: DateComponents { DateComponents(hour: startHour, minute: startMinute) }
    var endComponents: DateComponents { DateComponents(hour: endHour, minute: endMinute) }
}
