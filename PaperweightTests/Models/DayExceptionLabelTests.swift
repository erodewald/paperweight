import XCTest

final class DayExceptionLabelTests: XCTestCase {

    private let cal = TestLocale.calendar
    private let us = TestLocale.en
    private func key(_ m: Int, _ d: Int) -> DayKey { DayKey(year: 2026, month: m, day: d) }
    /// Saturday 2026-09-12 10:00.
    private var now: Date { cal.date(from: DateComponents(year: 2026, month: 9, day: 12, hour: 10))! }

    override func setUp() { TestLocale.useTestBundle() }

    func test_treatmentTitles() {
        XCTAssertEqual(DayException.Treatment.openAllDay.title(calendar: cal, locale: us), "Open all day")
        XCTAssertEqual(DayException.Treatment.quietAllDay.title(calendar: cal, locale: us), "Quiet all day")
        XCTAssertEqual(DayException.Treatment.likeWeekday(6).title(calendar: cal, locale: us), "Like Saturday")
    }

    /// Weekday names come from the calendar, so a Japanese device says 土曜日,
    /// not Saturday. Proves the English array is gone.
    func test_weekdayNamesFollowTheLocale() {
        let ja = Locale(identifier: "ja_JP")
        XCTAssertEqual(DayException.weekdayName(6, calendar: cal, locale: ja), "土曜日")
        XCTAssertEqual(DayException.weekdayName(0, calendar: cal, locale: us), "Sunday")
    }

    func test_dateLabelSingleDay() {
        let e = DayException(firstDay: key(9, 18), lastDay: key(9, 18), treatment: .openAllDay)
        XCTAssertEqual(e.dateLabel(calendar: cal, locale: us), "Fri, Sep 18")
    }

    func test_dateLabelRange() {
        let e = DayException(firstDay: key(9, 21), lastDay: key(9, 25), treatment: .openAllDay)
        XCTAssertEqual(e.dateLabel(calendar: cal, locale: us), "Mon, Sep 21 – Fri, Sep 25")
    }

    func test_shortLabelUsesWeekdayWithinTheWeek() {
        let e = DayException(firstDay: key(9, 18), lastDay: key(9, 18), treatment: .openAllDay)
        XCTAssertEqual(e.shortDateLabel(now: now, calendar: cal, locale: us), "Fri")
        let far = DayException(firstDay: key(10, 3), lastDay: key(10, 3), treatment: .openAllDay)
        XCTAssertEqual(far.shortDateLabel(now: now, calendar: cal, locale: us), "Oct 3")
    }

    func test_shortLabelRanges() {
        let same = DayException(firstDay: key(9, 21), lastDay: key(9, 25), treatment: .openAllDay)
        XCTAssertEqual(same.shortDateLabel(now: now, calendar: cal, locale: us), "Sep 21–25")
        let across = DayException(firstDay: key(9, 28), lastDay: key(10, 2), treatment: .openAllDay)
        XCTAssertEqual(across.shortDateLabel(now: now, calendar: cal, locale: us), "Sep 28 – Oct 2")
    }

    func test_rowValue() {
        var c = PaperweightConfig()
        XCTAssertNil(c.dayExceptionsRowValue(now: now, calendar: cal, locale: us))
        c.dayExceptions = [
            DayException(firstDay: key(9, 21), lastDay: key(9, 25), treatment: .openAllDay),
            DayException(firstDay: key(9, 18), lastDay: key(9, 18), treatment: .openAllDay),
            DayException(firstDay: key(9, 1), lastDay: key(9, 1), treatment: .openAllDay),   // past
        ]
        XCTAssertEqual(c.dayExceptionsRowValue(now: now, calendar: cal, locale: us), "Fri · 2 upcoming")
    }
}
