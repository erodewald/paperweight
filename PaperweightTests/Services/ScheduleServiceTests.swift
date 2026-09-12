import XCTest

#if os(iOS)
import DeviceActivity

final class ScheduleServiceTests: XCTestCase {

    private var center: MockDeviceActivityCenter!
    private var service: ScheduleService!

    override func setUp() {
        super.setUp()
        center = MockDeviceActivityCenter()
        service = ScheduleService(center: center)
    }

    private func armed(schedule: PaperweightSchedule? = nil) -> PaperweightConfig {
        var c = PaperweightConfig()
        c.isEnabled = true
        c.schedule = schedule
        return c
    }

    /// Sunday 2026-01-04 at a given time.
    private func sunday(_ hour: Int, _ minute: Int, _ second: Int = 0) -> Date {
        var c = DateComponents()
        c.year = 2026; c.month = 1; c.day = 4; c.hour = hour; c.minute = minute; c.second = second
        return Calendar.current.date(from: c)!
    }

    private func windowNames() -> Set<String> {
        center.names.filter { $0.hasPrefix("\(Paperweight.activityName).") && Int($0.split(separator: ".").last!) != nil }
    }

    // MARK: Existing behaviour, now pinned

    func test_disabledStopsMonitoringAndRegistersNothing() {
        var c = armed(schedule: .weekdayEvenings())
        c.isEnabled = false
        service.sync(config: c)
        XCTAssertEqual(center.stopCallCount, 1)
        XCTAssertTrue(center.names.isEmpty)
    }

    func test_armedWithNoScheduleRegistersOnlyHeartbeats() {
        service.sync(config: armed())
        XCTAssertFalse(center.names.isEmpty)
        XCTAssertTrue(center.names.allSatisfy { $0.hasPrefix("\(Paperweight.activityName).heartbeat") })
    }

    func test_registersOneActivityPerDistinctFreeWindow() throws {
        var s = PaperweightSchedule()
        for day in 1...5 { for hour in 17..<21 { s.setFree(day: day, hour: hour, true) } }
        for hour in 9..<12 { s.setFree(day: 0, hour: hour, true) }
        service.sync(config: armed(schedule: s))

        XCTAssertEqual(windowNames().count, 2)
        let first = try XCTUnwrap(center.schedule(named: "\(Paperweight.activityName).0"))
        XCTAssertEqual(first.intervalStart.hour, 9)
        XCTAssertEqual(first.intervalEnd.hour, 12)
        XCTAssertTrue(first.repeats)
    }

    // MARK: Pending (deferred-loosening) schedule

    /// A loosening lands at the day boundary inside the monitor, which can't
    /// re-register anything. Its boundaries have to be on the books already.
    func test_registersWindowsOfThePendingScheduleToo() throws {
        var active = PaperweightSchedule()
        for hour in 17..<21 { active.setFree(day: 0, hour: hour, true) }
        var pending = active
        for hour in 21..<23 { pending.setFree(day: 0, hour: hour, true) }

        var c = armed(schedule: active)
        c.pendingSchedule = pending
        c.pendingScheduleEffectiveAt = .distantFuture
        service.sync(config: c)

        let ends = Set(windowNames().compactMap { center.schedule(named: $0)?.intervalEnd.hour })
        XCTAssertEqual(ends, [21, 23], "both the active 17–21 and the pending 17–23 boundaries are needed")
    }

    // MARK: Timed unlock expiry

    func test_liveUnlockRegistersAOneShotExpiryActivity() throws {
        var c = armed(schedule: .weekdayEvenings())
        c.unlockExpiresAt = sunday(10, 18, 20)
        service.sync(config: c, now: sunday(10, 3, 20))

        let expiry = try XCTUnwrap(center.schedule(named: "\(Paperweight.activityName).unlockExpiry"))
        XCTAssertFalse(expiry.repeats)
        XCTAssertEqual(expiry.intervalStart.day, 4)
        XCTAssertEqual(expiry.intervalStart.hour, 10)
        // Rounded up to the next whole minute past the expiry, plus a minute of
        // margin: DeviceActivity works in minutes, and a callback that lands a
        // second *before* the expiry would see the unlock as still live.
        XCTAssertEqual(expiry.intervalStart.minute, 20)
        XCTAssertEqual(expiry.intervalStart.second ?? 0, 0)
        // DeviceActivity rejects intervals under 15 minutes.
        let start = Calendar.current.date(from: expiry.intervalStart)!
        let end = Calendar.current.date(from: expiry.intervalEnd)!
        XCTAssertGreaterThanOrEqual(end.timeIntervalSince(start), 15 * 60)
    }

    func test_expiredUnlockRegistersNoExpiryActivity() {
        var c = armed(schedule: .weekdayEvenings())
        c.unlockExpiresAt = sunday(10, 0)
        service.sync(config: c, now: sunday(10, 5))
        XCTAssertNil(center.schedule(named: "\(Paperweight.activityName).unlockExpiry"))
    }

    func test_relockDropsTheExpiryActivity() {
        var c = armed(schedule: .weekdayEvenings())
        c.unlockExpiresAt = sunday(10, 18)
        service.sync(config: c, now: sunday(10, 3))
        c.unlockExpiresAt = nil
        service.sync(config: c, now: sunday(10, 4))
        XCTAssertNil(center.schedule(named: "\(Paperweight.activityName).unlockExpiry"))
        XCTAssertFalse(windowNames().isEmpty, "the schedule windows survive the relock")
    }
}
#endif
