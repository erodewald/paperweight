import XCTest

final class PaperweightConfigTests: XCTestCase {

    func test_defaultConfig_isDisabled() {
        let config = PaperweightConfig()
        XCTAssertFalse(config.isEnabled)
    }

    func test_defaultConfig_hasNoSchedule() {
        let config = PaperweightConfig()
        XCTAssertNil(config.schedule)
    }

    func test_defaultUnlockDuration_is15Minutes() {
        let config = PaperweightConfig()
        XCTAssertEqual(config.unlockDuration, 15 * 60)
    }

    func test_config_roundtripsJSON() throws {
        var config = PaperweightConfig()
        config.isEnabled = true
        config.unlockDuration = 600
        config.requireWatchConfirmation = true
        // Don't encode selection in unit tests — requires device authorization

        // Test just the non-FamilyControls fields round-trip via a simplified struct
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(PaperweightConfig.self, from: data)

        XCTAssertEqual(decoded.isEnabled, true)
        XCTAssertEqual(decoded.unlockDuration, 600)
        XCTAssertEqual(decoded.requireWatchConfirmation, true)
    }

    func test_schedule_freeWindow_containsTime() {
        let schedule = AllowSchedule(
            startHour: 9, startMinute: 0,
            endHour: 22, endMinute: 0,
            weekdays: Set(1...7)
        )
        XCTAssertTrue(schedule.contains(hour: 12, minute: 0))
        XCTAssertFalse(schedule.contains(hour: 7, minute: 0))
        XCTAssertFalse(schedule.contains(hour: 23, minute: 0))
    }

    func test_schedule_midnightSpanning_notSupported() {
        let schedule = AllowSchedule(
            startHour: 22, startMinute: 0,
            endHour: 8, endMinute: 0,
            weekdays: Set(1...7)
        )
        XCTAssertFalse(schedule.isValid)
    }
}
