import XCTest

/// The line Home and the widgets show while a planned day decides the
/// schedule, and the link a widget tap follows to that day.
final class DayExceptionCalloutTests: XCTestCase {

    private let en = TestLocale.en
    private let cal = TestLocale.calendar

    override func setUp() { TestLocale.useTestBundle() }

    private let day = DayKey(year: 2026, month: 9, day: 22)

    private func exception(_ treatment: DayException.Treatment, note: String = "") -> DayException {
        DayException(firstDay: day, lastDay: day, treatment: treatment, note: note)
    }

    func test_calloutPrefersTheNote() {
        XCTAssertEqual(exception(.quietAllDay, note: "Demo day").callout(calendar: cal, locale: en), "Demo day")
    }

    func test_calloutFallsBackToTheTreatment() {
        XCTAssertEqual(exception(.quietAllDay).callout(calendar: cal, locale: en), "Quiet all day")
        XCTAssertEqual(exception(.openAllDay).callout(calendar: cal, locale: en), "Open all day")
        XCTAssertEqual(exception(.likeWeekday(1)).callout(calendar: cal, locale: en), "Like Monday")
    }

    /// A note of only whitespace is no note. The add sheet trims, but an older
    /// build's config may not have.
    func test_calloutIgnoresABlankNote() {
        XCTAssertEqual(exception(.quietAllDay, note: "  \n").callout(calendar: cal, locale: en), "Quiet all day")
    }

    func test_plannedLineNamesTheDay() {
        XCTAssertEqual(exception(.quietAllDay, note: "Demo day").plannedLine(calendar: cal, locale: en),
                       "Planned · Demo day")
        XCTAssertEqual(exception(.openAllDay).plannedLine(calendar: cal, locale: en),
                       "Planned · Open all day")
    }

    // MARK: Deep link

    func test_deepLinkRoundTripsTheID() {
        let e = exception(.quietAllDay)
        XCTAssertEqual(e.deepLink.scheme, "paperweight")
        XCTAssertEqual(e.deepLink.host, DayException.deepLinkHost)
        XCTAssertEqual(DayException.plannedDayID(from: e.deepLink), e.id)
    }

    func test_otherLinksAreNotPlannedDays() {
        XCTAssertNil(DayException.plannedDayID(from: URL(string: "paperweight://home")!))
        XCTAssertNil(DayException.plannedDayID(from: URL(string: "paperweight://planned-day")!))
        XCTAssertNil(DayException.plannedDayID(from: URL(string: "paperweight://planned-day/not-a-uuid")!))
        XCTAssertNil(DayException.plannedDayID(from: URL(string: "https://example.com/planned-day/\(UUID().uuidString)")!))
    }
}
