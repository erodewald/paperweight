import XCTest

final class WeekSegmentTests: XCTestCase {

    /// A day with nothing marked open is one full locked run.
    func test_emptyScheduleIsOneLockedRun() {
        let segments = PaperweightSchedule().daySegments(day: 0)
        XCTAssertEqual(segments, [.init(isLocked: true, fraction: 1)])
    }

    /// An all-open day is one full open run.
    func test_alwaysFreeIsOneOpenRun() {
        let segments = PaperweightSchedule.alwaysFree().daySegments(day: 3)
        XCTAssertEqual(segments, [.init(isLocked: false, fraction: 1)])
    }

    /// Open 07:00–21:00 on Monday: locked 7h, open 14h, locked 3h.
    func test_runsAreOrderedFromMidnightAndSumToOne() {
        var s = PaperweightSchedule()
        for hour in 7..<21 { s.setFree(day: 1, hour: hour, true) }
        let segments = s.daySegments(day: 1)

        XCTAssertEqual(segments.count, 3)
        XCTAssertEqual(segments[0].isLocked, true)
        XCTAssertEqual(segments[0].fraction, 7.0 / 24.0, accuracy: 0.0001)
        XCTAssertEqual(segments[1].isLocked, false)
        XCTAssertEqual(segments[1].fraction, 14.0 / 24.0, accuracy: 0.0001)
        XCTAssertEqual(segments[2].isLocked, true)
        XCTAssertEqual(segments[2].fraction, 3.0 / 24.0, accuracy: 0.0001)
        XCTAssertEqual(segments.reduce(0) { $0 + $1.fraction }, 1, accuracy: 0.0001)
    }

    /// Half-hour resolution survives — a 30-minute open run is its own segment.
    func test_halfHourRunsAreNotRoundedAway() {
        var s = PaperweightSchedule()
        s.setFree(day: 2, halfHour: 20, true)   // 10:00–10:30
        let segments = s.daySegments(day: 2)

        XCTAssertEqual(segments.count, 3)
        XCTAssertEqual(segments[1].isLocked, false)
        XCTAssertEqual(segments[1].fraction, 0.5 / 24.0, accuracy: 0.0001)
    }

    func test_isOpenAllDayOnlyWhenEverySlotIsOpen() {
        var s = PaperweightSchedule.alwaysFree()
        XCTAssertTrue(s.isOpenAllDay(day: 6))

        s.setFree(day: 6, hour: 3, false)
        XCTAssertFalse(s.isOpenAllDay(day: 6))
        XCTAssertTrue(s.isOpenAllDay(day: 5))
    }

    /// Quiet hours are the inverse of open hours across the 168-hour week.
    func test_quietHourCountIsTheInverseOfOpenHours() {
        XCTAssertEqual(PaperweightSchedule().quietHourCount, 168)
        XCTAssertEqual(PaperweightSchedule.alwaysFree().quietHourCount, 0)

        var s = PaperweightSchedule()
        for day in 1...5 { for hour in 17..<21 { s.setFree(day: day, hour: hour, true) } }
        XCTAssertEqual(s.quietHourCount, 168 - 20)
    }
}
