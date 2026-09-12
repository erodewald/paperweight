import Foundation

extension PaperweightConfig {

    var resolver: ScheduleResolver { resolver(calendar: .current) }

    func resolver(calendar: Calendar) -> ScheduleResolver {
        ScheduleResolver(schedule: schedule, exceptions: dayExceptions, calendar: calendar)
    }

    enum ExceptionError: Error, Equatable {
        case overlaps(DayException)
        case loosensToday
        case endsBeforeStart
    }

    enum ExceptionRemoval: Equatable {
        case removed, truncatedToToday, notFound
    }

    static let dayExceptionNoteLimit = 40

    /// Whether `treatment` on `day` would open any half-hour that is quiet under
    /// the schedule in force that day — exceptions included. Pure; the add
    /// sheet uses it to grey out today.
    func exceptionLoosens(_ treatment: DayException.Treatment, on day: DayKey,
                          calendar: Calendar = .current) -> Bool {
        let r = resolver(calendar: calendar)
        let current = r.openSlots(on: day)
        let proposed = r.openSlots(for: treatment, weekday: day.weekdayIndex(calendar: calendar))
        return !proposed.isSubset(of: current)
    }

    /// Adds an exception under the deferral rule, or throws.
    ///
    /// Tightening may start today. Loosening may not start before tomorrow —
    /// the same "sleep on it" boundary as a schedule edit. A start in the past
    /// is refused as `loosensToday` too: there is no separate message worth
    /// having for it.
    mutating func addDayException(_ exception: DayException, now: Date = Date(),
                                  calendar: Calendar = .current) throws {
        guard exception.firstDay <= exception.lastDay else { throw ExceptionError.endsBeforeStart }
        if let other = dayExceptions.first(where: { $0.overlaps(exception) }) {
            throw ExceptionError.overlaps(other)
        }
        let today = DayKey(now, calendar: calendar)
        if exception.firstDay < today { throw ExceptionError.loosensToday }
        if exception.firstDay == today,
           exceptionLoosens(exception.treatment, on: today, calendar: calendar) {
            throw ExceptionError.loosensToday
        }

        var e = exception
        e.note = String(e.note.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.dayExceptionNoteLimit))
        dayExceptions.append(e)
        dayExceptions.sort { $0.firstDay < $1.firstDay }
    }

    /// Removes an exception under the deferral rule. If removing it would open
    /// any half-hour today, it is truncated to end today instead — a quiet day
    /// "ends tonight" rather than at once.
    @discardableResult
    mutating func removeDayException(id: UUID, now: Date = Date(),
                                     calendar: Calendar = .current) -> ExceptionRemoval {
        guard let index = dayExceptions.firstIndex(where: { $0.id == id }) else { return .notFound }
        let today = DayKey(now, calendar: calendar)
        let exception = dayExceptions[index]

        if exception.covers(today) {
            let withIt = resolver(calendar: calendar).openSlots(on: today)
            let without = ScheduleResolver(schedule: schedule,
                                           exceptions: dayExceptions.filter { $0.id != id },
                                           calendar: calendar).openSlots(on: today)
            if !without.isSubset(of: withIt) {
                dayExceptions[index].lastDay = today
                return .truncatedToToday
            }
        }
        dayExceptions.remove(at: index)
        return .removed
    }

    /// Drops exceptions that ended before today. Returns whether anything changed.
    @discardableResult
    mutating func pruneDayExceptions(now: Date = Date(), calendar: Calendar = .current) -> Bool {
        let today = DayKey(now, calendar: calendar)
        let before = dayExceptions.count
        dayExceptions.removeAll { $0.lastDay < today }
        return dayExceptions.count != before
    }

    /// Exceptions that are today or later, soonest first.
    func upcomingDayExceptions(now: Date = Date(), calendar: Calendar = .current) -> [DayException] {
        let today = DayKey(now, calendar: calendar)
        return dayExceptions.filter { $0.lastDay >= today }.sorted { $0.firstDay < $1.firstDay }
    }
}
