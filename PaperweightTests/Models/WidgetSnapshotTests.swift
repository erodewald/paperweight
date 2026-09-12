import XCTest

#if os(iOS)
final class WidgetSnapshotTests: XCTestCase {

    /// Sunday 2026-01-04, 14:00 local — day index 0, half-hour 28.
    private var reference: Date {
        var c = DateComponents()
        c.year = 2026; c.month = 1; c.day = 4; c.hour = 14; c.minute = 0
        return Calendar.current.date(from: c)!
    }

    /// A snapshot that has cleared every setup gate, so `state(at:)` reaches the
    /// running states.
    private func readySnapshot(schedule: PaperweightSchedule? = nil) -> WidgetSnapshot {
        var s = WidgetSnapshot()
        s.isArmed = true
        s.hasSelection = true
        s.hasNFCToken = true
        s.isScreenTimeAuthorized = true
        s.schedule = schedule
        return s
    }

    // MARK: Precedence

    func test_unauthorized_outranksEverything() {
        var s = readySnapshot()
        s.isScreenTimeAuthorized = false
        s.unlockExpiresAt = reference.addingTimeInterval(600)
        XCTAssertEqual(s.state(at: reference), .notAuthorized)
    }

    func test_nothingChosen_outranksArmedState() {
        var s = readySnapshot()
        s.hasSelection = false
        XCTAssertEqual(s.state(at: reference), .nothingChosen)
    }

    func test_noUnlockMethod_showsNoWayBack_evenWhenDisarmed() {
        var s = readySnapshot()
        s.isArmed = false
        s.hasNFCToken = false
        s.hasRecoveryCodes = false
        XCTAssertEqual(s.state(at: reference), .noWayBack)
    }

    func test_recoveryCodesAloneSatisfyUnlockMethod() {
        var s = readySnapshot()
        s.hasNFCToken = false
        s.hasRecoveryCodes = true
        XCTAssertEqual(s.state(at: reference), .quietOpen)
    }

    func test_disarmed_showsOff() {
        var s = readySnapshot()
        s.isArmed = false
        XCTAssertEqual(s.state(at: reference), .off)
    }

    /// The unlock resolves in minutes and the cool-off in a day; the sooner one
    /// is the more useful fact.
    func test_timedUnlock_outranksCoolOff() {
        var s = readySnapshot()
        s.unlockExpiresAt = reference.addingTimeInterval(600)
        s.coolOffReleaseDate = reference.addingTimeInterval(86_400)
        guard case .timedUnlock = s.state(at: reference) else {
            return XCTFail("expected timedUnlock, got \(s.state(at: reference))")
        }
    }

    func test_expiredUnlock_fallsThroughToCoolOff() {
        var s = readySnapshot()
        s.unlockExpiresAt = reference.addingTimeInterval(-1)
        s.coolOffReleaseDate = reference.addingTimeInterval(86_400)
        guard case .coolOff = s.state(at: reference) else {
            return XCTFail("expected coolOff, got \(s.state(at: reference))")
        }
    }

    func test_unlockRing_depletesAcrossTheWindow() {
        var s = readySnapshot()
        s.unlockDuration = 900
        s.unlockExpiresAt = reference.addingTimeInterval(450)
        guard case .timedUnlock(_, let fraction) = s.state(at: reference) else {
            return XCTFail("expected timedUnlock")
        }
        XCTAssertEqual(fraction, 0.5, accuracy: 0.001)
    }

    // MARK: Schedule-driven states

    func test_noSchedule_isQuietOpen() {
        XCTAssertEqual(readySnapshot().state(at: reference), .quietOpen)
    }

    func test_emptySchedule_isQuietOpen() {
        XCTAssertEqual(readySnapshot(schedule: PaperweightSchedule()).state(at: reference), .quietOpen)
    }

    func test_insideFreeWindow_isFreeWindow() {
        var schedule = PaperweightSchedule()
        for hour in 13..<16 { schedule.setFree(day: 0, hour: hour, true) }
        guard case .freeWindow(let ends, _) = readySnapshot(schedule: schedule).state(at: reference) else {
            return XCTFail("expected freeWindow")
        }
        XCTAssertEqual(ends.timeIntervalSince(reference), 2 * 3600, accuracy: 1)
    }

    func test_outsideFreeWindow_isQuietBounded() {
        var schedule = PaperweightSchedule()
        for hour in 17..<21 { schedule.setFree(day: 0, hour: hour, true) }
        guard case .quietBounded(let ends, _) = readySnapshot(schedule: schedule).state(at: reference) else {
            return XCTFail("expected quietBounded")
        }
        XCTAssertEqual(ends.timeIntervalSince(reference), 3 * 3600, accuracy: 1)
    }

    /// An all-free schedule leaves nothing quiet, so the widget shouldn't claim a
    /// countdown it can't produce.
    func test_alwaysFreeSchedule_readsAsOff() {
        XCTAssertEqual(readySnapshot(schedule: .alwaysFree()).state(at: reference), .off)
    }

    func test_coolOffRing_depletesAcrossTheDelay() {
        var s = readySnapshot()
        s.coolOffRequestedAt = reference.addingTimeInterval(-86_400)
        s.coolOffReleaseDate = reference.addingTimeInterval(86_400)
        guard case .coolOff(_, let fraction) = s.state(at: reference) else {
            return XCTFail("expected coolOff")
        }
        XCTAssertEqual(fraction, 0.5, accuracy: 0.001)
    }

    /// A cool-off written by a build that didn't record the request date still
    /// renders — it just draws an empty track instead of a wrong arc.
    func test_coolOffWithoutRequestDate_hasNoArc() {
        var s = readySnapshot()
        s.coolOffReleaseDate = reference.addingTimeInterval(86_400)
        XCTAssertEqual(s.state(at: reference).ringProgress, 0)
    }

    // MARK: Boundaries

    func test_nextBoundary_isTheSoonestOfAll() {
        var schedule = PaperweightSchedule()
        for hour in 17..<21 { schedule.setFree(day: 0, hour: hour, true) }
        var s = readySnapshot(schedule: schedule)
        s.unlockExpiresAt = reference.addingTimeInterval(600)

        XCTAssertEqual(s.nextBoundary(at: reference)?.timeIntervalSince(reference) ?? 0,
                       600, accuracy: 1)
    }

    func test_nextBoundary_nilWhenNothingScheduled() {
        XCTAssertNil(readySnapshot().nextBoundary(at: reference))
    }

    /// Sunday 14:00 inside a quiet-all-day exception over a schedule that has a
    /// Sunday 13–17 open window: quiet, and the boundary is Monday's first open slot.
    func test_stateAndBoundaryAcrossAnExceptionEdge() throws {
        var schedule = PaperweightSchedule()
        for hour in 13..<17 { schedule.setFree(day: 0, hour: hour, true) }
        for hour in 9..<12 { schedule.setFree(day: 1, hour: hour, true) }
        var s = readySnapshot(schedule: schedule)
        let sunday = DayKey(year: 2026, month: 1, day: 4)
        s.dayExceptions = [DayException(firstDay: sunday, lastDay: sunday, treatment: .quietAllDay)]

        let monday9 = Calendar.current.date(from: DateComponents(year: 2026, month: 1, day: 5, hour: 9))!
        guard case .quietBounded(let ends, _) = s.state(at: reference) else { return XCTFail("expected quietBounded") }
        XCTAssertEqual(ends, monday9)
        XCTAssertEqual(s.nextBoundary(at: reference), monday9)
    }

    func test_dayOffOverAnEmptyScheduleIsOff() {
        var s = readySnapshot(schedule: PaperweightSchedule())
        let sunday = DayKey(year: 2026, month: 1, day: 4)
        s.dayExceptions = [DayException(firstDay: sunday, lastDay: sunday, treatment: .openAllDay)]
        // Open, and the next quiet slot is Monday 00:00 — a bounded open window.
        guard case .freeWindow(let ends, _) = s.state(at: reference) else { return XCTFail("expected freeWindow") }
        XCTAssertEqual(ends, Calendar.current.date(from: DateComponents(year: 2026, month: 1, day: 5))!)
    }

    // MARK: Copy

    func test_copyNeverSaysBlocked() {
        let states: [WidgetState] = [
            .unwritten, .notAuthorized, .nothingChosen, .noWayBack, .off,
            .quietOpen,
            .quietBounded(ends: reference.addingTimeInterval(3600), fraction: 0.5),
            .freeWindow(ends: reference.addingTimeInterval(3600), fraction: 0.5),
            .timedUnlock(ends: reference.addingTimeInterval(600), fraction: 0.5),
            .coolOff(ends: reference.addingTimeInterval(86_400), fraction: 0.5),
        ]

        for state in states {
            let copy = state.copy(at: reference)
            for line in [copy.eyebrow, copy.caption, copy.accessoryValue,
                         copy.accessoryLine, copy.boundaryLine] {
                XCTAssertFalse(line.lowercased().contains("block"),
                               "\(state) says \"block\" in: \(line)")
                XCTAssertFalse(line.lowercased().contains("restrict"),
                               "\(state) says \"restrict\" in: \(line)")
                XCTAssertFalse(line.contains("!"), "\(state) has an exclamation mark: \(line)")
            }
        }
    }

    /// The Lock Screen renders accessories in vibrant mode, where colour flattens
    /// to luminance — so no two states may rely on tint alone to be told apart.
    func test_everyDormantStateHasADistinctGlyph() {
        let dormant: [WidgetState] = [.notAuthorized, .nothingChosen, .noWayBack, .off]
        let glyphs = dormant.compactMap(\.glyph)
        XCTAssertEqual(glyphs.count, dormant.count, "a dormant state is missing its glyph")
        XCTAssertEqual(Set(glyphs).count, glyphs.count, "two dormant states share a glyph")
    }

    func test_rectangularLinesFitTheLockScreen() {
        let states: [WidgetState] = [
            .unwritten, .notAuthorized, .nothingChosen, .noWayBack, .off, .quietOpen,
            .quietBounded(ends: reference.addingTimeInterval(12 * 3600), fraction: 0.5),
            .freeWindow(ends: reference.addingTimeInterval(3600), fraction: 0.5),
            .timedUnlock(ends: reference.addingTimeInterval(600), fraction: 0.5),
            // Day-qualified boundaries are the long ones — "tomorrow" is the
            // worst case, longer than any abbreviated weekday.
            .quietBounded(ends: reference.addingTimeInterval(26 * 3600), fraction: 0.5),
            .freeWindow(ends: reference.addingTimeInterval(51 * 3600), fraction: 0.5),
        ]
        for state in states {
            let copy = state.copy(at: reference)
            XCTAssertLessThanOrEqual(copy.accessoryValue.count, 24, "\(state): \(copy.accessoryValue)")
            XCTAssertLessThanOrEqual(copy.accessoryLine.count, 24, "\(state): \(copy.accessoryLine)")
        }
    }

    func test_compactDuration() {
        XCTAssertEqual(WidgetState.compactDuration(3 * 3600 + 20 * 60), "3h 20m")
        XCTAssertEqual(WidgetState.compactDuration(3 * 3600), "3h")
        XCTAssertEqual(WidgetState.compactDuration(42 * 60), "42m")
        // A boundary that has arrived is a different state, never "0m".
        XCTAssertEqual(WidgetState.compactDuration(0), "1m")
        XCTAssertEqual(WidgetState.compactDuration(-500), "1m")
    }

    // MARK: Boundaries that aren't today

    /// A bare "02:00" reads as *tonight*. That's fine when it is tonight, and
    /// badly wrong when the free window runs 51 hours to Tuesday — the widget
    /// was telling people to expect quiet in a few hours.
    func test_boundaryLaterTodayStaysBareTime() {
        let ends = reference.addingTimeInterval(3 * 3600) // Sunday 17:00
        let copy = WidgetState.freeWindow(ends: ends, fraction: 0.5).copy(at: reference)
        XCTAssertEqual(copy.boundaryLine, "Open until \(WidgetState.clock(ends)), then quiet")
    }

    func test_boundaryTomorrowSaysTomorrow() {
        let ends = reference.addingTimeInterval(24 * 3600) // Monday 14:00
        let copy = WidgetState.freeWindow(ends: ends, fraction: 0.5).copy(at: reference)
        XCTAssertTrue(copy.boundaryLine.contains("tomorrow"), copy.boundaryLine)
    }

    func test_boundaryDaysOutNamesTheWeekday() {
        let ends = reference.addingTimeInterval(51 * 3600) // Tuesday 17:00
        let copy = WidgetState.freeWindow(ends: ends, fraction: 0.5).copy(at: reference)
        XCTAssertTrue(copy.boundaryLine.contains("Tuesday"), copy.boundaryLine)
        XCTAssertFalse(copy.boundaryLine.contains("tomorrow"), copy.boundaryLine)
    }

    /// Day-based, not 24-hour-based: 40 minutes across midnight is still a
    /// different day, and "00:10" alone would read as ten past midnight tonight.
    func test_boundaryJustPastMidnightSaysTomorrow() {
        let lateSunday = reference.addingTimeInterval(9.5 * 3600) // 23:30
        let ends = lateSunday.addingTimeInterval(40 * 60)         // Monday 00:10
        let copy = WidgetState.quietBounded(ends: ends, fraction: 0.5).copy(at: lateSunday)
        XCTAssertTrue(copy.boundaryLine.contains("tomorrow"), copy.boundaryLine)
    }

    // MARK: Deep links

    func test_setupStatesLinkToTheirFix() {
        XCTAssertEqual(WidgetState.nothingChosen.url?.host, "choose-apps")
        XCTAssertEqual(WidgetState.noWayBack.url?.host, "unlock-setup")
        XCTAssertEqual(WidgetState.timedUnlock(ends: reference, fraction: 1).url?.host, "unlock")
        XCTAssertEqual(WidgetState.quietOpen.url?.host, "home")
    }

    // MARK: Round-tripping

    func test_snapshotSurvivesEncodeDecode() throws {
        var s = readySnapshot(schedule: .weekdayEvenings())
        s.coolOffReleaseDate = reference
        s.unlockExpiresAt = reference.addingTimeInterval(600)
        s.unlockDuration = 1200

        let decoded = try JSONDecoder().decode(
            WidgetSnapshot.self, from: try JSONEncoder().encode(s))

        XCTAssertEqual(decoded, s)
    }

    /// Forward compatibility: a snapshot written by a build that didn't know
    /// about these keys still decodes with defaults, same as PaperweightConfig.
    func test_partialSnapshotDecodesWithDefaults() throws {
        let json = Data(#"{"isArmed":true}"#.utf8)
        let decoded = try JSONDecoder().decode(WidgetSnapshot.self, from: json)

        XCTAssertTrue(decoded.isArmed)
        XCTAssertFalse(decoded.hasSelection)
        XCTAssertNil(decoded.schedule)
        XCTAssertEqual(decoded.unlockDuration, Paperweight.defaultUnlockDuration)
    }

    func test_decodingASnapshotWithoutDayExceptionsGivesAnEmptyList() throws {
        let data = Data(#"{"isArmed":true}"#.utf8)
        let s = try JSONDecoder().decode(WidgetSnapshot.self, from: data)
        XCTAssertEqual(s.dayExceptions, [])
    }

    func test_snapshotFromConfigCopiesDayExceptions() {
        var config = PaperweightConfig()
        config.dayExceptions = [DayException(firstDay: DayKey(year: 2026, month: 9, day: 18),
                                             lastDay: DayKey(year: 2026, month: 9, day: 18),
                                             treatment: .quietAllDay)]
        let s = WidgetSnapshot(config: config, isScreenTimeAuthorized: true)
        XCTAssertEqual(s.dayExceptions, config.dayExceptions)
    }
}
#endif
