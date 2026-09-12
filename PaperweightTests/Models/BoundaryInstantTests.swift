import XCTest

/// A DeviceActivity boundary callback should evaluate the schedule on the far
/// side of the boundary it represents, not at the literal wall-clock moment the
/// callback happened to run.
final class BoundaryInstantTests: XCTestCase {

    private func date(_ day: Int, _ hour: Int, _ minute: Int, _ second: Int = 0) -> Date {
        var c = DateComponents()
        c.year = 2026; c.month = 1; c.day = day; c.hour = hour; c.minute = minute; c.second = second
        return Calendar.current.date(from: c)!
    }

    /// The end-of-day case: DeviceActivity can't express 24:00, so a free window
    /// running to midnight ends at 23:59. Evaluating at 23:59 still lands in the
    /// free 23:30 slot; the callback must be read as "midnight".
    func test_endOfDayCallbackSnapsToMidnight() {
        XCTAssertEqual(PaperweightSchedule.boundaryInstant(near: date(4, 23, 59, 12)), date(5, 0, 0))
    }

    func test_slightlyEarlyCallbackSnapsToTheMark() {
        XCTAssertEqual(PaperweightSchedule.boundaryInstant(near: date(4, 20, 58, 30)), date(4, 21, 0))
        XCTAssertEqual(PaperweightSchedule.boundaryInstant(near: date(4, 17, 28, 0)), date(4, 17, 30))
    }

    func test_lateCallbackIsLeftAlone() {
        XCTAssertEqual(PaperweightSchedule.boundaryInstant(near: date(4, 21, 3, 0)), date(4, 21, 3))
    }

    func test_midSlotInstantIsLeftAlone() {
        XCTAssertEqual(PaperweightSchedule.boundaryInstant(near: date(4, 10, 14, 0)), date(4, 10, 14))
    }

    func test_exactMarkIsLeftAlone() {
        XCTAssertEqual(PaperweightSchedule.boundaryInstant(near: date(4, 21, 0, 0)), date(4, 21, 0))
    }
}
