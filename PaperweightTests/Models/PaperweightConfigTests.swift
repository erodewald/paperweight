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
        config.coolOffDays = 2
        // Don't encode selection in unit tests — requires device authorization

        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(PaperweightConfig.self, from: data)

        XCTAssertEqual(decoded.isEnabled, true)
        XCTAssertEqual(decoded.unlockDuration, 600)
        XCTAssertEqual(decoded.coolOffDays, 2)
    }

    func test_schedule_isFreeSlot_roundtrips() {
        var schedule = PaperweightSchedule()
        schedule.setFree(day: 1, halfHour: 18, true)   // Monday 9:00am
        XCTAssertTrue(schedule.isFreeSlot(day: 1, halfHour: 18))
        XCTAssertFalse(schedule.isFreeSlot(day: 1, halfHour: 19))  // 9:30 still blocked
        schedule.setFree(day: 1, halfHour: 18, false)
        XCTAssertFalse(schedule.isFreeSlot(day: 1, halfHour: 18))
    }

    func test_schedule_halfHourResolution() {
        var schedule = PaperweightSchedule()
        schedule.setFree(day: 2, halfHour: PaperweightSchedule.halfHour(hour: 7, minute: 30), true)
        var comps = DateComponents()
        comps.year = 2026; comps.month = 6; comps.day = 16  // a Tuesday
        comps.hour = 7; comps.minute = 45
        let date = Calendar.current.date(from: comps)!
        XCTAssertTrue(schedule.isFree(at: date))
        let window = schedule.freeWindows().first
        XCTAssertEqual(window?.startHour, 7)
        XCTAssertEqual(window?.startMinute, 30)
    }

    func test_schedule_freeWindows_mergesContiguousHours() {
        var schedule = PaperweightSchedule()
        for hour in 9..<12 { schedule.setFree(day: 2, hour: hour, true) }  // Tue 9–12
        let windows = schedule.freeWindows()
        XCTAssertEqual(windows.count, 1)
        XCTAssertEqual(windows.first?.startHour, 9)
        XCTAssertEqual(windows.first?.endHour, 12)
    }

    func test_schedule_freeWindows_dedupesAcrossDays() {
        var schedule = PaperweightSchedule()
        for day in 1...5 { for hour in 17..<21 { schedule.setFree(day: day, hour: hour, true) } }
        // Same window on 5 weekdays collapses to one distinct window.
        XCTAssertEqual(schedule.freeWindows().count, 1)
    }

    func test_schedule_isFree_usesWeekdayAndHour() {
        var schedule = PaperweightSchedule()
        // Day 0 = Sunday; mark Sunday 14:00 free.
        schedule.setFree(day: 0, hour: 14, true)
        var comps = DateComponents()
        comps.year = 2026; comps.month = 6; comps.day = 14  // a Sunday
        comps.hour = 14; comps.minute = 30
        let date = Calendar.current.date(from: comps)!
        XCTAssertTrue(schedule.isFree(at: date))
    }

    func test_schedule_endOfDayRun_terminatesAt2359() {
        var schedule = PaperweightSchedule()
        for hour in 22..<24 { schedule.setFree(day: 3, hour: hour, true) }
        let window = schedule.freeWindows().first
        XCTAssertEqual(window?.endHour, 23)
        XCTAssertEqual(window?.endMinute, 59)
    }
}
