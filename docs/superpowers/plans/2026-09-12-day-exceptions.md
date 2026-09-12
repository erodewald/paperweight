# Day Exceptions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a calendar day, or a run of days, be treated as open all day, quiet all day, or like another weekday, under the existing rule that tightening applies now and loosening waits for tomorrow.

**Architecture:** Exceptions are a list on `PaperweightConfig`, layered over the weekly grid by a pure `ScheduleResolver` in `Shared/` that every shield decision and the widget consult. Mutation goes through two config methods that enforce the deferral rule. No per-exception DeviceActivity activities: a midnight heartbeat plus the existing union-of-windows registration cover every edge.

**Tech Stack:** Swift 5.9, SwiftUI, iOS 17+, XcodeGen, XCTest. Spec: `docs/superpowers/specs/2026-09-12-day-exceptions-design.md`.

## Global Constraints

- Deployment target iOS 17.0; Swift 5.9. No new dependencies.
- The `.xcodeproj` is generated and gitignored — run `xcodegen generate` **after adding or moving files**, before building.
- `PaperweightTests` compiles `PaperweightTests/` + `Shared/` only. **Anything needing a unit test must live in `Shared/`.**
- `Shared/` also compiles into the DeviceActivity monitor extension — keep `Shared/Models` and `Shared/Services` Foundation-only, no SwiftUI. (`Shared/ViewModels` already imports SwiftUI and is `#if os(iOS)`.)
- The widget target enumerates its `Shared` files one by one in `project.yml` and must never see `FamilyActivitySelection`. New Foundation-only model files it needs are listed in Task 6.
- `PaperweightConfig`'s decoder is deliberately tolerant: every field uses `decodeIfPresent` with a fallback, because a thrown decode would wipe the user's registered unlock token. New fields must follow that pattern exactly. Same for `WidgetSnapshot`.
- Named colours from the `PW` enum only — no literal hex. Fonts via `.grotesk(_:weight:)` / `.spectral(_:italic:)`.
- Text floor: **13px minimum** for anything the user reads (widget internals at 8–11pt are pre-existing and out of scope).
- Copy: the word **"free"** is banned from user-facing strings (quiet / open instead). No exclamation marks. `freeSlots`, `isFree(at:)`, `freeStatus` are model API and keep their names.
- Test-first for every task: write the test, run it and see it fail for the right reason, then implement.

**Test command** (run from the repo root; `-only-testing:` narrows to a class):

```bash
xcodebuild test -project Paperweight.xcodeproj -scheme PaperweightTests -destination 'platform=iOS Simulator,name=iPhone 17 Pro' CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "error:|Test Case.*failed|Executed [0-9]+ tests|TEST"
```

**Build command** (app + monitor + widget):

```bash
xcodebuild build -project Paperweight.xcodeproj -scheme Paperweight -destination 'platform=iOS Simulator,name=iPhone 17 Pro' CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "error:|BUILD"
```

The suite is 147 tests at the start of this plan.

---

### Task 1: `DayKey` — a zone-free calendar date

**Files:**
- Create: `Shared/Models/DayKey.swift`
- Test: `PaperweightTests/Models/DayKeyTests.swift`

**Interfaces:**
- Produces: `struct DayKey: Hashable, Comparable, Codable` with `init(year:month:day:)`, `init(_ date: Date, calendar:)`, `static today(calendar:)`, `date(calendar:) -> Date`, `next(calendar:)`, `previous(calendar:)`, `advanced(by:calendar:)`, `weekdayIndex(calendar:) -> Int` (0 = Sunday), `static week(containing:calendar:) -> [DayKey]` (Sunday…Saturday).

- [ ] **Step 1: Write the failing tests**

```swift
// PaperweightTests/Models/DayKeyTests.swift
import XCTest

final class DayKeyTests: XCTestCase {

    private let cal = Calendar.current

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }

    func test_initFromDateDropsTheTime() {
        XCTAssertEqual(DayKey(date(2026, 1, 4, 23), calendar: cal), DayKey(year: 2026, month: 1, day: 4))
    }

    func test_dateIsStartOfDay() {
        XCTAssertEqual(DayKey(year: 2026, month: 1, day: 4).date(calendar: cal), cal.startOfDay(for: date(2026, 1, 4)))
    }

    func test_nextCrossesAMonthEnd() {
        XCTAssertEqual(DayKey(year: 2026, month: 1, day: 31).next(calendar: cal), DayKey(year: 2026, month: 2, day: 1))
    }

    /// 2026-11-01 is the US fall-back day (25 real hours). Walking by calendar
    /// day must not skip or repeat it.
    func test_nextAcrossFallBackDST() {
        let oct31 = DayKey(year: 2026, month: 10, day: 31)
        XCTAssertEqual(oct31.next(calendar: cal), DayKey(year: 2026, month: 11, day: 1))
        XCTAssertEqual(oct31.next(calendar: cal).next(calendar: cal), DayKey(year: 2026, month: 11, day: 2))
        XCTAssertEqual(DayKey(year: 2026, month: 11, day: 2).previous(calendar: cal), DayKey(year: 2026, month: 11, day: 1))
    }

    func test_comparison() {
        XCTAssertLessThan(DayKey(year: 2026, month: 1, day: 31), DayKey(year: 2026, month: 2, day: 1))
        XCTAssertLessThan(DayKey(year: 2025, month: 12, day: 31), DayKey(year: 2026, month: 1, day: 1))
    }

    func test_weekdayIndexMatchesTheGrid() {
        // 2026-01-04 is a Sunday.
        XCTAssertEqual(DayKey(year: 2026, month: 1, day: 4).weekdayIndex(calendar: cal), 0)
        XCTAssertEqual(DayKey(year: 2026, month: 1, day: 10).weekdayIndex(calendar: cal), 6)
    }

    func test_weekContainingRunsSundayToSaturday() {
        let week = DayKey.week(containing: DayKey(year: 2026, month: 1, day: 7), calendar: cal)
        XCTAssertEqual(week.first, DayKey(year: 2026, month: 1, day: 4))
        XCTAssertEqual(week.last, DayKey(year: 2026, month: 1, day: 10))
        XCTAssertEqual(week.count, 7)
    }

    func test_codableRoundTripsAsISODateString() throws {
        let key = DayKey(year: 2026, month: 9, day: 5)
        let data = try JSONEncoder().encode(key)
        XCTAssertEqual(String(data: data, encoding: .utf8), "\"2026-09-05\"")
        XCTAssertEqual(try JSONDecoder().decode(DayKey.self, from: data), key)
    }

    func test_decodingGarbageThrows() {
        XCTAssertThrowsError(try JSONDecoder().decode(DayKey.self, from: Data("\"soon\"".utf8)))
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `xcodegen generate && <test command> -only-testing:PaperweightTests/DayKeyTests`
Expected: compile error `cannot find 'DayKey' in scope`.

- [ ] **Step 3: Implement**

```swift
// Shared/Models/DayKey.swift
import Foundation

/// A calendar date with no time and no zone, so a planned day means the same
/// day across DST changes and travel. Encoded as "YYYY-MM-DD".
struct DayKey: Hashable, Comparable, Codable {
    let year: Int
    let month: Int
    let day: Int

    init(year: Int, month: Int, day: Int) {
        self.year = year; self.month = month; self.day = day
    }

    init(_ date: Date, calendar: Calendar = .current) {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: c.year ?? 1, month: c.month ?? 1, day: c.day ?? 1)
    }

    static func today(calendar: Calendar = .current) -> DayKey {
        DayKey(Date(), calendar: calendar)
    }

    /// The first instant of the day. A well-formed key always resolves; the
    /// fallback fails closed (far future reads as "not yet").
    func date(calendar: Calendar = .current) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day)) ?? .distantFuture
    }

    func advanced(by days: Int, calendar: Calendar = .current) -> DayKey {
        // Ask the calendar rather than adding 86 400 s, so a 23- or 25-hour
        // DST day is still one day.
        guard let d = calendar.date(byAdding: .day, value: days, to: date(calendar: calendar)) else { return self }
        return DayKey(d, calendar: calendar)
    }

    func next(calendar: Calendar = .current) -> DayKey { advanced(by: 1, calendar: calendar) }
    func previous(calendar: Calendar = .current) -> DayKey { advanced(by: -1, calendar: calendar) }

    /// 0 = Sunday … 6 = Saturday, matching `PaperweightSchedule`'s day index.
    func weekdayIndex(calendar: Calendar = .current) -> Int {
        (calendar.component(.weekday, from: date(calendar: calendar)) - 1 + 7) % 7
    }

    /// Sunday through Saturday of the week containing `day`, in that order —
    /// the rows of the Home week strip.
    static func week(containing day: DayKey, calendar: Calendar = .current) -> [DayKey] {
        let sunday = day.advanced(by: -day.weekdayIndex(calendar: calendar), calendar: calendar)
        return (0..<7).map { sunday.advanced(by: $0, calendar: calendar) }
    }

    static func < (a: DayKey, b: DayKey) -> Bool {
        (a.year, a.month, a.day) < (b.year, b.month, b.day)
    }

    // MARK: Codable — "YYYY-MM-DD"

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        let parts = raw.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                                                    debugDescription: "DayKey expects YYYY-MM-DD, got \(raw)"))
        }
        self.init(year: parts[0], month: parts[1], day: parts[2])
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(String(format: "%04d-%02d-%02d", year, month, day))
    }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `xcodegen generate && <test command> -only-testing:PaperweightTests/DayKeyTests`
Expected: `Executed 9 tests, with 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add Shared/Models/DayKey.swift PaperweightTests/Models/DayKeyTests.swift
git commit -m "feat: add DayKey, a zone-free calendar date"
```

---

### Task 2: `DayException` and the config / snapshot fields

**Files:**
- Create: `Shared/Models/DayException.swift`
- Modify: `Shared/Models/PaperweightConfig.swift` (add field + decoder line)
- Modify: `Shared/Models/WidgetSnapshot.swift` (add field + decoder line)
- Modify: `Shared/Store/WidgetSnapshot+Config.swift` (copy the field)
- Test: `PaperweightTests/Models/DayExceptionTests.swift`, additions to `PaperweightTests/Models/PaperweightConfigTests.swift` and `PaperweightTests/Models/WidgetSnapshotTests.swift`

**Interfaces:**
- Consumes: `DayKey` (Task 1).
- Produces: `struct DayException: Codable, Equatable, Identifiable` with `id`, `firstDay`, `lastDay`, `treatment: DayException.Treatment` (`.openAllDay | .quietAllDay | .likeWeekday(Int)`), `note`, `createdAt`, `covers(_:)`, `overlaps(_:)`, `dayCount(calendar:)`. `PaperweightConfig.dayExceptions: [DayException]`. `WidgetSnapshot.dayExceptions: [DayException]`.

- [ ] **Step 1: Write the failing tests**

```swift
// PaperweightTests/Models/DayExceptionTests.swift
import XCTest

final class DayExceptionTests: XCTestCase {

    private func key(_ d: Int) -> DayKey { DayKey(year: 2026, month: 9, day: d) }

    /// A whole-second `createdAt`, so JSON round trips compare equal.
    private let created = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func exception(_ first: Int, _ last: Int, _ t: DayException.Treatment = .openAllDay) -> DayException {
        DayException(firstDay: key(first), lastDay: key(last), treatment: t, createdAt: created)
    }

    func test_coversIsInclusiveOnBothEnds() {
        let e = exception(21, 25)
        XCTAssertTrue(e.covers(key(21)))
        XCTAssertTrue(e.covers(key(25)))
        XCTAssertFalse(e.covers(key(20)))
        XCTAssertFalse(e.covers(key(26)))
    }

    func test_overlapsDetectsAnySharedDay() {
        XCTAssertTrue(exception(21, 25).overlaps(exception(25, 27)))
        XCTAssertTrue(exception(21, 25).overlaps(exception(19, 21)))
        XCTAssertTrue(exception(21, 25).overlaps(exception(22, 23)))
        XCTAssertFalse(exception(21, 25).overlaps(exception(26, 26)))
    }

    func test_dayCount() {
        XCTAssertEqual(exception(21, 25).dayCount(), 5)
        XCTAssertEqual(exception(21, 21).dayCount(), 1)
    }

    func test_treatmentRoundTripsThroughCodable() throws {
        for t: DayException.Treatment in [.openAllDay, .quietAllDay, .likeWeekday(6)] {
            let e = exception(21, 21, t)
            let back = try JSONDecoder().decode(DayException.self, from: try JSONEncoder().encode(e))
            XCTAssertEqual(back, e)
        }
    }
}
```

Add to `PaperweightConfigTests.swift`:

```swift
    func test_decodingAConfigWithoutDayExceptionsGivesAnEmptyList() throws {
        let data = Data(#"{"isEnabled":true}"#.utf8)
        let config = try JSONDecoder().decode(PaperweightConfig.self, from: data)
        XCTAssertTrue(config.isEnabled)
        XCTAssertEqual(config.dayExceptions, [])
    }

    func test_dayExceptionsRoundTrip() throws {
        var config = PaperweightConfig()
        config.dayExceptions = [DayException(firstDay: DayKey(year: 2026, month: 9, day: 18),
                                             lastDay: DayKey(year: 2026, month: 9, day: 18),
                                             treatment: .openAllDay, note: "Company holiday",
                                             createdAt: Date(timeIntervalSinceReferenceDate: 800_000_000))]
        let back = try JSONDecoder().decode(PaperweightConfig.self, from: try JSONEncoder().encode(config))
        XCTAssertEqual(back.dayExceptions, config.dayExceptions)
    }
```

Add to `WidgetSnapshotTests.swift`:

```swift
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
```

- [ ] **Step 2: Run to verify it fails**

Run: `xcodegen generate && <test command> -only-testing:PaperweightTests/DayExceptionTests -only-testing:PaperweightTests/PaperweightConfigTests -only-testing:PaperweightTests/WidgetSnapshotTests`
Expected: compile error `cannot find 'DayException' in scope`.

- [ ] **Step 3: Implement the model**

```swift
// Shared/Models/DayException.swift
import Foundation

/// A calendar day, or an inclusive run of days, on which the weekly grid is
/// replaced by a whole-day treatment. Exceptions never overlap; the mutation
/// API on `PaperweightConfig` enforces that, so the resolver never ranks them.
struct DayException: Codable, Equatable, Identifiable {
    var id: UUID = UUID()
    var firstDay: DayKey
    var lastDay: DayKey
    var treatment: Treatment
    /// Optional in the UI; "" when empty. At most 40 characters, trimmed.
    var note: String = ""
    var createdAt: Date = Date()

    enum Treatment: Codable, Equatable {
        case openAllDay
        case quietAllDay
        /// 0 = Sunday … 6 = Saturday, matching the grid's day index.
        case likeWeekday(Int)
    }

    init(id: UUID = UUID(), firstDay: DayKey, lastDay: DayKey, treatment: Treatment,
         note: String = "", createdAt: Date = Date()) {
        self.id = id; self.firstDay = firstDay; self.lastDay = lastDay
        self.treatment = treatment; self.note = note; self.createdAt = createdAt
    }

    func covers(_ day: DayKey) -> Bool { firstDay <= day && day <= lastDay }

    func overlaps(_ other: DayException) -> Bool {
        firstDay <= other.lastDay && other.firstDay <= lastDay
    }

    func dayCount(calendar: Calendar = .current) -> Int {
        (calendar.dateComponents([.day], from: firstDay.date(calendar: calendar),
                                 to: lastDay.date(calendar: calendar)).day ?? 0) + 1
    }
}
```

Then `PaperweightConfig.swift` — add the stored property after `pendingScheduleEffectiveAt`:

```swift
    /// Planned days off and quiet days, layered over the weekly schedule.
    var dayExceptions: [DayException] = []
```

and in `init(from:)`, after the `pendingScheduleEffectiveAt` line:

```swift
        dayExceptions = (try? c.decodeIfPresent([DayException].self, forKey: .dayExceptions)) ?? []
```

`WidgetSnapshot.swift` — add after `unlockDuration`:

```swift
    var dayExceptions: [DayException] = []
```

and in its `init(from:)` after the `unlockDuration` decode:

```swift
        dayExceptions = (try? c.decodeIfPresent([DayException].self, forKey: .dayExceptions)) ?? []
```

`WidgetSnapshot+Config.swift` — after `schedule = config.schedule`:

```swift
        dayExceptions = config.dayExceptions
```

- [ ] **Step 4: Run to verify it passes**

Run: `xcodegen generate && <test command> -only-testing:PaperweightTests/DayExceptionTests -only-testing:PaperweightTests/PaperweightConfigTests -only-testing:PaperweightTests/WidgetSnapshotTests`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add Shared/Models/DayException.swift Shared/Models/PaperweightConfig.swift Shared/Models/WidgetSnapshot.swift Shared/Store/WidgetSnapshot+Config.swift PaperweightTests/Models/DayExceptionTests.swift PaperweightTests/Models/PaperweightConfigTests.swift PaperweightTests/Models/WidgetSnapshotTests.swift
git commit -m "feat: add DayException and the dayExceptions field on config and snapshot"
```

---

### Task 3: `ScheduleResolver`

**Files:**
- Create: `Shared/Models/ScheduleResolver.swift`
- Modify: `Shared/Models/PaperweightSchedule+Week.swift` (extract `segments(openSlots:)`)
- Test: `PaperweightTests/Models/ScheduleResolverTests.swift`

**Interfaces:**
- Consumes: `DayKey`, `DayException`, `PaperweightSchedule`, `PaperweightSchedule.DaySegment`.
- Produces: `struct ScheduleResolver { init(schedule: PaperweightSchedule?, exceptions: [DayException], calendar: Calendar = .current) }` with `exception(on:)`, `openSlots(on:)`, `openSlots(for treatment: DayException.Treatment?, weekday: Int)`, `isFree(at:)`, `quietStatus(at:)`, `freeStatus(at:)`, `daySegments(on:)`, `isOpenAllDay(on:)`. `PaperweightSchedule.segments(openSlots:) -> [DaySegment]` (static).

- [ ] **Step 1: Write the failing tests**

```swift
// PaperweightTests/Models/ScheduleResolverTests.swift
import XCTest

final class ScheduleResolverTests: XCTestCase {

    private let cal = Calendar.current

    /// January 2026 — no DST inside the test window. 2026-01-04 is a Sunday.
    private func jan(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 1, day: day, hour: hour, minute: minute))!
    }
    private func key(_ day: Int) -> DayKey { DayKey(year: 2026, month: 1, day: day) }

    /// Weekday evenings 17–21 open; Saturday 9–12 open; Sunday all quiet.
    private var weekly: PaperweightSchedule {
        var s = PaperweightSchedule.weekdayEvenings()
        for hour in 9..<12 { s.setFree(day: 6, hour: hour, true) }
        return s
    }

    private func resolver(_ exceptions: [DayException] = [], schedule: PaperweightSchedule? = nil) -> ScheduleResolver {
        ScheduleResolver(schedule: schedule ?? weekly, exceptions: exceptions, calendar: cal)
    }

    // MARK: Equivalence with the weekly schedule

    func test_withNoExceptionsMatchesTheWeeklyScheduleEverywhere() {
        let r = resolver()
        for day in 4...10 {
            for half in 0..<48 {
                let at = jan(day, half / 2, (half % 2) * 30).addingTimeInterval(7 * 60)
                XCTAssertEqual(r.isFree(at: at), weekly.isFree(at: at, calendar: cal), "\(at)")
                let q1 = r.quietStatus(at: at), q2 = weekly.quietStatus(at: at, calendar: cal)
                XCTAssertEqual(q1?.ends, q2?.ends, "\(at)")
                XCTAssertEqual(q1?.remainingFraction ?? -1, q2?.remainingFraction ?? -1, accuracy: 1e-9, "\(at)")
                let f1 = r.freeStatus(at: at), f2 = weekly.freeStatus(at: at, calendar: cal)
                XCTAssertEqual(f1?.ends, f2?.ends, "\(at)")
                XCTAssertEqual(f1?.elapsedFraction ?? -1, f2?.elapsedFraction ?? -1, accuracy: 1e-9, "\(at)")
            }
        }
    }

    // MARK: Treatments

    func test_openAllDayIsOpenFromMidnightToMidnight() {
        let r = resolver([DayException(firstDay: key(5), lastDay: key(5), treatment: .openAllDay)])
        XCTAssertTrue(r.isFree(at: jan(5, 0, 0)))
        XCTAssertTrue(r.isFree(at: jan(5, 12, 0)))
        XCTAssertTrue(r.isFree(at: jan(5, 23, 59)))
        XCTAssertFalse(r.isFree(at: jan(6, 0, 0)), "Tuesday is an ordinary day again")
    }

    func test_quietAllDayOverridesAnOpenEvening() {
        let r = resolver([DayException(firstDay: key(5), lastDay: key(5), treatment: .quietAllDay)])
        XCTAssertFalse(r.isFree(at: jan(5, 18, 0)))
        XCTAssertTrue(r.isFree(at: jan(6, 18, 0)))
    }

    func test_likeWeekdayReadsThatWeekdaysColumn() {
        // Monday the 5th treated like Saturday: open 9–12, quiet in the evening.
        let r = resolver([DayException(firstDay: key(5), lastDay: key(5), treatment: .likeWeekday(6))])
        XCTAssertTrue(r.isFree(at: jan(5, 10, 0)))
        XCTAssertFalse(r.isFree(at: jan(5, 18, 0)))
    }

    func test_rangeCoversEveryDayInIt() {
        let r = resolver([DayException(firstDay: key(5), lastDay: key(7), treatment: .quietAllDay)])
        XCTAssertFalse(r.isFree(at: jan(6, 18, 0)))
        XCTAssertTrue(r.isFree(at: jan(8, 18, 0)))
    }

    func test_openAllDayOverAnEmptyWeeklyScheduleStillOpens() {
        let r = resolver([DayException(firstDay: key(5), lastDay: key(5), treatment: .openAllDay)],
                         schedule: PaperweightSchedule())
        XCTAssertTrue(r.isFree(at: jan(5, 12, 0)))
        XCTAssertFalse(r.isFree(at: jan(6, 12, 0)))
    }

    // MARK: Countdowns across an edge

    /// Thursday 21:00 → quiet; Friday is a day off; so quiet ends at Friday 00:00.
    func test_quietCountdownEndsAtTheStartOfADayOff() throws {
        let r = resolver([DayException(firstDay: key(9), lastDay: key(9), treatment: .openAllDay)])
        let q = try XCTUnwrap(r.quietStatus(at: jan(8, 22, 0)))
        XCTAssertEqual(q.ends, jan(9, 0, 0))
        XCTAssertEqual(q.remaining, 2 * 3600, accuracy: 1)
    }

    /// Inside a day off at noon: open until the first quiet slot of Saturday (00:00).
    func test_openCountdownInsideADayOffEndsAtTheNextQuietSlot() throws {
        let r = resolver([DayException(firstDay: key(9), lastDay: key(9), treatment: .openAllDay)])
        let f = try XCTUnwrap(r.freeStatus(at: jan(9, 12, 0)))
        XCTAssertEqual(f.ends, jan(10, 0, 0))
        // Thursday 21:00–24:00 is quiet, so the open run is exactly Friday: 24h, half spent at noon.
        XCTAssertEqual(f.elapsedFraction, 0.5, accuracy: 1e-9)
    }

    /// A quiet day on Monday: from Sunday 20:00 the quiet run ends Tuesday 17:00.
    func test_quietCountdownSkipsAQuietDay() throws {
        let r = resolver([DayException(firstDay: key(5), lastDay: key(5), treatment: .quietAllDay)])
        let q = try XCTUnwrap(r.quietStatus(at: jan(4, 20, 0)))
        XCTAssertEqual(q.ends, jan(6, 17, 0))
    }

    func test_nilWhenNoBoundaryWithinAWeek() {
        XCTAssertNil(resolver(schedule: PaperweightSchedule()).quietStatus(at: jan(5, 12, 0)))
        XCTAssertNil(resolver(schedule: .alwaysFree()).freeStatus(at: jan(5, 12, 0)))
    }

    // MARK: Day drawing

    func test_daySegmentsForAnExceptionDay() {
        let r = resolver([DayException(firstDay: key(5), lastDay: key(5), treatment: .quietAllDay)])
        XCTAssertEqual(r.daySegments(on: key(5)), [.init(isLocked: true, fraction: 1)])
        XCTAssertTrue(r.isOpenAllDay(on: key(5)) == false)
        let off = resolver([DayException(firstDay: key(5), lastDay: key(5), treatment: .openAllDay)])
        XCTAssertTrue(off.isOpenAllDay(on: key(5)))
    }

    func test_daySegmentsWithoutAnExceptionMatchTheWeeklyGrid() {
        XCTAssertEqual(resolver().daySegments(on: key(5)), weekly.daySegments(day: 1))
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `xcodegen generate && <test command> -only-testing:PaperweightTests/ScheduleResolverTests`
Expected: compile error `cannot find 'ScheduleResolver' in scope`.

- [ ] **Step 3: Extract the segment builder**

In `Shared/Models/PaperweightSchedule+Week.swift`, replace the body of `daySegments(day:)` with a call to a new static that works on a slot set:

```swift
    /// The day's runs in clock order from midnight. Always at least one segment,
    /// and the fractions always sum to 1.
    func daySegments(day: Int) -> [DaySegment] {
        Self.segments(openSlots: Set((0..<Self.halfHoursPerDay).filter { isFreeSlot(day: day, halfHour: $0) }))
    }

    /// `daySegments(day:)` for an arbitrary day expressed as its open half-hours
    /// (0…47) — how the resolver draws an exception day.
    static func segments(openSlots: Set<Int>) -> [DaySegment] {
        var segments: [DaySegment] = []
        var half = 0
        while half < halfHoursPerDay {
            let locked = !openSlots.contains(half)
            var end = half
            while end < halfHoursPerDay, (!openSlots.contains(end)) == locked { end += 1 }
            segments.append(DaySegment(isLocked: locked, fraction: Double(end - half) / Double(halfHoursPerDay)))
            half = end
        }
        return segments
    }
```

- [ ] **Step 4: Implement the resolver**

```swift
// Shared/Models/ScheduleResolver.swift
import Foundation

/// Answers "is the phone open at this instant, and until when?" with day
/// exceptions layered over the weekly grid. Pure; every shield decision, the
/// widget, and the week strip go through it.
///
/// With no exceptions it gives exactly the weekly schedule's answers — that
/// equivalence is a test.
struct ScheduleResolver {
    let schedule: PaperweightSchedule?
    let exceptions: [DayException]
    let calendar: Calendar

    init(schedule: PaperweightSchedule?, exceptions: [DayException], calendar: Calendar = .current) {
        self.schedule = schedule
        self.exceptions = exceptions
        self.calendar = calendar
    }

    /// The exception covering `day`, if any. Exceptions never overlap, so the
    /// first match is the only match.
    func exception(on day: DayKey) -> DayException? {
        exceptions.first { $0.covers(day) }
    }

    /// The half-hours (0…47) that are open under `treatment` on a day whose
    /// weekday is `weekday`; nil treatment means the plain weekly grid.
    func openSlots(for treatment: DayException.Treatment?, weekday: Int) -> Set<Int> {
        switch treatment {
        case .openAllDay: return Set(0..<PaperweightSchedule.halfHoursPerDay)
        case .quietAllDay: return []
        case .likeWeekday(let w): return weeklyOpenSlots(weekday: w)
        case nil: return weeklyOpenSlots(weekday: weekday)
        }
    }

    /// The half-hours open on a calendar day, exceptions applied.
    func openSlots(on day: DayKey) -> Set<Int> {
        openSlots(for: exception(on: day)?.treatment, weekday: day.weekdayIndex(calendar: calendar))
    }

    private func weeklyOpenSlots(weekday: Int) -> Set<Int> {
        guard let schedule else { return [] }
        return Set((0..<PaperweightSchedule.halfHoursPerDay).filter { schedule.isFreeSlot(day: weekday, halfHour: $0) })
    }

    func isFree(at date: Date) -> Bool {
        openSlots(on: DayKey(date, calendar: calendar)).contains(halfHour(of: date))
    }

    func daySegments(on day: DayKey) -> [PaperweightSchedule.DaySegment] {
        PaperweightSchedule.segments(openSlots: openSlots(on: day))
    }

    func isOpenAllDay(on day: DayKey) -> Bool {
        openSlots(on: day).count == PaperweightSchedule.halfHoursPerDay
    }

    // MARK: Countdowns

    /// While quiet: time until the next open slot, the fraction of this quiet
    /// run still remaining (depleting ring), and when it ends. Nil when open or
    /// when no open slot lies within a week.
    func quietStatus(at date: Date) -> (remaining: TimeInterval, remainingFraction: Double, ends: Date)? {
        guard let run = run(containing: date), !run.isOpen else { return nil }
        let remaining = run.ends.timeIntervalSince(date)
        let total = run.ends.timeIntervalSince(run.starts)
        let fraction = total > 0 ? remaining / total : 0
        return (remaining, max(0, min(1, fraction)), run.ends)
    }

    /// While open: time until the next quiet slot, the fraction of this open
    /// run already spent (filling ring), and when it ends. Nil when quiet or
    /// when no quiet slot lies within a week.
    func freeStatus(at date: Date) -> (remaining: TimeInterval, elapsedFraction: Double, ends: Date)? {
        guard let run = run(containing: date), run.isOpen else { return nil }
        let remaining = run.ends.timeIntervalSince(date)
        let total = run.ends.timeIntervalSince(run.starts)
        let elapsed = total > 0 ? (total - remaining) / total : 0
        return (remaining, max(0, min(1, elapsed)), run.ends)
    }

    // MARK: Slot walking

    private struct Cursor { var day: DayKey; var half: Int }

    // Day exceptions can make a run longer than a week (a two-week quiet
    // range, or a vacation range adjoining a weekend), so this walks 60 days
    // in either direction rather than 7. The per-day cache below means a
    // 60-day walk is still cheap. Nil still just means "no boundary within
    // the walk" — an always-quiet or always-open week never finds one. The
    // backward walk's silent clamp (falling out of the loop and treating the
    // truncation point as the run's start) is unchanged: at 60 days it can
    // only bite on a run longer than two months, and accepting a clamped
    // fraction in that rare case is fine.
    private static let maxWalk = 60 * PaperweightSchedule.halfHoursPerDay

    private func halfHour(of date: Date) -> Int {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return PaperweightSchedule.halfHour(hour: c.hour ?? 0, minute: c.minute ?? 0)
    }

    private func next(_ c: Cursor) -> Cursor {
        c.half + 1 < PaperweightSchedule.halfHoursPerDay
            ? Cursor(day: c.day, half: c.half + 1)
            : Cursor(day: c.day.next(calendar: calendar), half: 0)
    }

    private func previous(_ c: Cursor) -> Cursor {
        c.half > 0
            ? Cursor(day: c.day, half: c.half - 1)
            : Cursor(day: c.day.previous(calendar: calendar), half: PaperweightSchedule.halfHoursPerDay - 1)
    }

    private func slotStart(_ c: Cursor) -> Date {
        let dayStart = c.day.date(calendar: calendar)
        return calendar.date(bySettingHour: c.half / 2, minute: (c.half % 2) * 30, second: 0, of: dayStart) ?? dayStart
    }

    /// The contiguous run of same-kind slots containing `date`: whether it is
    /// open, the start of its first slot, and the start of the first slot of
    /// the other kind after it. Nil when the run doesn't end within a week.
    /// Walks by calendar day so a 23- or 25-hour DST day is still one day.
    private func run(containing date: Date) -> (isOpen: Bool, starts: Date, ends: Date)? {
        var cache: [DayKey: Set<Int>] = [:]
        func isOpen(_ c: Cursor) -> Bool {
            if let slots = cache[c.day] { return slots.contains(c.half) }
            let slots = openSlots(on: c.day)
            cache[c.day] = slots
            return slots.contains(c.half)
        }

        let here = Cursor(day: DayKey(date, calendar: calendar), half: halfHour(of: date))
        let open = isOpen(here)

        var ahead = next(here)
        var steps = 1
        while isOpen(ahead) == open {
            if steps >= Self.maxWalk { return nil }
            ahead = next(ahead)
            steps += 1
        }

        var first = here
        steps = 0
        while steps < Self.maxWalk, isOpen(previous(first)) == open {
            first = previous(first)
            steps += 1
        }

        return (open, slotStart(first), slotStart(ahead))
    }
}
```

- [ ] **Step 5: Run to verify it passes**

Run: `xcodegen generate && <test command> -only-testing:PaperweightTests/ScheduleResolverTests -only-testing:PaperweightTests/WeekSegmentTests`
Expected: all pass, including the equivalence sweep (336 instants × 3 comparisons). If `test_openCountdownInsideADayOffEndsAtTheNextQuietSlot` fails on the fraction, check the backward walk: Thursday 21:00–24:00 is quiet, so the open run starts at Friday 00:00, not inside Thursday's evening window.

- [ ] **Step 6: Commit**

```bash
git add Shared/Models/ScheduleResolver.swift Shared/Models/PaperweightSchedule+Week.swift PaperweightTests/Models/ScheduleResolverTests.swift
git commit -m "feat: add ScheduleResolver, day exceptions layered over the weekly grid"
```

---

### Task 4: The rule — add, remove, prune

**Files:**
- Create: `Shared/Models/DayException+Rule.swift`
- Modify: `Shared/Store/ConfigStore.swift` (prune on load)
- Test: `PaperweightTests/Models/DayExceptionRuleTests.swift`, addition to `PaperweightTests/Models/ConfigStoreTests.swift`

**Interfaces:**
- Consumes: `ScheduleResolver`, `DayException`, `DayKey`, `PaperweightConfig.dayExceptions`.
- Produces on `PaperweightConfig`: `var resolver: ScheduleResolver`, `func resolver(calendar:) -> ScheduleResolver`, `enum ExceptionError: Error, Equatable { case overlaps(DayException), loosensToday, endsBeforeStart }`, `enum ExceptionRemoval: Equatable { case removed, truncatedToToday, notFound }`, `func exceptionLoosens(_:on:calendar:) -> Bool`, `mutating func addDayException(_:now:calendar:) throws`, `@discardableResult mutating func removeDayException(id:now:calendar:) -> ExceptionRemoval`, `@discardableResult mutating func pruneDayExceptions(now:calendar:) -> Bool`, `func upcomingDayExceptions(now:calendar:) -> [DayException]`.

- [ ] **Step 1: Write the failing tests**

```swift
// PaperweightTests/Models/DayExceptionRuleTests.swift
import XCTest

final class DayExceptionRuleTests: XCTestCase {

    private let cal = Calendar.current

    /// "Now" is Monday 2026-01-05 at 10:00. Weekday evenings 17–21 are open;
    /// Saturday 9–12 is open; Sunday is all quiet.
    private var now: Date { cal.date(from: DateComponents(year: 2026, month: 1, day: 5, hour: 10))! }
    private func key(_ day: Int) -> DayKey { DayKey(year: 2026, month: 1, day: day) }

    private func armedConfig() -> PaperweightConfig {
        var c = PaperweightConfig()
        c.isEnabled = true
        var s = PaperweightSchedule.weekdayEvenings()
        for hour in 9..<12 { s.setFree(day: 6, hour: hour, true) }
        c.schedule = s
        return c
    }

    private func exception(_ first: Int, _ last: Int, _ t: DayException.Treatment) -> DayException {
        DayException(firstDay: key(first), lastDay: key(last), treatment: t)
    }

    // MARK: Adding

    func test_dayOffTodayIsRefused() {
        var c = armedConfig()
        XCTAssertThrowsError(try c.addDayException(exception(5, 5, .openAllDay), now: now, calendar: cal)) {
            XCTAssertEqual($0 as? PaperweightConfig.ExceptionError, .loosensToday)
        }
        XCTAssertTrue(c.dayExceptions.isEmpty)
    }

    func test_dayOffTomorrowIsAllowed() throws {
        var c = armedConfig()
        try c.addDayException(exception(6, 6, .openAllDay), now: now, calendar: cal)
        XCTAssertEqual(c.dayExceptions.count, 1)
    }

    func test_quietDayTodayIsAllowed() throws {
        var c = armedConfig()
        try c.addDayException(exception(5, 5, .quietAllDay), now: now, calendar: cal)
        XCTAssertEqual(c.dayExceptions.count, 1)
    }

    /// Monday like Sunday (all quiet) tightens; Monday like Saturday (9–12 open) loosens.
    func test_likeWeekdayTodayIsAllowedOnlyWhenItTightens() throws {
        var c = armedConfig()
        try c.addDayException(exception(5, 5, .likeWeekday(0)), now: now, calendar: cal)
        var d = armedConfig()
        XCTAssertThrowsError(try d.addDayException(exception(5, 5, .likeWeekday(6)), now: now, calendar: cal))
    }

    func test_pastStartIsRefused() {
        var c = armedConfig()
        XCTAssertThrowsError(try c.addDayException(exception(4, 6, .quietAllDay), now: now, calendar: cal)) {
            XCTAssertEqual($0 as? PaperweightConfig.ExceptionError, .loosensToday)
        }
    }

    func test_endBeforeStartIsRefused() {
        var c = armedConfig()
        XCTAssertThrowsError(try c.addDayException(exception(8, 6, .quietAllDay), now: now, calendar: cal)) {
            XCTAssertEqual($0 as? PaperweightConfig.ExceptionError, .endsBeforeStart)
        }
    }

    func test_overlapIsRefusedAndNamesTheOther() throws {
        var c = armedConfig()
        let existing = exception(7, 9, .openAllDay)
        try c.addDayException(existing, now: now, calendar: cal)
        XCTAssertThrowsError(try c.addDayException(exception(9, 10, .quietAllDay), now: now, calendar: cal)) {
            XCTAssertEqual($0 as? PaperweightConfig.ExceptionError, .overlaps(existing))
        }
    }

    func test_addTrimsAndCapsTheNote() throws {
        var c = armedConfig()
        var e = exception(6, 6, .openAllDay)
        e.note = "  " + String(repeating: "x", count: 60) + "  "
        try c.addDayException(e, now: now, calendar: cal)
        XCTAssertEqual(c.dayExceptions[0].note.count, 40)
    }

    func test_addKeepsTheListSortedByFirstDay() throws {
        var c = armedConfig()
        try c.addDayException(exception(9, 9, .openAllDay), now: now, calendar: cal)
        try c.addDayException(exception(6, 6, .openAllDay), now: now, calendar: cal)
        XCTAssertEqual(c.dayExceptions.map(\.firstDay), [key(6), key(9)])
    }

    // MARK: Removing

    func test_removingATodayTighteningThatHidesAnOpenWindowTruncates() throws {
        var c = armedConfig()
        let e = exception(5, 5, .likeWeekday(0))   // today, tightening — allowed
        try c.addDayException(e, now: now, calendar: cal)
        // Removing it would restore this evening's open window: a loosening, so it ends tonight.
        XCTAssertEqual(c.removeDayException(id: e.id, now: now, calendar: cal), .truncatedToToday)
        XCTAssertEqual(c.dayExceptions[0].lastDay, key(5))
    }

    func test_removingAnUpcomingDayOffDeletesIt() throws {
        var c = armedConfig()
        let e = exception(6, 6, .openAllDay)
        try c.addDayException(e, now: now, calendar: cal)
        XCTAssertEqual(c.removeDayException(id: e.id, now: now, calendar: cal), .removed)
        XCTAssertTrue(c.dayExceptions.isEmpty)
    }

    func test_removingTodaysQuietDayEndsTonight() throws {
        var c = armedConfig()
        let e = exception(5, 8, .quietAllDay)
        try c.addDayException(e, now: now, calendar: cal)
        XCTAssertEqual(c.removeDayException(id: e.id, now: now, calendar: cal), .truncatedToToday)
        XCTAssertEqual(c.dayExceptions[0].firstDay, key(5))
        XCTAssertEqual(c.dayExceptions[0].lastDay, key(5))
    }

    /// A quiet Sunday-through-Wednesday started yesterday; removing it on Monday
    /// keeps Sunday and Monday, drops Tuesday and Wednesday.
    func test_removingARunningQuietRangeTruncatesToToday() throws {
        var c = armedConfig()
        c.dayExceptions = [exception(4, 7, .quietAllDay)]
        XCTAssertEqual(c.removeDayException(id: c.dayExceptions[0].id, now: now, calendar: cal), .truncatedToToday)
        XCTAssertEqual(c.dayExceptions[0].lastDay, key(5))
    }

    /// Today is a quiet Sunday-pattern day, and Sunday is all quiet anyway — the
    /// weekly grid has no open slot the exception hides, so removal is immediate.
    func test_removingATodayExceptionThatHidesNothingIsImmediate() throws {
        var c = armedConfig()
        c.schedule = PaperweightSchedule()                       // whole week quiet
        c.dayExceptions = [exception(5, 5, .quietAllDay)]
        XCTAssertEqual(c.removeDayException(id: c.dayExceptions[0].id, now: now, calendar: cal), .removed)
    }

    func test_removingUnknownIDIsNotFound() {
        var c = armedConfig()
        XCTAssertEqual(c.removeDayException(id: UUID(), now: now, calendar: cal), .notFound)
    }

    // MARK: Pruning and listing

    func test_pruneDropsPastKeepsTodayAndLater() {
        var c = armedConfig()
        c.dayExceptions = [exception(1, 4, .openAllDay), exception(3, 5, .quietAllDay), exception(9, 9, .openAllDay)]
        XCTAssertTrue(c.pruneDayExceptions(now: now, calendar: cal))
        XCTAssertEqual(c.dayExceptions.map(\.firstDay), [key(3), key(9)])
        XCTAssertFalse(c.pruneDayExceptions(now: now, calendar: cal), "nothing left to drop")
    }

    func test_upcomingIsSortedAndExcludesPast() {
        var c = armedConfig()
        c.dayExceptions = [exception(9, 9, .openAllDay), exception(1, 2, .openAllDay), exception(5, 5, .quietAllDay)]
        XCTAssertEqual(c.upcomingDayExceptions(now: now, calendar: cal).map(\.firstDay), [key(5), key(9)])
    }
}
```

Add to `ConfigStoreTests.swift` (its `setUp` already gives every test an isolated `store`):

```swift
    func test_loadPrunesPastDayExceptions() throws {
        var config = PaperweightConfig()
        let created = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let past = DayException(firstDay: DayKey(year: 2000, month: 1, day: 1),
                                lastDay: DayKey(year: 2000, month: 1, day: 2),
                                treatment: .openAllDay, createdAt: created)
        let future = DayException(firstDay: DayKey(year: 2999, month: 1, day: 1),
                                  lastDay: DayKey(year: 2999, month: 1, day: 1),
                                  treatment: .openAllDay, createdAt: created)
        config.dayExceptions = [past, future]
        try store.save(config)

        XCTAssertEqual(store.load().dayExceptions, [future])
        XCTAssertEqual(store.load().dayExceptions, [future], "pruned on the first load, stable after")
    }
```

- [ ] **Step 2: Run to verify it fails**

Run: `xcodegen generate && <test command> -only-testing:PaperweightTests/DayExceptionRuleTests -only-testing:PaperweightTests/ConfigStoreTests`
Expected: compile errors for `addDayException` etc.

- [ ] **Step 3: Implement the rule**

```swift
// Shared/Models/DayException+Rule.swift
import Foundation

extension PaperweightConfig {

    var resolver: ScheduleResolver { resolver(calendar: .current) }

    func resolver(calendar: Calendar) -> ScheduleResolver {
        ScheduleResolver(schedule: schedule, exceptions: dayExceptions, calendar: calendar)
    }

    enum ExceptionError: Error, Equatable {
        case overlaps(DayException)
        case loosensToday
        case endsBeforeStart
    }

    enum ExceptionRemoval: Equatable {
        case removed, truncatedToToday, notFound
    }

    static let dayExceptionNoteLimit = 40

    /// Whether `treatment` on `day` would open any half-hour that is quiet under
    /// the schedule in force that day — exceptions included. Pure; the add
    /// sheet uses it to grey out today.
    func exceptionLoosens(_ treatment: DayException.Treatment, on day: DayKey,
                          calendar: Calendar = .current) -> Bool {
        let r = resolver(calendar: calendar)
        let current = r.openSlots(on: day)
        let proposed = r.openSlots(for: treatment, weekday: day.weekdayIndex(calendar: calendar))
        return !proposed.isSubset(of: current)
    }

    /// Adds an exception under the deferral rule, or throws.
    ///
    /// Tightening may start today. Loosening may not start before tomorrow —
    /// the same "sleep on it" boundary as a schedule edit. A start in the past
    /// is refused as `loosensToday` too: there is no separate message worth
    /// having for it.
    mutating func addDayException(_ exception: DayException, now: Date = Date(),
                                  calendar: Calendar = .current) throws {
        guard exception.firstDay <= exception.lastDay else { throw ExceptionError.endsBeforeStart }
        if let other = dayExceptions.first(where: { $0.overlaps(exception) }) {
            throw ExceptionError.overlaps(other)
        }
        let today = DayKey(now, calendar: calendar)
        if exception.firstDay < today { throw ExceptionError.loosensToday }
        if exception.firstDay == today,
           exceptionLoosens(exception.treatment, on: today, calendar: calendar) {
            throw ExceptionError.loosensToday
        }

        var e = exception
        e.note = String(e.note.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.dayExceptionNoteLimit))
        dayExceptions.append(e)
        dayExceptions.sort { $0.firstDay < $1.firstDay }
    }

    /// Removes an exception under the deferral rule. If removing it would open
    /// any half-hour today, it is truncated to end today instead — a quiet day
    /// "ends tonight" rather than at once.
    @discardableResult
    mutating func removeDayException(id: UUID, now: Date = Date(),
                                     calendar: Calendar = .current) -> ExceptionRemoval {
        guard let index = dayExceptions.firstIndex(where: { $0.id == id }) else { return .notFound }
        let today = DayKey(now, calendar: calendar)
        let exception = dayExceptions[index]

        if exception.covers(today) {
            let withIt = resolver(calendar: calendar).openSlots(on: today)
            let without = ScheduleResolver(schedule: schedule,
                                           exceptions: dayExceptions.filter { $0.id != id },
                                           calendar: calendar).openSlots(on: today)
            if !without.isSubset(of: withIt) {
                dayExceptions[index].lastDay = today
                return .truncatedToToday
            }
        }
        dayExceptions.remove(at: index)
        return .removed
    }

    /// Drops exceptions that ended before today. Returns whether anything changed.
    @discardableResult
    mutating func pruneDayExceptions(now: Date = Date(), calendar: Calendar = .current) -> Bool {
        let today = DayKey(now, calendar: calendar)
        let before = dayExceptions.count
        dayExceptions.removeAll { $0.lastDay < today }
        return dayExceptions.count != before
    }

    /// Exceptions that are today or later, soonest first.
    func upcomingDayExceptions(now: Date = Date(), calendar: Calendar = .current) -> [DayException] {
        let today = DayKey(now, calendar: calendar)
        return dayExceptions.filter { $0.lastDay >= today }.sorted { $0.firstDay < $1.firstDay }
    }
}
```

Then in `Shared/Store/ConfigStore.swift`, replace the body of `load()` after the decode guard:

```swift
        var promoted = config
        promoted.promotePendingScheduleIfDue()
        // Only a due promotion clears pendingSchedule here, so this also tells
        // us whether anything actually changed and needs persisting.
        var changed = config.pendingSchedule != nil && promoted.pendingSchedule == nil
        if promoted.pruneDayExceptions() { changed = true }
        if changed {
            // A failure to persist must not prevent returning the promoted,
            // pruned config — worst case it's recomputed on the next load.
            try? save(promoted)
        }
        return promoted
```

- [ ] **Step 4: Run to verify it passes**

Run: `<test command> -only-testing:PaperweightTests/DayExceptionRuleTests -only-testing:PaperweightTests/ConfigStoreTests`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add Shared/Models/DayException+Rule.swift Shared/Store/ConfigStore.swift PaperweightTests/Models/DayExceptionRuleTests.swift PaperweightTests/Models/ConfigStoreTests.swift
git commit -m "feat: add, remove and prune day exceptions under the deferral rule"
```

---

### Task 5: Enforcement — resolver at every shield decision, midnight heartbeat, view-model methods

**Files:**
- Modify: `PaperweightMonitor/PaperweightMonitor.swift` (the schedule branch of `syncShield`)
- Modify: `Shared/ViewModels/HomeViewModel.swift` (`syncRestrictions` + two new methods)
- Modify: `Shared/Services/UnlockService.swift` (`syncRestrictions`)
- Modify: `Shared/Services/ScheduleService.swift` (`heartbeatHours`)
- Test: additions to `PaperweightTests/Services/HomeViewModelTests.swift`, `PaperweightTests/Services/UnlockServiceTests.swift`, `PaperweightTests/Services/ScheduleServiceTests.swift`

**Interfaces:**
- Consumes: `PaperweightConfig.resolver`, `addDayException`, `removeDayException`, `ExceptionRemoval`.
- Produces on `HomeViewModel`: `func addDayException(_ e: DayException) throws`, `@discardableResult func removeDayException(id: UUID) -> PaperweightConfig.ExceptionRemoval`. `ScheduleService.heartbeatHours == [0, 6, 12, 18]`.

- [ ] **Step 1: Write the failing tests**

Add to `HomeViewModelTests.swift`:

```swift
    /// An open-all-day exception over an all-quiet week must lift the shield —
    /// the old `!schedule.isEmpty` guard would have kept it applied.
    @MainActor
    func test_syncRestrictions_liftsForADayOffOverAnEmptySchedule() throws {
        familyService.isAuthorized = true
        var config = PaperweightConfig()
        config.isEnabled = true
        config.schedule = PaperweightSchedule()
        config.dayExceptions = [DayException(firstDay: .today(), lastDay: .today(), treatment: .openAllDay)]
        try configStore.save(config)
        let shield = MockManagedSettingsStore()
        let vm = HomeViewModel(configStore: configStore, familyService: familyService,
                               restrictionService: RestrictionService(store: shield), widgetStore: widgetStore)

        vm.syncRestrictions()

        XCTAssertTrue(shield.shieldWasCleared)
        XCTAssertFalse(shield.shieldApplicationsWasSet)
    }

    @MainActor
    func test_addDayException_persistsAndResyncs() throws {
        familyService.isAuthorized = true
        var config = PaperweightConfig()
        config.isEnabled = true
        try configStore.save(config)
        let shield = MockManagedSettingsStore()
        let vm = HomeViewModel(configStore: configStore, familyService: familyService,
                               restrictionService: RestrictionService(store: shield), widgetStore: widgetStore)

        let tomorrow = DayKey.today().next()
        try vm.addDayException(DayException(firstDay: tomorrow, lastDay: tomorrow, treatment: .openAllDay))

        XCTAssertEqual(configStore.load().dayExceptions.count, 1)
        XCTAssertTrue(shield.shieldApplicationsWasSet || shield.shieldWasCleared, "the shield was re-evaluated")
    }

    @MainActor
    func test_removeDayException_persistsTheResult() throws {
        familyService.isAuthorized = true
        var config = PaperweightConfig()
        config.isEnabled = true
        let tomorrow = DayKey.today().next()
        let e = DayException(firstDay: tomorrow, lastDay: tomorrow, treatment: .openAllDay)
        config.dayExceptions = [e]
        try configStore.save(config)
        let vm = HomeViewModel(configStore: configStore, familyService: familyService,
                               restrictionService: restrictionService, widgetStore: widgetStore)

        XCTAssertEqual(vm.removeDayException(id: e.id), .removed)
        XCTAssertTrue(configStore.load().dayExceptions.isEmpty)
    }
```

Add to `UnlockServiceTests.swift`:

```swift
    /// After a relock, the shield follows the resolver: a day off keeps it lifted.
    @MainActor
    func test_relock_keepsTheShieldLiftedOnADayOff() throws {
        var config = PaperweightConfig()
        config.isEnabled = true
        config.dayExceptions = [DayException(firstDay: .today(), lastDay: .today(), treatment: .openAllDay)]
        try configStore.save(config)
        let shield = MockManagedSettingsStore()
        let service = UnlockService(configStore: configStore, nfcService: nfcService,
                                    restrictionService: RestrictionService(store: shield),
                                    widgetStore: widgetStore, scheduleService: scheduleService)

        service.relock()

        XCTAssertFalse(shield.shieldApplicationsWasSet)
    }
```

In `ScheduleServiceTests.swift`, change `test_registersAHeartbeatSeveralTimesADay`'s last assertion to:

```swift
        XCTAssertTrue(hours.contains(0), "a midnight heartbeat, so whole-day exceptions get their boundary")
        XCTAssertGreaterThanOrEqual(heartbeats.count, 4)
```

- [ ] **Step 2: Run to verify it fails**

Run: `<test command> -only-testing:PaperweightTests/HomeViewModelTests -only-testing:PaperweightTests/UnlockServiceTests -only-testing:PaperweightTests/ScheduleServiceTests`
Expected: compile errors for `vm.addDayException`; the heartbeat test fails on `hours.contains(0)`.

- [ ] **Step 3: Implement**

`Shared/Services/ScheduleService.swift` — replace the `heartbeatHours` declaration and its comment:

```swift
    /// Hours at which a heartbeat fires. DeviceActivity does drop boundary
    /// callbacks now and then, and a dropped one used to leave the wrong shield
    /// state for up to a day; four a day bounds that to six hours. Midnight is
    /// also the only boundary an open-all-day or quiet-all-day exception has.
    static let heartbeatHours = [0, 6, 12, 18]
```

`PaperweightMonitor/PaperweightMonitor.swift` — replace the schedule branch at the end of `syncShield()`:

```swift
        if config.resolver.isFree(at: now) {
            service.removeAll()
        } else {
            #if os(iOS)
            service.apply(selection: config.selection, overrides: config.appOverrides)
            #endif
        }
```

`Shared/ViewModels/HomeViewModel.swift` — in `syncRestrictions()`, replace the `if let schedule … else` block with:

```swift
        if config.resolver.isFree(at: Date()) {
            restrictionService.removeAll()
        } else {
            restrictionService.apply(selection: config.selection, overrides: config.appOverrides)
        }
```

and add, after `saveScheduleEdit`:

```swift
    /// Adds a planned day under the deferral rule (see `PaperweightConfig.addDayException`),
    /// then persists and re-evaluates the shield. Throws `PaperweightConfig.ExceptionError`.
    func addDayException(_ exception: DayException) throws {
        try config.addDayException(exception)
        try configStore.save(config)
        syncRestrictions()
    }

    /// Removes a planned day; a quiet day that is today ends tonight instead.
    @discardableResult
    func removeDayException(id: UUID) -> PaperweightConfig.ExceptionRemoval {
        let result = config.removeDayException(id: id)
        try? configStore.save(config)
        syncRestrictions()
        return result
    }
```

`Shared/Services/UnlockService.swift` — in its private `syncRestrictions()`, replace the `if let schedule … else` block with:

```swift
        if config.resolver.isFree(at: Date()) {
            restrictionService.removeAll()
        } else {
            restrictionService.apply(selection: config.selection, overrides: config.appOverrides)
        }
```

- [ ] **Step 4: Run the whole suite and build**

Run: `<test command>` then `<build command>`
Expected: all tests pass; `BUILD SUCCEEDED`.

- [ ] **Step 5: Commit**

```bash
git add PaperweightMonitor/PaperweightMonitor.swift Shared/ViewModels/HomeViewModel.swift Shared/Services/UnlockService.swift Shared/Services/ScheduleService.swift PaperweightTests/Services
git commit -m "feat: enforce day exceptions at every shield decision; heartbeat at midnight"
```

---

### Task 6: Widget — state, boundary, ribbon

**Files:**
- Modify: `Shared/Models/WidgetSnapshot.swift` (`resolver(calendar:)`, `state(at:)`, `nextBoundary(at:)`)
- Modify: `PaperweightWidget/PaperweightProvider.swift` (`PaperweightEntry.resolver`)
- Modify: `PaperweightWidget/PaperweightWidgetViews.swift` (`RibbonWidgetView`, `DayRibbon`)
- Modify: `project.yml` (widget sources)
- Test: additions to `PaperweightTests/Models/WidgetSnapshotTests.swift`

**Interfaces:**
- Consumes: `ScheduleResolver`, `WidgetSnapshot.dayExceptions`.
- Produces: `WidgetSnapshot.resolver(calendar:) -> ScheduleResolver`; `PaperweightEntry.resolver: ScheduleResolver?` replaces `PaperweightEntry.schedule`; `DayRibbon(openSlots:date:)` replaces `DayRibbon(schedule:day:date:)`.

- [ ] **Step 1: Write the failing tests**

Add to `WidgetSnapshotTests.swift` (uses the file's existing `reference` = Sunday 2026-01-04 14:00 and `readySnapshot(schedule:)`):

```swift
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
```

- [ ] **Step 2: Run to verify it fails**

Run: `<test command> -only-testing:PaperweightTests/WidgetSnapshotTests`
Expected: the first test fails (state is `.freeWindow` because the weekly schedule is read directly); the second fails with `.quietOpen`.

- [ ] **Step 3: Implement in `WidgetSnapshot.swift`**

Add inside the `// MARK: - State` extension, before `state(at:)`:

```swift
    func resolver(calendar: Calendar = .current) -> ScheduleResolver {
        ScheduleResolver(schedule: schedule, exceptions: dayExceptions, calendar: calendar)
    }
```

Replace the tail of `state(at:)` from `guard let schedule, !schedule.isEmpty else { return .quietOpen }` to the end of the function with:

```swift
        let resolver = resolver(calendar: calendar)
        if let free = resolver.freeStatus(at: date) {
            return .freeWindow(ends: free.ends, fraction: free.elapsedFraction)
        }
        if resolver.isFree(at: date) {
            // Open with no boundary ahead (always open).
            return .off
        }
        if let quiet = resolver.quietStatus(at: date) {
            return .quietBounded(ends: quiet.ends, fraction: quiet.remainingFraction)
        }
        return .quietOpen
```

Replace the `if let schedule, !schedule.isEmpty { … }` block in `nextBoundary(at:)` with:

```swift
        let resolver = resolver(calendar: calendar)
        if let quiet = resolver.quietStatus(at: date) { candidates.append(quiet.ends) }
        if let free = resolver.freeStatus(at: date) { candidates.append(free.ends) }
```

- [ ] **Step 4: Run to verify it passes**

Run: `<test command> -only-testing:PaperweightTests/WidgetSnapshotTests`
Expected: all pass (including the pre-existing precedence tests, whose `readySnapshot()` with no schedule now resolves to `.quietOpen` through the resolver just as before).

- [ ] **Step 5: Wire the widget target**

`project.yml` — in the `PaperweightWidget` target's `sources`, after `- path: Shared/Models/PaperweightSchedule.swift`, add:

```yaml
      - path: Shared/Models/PaperweightSchedule+Week.swift
      - path: Shared/Models/DayKey.swift
      - path: Shared/Models/DayException.swift
      - path: Shared/Models/ScheduleResolver.swift
```

`PaperweightWidget/PaperweightProvider.swift` — replace the `schedule` property and its comment on `PaperweightEntry` with:

```swift
    /// Carried on the entry rather than re-read at render time, so the medium
    /// ribbon draws the same week the state was derived from.
    let resolver: ScheduleResolver?
```

update `preview(at:)`:

```swift
        PaperweightEntry(
            date: date,
            state: .quietBounded(ends: date.addingTimeInterval(2.5 * 3600), fraction: 0.72),
            resolver: ScheduleResolver(schedule: .weekdayEvenings(), exceptions: []))
```

and `entry(at:from:)`:

```swift
        PaperweightEntry(date: date,
                         state: snapshot?.state(at: date) ?? .unwritten,
                         resolver: snapshot?.resolver())
```

`PaperweightWidget/PaperweightWidgetViews.swift` — in `RibbonWidgetView`, replace the `schedule` computed property, `body`, and the `ribbon(_:)` signature/first line:

```swift
    /// Today's open half-hours, or nil when there is nothing to draw: dormant
    /// states, or no schedule and no exception covering today. Dormant states
    /// get a wide version of the small layout instead of a strip of empty cells.
    private var todaySlots: Set<Int>? {
        guard !state.isDormant, let resolver = entry.resolver else { return nil }
        let today = DayKey(entry.date)
        let hasWeekly = !(resolver.schedule?.isEmpty ?? true)
        guard hasWeekly || resolver.exception(on: today) != nil else { return nil }
        return resolver.openSlots(on: today)
    }

    var body: some View {
        if let todaySlots {
            ribbon(openSlots: todaySlots)
        } else {
            dormant
        }
    }

    private func ribbon(openSlots: Set<Int>) -> some View {
        return VStack(alignment: .leading, spacing: 0) {
```

(delete the old `let day = …` line) and change the `DayRibbon` call to:

```swift
            DayRibbon(openSlots: openSlots, date: entry.date)
                .frame(height: 14)
```

Replace `DayRibbon`'s stored properties and the cell fill:

```swift
struct DayRibbon: View {
    let openSlots: Set<Int>
    let date: Date
```

```swift
                            .fill(openSlots.contains(half)
                                  ? PW.moss.opacity(0.55) : PW.deepForest)
```

- [ ] **Step 6: Build**

Run: `xcodegen generate && <build command>`
Expected: `BUILD SUCCEEDED`. If the widget target reports `cannot find 'DaySegment'`, the `PaperweightSchedule+Week.swift` line in `project.yml` is missing.

- [ ] **Step 7: Commit**

```bash
git add Shared/Models/WidgetSnapshot.swift PaperweightWidget project.yml PaperweightTests/Models/WidgetSnapshotTests.swift
git commit -m "feat: widget state, boundary and ribbon follow day exceptions"
```

---

### Task 7: Labels, the week-strip marker, and the two entry rows

**Files:**
- Create: `Shared/Models/DayException+Labels.swift`
- Modify: `Paperweight/Views/Components/WeekStrip.swift`
- Modify: `Paperweight/Views/HomeView.swift:250-266` (strip + card)
- Modify: `Paperweight/Views/SettingsView.swift:34-41` (row)
- Test: `PaperweightTests/Models/DayExceptionLabelTests.swift`

**Interfaces:**
- Consumes: `DayException`, `DayKey`, `ScheduleResolver`, `PaperweightConfig.upcomingDayExceptions`.
- Produces: `DayException.Treatment.title: String` ("Open all day" / "Quiet all day" / "Like Saturday"), `DayException.dateLabel(calendar:locale:) -> String` ("Fri, Sep 18" / "Mon, Sep 21 – Fri, Sep 25"), `DayException.shortDateLabel(now:calendar:locale:) -> String` ("Fri" within the next 6 days, else "Sep 18"; ranges "Sep 21–25" or "Sep 28 – Oct 2"), `PaperweightConfig.dayExceptionsRowValue(now:calendar:locale:) -> String?`. `WeekStrip(resolver:week:)`. A placeholder `DayExceptionsView(vm:)` so the rows compile (Task 8 fills it in).

- [ ] **Step 1: Write the failing tests**

```swift
// PaperweightTests/Models/DayExceptionLabelTests.swift
import XCTest

final class DayExceptionLabelTests: XCTestCase {

    private let cal = Calendar.current
    private let us = Locale(identifier: "en_US")
    private func key(_ m: Int, _ d: Int) -> DayKey { DayKey(year: 2026, month: m, day: d) }
    /// Saturday 2026-09-12 10:00.
    private var now: Date { cal.date(from: DateComponents(year: 2026, month: 9, day: 12, hour: 10))! }

    func test_treatmentTitles() {
        XCTAssertEqual(DayException.Treatment.openAllDay.title, "Open all day")
        XCTAssertEqual(DayException.Treatment.quietAllDay.title, "Quiet all day")
        XCTAssertEqual(DayException.Treatment.likeWeekday(6).title, "Like Saturday")
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
```

- [ ] **Step 2: Run to verify it fails**

Run: `xcodegen generate && <test command> -only-testing:PaperweightTests/DayExceptionLabelTests`
Expected: compile errors (`title`, `dateLabel`…).

- [ ] **Step 3: Implement the labels**

```swift
// Shared/Models/DayException+Labels.swift
import Foundation

extension DayException.Treatment {
    /// The pill text. Sentence case; the word is "quiet", never "blocked".
    var title: String {
        switch self {
        case .openAllDay: return "Open all day"
        case .quietAllDay: return "Quiet all day"
        case .likeWeekday(let w):
            return "Like \(DayException.weekdayNames[((w % 7) + 7) % 7])"
        }
    }
}

extension DayException {
    static let weekdayNames = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]

    /// "Fri, Sep 18" or "Mon, Sep 21 – Fri, Sep 25".
    func dateLabel(calendar: Calendar = .current, locale: Locale = .current) -> String {
        let style = Date.FormatStyle(locale: locale, calendar: calendar).weekday(.abbreviated).month(.abbreviated).day()
        let first = firstDay.date(calendar: calendar).formatted(style)
        guard firstDay != lastDay else { return first }
        return "\(first) – \(lastDay.date(calendar: calendar).formatted(style))"
    }

    /// Compact form for the Home row value: a bare weekday when the day is
    /// within the next six days ("Fri"), otherwise "Sep 18"; ranges as
    /// "Sep 21–25" or "Sep 28 – Oct 2".
    func shortDateLabel(now: Date = Date(), calendar: Calendar = .current, locale: Locale = .current) -> String {
        let monthDay = Date.FormatStyle(locale: locale, calendar: calendar).month(.abbreviated).day()
        let firstDate = firstDay.date(calendar: calendar)
        if firstDay == lastDay {
            let today = DayKey(now, calendar: calendar)
            let days = calendar.dateComponents([.day], from: today.date(calendar: calendar), to: firstDate).day ?? 7
            if (0...6).contains(days) {
                return firstDate.formatted(Date.FormatStyle(locale: locale, calendar: calendar).weekday(.abbreviated))
            }
            return firstDate.formatted(monthDay)
        }
        let lastDate = lastDay.date(calendar: calendar)
        if firstDay.month == lastDay.month && firstDay.year == lastDay.year {
            return "\(firstDate.formatted(monthDay))–\(lastDay.day)"
        }
        return "\(firstDate.formatted(monthDay)) – \(lastDate.formatted(monthDay))"
    }
}

extension PaperweightConfig {
    /// The Home row's trailing value: the next planned day and how many are
    /// upcoming, or nil when there are none.
    func dayExceptionsRowValue(now: Date = Date(), calendar: Calendar = .current,
                               locale: Locale = .current) -> String? {
        let upcoming = upcomingDayExceptions(now: now, calendar: calendar)
        guard let next = upcoming.first else { return nil }
        return "\(next.shortDateLabel(now: now, calendar: calendar, locale: locale)) · \(upcoming.count) upcoming"
    }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `<test command> -only-testing:PaperweightTests/DayExceptionLabelTests`
Expected: all pass. If `dateLabel` comes back as "Fri, Sep 18" with a different separator on your locale data, the test locale is `en_US` on purpose; do not loosen the assertion.

- [ ] **Step 5: The week strip**

Replace `Paperweight/Views/Components/WeekStrip.swift` in full:

```swift
import SwiftUI

/// Screen 02's "This week": one row per day, each a proportional bar of quiet
/// (moss) and open (faint) runs, drawn for the actual calendar week so a
/// planned day shows as it will really be. A day with nothing quiet reads as a
/// dashed outline rather than an empty bar, so "no lock at all" can't be
/// mistaken for a rendering failure. A planned day gets a sage dot after its
/// name — the bar already says *what*, the dot says *why*.
struct WeekStrip: View {
    let resolver: ScheduleResolver
    /// Sunday through Saturday; see `DayKey.week(containing:)`.
    let week: [DayKey]

    private static let dayNames = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
    private static let barHeight: CGFloat = 15

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("This week").pwScreenLabel()

            VStack(spacing: 6) {
                ForEach(Array(week.enumerated()), id: \.offset) { index, day in
                    HStack(spacing: 8) {
                        HStack(spacing: 4) {
                            Text(Self.dayNames[index])
                                .font(.grotesk(13, weight: .semibold))
                                .foregroundStyle(PW.textMuted)
                            if resolver.exception(on: day) != nil {
                                Circle().fill(PW.sage).frame(width: 6, height: 6)
                            }
                        }
                        .frame(width: 44, alignment: .leading)
                        row(day: day)
                    }
                }
            }

            HStack(spacing: 12) {
                legend(color: PW.moss, label: "Locked — quiet")
                legend(color: nil, label: "Open")
                HStack(spacing: 6) {
                    Circle().fill(PW.sage).frame(width: 6, height: 6)
                    Text("Planned").font(.grotesk(13)).foregroundStyle(PW.textMuted)
                }
            }
        }
    }

    @ViewBuilder
    private func row(day: DayKey) -> some View {
        if resolver.isOpenAllDay(on: day) {
            Text("OPEN ALL DAY")
                .font(.grotesk(13, weight: .medium))
                .tracking(0.8)
                .foregroundStyle(PW.textLabel)
                .frame(maxWidth: .infinity)
                .frame(height: Self.barHeight)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(Color.white.opacity(0.18),
                                      style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                )
        } else {
            GeometryReader { geo in
                HStack(spacing: 0) {
                    ForEach(Array(resolver.daySegments(on: day).enumerated()), id: \.offset) { _, segment in
                        Rectangle()
                            .fill(segment.isLocked ? PW.moss : Color.white.opacity(0.04))
                            .frame(width: max(0, geo.size.width * segment.fraction))
                    }
                }
            }
            .frame(height: Self.barHeight)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            )
        }
    }

    private func legend(color: Color?, label: String) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 3)
                .fill(color ?? Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(color == nil ? Color.white.opacity(0.16) : .clear, lineWidth: 1)
                )
                .frame(width: 10, height: 10)
            Text(label)
                .font(.grotesk(13))
                .foregroundStyle(PW.textMuted)
        }
    }
}
```

- [ ] **Step 6: Home and Settings rows, plus a placeholder list screen**

Create `Paperweight/Views/DayExceptionsView.swift` as a stub so the rows compile (Task 8 replaces it in full):

```swift
import SwiftUI

struct DayExceptionsView: View {
    @ObservedObject var vm: HomeViewModel
    var body: some View {
        Text("Nothing planned.").pwScreen()
            .navigationTitle("Days off & quiet days")
            .navigationBarTitleDisplayMode(.inline)
    }
}
```

`Paperweight/Views/HomeView.swift` — in `openState`, replace the strip guard and the `GroupedCard`:

```swift
                    if !(vm.config.schedule?.isEmpty ?? true) || !vm.config.dayExceptions.isEmpty {
                        WeekStrip(resolver: vm.config.resolver, week: DayKey.week(containing: .today()))
                            .padding(.top, 20)
                    }

                    GroupedCard {
                        Button { showingPicker = true } label: {
                            NavRow(title: "Restricted apps",
                                   systemImage: "lock",
                                   iconColor: PW.textMuted,
                                   value: restrictedCountText)
                        }
                        .buttonStyle(.plain)
                        CardDivider()
                        NavigationLink { DayExceptionsView(vm: vm) } label: {
                            NavRow(title: "Days off & quiet days",
                                   systemImage: "calendar",
                                   iconColor: PW.textMuted,
                                   value: vm.config.dayExceptionsRowValue())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.top, 18)
```

`Paperweight/Views/SettingsView.swift` — between the Schedule and NFC rows:

```swift
                    CardDivider()
                    NavigationLink { DayExceptionsView(vm: vm) } label: {
                        NavRow(title: "Days off & quiet days", value: vm.config.dayExceptionsRowValue())
                    }
```

- [ ] **Step 7: Build and run the suite**

Run: `xcodegen generate && <build command> && <test command>`
Expected: `BUILD SUCCEEDED`; all tests pass. If `HomeView` is not inside a `NavigationStack` at the point of the `NavigationLink` (check for `NavigationStack {` near the top of `HomeView.body`), the link renders but does nothing — Settings uses the same pattern, so match wherever Settings' links resolve.

- [ ] **Step 8: Commit**

```bash
git add Shared/Models/DayException+Labels.swift Paperweight/Views/Components/WeekStrip.swift Paperweight/Views/HomeView.swift Paperweight/Views/SettingsView.swift Paperweight/Views/DayExceptionsView.swift PaperweightTests/Models/DayExceptionLabelTests.swift
git commit -m "feat: planned-day marker on the week strip and the entry rows"
```

---

### Task 8: `DayExceptionsView` — the list

**Files:**
- Modify (replace in full): `Paperweight/Views/DayExceptionsView.swift`

**Interfaces:**
- Consumes: `HomeViewModel.removeDayException(id:)`, `PaperweightConfig.upcomingDayExceptions`, `DayException.dateLabel`, `Treatment.title`, `DayException.dayCount`.
- Produces: `DayExceptionsView(vm:)`; presents `AddDayExceptionSheet(vm:editing:)` (Task 9) — for this task, stub the sheet as shown in Step 2 so it compiles.

This task has no unit test: it is SwiftUI glue over already-tested model calls. Verification is the build plus the on-device checklist at the end of the plan.

- [ ] **Step 1: Write the view**

```swift
// Paperweight/Views/DayExceptionsView.swift
import SwiftUI

/// Planned days off and quiet days. A `List` rather than a `GroupedCard` so
/// swipe-to-remove comes for free; styled to sit with the grouped cards.
struct DayExceptionsView: View {
    @ObservedObject var vm: HomeViewModel
    @State private var editing: DayException?
    @State private var adding = false

    private var today: DayKey { .today() }
    private var upcoming: [DayException] { vm.config.upcomingDayExceptions() }
    private var current: DayException? { upcoming.first { $0.covers(today) } }
    private var later: [DayException] { upcoming.filter { !$0.covers(today) } }

    var body: some View {
        List {
            if let current {
                section("Today") { row(current) }
            }
            section("Upcoming") {
                if later.isEmpty && current == nil {
                    empty
                } else if later.isEmpty {
                    Text("Nothing more planned.")
                        .font(.grotesk(13)).foregroundStyle(PW.textMuted)
                        .listRowBackground(PW.surface)
                } else {
                    ForEach(later) { row($0) }
                }
            }
            Section {
                VStack(spacing: 2) {
                    Text("A day off has to be set the day before.")
                    Text("A quiet day can start right now.")
                }
                .font(.grotesk(13)).foregroundStyle(PW.textFaint)
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .pwScreen()
        .safeAreaInset(edge: .bottom) {
            AccentButton(title: "Add a day") { adding = true }
                .padding(.horizontal, 20).padding(.bottom, 12)
                .background(PW.black.opacity(0.9))
        }
        .navigationTitle("Days off & quiet days")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { adding = true } label: {
                    Image(systemName: "plus").foregroundStyle(PW.sage)
                }
            }
        }
        .sheet(isPresented: $adding) {
            AddDayExceptionSheet(vm: vm, editing: nil)
                .presentationDragIndicator(.visible)
        }
        .sheet(item: $editing) { e in
            AddDayExceptionSheet(vm: vm, editing: e)
                .presentationDragIndicator(.visible)
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        Section {
            content()
        } header: {
            Text(title).pwScreenLabel()
        }
    }

    private var empty: some View {
        VStack(spacing: 6) {
            Text("Nothing planned.")
                .font(.spectral(16, italic: true)).foregroundStyle(PW.textPrimary)
            Text("Holidays, trips, exam days. Add one and the week bends around it.")
                .font(.grotesk(13)).foregroundStyle(PW.textMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .listRowBackground(PW.surface)
    }

    private func row(_ e: DayException) -> some View {
        Button { editing = e } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    Text(e.dateLabel())
                        .font(.grotesk(15)).foregroundStyle(PW.textPrimary)
                    Spacer(minLength: 8)
                    pill(e.treatment)
                }
                Text(secondLine(e))
                    .font(.grotesk(13)).foregroundStyle(PW.textMuted)
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .listRowBackground(PW.surface)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) { vm.removeDayException(id: e.id) } label: { Text("Remove") }
                .tint(PW.clay)
        }
    }

    private func secondLine(_ e: DayException) -> String {
        if e.covers(today), e.lastDay == today, e.treatment == .quietAllDay {
            return "Ends tonight · removing a quiet day lands tomorrow"
        }
        var parts: [String] = []
        if !e.note.isEmpty { parts.append(e.note) }
        if e.dayCount() > 1 { parts.append("\(e.dayCount()) days") }
        return parts.isEmpty ? " " : parts.joined(separator: " · ")
    }

    private func pill(_ t: DayException.Treatment) -> some View {
        let (fg, bg, border): (Color, Color, Color) = {
            switch t {
            case .openAllDay: return (PW.sage, .clear, PW.sage.opacity(0.5))
            case .quietAllDay: return (PW.moss, PW.moss.opacity(0.18), PW.moss.opacity(0.7))
            case .likeWeekday: return (PW.textMuted, .clear, Color.white.opacity(0.18))
            }
        }()
        return Text(t.title)
            .font(.grotesk(13))
            .foregroundStyle(fg)
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(bg)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(border, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
```

- [ ] **Step 2: Stub the sheet so the target builds**

Create `Paperweight/Views/AddDayExceptionSheet.swift` with a stub that Task 9 replaces:

```swift
import SwiftUI

struct AddDayExceptionSheet: View {
    @ObservedObject var vm: HomeViewModel
    let editing: DayException?
    var body: some View { Text("Add a day").pwScreen() }
}
```

- [ ] **Step 3: Build**

Run: `xcodegen generate && <build command>`
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 4: Commit**

```bash
git add Paperweight/Views/DayExceptionsView.swift Paperweight/Views/AddDayExceptionSheet.swift
git commit -m "feat: the days off & quiet days list"
```

---

### Task 9: `AddDayExceptionSheet` — add and edit

**Files:**
- Modify (replace in full): `Paperweight/Views/AddDayExceptionSheet.swift`

**Interfaces:**
- Consumes: `HomeViewModel.addDayException(_:)`, `removeDayException(id:)`, `PaperweightConfig.exceptionLoosens(_:on:)`, `ExceptionError`, `DayException.dateLabel`, `PWSegmented`, `DayKey`.
- Produces: `AddDayExceptionSheet(vm:editing:)`.

No unit test: SwiftUI glue over tested rules. The one piece of logic here — which dates the picker allows — is a direct call to `exceptionLoosens`.

- [ ] **Step 1: Write the sheet**

```swift
// Paperweight/Views/AddDayExceptionSheet.swift
import SwiftUI

/// One sheet for adding and editing. Treatment comes first because it decides
/// which dates are allowed: a loosening treatment cannot start today, so today
/// is left out of the picker's range and one line says why.
struct AddDayExceptionSheet: View {
    @ObservedObject var vm: HomeViewModel
    let editing: DayException?
    @Environment(\.dismiss) private var dismiss

    private enum Kind: Hashable { case open, quiet, like }
    private enum Field { case from, to }

    @State private var kind: Kind = .open
    @State private var weekday: Int = DayKey.today().weekdayIndex()
    @State private var from: DayKey = DayKey.today().next()
    @State private var to: DayKey? = nil
    @State private var note: String = ""
    @State private var field: Field = .from
    @State private var errorText: String?

    private static let weekdayShort = ["S", "M", "T", "W", "T", "F", "S"]
    private static let kinds: [(value: Kind, label: String)] = [
        (.open, "Open all day"), (.quiet, "Quiet all day"), (.like, "Like a weekday…")]
    private static let weekdays: [(value: Int, label: String)] = (0..<7).map { ($0, weekdayShort[$0]) }

    private var treatment: DayException.Treatment {
        switch kind {
        case .open: return .openAllDay
        case .quiet: return .quietAllDay
        case .like: return .likeWeekday(weekday)
        }
    }

    /// Whether today is off the table for the chosen treatment.
    private var todayLoosens: Bool {
        vm.config.exceptionLoosens(treatment, on: .today())
    }

    private var earliestStart: DayKey {
        todayLoosens ? DayKey.today().next() : DayKey.today()
    }

    private var pickerRange: ClosedRange<Date> {
        let lower = (field == .from ? earliestStart : from).date()
        return lower...Calendar.current.date(byAdding: .year, value: 2, to: lower)!
    }

    private var pickerSelection: Binding<Date> {
        Binding(
            get: { (field == .from ? from : (to ?? from)).date() },
            set: { picked in
                let key = DayKey(picked)
                if field == .from {
                    from = key
                    if let t = to, t < key { to = nil }
                } else {
                    to = key == from ? nil : key
                }
                errorText = nil
            })
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    PWSegmented(options: Self.kinds, selection: $kind)
                    if kind == .like {
                        PWSegmented(options: Self.weekdays, selection: $weekday)
                    }

                    GroupedCard {
                        fieldRow("From", value: from.date().formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()),
                                 active: field == .from) { field = .from }
                        CardDivider()
                        fieldRow("To", value: to.map { $0.date().formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()) } ?? "Same day",
                                 active: field == .to, muted: to == nil) { field = .to }
                        CardDivider()
                        HStack {
                            Text("Note").font(.grotesk(15)).foregroundStyle(PW.textPrimary)
                            Spacer(minLength: 12)
                            TextField("Optional", text: $note)
                                .font(.grotesk(15))
                                .multilineTextAlignment(.trailing)
                                .foregroundStyle(PW.textMuted)
                                .onChange(of: note) { _, new in
                                    if new.count > PaperweightConfig.dayExceptionNoteLimit {
                                        note = String(new.prefix(PaperweightConfig.dayExceptionNoteLimit))
                                    }
                                }
                        }
                        .padding(.horizontal, 16).padding(.vertical, 12)
                    }

                    DatePicker("", selection: pickerSelection, in: pickerRange, displayedComponents: .date)
                        .datePickerStyle(.graphical)
                        .tint(PW.sage)
                        .labelsHidden()

                    if todayLoosens {
                        Text("Opening up takes effect from tomorrow, so today isn't offered.")
                            .font(.grotesk(13)).foregroundStyle(PW.textFaint)
                            .frame(maxWidth: .infinity)
                    }
                    if let errorText {
                        Text(errorText)
                            .font(.grotesk(13)).foregroundStyle(PW.clay)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 24)
            }
            .pwScreen()
            .navigationTitle(editing == nil ? "Add a day" : "Edit day")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.foregroundStyle(PW.textMuted)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.foregroundStyle(PW.sage)
                }
            }
        }
        .tint(PW.sage)
        .onAppear(perform: seed)
        .onChange(of: kind) { _, _ in clampStart() }
        .onChange(of: weekday) { _, _ in clampStart() }
    }

    private func fieldRow(_ title: String, value: String, active: Bool, muted: Bool = false,
                          action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title).font(.grotesk(15)).foregroundStyle(PW.textPrimary)
                Spacer(minLength: 12)
                Text(value)
                    .font(.grotesk(15))
                    .foregroundStyle(muted ? PW.textMuted : PW.sage)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(active ? PW.sage.opacity(0.12) : .clear)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func seed() {
        guard let e = editing else { return }
        switch e.treatment {
        case .openAllDay: kind = .open
        case .quietAllDay: kind = .quiet
        case .likeWeekday(let w): kind = .like; weekday = w
        }
        from = max(e.firstDay, .today())
        to = e.lastDay == e.firstDay ? nil : e.lastDay
        note = e.note
    }

    /// If the treatment changed to one that cannot start today, move a
    /// today-start to tomorrow rather than leaving an unsaveable form.
    private func clampStart() {
        if from < earliestStart { from = earliestStart }
        errorText = nil
    }

    private func save() {
        let new = DayException(firstDay: from, lastDay: to ?? from, treatment: treatment, note: note)
        do {
            if let old = editing {
                vm.removeDayException(id: old.id)
            }
            try vm.addDayException(new)
            dismiss()
        } catch let error as PaperweightConfig.ExceptionError {
            switch error {
            case .overlaps(let other):
                errorText = "Overlaps \(other.dateLabel()). Remove that one first."
            case .loosensToday:
                errorText = "Opening up takes effect from tomorrow."
            case .endsBeforeStart:
                errorText = "The last day is before the first."
            }
        } catch {
            errorText = error.localizedDescription
        }
    }
}
```

- [ ] **Step 2: Build**

Run: `xcodegen generate && <build command>`
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 3: Run the whole suite one more time**

Run: `<test command>`
Expected: all tests pass; the count is at least 147 + the tests added in Tasks 1–7.

- [ ] **Step 4: Commit**

```bash
git add Paperweight/Views/AddDayExceptionSheet.swift
git commit -m "feat: add and edit a planned day"
```

---

### Task 10: Simulator walk-through and PR

**Files:** none new.

- [ ] **Step 1: Run the app on the simulator** (the `run` skill or `preview_start`) and, with a schedule set and Paperweight armed:
  - Home shows the "Days off & quiet days" row with no value.
  - Add a day off for tomorrow: the sheet greys out today; save; the row reads "Tomorrow's weekday · 1 upcoming"; the week strip shows that day as OPEN ALL DAY with a dot.
  - Add a quiet day for today: allowed; the strip's today row is all moss with a dot; the Home banner flips to Locked if it was open.
  - Remove today's quiet day: it moves to the Today section reading "Ends tonight…".
  - Edit the day off to a two-day range: list shows the range and "2 days".

- [ ] **Step 2: Open the PR** against `main` from `feat/day-exceptions` with the on-device checklist from the spec's §8 in the test plan (a day off starting tomorrow lifts the shield at 00:00; a quiet day added now applies at once; the widget's countdown crosses the day-off edge without opening the app). DeviceActivity does not run on the simulator, so those three are the real verification.
