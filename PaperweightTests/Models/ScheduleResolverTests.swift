import XCTest

final class ScheduleResolverTests: XCTestCase {

    private let cal = Calendar.current

    /// January 2026 — no DST inside the test window. 2026-01-04 is a Sunday.
    private func jan(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 1, day: day, hour: hour, minute: minute))!
    }
    private func key(_ day: Int) -> DayKey { DayKey(year: 2026, month: 1, day: day) }

    /// Weekday evenings 17–21 open; Saturday 9–12 open; Sunday all quiet.
    private var weekly: PaperweightSchedule {
        var s = PaperweightSchedule.weekdayEvenings()
        for hour in 9..<12 { s.setFree(day: 6, hour: hour, true) }
        return s
    }

    private func resolver(_ exceptions: [DayException] = [], schedule: PaperweightSchedule? = nil) -> ScheduleResolver {
        ScheduleResolver(schedule: schedule ?? weekly, exceptions: exceptions, calendar: cal)
    }

    // MARK: Equivalence with the weekly schedule

    func test_withNoExceptionsMatchesTheWeeklyScheduleEverywhere() {
        let r = resolver()
        for day in 4...10 {
            for half in 0..<48 {
                let at = jan(day, half / 2, (half % 2) * 30).addingTimeInterval(7 * 60)
                XCTAssertEqual(r.isFree(at: at), weekly.isFree(at: at, calendar: cal), "\(at)")
                let q1 = r.quietStatus(at: at), q2 = weekly.quietStatus(at: at, calendar: cal)
                XCTAssertEqual(q1?.ends, q2?.ends, "\(at)")
                XCTAssertEqual(q1?.remainingFraction ?? -1, q2?.remainingFraction ?? -1, accuracy: 1e-9, "\(at)")
                let f1 = r.freeStatus(at: at), f2 = weekly.freeStatus(at: at, calendar: cal)
                XCTAssertEqual(f1?.ends, f2?.ends, "\(at)")
                XCTAssertEqual(f1?.elapsedFraction ?? -1, f2?.elapsedFraction ?? -1, accuracy: 1e-9, "\(at)")
            }
        }
    }

    // MARK: Treatments

    func test_openAllDayIsOpenFromMidnightToMidnight() {
        let r = resolver([DayException(firstDay: key(5), lastDay: key(5), treatment: .openAllDay)])
        XCTAssertTrue(r.isFree(at: jan(5, 0, 0)))
        XCTAssertTrue(r.isFree(at: jan(5, 12, 0)))
        XCTAssertTrue(r.isFree(at: jan(5, 23, 59)))
        XCTAssertFalse(r.isFree(at: jan(6, 0, 0)), "Tuesday is an ordinary day again")
    }

    func test_quietAllDayOverridesAnOpenEvening() {
        let r = resolver([DayException(firstDay: key(5), lastDay: key(5), treatment: .quietAllDay)])
        XCTAssertFalse(r.isFree(at: jan(5, 18, 0)))
        XCTAssertTrue(r.isFree(at: jan(6, 18, 0)))
    }

    func test_likeWeekdayReadsThatWeekdaysColumn() {
        // Monday the 5th treated like Saturday: open 9–12, quiet in the evening.
        let r = resolver([DayException(firstDay: key(5), lastDay: key(5), treatment: .likeWeekday(6))])
        XCTAssertTrue(r.isFree(at: jan(5, 10, 0)))
        XCTAssertFalse(r.isFree(at: jan(5, 18, 0)))
    }

    func test_rangeCoversEveryDayInIt() {
        let r = resolver([DayException(firstDay: key(5), lastDay: key(7), treatment: .quietAllDay)])
        XCTAssertFalse(r.isFree(at: jan(6, 18, 0)))
        XCTAssertTrue(r.isFree(at: jan(8, 18, 0)))
    }

    func test_openAllDayOverAnEmptyWeeklyScheduleStillOpens() {
        let r = resolver([DayException(firstDay: key(5), lastDay: key(5), treatment: .openAllDay)],
                         schedule: PaperweightSchedule())
        XCTAssertTrue(r.isFree(at: jan(5, 12, 0)))
        XCTAssertFalse(r.isFree(at: jan(6, 12, 0)))
    }

    // MARK: Countdowns across an edge

    /// Thursday 21:00 → quiet; Friday is a day off; so quiet ends at Friday 00:00.
    func test_quietCountdownEndsAtTheStartOfADayOff() throws {
        let r = resolver([DayException(firstDay: key(9), lastDay: key(9), treatment: .openAllDay)])
        let q = try XCTUnwrap(r.quietStatus(at: jan(8, 22, 0)))
        XCTAssertEqual(q.ends, jan(9, 0, 0))
        XCTAssertEqual(q.remaining, 2 * 3600, accuracy: 1)
    }

    /// Inside a day off at noon: open until the first quiet slot of Saturday (00:00).
    func test_openCountdownInsideADayOffEndsAtTheNextQuietSlot() throws {
        let r = resolver([DayException(firstDay: key(9), lastDay: key(9), treatment: .openAllDay)])
        let f = try XCTUnwrap(r.freeStatus(at: jan(9, 12, 0)))
        XCTAssertEqual(f.ends, jan(10, 0, 0))
        // Thursday 21:00–24:00 is quiet, so the open run is exactly Friday: 24h, half spent at noon.
        XCTAssertEqual(f.elapsedFraction, 0.5, accuracy: 1e-9)
    }

    /// A quiet day on Monday: from Sunday 20:00 the quiet run ends Tuesday 17:00.
    func test_quietCountdownSkipsAQuietDay() throws {
        let r = resolver([DayException(firstDay: key(5), lastDay: key(5), treatment: .quietAllDay)])
        let q = try XCTUnwrap(r.quietStatus(at: jan(4, 20, 0)))
        XCTAssertEqual(q.ends, jan(6, 17, 0))
    }

    func test_nilWhenNoBoundaryWithinAWeek() {
        XCTAssertNil(resolver(schedule: PaperweightSchedule()).quietStatus(at: jan(5, 12, 0)))
        XCTAssertNil(resolver(schedule: .alwaysFree()).freeStatus(at: jan(5, 12, 0)))
    }

    // MARK: Day drawing

    func test_daySegmentsForAnExceptionDay() {
        let r = resolver([DayException(firstDay: key(5), lastDay: key(5), treatment: .quietAllDay)])
        XCTAssertEqual(r.daySegments(on: key(5)), [.init(isLocked: true, fraction: 1)])
        XCTAssertTrue(r.isOpenAllDay(on: key(5)) == false)
        let off = resolver([DayException(firstDay: key(5), lastDay: key(5), treatment: .openAllDay)])
        XCTAssertTrue(off.isOpenAllDay(on: key(5)))
    }

    func test_daySegmentsWithoutAnExceptionMatchTheWeeklyGrid() {
        XCTAssertEqual(resolver().daySegments(on: key(5)), weekly.daySegments(day: 1))
    }

    // MARK: Runs longer than a week

    /// A ten-day quiet range. Near its far end the ring fraction must reflect
    /// the whole run, not a seven-day truncation of it.
    func test_longQuietRangeFractionUsesTheWholeRun() throws {
        // Quiet Mon Jan 5 … Wed Jan 14; Thursday Jan 15 opens at 17:00.
        let r = resolver([DayException(firstDay: key(5), lastDay: key(14), treatment: .quietAllDay)])
        // Sunday Jan 4 is quiet all day in `weekly`, and Saturday Jan 3 was
        // open 9–12, so the run starts Saturday Jan 3 12:00.
        let q = try XCTUnwrap(r.quietStatus(at: jan(14, 12, 0)))
        XCTAssertEqual(q.ends, jan(15, 17, 0))
        let starts = jan(3, 12, 0)
        let total = q.ends.timeIntervalSince(starts)
        XCTAssertEqual(q.remainingFraction, q.remaining / total, accuracy: 1e-9)
        XCTAssertGreaterThan(total, 7 * 24 * 3600, "the run really is longer than a week")
    }

    /// Near the start of the same range the countdown must still find the end.
    func test_longQuietRangeStillHasACountdownAtItsStart() throws {
        let r = resolver([DayException(firstDay: key(5), lastDay: key(14), treatment: .quietAllDay)])
        let q = try XCTUnwrap(r.quietStatus(at: jan(5, 12, 0)))
        XCTAssertEqual(q.ends, jan(15, 17, 0))
    }
}
