import Foundation

/// Answers "is the phone open at this instant, and until when?" with day
/// exceptions layered over the weekly grid. Pure; every shield decision, the
/// widget, and the week strip go through it.
///
/// With no exceptions it gives exactly the weekly schedule's answers — that
/// equivalence is a test.
struct ScheduleResolver {
    let schedule: PaperweightSchedule?
    let exceptions: [DayException]
    let calendar: Calendar

    init(schedule: PaperweightSchedule?, exceptions: [DayException], calendar: Calendar = .current) {
        self.schedule = schedule
        self.exceptions = exceptions
        self.calendar = calendar
    }

    /// The exception covering `day`, if any. Exceptions never overlap, so the
    /// first match is the only match.
    func exception(on day: DayKey) -> DayException? {
        exceptions.first { $0.covers(day) }
    }

    /// The half-hours (0…47) that are open under `treatment` on a day whose
    /// weekday is `weekday`; nil treatment means the plain weekly grid.
    func openSlots(for treatment: DayException.Treatment?, weekday: Int) -> Set<Int> {
        switch treatment {
        case .openAllDay: return Set(0..<PaperweightSchedule.halfHoursPerDay)
        case .quietAllDay: return []
        case .likeWeekday(let w): return weeklyOpenSlots(weekday: w)
        case nil: return weeklyOpenSlots(weekday: weekday)
        }
    }

    /// The half-hours open on a calendar day, exceptions applied.
    func openSlots(on day: DayKey) -> Set<Int> {
        openSlots(for: exception(on: day)?.treatment, weekday: day.weekdayIndex(calendar: calendar))
    }

    private func weeklyOpenSlots(weekday: Int) -> Set<Int> {
        guard let schedule else { return [] }
        return Set((0..<PaperweightSchedule.halfHoursPerDay).filter { schedule.isFreeSlot(day: weekday, halfHour: $0) })
    }

    func isFree(at date: Date) -> Bool {
        openSlots(on: DayKey(date, calendar: calendar)).contains(halfHour(of: date))
    }

    func daySegments(on day: DayKey) -> [PaperweightSchedule.DaySegment] {
        PaperweightSchedule.segments(openSlots: openSlots(on: day))
    }

    func isOpenAllDay(on day: DayKey) -> Bool {
        openSlots(on: day).count == PaperweightSchedule.halfHoursPerDay
    }

    // MARK: Countdowns

    /// While quiet: time until the next open slot, the fraction of this quiet
    /// run still remaining (depleting ring), and when it ends. Nil when open or
    /// when no open slot lies within a week.
    func quietStatus(at date: Date) -> (remaining: TimeInterval, remainingFraction: Double, ends: Date)? {
        guard let run = run(containing: date), !run.isOpen else { return nil }
        let remaining = run.ends.timeIntervalSince(date)
        let total = run.ends.timeIntervalSince(run.starts)
        let fraction = total > 0 ? remaining / total : 0
        return (remaining, max(0, min(1, fraction)), run.ends)
    }

    /// While open: time until the next quiet slot, the fraction of this open
    /// run already spent (filling ring), and when it ends. Nil when quiet or
    /// when no quiet slot lies within a week.
    func freeStatus(at date: Date) -> (remaining: TimeInterval, elapsedFraction: Double, ends: Date)? {
        guard let run = run(containing: date), run.isOpen else { return nil }
        let remaining = run.ends.timeIntervalSince(date)
        let total = run.ends.timeIntervalSince(run.starts)
        let elapsed = total > 0 ? (total - remaining) / total : 0
        return (remaining, max(0, min(1, elapsed)), run.ends)
    }

    // MARK: Slot walking

    private struct Cursor { var day: DayKey; var half: Int }

    private static let maxWalk = PaperweightSchedule.slotCount   // one week of half-hours

    private func halfHour(of date: Date) -> Int {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return PaperweightSchedule.halfHour(hour: c.hour ?? 0, minute: c.minute ?? 0)
    }

    private func next(_ c: Cursor) -> Cursor {
        c.half + 1 < PaperweightSchedule.halfHoursPerDay
            ? Cursor(day: c.day, half: c.half + 1)
            : Cursor(day: c.day.next(calendar: calendar), half: 0)
    }

    private func previous(_ c: Cursor) -> Cursor {
        c.half > 0
            ? Cursor(day: c.day, half: c.half - 1)
            : Cursor(day: c.day.previous(calendar: calendar), half: PaperweightSchedule.halfHoursPerDay - 1)
    }

    private func slotStart(_ c: Cursor) -> Date {
        let dayStart = c.day.date(calendar: calendar)
        return calendar.date(bySettingHour: c.half / 2, minute: (c.half % 2) * 30, second: 0, of: dayStart) ?? dayStart
    }

    /// The contiguous run of same-kind slots containing `date`: whether it is
    /// open, the start of its first slot, and the start of the first slot of
    /// the other kind after it. Nil when the run doesn't end within a week.
    /// Walks by calendar day so a 23- or 25-hour DST day is still one day.
    private func run(containing date: Date) -> (isOpen: Bool, starts: Date, ends: Date)? {
        var cache: [DayKey: Set<Int>] = [:]
        func isOpen(_ c: Cursor) -> Bool {
            if let slots = cache[c.day] { return slots.contains(c.half) }
            let slots = openSlots(on: c.day)
            cache[c.day] = slots
            return slots.contains(c.half)
        }

        let here = Cursor(day: DayKey(date, calendar: calendar), half: halfHour(of: date))
        let open = isOpen(here)

        var ahead = next(here)
        var steps = 1
        while isOpen(ahead) == open {
            if steps >= Self.maxWalk { return nil }
            ahead = next(ahead)
            steps += 1
        }

        var first = here
        steps = 0
        while steps < Self.maxWalk, isOpen(previous(first)) == open {
            first = previous(first)
            steps += 1
        }

        return (open, slotStart(first), slotStart(ahead))
    }
}
