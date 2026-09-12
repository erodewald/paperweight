import XCTest

final class DayExceptionRuleTests: XCTestCase {

    private let cal = Calendar.current

    /// "Now" is Monday 2026-01-05 at 10:00. Weekday evenings 17–21 are open;
    /// Saturday 9–12 is open; Sunday is all quiet.
    private var now: Date { cal.date(from: DateComponents(year: 2026, month: 1, day: 5, hour: 10))! }
    private func key(_ day: Int) -> DayKey { DayKey(year: 2026, month: 1, day: day) }

    private func armedConfig() -> PaperweightConfig {
        var c = PaperweightConfig()
        c.isEnabled = true
        var s = PaperweightSchedule.weekdayEvenings()
        for hour in 9..<12 { s.setFree(day: 6, hour: hour, true) }
        c.schedule = s
        return c
    }

    private func exception(_ first: Int, _ last: Int, _ t: DayException.Treatment) -> DayException {
        DayException(firstDay: key(first), lastDay: key(last), treatment: t)
    }

    // MARK: Adding

    func test_dayOffTodayIsRefused() {
        var c = armedConfig()
        XCTAssertThrowsError(try c.addDayException(exception(5, 5, .openAllDay), now: now, calendar: cal)) {
            XCTAssertEqual($0 as? PaperweightConfig.ExceptionError, .loosensToday)
        }
        XCTAssertTrue(c.dayExceptions.isEmpty)
    }

    func test_dayOffTomorrowIsAllowed() throws {
        var c = armedConfig()
        try c.addDayException(exception(6, 6, .openAllDay), now: now, calendar: cal)
        XCTAssertEqual(c.dayExceptions.count, 1)
    }

    func test_quietDayTodayIsAllowed() throws {
        var c = armedConfig()
        try c.addDayException(exception(5, 5, .quietAllDay), now: now, calendar: cal)
        XCTAssertEqual(c.dayExceptions.count, 1)
    }

    /// Monday like Sunday (all quiet) tightens; Monday like Saturday (9–12 open) loosens.
    func test_likeWeekdayTodayIsAllowedOnlyWhenItTightens() throws {
        var c = armedConfig()
        try c.addDayException(exception(5, 5, .likeWeekday(0)), now: now, calendar: cal)
        var d = armedConfig()
        XCTAssertThrowsError(try d.addDayException(exception(5, 5, .likeWeekday(6)), now: now, calendar: cal))
    }

    /// Monday like Monday is a no-op: it changes nothing about today, so it is
    /// allowed and leaves `isFree` exactly as the weekly schedule already says.
    func test_likeWeekdayOfItsOwnWeekdayIsANoOpToday() throws {
        var c = armedConfig()
        try c.addDayException(exception(5, 5, .likeWeekday(1)), now: now, calendar: cal)
        let at = cal.date(from: DateComponents(year: 2026, month: 1, day: 5, hour: 18))!
        XCTAssertEqual(c.resolver.isFree(at: at), c.schedule!.isFree(at: at, calendar: cal))
    }

    func test_pastStartIsRefused() {
        var c = armedConfig()
        XCTAssertThrowsError(try c.addDayException(exception(4, 6, .quietAllDay), now: now, calendar: cal)) {
            XCTAssertEqual($0 as? PaperweightConfig.ExceptionError, .loosensToday)
        }
    }

    func test_endBeforeStartIsRefused() {
        var c = armedConfig()
        XCTAssertThrowsError(try c.addDayException(exception(8, 6, .quietAllDay), now: now, calendar: cal)) {
            XCTAssertEqual($0 as? PaperweightConfig.ExceptionError, .endsBeforeStart)
        }
    }

    func test_overlapIsRefusedAndNamesTheOther() throws {
        var c = armedConfig()
        let existing = exception(7, 9, .openAllDay)
        try c.addDayException(existing, now: now, calendar: cal)
        XCTAssertThrowsError(try c.addDayException(exception(9, 10, .quietAllDay), now: now, calendar: cal)) {
            XCTAssertEqual($0 as? PaperweightConfig.ExceptionError, .overlaps(existing))
        }
    }

    func test_addTrimsAndCapsTheNote() throws {
        var c = armedConfig()
        var e = exception(6, 6, .openAllDay)
        e.note = "  " + String(repeating: "x", count: 60) + "  "
        try c.addDayException(e, now: now, calendar: cal)
        XCTAssertEqual(c.dayExceptions[0].note.count, 40)
    }

    func test_addKeepsTheListSortedByFirstDay() throws {
        var c = armedConfig()
        try c.addDayException(exception(9, 9, .openAllDay), now: now, calendar: cal)
        try c.addDayException(exception(6, 6, .openAllDay), now: now, calendar: cal)
        XCTAssertEqual(c.dayExceptions.map(\.firstDay), [key(6), key(9)])
    }

    /// A quiet range crossing a month end resolves correctly on the far side.
    func test_addDayExceptionRangeCrossingAMonthEnd() throws {
        var c = armedConfig()
        let e = DayException(firstDay: DayKey(year: 2026, month: 1, day: 30),
                             lastDay: DayKey(year: 2026, month: 2, day: 2),
                             treatment: .quietAllDay)
        try c.addDayException(e, now: now, calendar: cal)
        // Feb 2, 2026 is a Monday, normally open 17:00–21:00 — quiet here instead.
        let at = cal.date(from: DateComponents(year: 2026, month: 2, day: 2, hour: 18))!
        XCTAssertFalse(c.resolver.isFree(at: at))
    }

    // MARK: Removing

    func test_removingATodayTighteningThatHidesAnOpenWindowTruncates() throws {
        var c = armedConfig()
        let e = exception(5, 5, .likeWeekday(0))   // today, tightening — allowed
        try c.addDayException(e, now: now, calendar: cal)
        // Removing it would restore this evening's open window: a loosening, so it ends tonight.
        XCTAssertEqual(c.removeDayException(id: e.id, now: now, calendar: cal), .truncatedToToday)
        XCTAssertEqual(c.dayExceptions[0].lastDay, key(5))
    }

    func test_removingAnUpcomingDayOffDeletesIt() throws {
        var c = armedConfig()
        let e = exception(6, 6, .openAllDay)
        try c.addDayException(e, now: now, calendar: cal)
        XCTAssertEqual(c.removeDayException(id: e.id, now: now, calendar: cal), .removed)
        XCTAssertTrue(c.dayExceptions.isEmpty)
    }

    func test_removingTodaysQuietDayEndsTonight() throws {
        var c = armedConfig()
        let e = exception(5, 8, .quietAllDay)
        try c.addDayException(e, now: now, calendar: cal)
        XCTAssertEqual(c.removeDayException(id: e.id, now: now, calendar: cal), .truncatedToToday)
        XCTAssertEqual(c.dayExceptions[0].firstDay, key(5))
        XCTAssertEqual(c.dayExceptions[0].lastDay, key(5))
    }

    /// A quiet Sunday-through-Wednesday started yesterday; removing it on Monday
    /// keeps Sunday and Monday, drops Tuesday and Wednesday.
    func test_removingARunningQuietRangeTruncatesToToday() throws {
        var c = armedConfig()
        c.dayExceptions = [exception(4, 7, .quietAllDay)]
        XCTAssertEqual(c.removeDayException(id: c.dayExceptions[0].id, now: now, calendar: cal), .truncatedToToday)
        XCTAssertEqual(c.dayExceptions[0].lastDay, key(5))
    }

    /// Today is a quiet Sunday-pattern day, and Sunday is all quiet anyway — the
    /// weekly grid has no open slot the exception hides, so removal is immediate.
    func test_removingATodayExceptionThatHidesNothingIsImmediate() throws {
        var c = armedConfig()
        c.schedule = PaperweightSchedule()                       // whole week quiet
        c.dayExceptions = [exception(5, 5, .quietAllDay)]
        XCTAssertEqual(c.removeDayException(id: c.dayExceptions[0].id, now: now, calendar: cal), .removed)
    }

    func test_removingUnknownIDIsNotFound() {
        var c = armedConfig()
        XCTAssertEqual(c.removeDayException(id: UUID(), now: now, calendar: cal), .notFound)
    }

    // MARK: Replacing (edit)

    /// Editing only the note of a range that is in force today keeps the range whole.
    func test_replaceNoteOnlyOnARunningRangeKeepsItWhole() throws {
        var c = armedConfig()
        var old = exception(4, 9, .quietAllDay)        // Sun–Fri, today is Mon
        old.note = "Exams"
        c.dayExceptions = [old]
        var new = old
        new.note = "Finals"
        try c.replaceDayException(id: old.id, with: new, now: now, calendar: cal)
        XCTAssertEqual(c.dayExceptions.count, 1)
        XCTAssertEqual(c.dayExceptions[0].firstDay, key(4))
        XCTAssertEqual(c.dayExceptions[0].lastDay, key(9))
        XCTAssertEqual(c.dayExceptions[0].note, "Finals")
    }

    /// Shortening a running quiet range changes nothing about today: applied outright.
    func test_replaceShorteningARunningRangeAppliesOutright() throws {
        var c = armedConfig()
        let old = exception(4, 9, .quietAllDay)
        c.dayExceptions = [old]
        var new = old
        new.lastDay = key(6)
        try c.replaceDayException(id: old.id, with: new, now: now, calendar: cal)
        XCTAssertEqual(c.dayExceptions.map(\.lastDay), [key(6)])
    }

    /// Turning a running quiet range into a day off would open tonight: today keeps
    /// the old exception and the new one begins tomorrow.
    func test_replaceThatLoosensTodayKeepsTodayAndStartsTomorrow() throws {
        var c = armedConfig()
        let old = exception(4, 9, .quietAllDay)
        c.dayExceptions = [old]
        var new = old
        new.treatment = .openAllDay
        try c.replaceDayException(id: old.id, with: new, now: now, calendar: cal)
        XCTAssertEqual(c.dayExceptions.count, 2)
        XCTAssertEqual(c.dayExceptions[0].id, old.id)
        XCTAssertEqual(c.dayExceptions[0].lastDay, key(5), "the old quiet day ends tonight")
        XCTAssertEqual(c.dayExceptions[1].firstDay, key(6))
        XCTAssertEqual(c.dayExceptions[1].lastDay, key(9))
        XCTAssertEqual(c.dayExceptions[1].treatment, .openAllDay)
    }

    /// A loosening edit that would only ever apply today has nothing left to apply.
    func test_replaceThatLoosensOnlyTodayIsRefused() {
        var c = armedConfig()
        let old = exception(5, 5, .quietAllDay)
        c.dayExceptions = [old]
        var new = old
        new.treatment = .openAllDay
        XCTAssertThrowsError(try c.replaceDayException(id: old.id, with: new, now: now, calendar: cal)) {
            XCTAssertEqual($0 as? PaperweightConfig.ExceptionError, .loosensToday)
        }
        XCTAssertEqual(c.dayExceptions, [old], "nothing changed")
    }

    func test_replaceOverlappingAnotherIsRefusedAndChangesNothing() throws {
        var c = armedConfig()
        let old = exception(6, 6, .openAllDay)
        let other = exception(8, 9, .openAllDay)
        c.dayExceptions = [old, other]
        var new = old
        new.lastDay = key(8)
        XCTAssertThrowsError(try c.replaceDayException(id: old.id, with: new, now: now, calendar: cal)) {
            XCTAssertEqual($0 as? PaperweightConfig.ExceptionError, .overlaps(other))
        }
        XCTAssertEqual(c.dayExceptions, [old, other])
    }

    func test_replaceAnUpcomingExceptionMovesIt() throws {
        var c = armedConfig()
        let old = exception(9, 9, .openAllDay)
        c.dayExceptions = [old]
        var new = old
        new.firstDay = key(10); new.lastDay = key(10)
        try c.replaceDayException(id: old.id, with: new, now: now, calendar: cal)
        XCTAssertEqual(c.dayExceptions.map(\.firstDay), [key(10)])
    }

    /// Editing an upcoming day off into one that starts today is a loosening today:
    /// it begins tomorrow instead.
    func test_replacePullingADayOffForwardToTodayStartsTomorrow() throws {
        var c = armedConfig()
        let old = exception(9, 9, .openAllDay)
        c.dayExceptions = [old]
        var new = old
        new.firstDay = key(5)
        try c.replaceDayException(id: old.id, with: new, now: now, calendar: cal)
        XCTAssertEqual(c.dayExceptions.count, 1)
        XCTAssertEqual(c.dayExceptions[0].firstDay, key(6))
        XCTAssertEqual(c.dayExceptions[0].lastDay, key(9))
    }

    /// A split keeps the old exception's id on the truncated remnant and gives the
    /// edited one a fresh id, so the list never holds two rows with the same id.
    func test_replaceSplitNeverDuplicatesIDs() throws {
        var c = armedConfig()
        let old = exception(4, 9, .quietAllDay)
        c.dayExceptions = [old]
        var new = old                       // same id, as the sheet passes it
        new.treatment = .openAllDay
        try c.replaceDayException(id: old.id, with: new, now: now, calendar: cal)
        XCTAssertEqual(Set(c.dayExceptions.map(\.id)).count, c.dayExceptions.count)
        XCTAssertEqual(c.dayExceptions[0].id, old.id)
    }

    /// A plain replace keeps the id the caller passed, so identity survives an edit.
    func test_replaceKeepsTheEditedID() throws {
        var c = armedConfig()
        let old = exception(9, 9, .openAllDay)
        c.dayExceptions = [old]
        var new = old
        new.note = "Trip"
        try c.replaceDayException(id: old.id, with: new, now: now, calendar: cal)
        XCTAssertEqual(c.dayExceptions.map(\.id), [old.id])
    }

    /// An unknown id falls back to a plain add rather than failing silently.
    func test_replaceWithUnknownIDFallsBackToAdd() throws {
        var c = armedConfig()
        c.dayExceptions = [exception(9, 9, .openAllDay)]
        try c.replaceDayException(id: UUID(), with: exception(11, 11, .quietAllDay), now: now, calendar: cal)
        XCTAssertEqual(c.dayExceptions.count, 2)
    }

    // MARK: Pruning and listing

    func test_pruneDropsPastKeepsTodayAndLater() {
        var c = armedConfig()
        c.dayExceptions = [exception(1, 4, .openAllDay), exception(3, 5, .quietAllDay), exception(9, 9, .openAllDay)]
        XCTAssertTrue(c.pruneDayExceptions(now: now, calendar: cal))
        XCTAssertEqual(c.dayExceptions.map(\.firstDay), [key(3), key(9)])
        XCTAssertFalse(c.pruneDayExceptions(now: now, calendar: cal), "nothing left to drop")
    }

    func test_upcomingIsSortedAndExcludesPast() {
        var c = armedConfig()
        c.dayExceptions = [exception(9, 9, .openAllDay), exception(1, 2, .openAllDay), exception(5, 5, .quietAllDay)]
        XCTAssertEqual(c.upcomingDayExceptions(now: now, calendar: cal).map(\.firstDay), [key(5), key(9)])
    }
}
