// PaperweightTests/Models/DayKeyTests.swift
import XCTest

final class DayKeyTests: XCTestCase {

    private let cal = Calendar.current

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }

    func test_initFromDateDropsTheTime() {
        XCTAssertEqual(DayKey(date(2026, 1, 4, 23), calendar: cal), DayKey(year: 2026, month: 1, day: 4))
    }

    func test_dateIsStartOfDay() {
        XCTAssertEqual(DayKey(year: 2026, month: 1, day: 4).date(calendar: cal), cal.startOfDay(for: date(2026, 1, 4)))
    }

    func test_nextCrossesAMonthEnd() {
        XCTAssertEqual(DayKey(year: 2026, month: 1, day: 31).next(calendar: cal), DayKey(year: 2026, month: 2, day: 1))
    }

    /// 2026-11-01 is the US fall-back day (25 real hours). Walking by calendar
    /// day must not skip or repeat it.
    func test_nextAcrossFallBackDST() {
        let oct31 = DayKey(year: 2026, month: 10, day: 31)
        XCTAssertEqual(oct31.next(calendar: cal), DayKey(year: 2026, month: 11, day: 1))
        XCTAssertEqual(oct31.next(calendar: cal).next(calendar: cal), DayKey(year: 2026, month: 11, day: 2))
        XCTAssertEqual(DayKey(year: 2026, month: 11, day: 2).previous(calendar: cal), DayKey(year: 2026, month: 11, day: 1))
    }

    func test_comparison() {
        XCTAssertLessThan(DayKey(year: 2026, month: 1, day: 31), DayKey(year: 2026, month: 2, day: 1))
        XCTAssertLessThan(DayKey(year: 2025, month: 12, day: 31), DayKey(year: 2026, month: 1, day: 1))
    }

    func test_weekdayIndexMatchesTheGrid() {
        // 2026-01-04 is a Sunday.
        XCTAssertEqual(DayKey(year: 2026, month: 1, day: 4).weekdayIndex(calendar: cal), 0)
        XCTAssertEqual(DayKey(year: 2026, month: 1, day: 10).weekdayIndex(calendar: cal), 6)
    }

    /// The Home strip is an outlook, not a calendar week: it starts today.
    func test_weekAheadStartsTodayAndRunsSevenDays() {
        // 2026-01-10 is a Saturday; the calendar week would be almost all past.
        let week = DayKey.weekAhead(from: DayKey(year: 2026, month: 1, day: 10), calendar: cal)
        XCTAssertEqual(week.first, DayKey(year: 2026, month: 1, day: 10))
        XCTAssertEqual(week.last, DayKey(year: 2026, month: 1, day: 16))
        XCTAssertEqual(week.count, 7)
        XCTAssertEqual(week.map { $0.weekdayIndex(calendar: cal) }, [6, 0, 1, 2, 3, 4, 5])
    }

    func test_codableRoundTripsAsISODateString() throws {
        let key = DayKey(year: 2026, month: 9, day: 5)
        let data = try JSONEncoder().encode(key)
        XCTAssertEqual(String(data: data, encoding: .utf8), "\"2026-09-05\"")
        XCTAssertEqual(try JSONDecoder().decode(DayKey.self, from: data), key)
    }

    func test_decodingGarbageThrows() {
        XCTAssertThrowsError(try JSONDecoder().decode(DayKey.self, from: Data("\"soon\"".utf8)))
    }
}
