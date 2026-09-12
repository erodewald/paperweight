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

    /// Replaces an exception with an edited one as a single validated change —
    /// nothing is mutated unless every check passes.
    ///
    /// The deferral rule for an edit: if the edited exception would open any
    /// half-hour today that is quiet right now, today keeps the old exception
    /// (truncated to end tonight) and the new one begins tomorrow. Otherwise the
    /// edit applies outright. An unknown id falls back to a plain add.
    mutating func replaceDayException(id: UUID, with edited: DayException,
                                      now: Date = Date(), calendar: Calendar = .current) throws {
        guard let index = dayExceptions.firstIndex(where: { $0.id == id }) else {
            try addDayException(edited, now: now, calendar: calendar)
            return
        }
        guard edited.firstDay <= edited.lastDay else { throw ExceptionError.endsBeforeStart }
        let others = dayExceptions.filter { $0.id != id }
        if let other = others.first(where: { $0.overlaps(edited) }) {
            throw ExceptionError.overlaps(other)
        }
        let today = DayKey(now, calendar: calendar)
        guard edited.lastDay >= today else { throw ExceptionError.loosensToday }

        var replacement = edited
        replacement.note = String(replacement.note.trimmingCharacters(in: .whitespacesAndNewlines)
                                    .prefix(Self.dayExceptionNoteLimit))
        var result = others

        let before = resolver(calendar: calendar).openSlots(on: today)
        let after = ScheduleResolver(schedule: schedule, exceptions: others + [replacement],
                                     calendar: calendar).openSlots(on: today)
        if !after.isSubset(of: before) {
            // Opening something today has to wait: keep today as it is, start tomorrow.
            let tomorrow = today.next(calendar: calendar)
            guard replacement.lastDay >= tomorrow else { throw ExceptionError.loosensToday }
            replacement.firstDay = max(replacement.firstDay, tomorrow)
            var old = dayExceptions[index]
            if old.covers(today) {
                old.lastDay = today
                result.append(old)
            }
        }

        result.append(replacement)
        result.sort { $0.firstDay < $1.firstDay }
        dayExceptions = result
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
