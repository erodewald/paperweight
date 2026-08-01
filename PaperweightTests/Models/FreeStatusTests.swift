import XCTest

final class FreeStatusTests: XCTestCase {

    /// Sunday 2026-01-04 at a given hour/minute — day index 0.
    private func sunday(_ hour: Int, _ minute: Int = 0) -> Date {
        var c = DateComponents()
        c.year = 2026; c.month = 1; c.day = 4; c.hour = hour; c.minute = minute
        return Calendar.current.date(from: c)!
    }

    private func schedule(freeHours: Range<Int>) -> PaperweightSchedule {
        var s = PaperweightSchedule()
        for hour in freeHours { s.setFree(day: 0, hour: hour, true) }
        return s
    }

    func test_nilWhenQuiet() {
        XCTAssertNil(schedule(freeHours: 17..<21).freeStatus(at: sunday(14)))
    }

    func test_nilWhenNoScheduleSet() {
        XCTAssertNil(PaperweightSchedule().freeStatus(at: sunday(14)))
    }

    /// An always-free week has no boundary ahead, so there's no countdown to give.
    func test_nilWhenAlwaysFree() {
        XCTAssertNil(PaperweightSchedule.alwaysFree().freeStatus(at: sunday(14)))
    }

    func test_remainingCountsToTheEndOfTheWindow() throws {
        let status = try XCTUnwrap(schedule(freeHours: 13..<16).freeStatus(at: sunday(14)))
        XCTAssertEqual(status.remaining, 2 * 3600, accuracy: 1)
        XCTAssertEqual(status.ends, sunday(16))
    }

    /// The free-window ring *fills* as the window is spent — the inverse of the
    /// depleting quiet ring.
    func test_elapsedFractionFillsAcrossTheWindow() throws {
        let s = schedule(freeHours: 13..<17)

        let start = try XCTUnwrap(s.freeStatus(at: sunday(13)))
        XCTAssertEqual(start.elapsedFraction, 0, accuracy: 0.001)

        let middle = try XCTUnwrap(s.freeStatus(at: sunday(15)))
        XCTAssertEqual(middle.elapsedFraction, 0.5, accuracy: 0.001)

        let nearlyDone = try XCTUnwrap(s.freeStatus(at: sunday(16, 30)))
        XCTAssertEqual(nearlyDone.elapsedFraction, 0.875, accuracy: 0.001)
    }

    func test_halfHourResolution() throws {
        var s = PaperweightSchedule()
        s.setFree(day: 0, halfHour: 28, true)   // 14:00–14:30 only
        let status = try XCTUnwrap(s.freeStatus(at: sunday(14, 10)))
        XCTAssertEqual(status.remaining, 20 * 60, accuracy: 1)
        XCTAssertEqual(status.ends, sunday(14, 30))
    }

    /// freeStatus and quietStatus are exclusive: at any instant with a schedule,
    /// exactly one of them can produce a value.
    func test_freeAndQuietStatusAreMutuallyExclusive() {
        let s = schedule(freeHours: 9..<12)
        for hour in 0..<24 {
            let date = sunday(hour)
            let free = s.freeStatus(at: date) != nil
            let quiet = s.quietStatus(at: date) != nil
            XCTAssertFalse(free && quiet, "both statuses returned a value at \(hour):00")
        }
    }

    /// A window running to the end of the day ends at midnight. Unlike
    /// freeWindows(), which clamps to 23:59 because DeviceActivity can't express
    /// 24:00, this is a plain instant and needs no clamp.
    func test_windowReachingEndOfDay() throws {
        let status = try XCTUnwrap(schedule(freeHours: 22..<24).freeStatus(at: sunday(23)))
        XCTAssertEqual(status.remaining, 3600, accuracy: 1)
    }
}
