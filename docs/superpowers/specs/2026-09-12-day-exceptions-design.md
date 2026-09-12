# Paperweight — Day exceptions ("Days off & quiet days")

**Date:** 2026-09-12
**Mockups:** `.superpowers/brainstorm/62262-1789235756/content/` (gitignored; decisions are
recorded in §7 so this spec stands on its own).
**Depends on:** PR #31 (`fix/enforcement-drift`) — the midnight boundary snap,
`ScheduleService.sync(config:)`, the heartbeat list, and `WidgetSnapshot.timelineDates`.
Implement on top of `main` once that PR is merged.

---

## 1. What this is

A weekly schedule cannot say "not this Friday". Today a company holiday is a day of being
locked at the usual hours, and the only ways out are the 15-minute NFC unlock or editing the
whole week and editing it back. This feature adds **date exceptions**: a calendar day, or a run
of days, on which the weekly grid is replaced by a whole-day treatment. Exceptions go either
way — a day off *or* a quiet day — and they obey the same rule as every other schedule change:
**tightening applies now, loosening waits for tomorrow.**

Not in scope: recurrence (a holiday is entered as a date each year), per-slot painting on a
specific date, named schedule profiles, reading the user's calendar. Each was considered and
deferred; none of them would need the model below to change.

## 2. Model

New field on `PaperweightConfig`, decoded with `decodeIfPresent` and a `[]` fallback like every
other field (a thrown decode would wipe the registered unlock token):

```swift
struct DayException: Codable, Equatable, Identifiable {
    var id: UUID
    var firstDay: DayKey        // inclusive
    var lastDay: DayKey         // inclusive; == firstDay for a single day
    var treatment: Treatment
    var note: String            // optional in the UI, "" when empty
    var createdAt: Date

    enum Treatment: Codable, Equatable {
        case openAllDay
        case quietAllDay
        case likeWeekday(Int)   // 0 = Sunday … 6 = Saturday, matching the grid's day index
    }
}

/// A calendar date with no time or zone, so an exception means the same thing across
/// DST changes and travel. Stored as "YYYY-MM-DD".
struct DayKey: Codable, Hashable, Comparable {
    var year: Int, month: Int, day: Int
    init(_ date: Date, calendar: Calendar = .current)
    func date(calendar: Calendar = .current) -> Date        // start of that day
    func next(calendar: Calendar = .current) -> DayKey
    static func today(calendar: Calendar = .current) -> DayKey
}

extension PaperweightConfig {
    var dayExceptions: [DayException]       // default []
}
```

Invariants, enforced by the mutation API in §3 and never assumed by the resolver:

- `firstDay <= lastDay`.
- No two exceptions overlap. Because of this the resolver never has to rank exceptions.
- `note` is at most 40 characters, trimmed.

## 3. The rule

All mutation goes through one API on `PaperweightConfig`, mirroring `applyScheduleEdit`:

```swift
extension PaperweightConfig {
    enum ExceptionError: Error { case overlaps(DayException), loosensToday, endsBeforeStart }

    /// Adds an exception, or throws. `now` decides what "today" means.
    mutating func addDayException(_ e: DayException, now: Date = Date(), calendar: Calendar = .current) throws

    /// Removes an exception under the deferral rule. Returns what actually happened.
    @discardableResult
    mutating func removeDayException(id: UUID, now: Date = Date(), calendar: Calendar = .current) -> ExceptionRemoval

    enum ExceptionRemoval: Equatable { case removed, truncatedToToday, notFound }

    /// Whether `treatment` on `day` would open any slot that is quiet under the schedule in
    /// force that day. Pure; used by the add sheet to grey out today.
    func exceptionLoosens(_ treatment: DayException.Treatment, on day: DayKey) -> Bool
}
```

Precisely:

- **Loosening waits.** `addDayException` throws `loosensToday` when `firstDay == today` and
  `exceptionLoosens(treatment, on: today)` is true. `firstDay < today` is always rejected (as
  `loosensToday` too — there is no separate "in the past" case worth a message). The rule is
  evaluated only for the first day: later days of a range are by definition tomorrow or later.
- **Tightening is immediate.** `quietAllDay` may start today. `likeWeekday(w)` may start today
  only when weekday `w`'s pattern has no slot open that today's effective pattern has quiet —
  the same set test `merging(tighteningFrom:)` already makes:
  `weekdayPattern(w).freeSlots ⊆ effectivePattern(today).freeSlots` (both expressed as a
  single day's 48 half-hours).
- **`exceptionLoosens` reads the effective day, not just the weekly grid.** If today is
  already a quiet day by exception, adding an open-all-day exception for today loosens.
  (Overlap is refused first anyway; this matters for `removeDayException`.)
- **Removing follows the same rule.** Removing an exception is a change back to the weekly
  pattern for those days. It loosens today when the exception covers today and today's weekly
  pattern has a slot open that the exception keeps quiet. In that case the exception is not
  deleted but **truncated**: `lastDay = today` (the exception necessarily started on or before
  today, so `firstDay <= lastDay` still holds). Otherwise it is removed outright. In practice:
  removing a day off is immediate; removing a quiet day that is today "ends tonight".
- **Editing is add + remove.** The UI edits an exception by removing it and adding the edited
  one; both halves apply their own rule. That keeps one code path.
- **Overlap** is rejected on add with the offending exception, so the sheet can name it.
- **Pruning.** `ConfigStore.load()` drops exceptions whose `lastDay < today`, next to where it
  promotes a pending schedule, and persists when anything was dropped.
- **Pending schedule interaction.** Exceptions are a layer above whichever weekly schedule is
  active. `pendingSchedule` promotion is untouched. `exceptionLoosens` uses the *active*
  schedule for today (the pending one cannot be in force today by construction).

## 4. Resolution

A single pure resolver in `Shared/Models/ScheduleResolver.swift`, used everywhere a decision is
made. It wraps the existing `PaperweightSchedule` functions rather than replacing them; the
weekly schedule's API stays as it is.

```swift
struct ScheduleResolver {
    let schedule: PaperweightSchedule?
    let exceptions: [DayException]

    /// The exception covering `day`, if any.
    func exception(on day: DayKey) -> DayException?

    /// The 48 half-hour slots open on a given calendar day (0…47), with exceptions applied.
    func openSlots(on day: DayKey) -> Set<Int>

    /// The three decisions the app makes today, with the same shapes as the schedule's own.
    func isFree(at date: Date) -> Bool
    func quietStatus(at date: Date) -> (remaining: TimeInterval, remainingFraction: Double, ends: Date)?
    func freeStatus(at date: Date) -> (remaining: TimeInterval, elapsedFraction: Double, ends: Date)?

    /// Day-ribbon and week-strip segments for a calendar day, with exceptions applied.
    func daySegments(on day: DayKey) -> [PaperweightSchedule.DaySegment]
    func isOpenAllDay(on day: DayKey) -> Bool
}
```

Semantics:

- `openSlots(on:)`: `openAllDay` → all 48; `quietAllDay` → none; `likeWeekday(w)` → the weekly
  grid's day `w`; no exception → the weekly grid's day for that date's weekday. With
  `schedule == nil` or empty the weekly grid contributes nothing (all quiet), exactly as today.
- `quietStatus` / `freeStatus` walk half-hour slots forward and backward from `date` using
  `openSlots(on:)` day by day, capped at 60 days ahead and 60 behind, so a planned range longer
  than a week still gets a countdown and a correct ring fraction. This replaces the weekly
  functions' modular walk over 336 slots. Boundaries are the same shape (`ends` is the first
  instant of the first slot of the other kind), so callers change nothing but the receiver. Walk
  by `DayKey.next()` rather than adding 86 400 seconds, for the DST reason already documented in
  `applyScheduleEdit`.
- "Always quiet" / "always open" (no boundary within 7 days) returns nil, as today.
- A resolver with `exceptions == []` must give identical answers to the weekly schedule for
  every input; that equivalence is a test.

`PaperweightConfig.resolver` and `WidgetSnapshot.resolver` are one-line conveniences.

## 5. Enforcement and DeviceActivity

- **Call sites.** The three places that decide the shield — `PaperweightMonitor.syncShield`,
  `HomeViewModel.syncRestrictions`, `UnlockService.syncRestrictions` — replace
  `schedule.isFree(at: now)` with `config.resolver.isFree(at: now)`. The
  `!schedule.isEmpty` guard goes: an empty weekly schedule with an open-all-day exception
  must lift the shield.
- **Registrations.** No per-exception DeviceActivity activities. `likeWeekday` needs nothing:
  free windows are already registered as the union across all seven days and the monitor
  re-derives the truth at callback time. `openAllDay` and `quietAllDay` need a boundary at
  midnight, so `ScheduleService.heartbeatHours` becomes `[0, 6, 12, 18]`. The window budget
  is derived from `heartbeatHours.count`, so it drops from 16 to 15 distinct windows on its own;
  the total stays within DeviceActivity's 20.
- **Midnight.** A window ending at 23:59 the day before a day off evaluates at 00:00 via
  `boundaryInstant(near:)` and lifts correctly; the 00:00 heartbeat covers a day whose
  previous day had no window ending at midnight. Both paths go through the resolver.
- **Foreground.** `HomeViewModel.refresh()` already reloads from disk; nothing new.

## 6. Widget

- `WidgetSnapshot` gains `dayExceptions: [DayException]` (token-free, `Codable`, decoded with a
  `[]` fallback). `WidgetSnapshot(config:isScreenTimeAuthorized:)` copies it.
- `state(at:)` and `nextBoundary(at:)` use `resolver.freeStatus` / `quietStatus` / `isFree`.
  The `.off`-when-always-free special case stays.
- `timelineDates` needs no change: an exception edge is just another boundary.
- The medium widget's day ribbon paints `resolver.daySegments(on: today)`.
- `DayException` and `DayKey` are Foundation-only so they can join the widget target's
  file-by-file source list; `ScheduleResolver.swift` joins it too.

## 7. UI

Decisions from the mockup session; copy follows the house rules (the word is "quiet", never
"blocked"; "free" is banned; no exclamation marks; 13px floor; `PW` colours only).

### 7a. Entry point — Home (chosen: row on Home, marker on the strip)

- The open-state Home screen's `GroupedCard` gains a second `NavRow` under "Restricted apps":
  title **"Days off & quiet days"**, `systemImage: "calendar"`, `iconColor: PW.textMuted`,
  value = the next upcoming exception as `"Fri · 1 upcoming"` (`"Sep 21–25 · 2 upcoming"` for
  a range; `nil` when none). It pushes `DayExceptionsView`.
- The locked-state Home screen does not get the row (its only action is "View schedule",
  unchanged). The list is still reachable from Settings (§7d).

### 7b. Week strip marker (chosen: effective bar, dot on the day)

- `WeekStrip` takes a `ScheduleResolver` and the seven `DayKey`s of the current week (the
  Sunday on or before today through the following Saturday, matching the rows), and paints
  `daySegments(on:)` / `isOpenAllDay(on:)` for each — so a quiet Sunday is a full moss bar and a
  day off is the existing dashed "OPEN ALL DAY" row.
- A day with an exception gets a 6pt sage dot after its name (`PW.sage`, `Circle`, 4pt
  leading). Legend gains a third item, the dot followed by **"Planned"**.
- Nothing else on the strip changes.

### 7c. The list — `DayExceptionsView`

- Navigation title **"Days off & quiet days"**, `+` trailing toolbar item (`PW.sage`).
- Sections, each a `SectionHeader` over a `GroupedCard`: **"Today"** (an exception covering
  today, if any) then **"Upcoming"**. Empty state inside the card when there are none:
  Spectral italic **"Nothing planned."** over grotesk 13 `PW.textMuted`
  **"Holidays, trips, exam days. Add one and the week bends around it."**
- Row: date on the left in grotesk 15 (`"Fri, Sep 18"` or `"Mon, Sep 21 – Fri, Sep 25"`),
  treatment pill on the right; second line grotesk 13 `PW.textMuted` with the note, and for a
  range `" · 5 days"` appended.
- Pills: **"Open all day"** (`PW.sage` text, 50% sage border), **"Quiet all day"** (moss fill
  at 18%, `PW.moss` text), **"Like Saturday"** (`PW.textMuted`, 18% white border). Grotesk 13,
  sentence case, no tracking (the mockup's 11pt uppercase is under the text floor).
- Swipe-to-remove, `PW.clay`, label **"Remove"**. When removal truncates, the row moves to the
  Today section with the second line **"Ends tonight · removing a quiet day lands tomorrow"**.
- Footer under the list, grotesk 13 `PW.textFaint`, two lines:
  **"A day off has to be set the day before."** / **"A quiet day can start right now."**
- `AccentButton` **"Add a day"** at the bottom, same target as `+`.

### 7d. Settings

- `SettingsView` gains the same row between "Schedule" and "NFC Token & Recovery", so the
  screen is reachable while locked.

### 7e. Add sheet — `AddDayExceptionSheet` (chosen as drawn, note kept)

- Presented as a sheet with drag indicator, `.tint(PW.sage)`. Toolbar: **Cancel** / title
  **"Add a day"** / **Save** (disabled until valid).
- Order: treatment first, because it decides which dates are allowed.
  1. `PWSegmented` with **"Open all day"**, **"Quiet all day"**, **"Like a weekday…"**. Choosing
     the third reveals a second segmented row S M T W T F S beneath it (default: today's
     weekday).
  2. `GroupedCard` of three rows: **From** (date, `PW.sage`), **To** (default **"Same day"**,
     `PW.textMuted`; tapping shows a date), **Note** (placeholder **"Optional"**, 40 chars).
  3. An inline month calendar (`DatePicker` `.graphical` styled to the theme, or a small custom
     grid if the system one cannot be themed within the floor) bound to whichever of From/To
     was last tapped. Dates before today are struck through; **today is struck through as well
     whenever `exceptionLoosens(treatment, on: today)`** and is re-enabled the moment the
     treatment changes to one that doesn't.
  4. One footer line, grotesk 13 `PW.textFaint`, shown only while today is disabled:
     **"Opening up takes effect from tomorrow, so today isn't offered."**
- Validation is the model's: Save calls `addDayException`; `overlaps` shows an inline
  `PW.clay` line **"Overlaps Sep 21 – 25. Remove that one first."**; `endsBeforeStart` cannot
  be produced by the picker but is handled the same way; `loosensToday` cannot be produced
  either because the date is disabled, and is handled the same way.
- On save: `try configStore.save(config)`, `syncRestrictions()`, `ScheduleService.shared.sync
  (config:)`, dismiss. The view model owns this in `addDayException(_:)` /
  `removeDayException(id:)` methods that wrap the config API and do the three follow-ups.

### 7f. Edit

- Tapping a row opens the same sheet pre-filled, title **"Edit day"**. Save = remove old +
  add new under the rule; if the remove truncates and the add starts tomorrow, the user sees
  both rows (one "ends tonight", one upcoming), which is the honest picture.

## 8. Testing

All in `PaperweightTests` (which compiles `Shared/`), test-first:

- **`DayKeyTests`**: round trip through `Codable`, `next()` across a month end and across the
  fall-back DST day, comparison.
- **`ScheduleResolverTests`**: with no exceptions, `isFree` / `quietStatus` / `freeStatus` equal
  the weekly schedule's for a grid of instants across a week; `openAllDay` lifts from 00:00 to
  23:59:59; `quietAllDay` over a day with an open evening; `likeWeekday` reads the right column;
  the countdown from a Thursday evening across a Friday day off lands on Saturday's first quiet
  slot; the countdown from a quiet day into an ordinary day; nil when no boundary in 7 days.
- **`DayExceptionRuleTests`**: `loosensToday` for open-all-day today; quiet-all-day today is
  allowed; `likeWeekday` today allowed only when it tightens; tomorrow always allowed; overlap
  refused and names the other exception; removing a day off is `.removed`; removing today's quiet
  day is `.truncatedToToday` with `lastDay == today`; removing a quiet range that started
  yesterday truncates; pruning drops past exceptions and keeps today's.
- **`WidgetSnapshotTests`** additions: state and `nextBoundary` across an exception edge; day
  segments for an exception day; decoding a snapshot without the new key.
- **`ScheduleServiceTests`**: heartbeats include 00:00; total stays ≤ 20 with the new count.
- **On device** (DeviceActivity does not run on the simulator): a day off starting tomorrow
  lifts the shield at 00:00; a quiet day added now applies at once; the widget's countdown crosses
  the day-off edge without opening the app.

## 9. Files

New: `Shared/Models/DayKey.swift`, `Shared/Models/DayException.swift`,
`Shared/Models/ScheduleResolver.swift`, `Shared/Models/DayException+Rule.swift`,
`Paperweight/Views/DayExceptionsView.swift`, `Paperweight/Views/AddDayExceptionSheet.swift`,
the four test files above.

Modified: `PaperweightConfig`, `ConfigStore.load()`, `HomeViewModel`, `HomeView`,
`SettingsView`, `WeekStrip`, `WidgetSnapshot`, `WidgetSnapshot+Config`,
`PaperweightWidgetViews` (ribbon), `PaperweightMonitor`, `UnlockService`, `ScheduleService`,
`project.yml` (widget target gains the three new Shared files).
