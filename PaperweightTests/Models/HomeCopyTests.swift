import XCTest

final class HomeCopyTests: XCTestCase {

    override func setUp() { TestLocale.useTestBundle() }

    func test_hoursAndMinutesUseAColon() {
        XCTAssertEqual(HomeCopy.countdown(2 * 3600 + 14 * 60, locale: TestLocale.en), "2:14")
    }

    /// Minutes are always two digits so the numeral doesn't reflow as it counts.
    func test_minutesArePadded() {
        XCTAssertEqual(HomeCopy.countdown(3 * 3600 + 5 * 60, locale: TestLocale.en), "3:05")
    }

    /// Under an hour there is no leading zero hour — "0:42" reads as a clock.
    func test_underAnHourShowsMinutesOnly() {
        XCTAssertEqual(HomeCopy.countdown(42 * 60, locale: TestLocale.en), "42m")
    }

    /// Seconds round down, so a boundary never reads as already passed.
    func test_secondsRoundDown() {
        XCTAssertEqual(HomeCopy.countdown(2 * 3600 + 14 * 60 + 59, locale: TestLocale.en), "2:14")
    }

    /// A window that has run out shows a floor, never a negative or empty string.
    func test_expiredShowsAMinuteFloor() {
        XCTAssertEqual(HomeCopy.countdown(0, locale: TestLocale.en), "0m")
        XCTAssertEqual(HomeCopy.countdown(-90, locale: TestLocale.en), "0m")
    }

    /// The locked screen's big number follows the widget past a day: "51:30"
    /// is not a countdown anyone reads, "2 days" is.
    func test_countdown_speaksInDaysPastTwentyFourHours() {
        XCTAssertEqual(HomeCopy.countdown(24 * 3600, locale: TestLocale.en), "1 day")
        XCTAssertEqual(HomeCopy.countdown(63 * 3600 + 44 * 60, locale: TestLocale.en), "2½ days")
        XCTAssertEqual(HomeCopy.countdown(23 * 3600 + 59 * 60, locale: TestLocale.en), "23:59")
    }
}
