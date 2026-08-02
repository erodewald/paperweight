import XCTest

final class ScheduleDeferralTests: XCTestCase {

    /// Sunday 2026-01-04 at the given hour.
    private func sunday(_ hour: Int, _ minute: Int = 0) -> Date {
        var c = DateComponents()
        c.year = 2026; c.month = 1; c.day = 4; c.hour = hour; c.minute = minute
        return Calendar.current.date(from: c)!
    }

    private func schedule(openHours: Range<Int>, day: Int = 0) -> PaperweightSchedule {
        var s = PaperweightSchedule()
        for hour in openHours { s.setFree(day: day, hour: hour, true) }
        return s
    }

    // MARK: merging

    /// A slot is open now only if it was open before AND stays open in the edit.
    func test_mergeKeepsOnlySlotsOpenInBoth() {
        let active = schedule(openHours: 9..<17)
        let edited = schedule(openHours: 12..<20)
        let merged = active.merging(tighteningFrom: edited)

        // 9-12 closed by the edit (tightening, applies now).
        XCTAssertFalse(merged.isFreeSlot(day: 0, halfHour: 9 * 2))
        // 12-17 open in both.
        XCTAssertTrue(merged.isFreeSlot(day: 0, halfHour: 13 * 2))
        // 17-20 newly open in the edit — must NOT open yet.
        XCTAssertFalse(merged.isFreeSlot(day: 0, halfHour: 18 * 2))
    }

    func test_pureTighteningMergesToTheEditItself() {
        let active = schedule(openHours: 9..<17)
        let edited = schedule(openHours: 9..<12)
        XCTAssertEqual(active.merging(tighteningFrom: edited), edited)
    }

    func test_pureLooseningLeavesTheActiveScheduleUnchanged() {
        let active = schedule(openHours: 9..<12)
        let edited = schedule(openHours: 9..<17)
        XCTAssertEqual(active.merging(tighteningFrom: edited), active)
    }

    // MARK: applying an edit

    func test_pureTighteningStoresNoPendingSchedule() {
        var config = PaperweightConfig()
        config.schedule = schedule(openHours: 9..<17)
        config.applyScheduleEdit(schedule(openHours: 9..<12), now: sunday(10))

        XCTAssertEqual(config.schedule, schedule(openHours: 9..<12))
        XCTAssertNil(config.pendingSchedule)
        XCTAssertNil(config.pendingScheduleEffectiveAt)
    }

    func test_looseningIsHeldUntilTheNextDayBoundary() {
        var config = PaperweightConfig()
        config.schedule = schedule(openHours: 9..<12)
        config.applyScheduleEdit(schedule(openHours: 9..<17), now: sunday(10))

        // Nothing opened up today.
        XCTAssertEqual(config.schedule, schedule(openHours: 9..<12))
        XCTAssertEqual(config.pendingSchedule, schedule(openHours: 9..<17))
        XCTAssertEqual(config.pendingScheduleEffectiveAt,
                       Calendar.current.startOfDay(for: sunday(10)).addingTimeInterval(86400))
    }

    /// The interesting case: one edit that both tightens and loosens.
    func test_aMixedEditTightensNowAndLoosensLater() {
        var config = PaperweightConfig()
        config.schedule = schedule(openHours: 9..<17)
        config.applyScheduleEdit(schedule(openHours: 14..<20), now: sunday(10))

        // 9-14 closed immediately.
        XCTAssertFalse(config.schedule!.isFreeSlot(day: 0, halfHour: 10 * 2))
        // 17-20 still quiet today.
        XCTAssertFalse(config.schedule!.isFreeSlot(day: 0, halfHour: 18 * 2))
        // …but pending has them open.
        XCTAssertTrue(config.pendingSchedule!.isFreeSlot(day: 0, halfHour: 18 * 2))
    }

    // MARK: promotion

    func test_pendingIsNotPromotedBeforeItIsDue() {
        var config = PaperweightConfig()
        config.schedule = schedule(openHours: 9..<12)
        config.applyScheduleEdit(schedule(openHours: 9..<17), now: sunday(10))

        config.promotePendingScheduleIfDue(now: sunday(23))

        XCTAssertEqual(config.schedule, schedule(openHours: 9..<12))
        XCTAssertNotNil(config.pendingSchedule)
    }

    func test_pendingIsPromotedOnceDue() {
        var config = PaperweightConfig()
        config.schedule = schedule(openHours: 9..<12)
        config.applyScheduleEdit(schedule(openHours: 9..<17), now: sunday(10))

        let tomorrow = Calendar.current.startOfDay(for: sunday(10)).addingTimeInterval(86400 + 60)
        config.promotePendingScheduleIfDue(now: tomorrow)

        XCTAssertEqual(config.schedule, schedule(openHours: 9..<17))
        XCTAssertNil(config.pendingSchedule)
        XCTAssertNil(config.pendingScheduleEffectiveAt)
    }

    func test_promotionIsANoOpWithNothingPending() {
        var config = PaperweightConfig()
        config.schedule = schedule(openHours: 9..<12)
        config.promotePendingScheduleIfDue(now: sunday(23))

        XCTAssertEqual(config.schedule, schedule(openHours: 9..<12))
        XCTAssertNil(config.pendingSchedule)
    }

    /// A second edit before the first lands must not strand the first one.
    func test_asecondEditReplacesTheStandingPendingSchedule() {
        var config = PaperweightConfig()
        config.schedule = schedule(openHours: 9..<12)
        config.applyScheduleEdit(schedule(openHours: 9..<17), now: sunday(10))
        config.applyScheduleEdit(schedule(openHours: 9..<20), now: sunday(11))

        XCTAssertEqual(config.pendingSchedule, schedule(openHours: 9..<20))
    }

    // MARK: what the grid marks

    func test_pendingOpeningSlotsAreTheOnesQuietNowThatOpenLater() {
        var config = PaperweightConfig()
        config.schedule = schedule(openHours: 9..<12)
        config.applyScheduleEdit(schedule(openHours: 9..<14), now: sunday(10))

        let opening = config.pendingOpeningSlots
        XCTAssertTrue(opening.contains(PaperweightSchedule.slot(day: 0, halfHour: 12 * 2)))
        XCTAssertTrue(opening.contains(PaperweightSchedule.slot(day: 0, halfHour: 13 * 2)))
        XCTAssertFalse(opening.contains(PaperweightSchedule.slot(day: 0, halfHour: 10 * 2)))
        XCTAssertFalse(opening.contains(PaperweightSchedule.slot(day: 0, halfHour: 20 * 2)))
    }

    func test_pendingOpeningSlotsAreEmptyWithNothingPending() {
        var config = PaperweightConfig()
        config.schedule = schedule(openHours: 9..<12)
        XCTAssertTrue(config.pendingOpeningSlots.isEmpty)
    }

    // MARK: persistence

    func test_aPendingScheduleSurvivesARoundTrip() throws {
        var config = PaperweightConfig()
        config.schedule = schedule(openHours: 9..<12)
        config.applyScheduleEdit(schedule(openHours: 9..<17), now: sunday(10))

        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(PaperweightConfig.self, from: data)

        XCTAssertEqual(decoded.pendingSchedule, config.pendingSchedule)
        XCTAssertEqual(decoded.pendingScheduleEffectiveAt, config.pendingScheduleEffectiveAt)
    }

    /// A config saved before these fields existed must still decode.
    func test_aConfigWithoutTheNewKeysDecodes() throws {
        let json = Data(#"{"isEnabled":true}"#.utf8)
        let config = try JSONDecoder().decode(PaperweightConfig.self, from: json)

        XCTAssertNil(config.pendingSchedule)
        XCTAssertNil(config.pendingScheduleEffectiveAt)
        XCTAssertTrue(config.isEnabled)
    }
}
