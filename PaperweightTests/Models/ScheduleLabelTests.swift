import XCTest

final class ScheduleLabelTests: XCTestCase {
    private let en = TestLocale.en
    private let cal = TestLocale.calendar

    /// iOS separates the hour from AM/PM with a narrow no-break space
    /// (U+202F); Dutch pads to two digits.
    func test_hourLabels_useTheLocalesClock() {
        XCTAssertEqual(PaperweightSchedule.hourLabel(0, calendar: cal, locale: en), "12\u{202F}AM")
        XCTAssertEqual(PaperweightSchedule.hourLabel(6, calendar: cal, locale: en), "6\u{202F}AM")
        XCTAssertEqual(PaperweightSchedule.hourLabel(12, calendar: cal, locale: en), "12\u{202F}PM")
        XCTAssertEqual(PaperweightSchedule.hourLabel(18, calendar: cal, locale: en), "6\u{202F}PM")
        XCTAssertEqual(PaperweightSchedule.hourLabel(24, calendar: cal, locale: en), "12\u{202F}AM")
        let nl = Locale(identifier: "nl_NL")
        XCTAssertEqual(PaperweightSchedule.hourLabel(18, calendar: cal, locale: nl), "18")
        XCTAssertEqual(PaperweightSchedule.hourLabel(6, calendar: cal, locale: nl), "06")
    }

    /// Display order follows the calendar's first weekday; the indexes
    /// themselves stay Sunday-based so storage never moves.
    func test_displayOrder_startsAtTheCalendarsFirstWeekday() {
        var sunday = cal; sunday.firstWeekday = 1
        XCTAssertEqual(PaperweightSchedule.displayOrder(calendar: sunday), [0, 1, 2, 3, 4, 5, 6])
        var monday = cal; monday.firstWeekday = 2
        XCTAssertEqual(PaperweightSchedule.displayOrder(calendar: monday), [1, 2, 3, 4, 5, 6, 0])
        var saturday = cal; saturday.firstWeekday = 7
        XCTAssertEqual(PaperweightSchedule.displayOrder(calendar: saturday), [6, 0, 1, 2, 3, 4, 5])
    }
}
