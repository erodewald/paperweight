import XCTest

/// The widget's timeline is pure schedule math. It must keep producing entries
/// on the far side of a boundary: WidgetKit honours a `.after` reload policy
/// on its own schedule, and a timeline that stops at the boundary leaves a
/// frozen "3h 20m" on screen until that reload eventually comes.
final class WidgetTimelineTests: XCTestCase {

    /// Sunday 2026-01-04 at a given time — day index 0.
    private func sunday(_ hour: Int, _ minute: Int = 0) -> Date {
        var c = DateComponents()
        c.year = 2026; c.month = 1; c.day = 4; c.hour = hour; c.minute = minute
        return Calendar.current.date(from: c)!
    }

    private func readySnapshot(freeHours: Range<Int>) -> WidgetSnapshot {
        var s = WidgetSnapshot()
        s.isArmed = true
        s.hasSelection = true
        s.hasNFCToken = true
        s.isScreenTimeAuthorized = true
        var schedule = PaperweightSchedule()
        for hour in freeHours { schedule.setFree(day: 0, hour: hour, true) }
        s.schedule = schedule
        return s
    }

    func test_entriesContinuePastTheBoundaryToTheHorizon() {
        // Quiet until 16:00, asked at 14:00 with a 4h horizon.
        let dates = readySnapshot(freeHours: 16..<20)
            .timelineDates(from: sunday(14), step: 300, horizon: 4 * 3600, maxEntries: 60)

        XCTAssertEqual(dates.first, sunday(14))
        XCTAssertTrue(dates.contains { $0 > sunday(16, 30) }, "must not stop at the 16:00 boundary")
        XCTAssertLessThanOrEqual(dates.last!, sunday(18))
    }

    func test_includesAnEntryJustPastEachBoundary() {
        let dates = readySnapshot(freeHours: 16..<17)
            .timelineDates(from: sunday(14), step: 300, horizon: 4 * 3600, maxEntries: 60)

        XCTAssertTrue(dates.contains(sunday(16).addingTimeInterval(1)), "quiet → free at 16:00")
        XCTAssertTrue(dates.contains(sunday(17).addingTimeInterval(1)), "free → quiet at 17:00")
    }

    func test_datesAreStrictlyIncreasing() {
        let dates = readySnapshot(freeHours: 16..<17)
            .timelineDates(from: sunday(14), step: 300, horizon: 4 * 3600, maxEntries: 60)
        XCTAssertEqual(dates, Array(Set(dates)).sorted())
    }

    func test_respectsMaxEntries() {
        let dates = readySnapshot(freeHours: 16..<17)
            .timelineDates(from: sunday(14), step: 300, horizon: 4 * 3600, maxEntries: 10)
        XCTAssertEqual(dates.count, 10)
    }

    func test_dormantSnapshotStillFillsTheHorizon() {
        var s = readySnapshot(freeHours: 16..<17)
        s.isArmed = false
        let dates = s.timelineDates(from: sunday(14), step: 300, horizon: 4 * 3600, maxEntries: 60)
        XCTAssertEqual(dates.first, sunday(14))
        XCTAssertGreaterThan(dates.count, 1)
    }
}
