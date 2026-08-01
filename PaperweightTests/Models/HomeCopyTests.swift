import XCTest

final class HomeCopyTests: XCTestCase {

    func test_hoursAndMinutesUseAColon() {
        XCTAssertEqual(HomeCopy.countdown(2 * 3600 + 14 * 60), "2:14")
    }

    /// Minutes are always two digits so the numeral doesn't reflow as it counts.
    func test_minutesArePadded() {
        XCTAssertEqual(HomeCopy.countdown(3 * 3600 + 5 * 60), "3:05")
    }

    /// Under an hour there is no leading zero hour — "0:42" reads as a clock.
    func test_underAnHourShowsMinutesOnly() {
        XCTAssertEqual(HomeCopy.countdown(42 * 60), "42m")
    }

    /// Seconds round down, so a boundary never reads as already passed.
    func test_secondsRoundDown() {
        XCTAssertEqual(HomeCopy.countdown(2 * 3600 + 14 * 60 + 59), "2:14")
    }

    /// A window that has run out shows a floor, never a negative or empty string.
    func test_expiredShowsAMinuteFloor() {
        XCTAssertEqual(HomeCopy.countdown(0), "0m")
        XCTAssertEqual(HomeCopy.countdown(-90), "0m")
    }
}
