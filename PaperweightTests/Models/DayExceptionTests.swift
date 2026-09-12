import XCTest

final class DayExceptionTests: XCTestCase {

    private func key(_ d: Int) -> DayKey { DayKey(year: 2026, month: 9, day: d) }

    /// A whole-second `createdAt`, so JSON round trips compare equal.
    private let created = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func exception(_ first: Int, _ last: Int, _ t: DayException.Treatment = .openAllDay) -> DayException {
        DayException(firstDay: key(first), lastDay: key(last), treatment: t, createdAt: created)
    }

    func test_coversIsInclusiveOnBothEnds() {
        let e = exception(21, 25)
        XCTAssertTrue(e.covers(key(21)))
        XCTAssertTrue(e.covers(key(25)))
        XCTAssertFalse(e.covers(key(20)))
        XCTAssertFalse(e.covers(key(26)))
    }

    func test_overlapsDetectsAnySharedDay() {
        XCTAssertTrue(exception(21, 25).overlaps(exception(25, 27)))
        XCTAssertTrue(exception(21, 25).overlaps(exception(19, 21)))
        XCTAssertTrue(exception(21, 25).overlaps(exception(22, 23)))
        XCTAssertFalse(exception(21, 25).overlaps(exception(26, 26)))
    }

    func test_dayCount() {
        XCTAssertEqual(exception(21, 25).dayCount(), 5)
        XCTAssertEqual(exception(21, 21).dayCount(), 1)
    }

    func test_treatmentRoundTripsThroughCodable() throws {
        for t: DayException.Treatment in [.openAllDay, .quietAllDay, .likeWeekday(6)] {
            let e = exception(21, 21, t)
            let back = try JSONDecoder().decode(DayException.self, from: try JSONEncoder().encode(e))
            XCTAssertEqual(back, e)
        }
    }
}
