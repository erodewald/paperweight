# Deferred loosening — editing the schedule while armed

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the schedule be edited while Paperweight is armed, with tightening applying immediately and loosening deferred to the next calendar day.

**Architecture:** The merge and the promotion are pure functions on `PaperweightConfig` and `PaperweightSchedule`, so they live in `Shared/` and are unit-tested directly. Promotion happens in `ConfigStore.load()`, which means the app, the widget, and the DeviceActivity monitor all see a promoted schedule without each needing its own clock check.

**Tech Stack:** Swift 5.9, SwiftUI, iOS 17+, XcodeGen, XCTest.

**Spec:** `docs/superpowers/specs/2026-08-01-app-screens-v2-design.md` §6(b) — the last unimplemented item in the v2 spec.

## The rule, precisely

While armed, saving an edited schedule splits into two effects:

- **Tightening applies now.** Any half-hour the edit marks quiet that was previously open becomes quiet immediately. Adding restriction can never be used to escape a lock, so making it wait would be friction with no safety benefit.
- **Loosening waits.** Any half-hour the edit marks open that is currently quiet stays quiet until the next calendar day boundary, then opens.

In set terms, where `freeSlots` means "apps are open then":

- Immediately active: `active.freeSlots ∩ edited.freeSlots` — a slot is only open now if it was open before *and* the edit keeps it open.
- Pending: the edited schedule in full, promoted at the next midnight.
- If the merge equals the edit, the change was pure tightening and **no pending schedule is stored**.

This is what stops the deferral being a loophole: you can never repaint "now" as open and slip today's lock without the token.

## Global Constraints

- Deployment target iOS 17.0; Swift 5.9. No new dependencies.
- The `.xcodeproj` is generated and gitignored — run `xcodegen generate` **after** file changes.
- `PaperweightTests` compiles `PaperweightTests` + `Shared` only. **Anything needing a unit test must live in `Shared/`.**
- `Shared/` also compiles into the DeviceActivity monitor extension — keep additions Foundation-only, no SwiftUI.
- `PaperweightConfig`'s decoder is deliberately tolerant: every field uses `decodeIfPresent` with a fallback, because a thrown decode would wipe the user's registered unlock token. New fields must follow that pattern exactly.
- Named colours from the `PW` enum — no literal hex. Neutral fills use `Color.white.opacity(…)`.
- Text floor: **13px minimum**.
- Copy rule: the word **"free"** is banned from user-facing strings. Quiet hours are "quiet", unrestricted time is "open". `freeSlots` and `isFree(at:)` are model API and keep their names.
- `RestrictionService`, `NFCService`, `UnlockService`, and `RecoveryCodeService` are not modified.

**Test command:**

```bash
xcodegen generate && xcodebuild test -project Paperweight.xcodeproj -scheme PaperweightTests -destination 'platform=iOS Simulator,name=iPhone 17' CODE_SIGNING_ALLOWED=NO
```

**Build command:**

```bash
xcodegen generate && xcodebuild build -project Paperweight.xcodeproj -scheme Paperweight -destination 'platform=iOS Simulator,name=iPhone 17' CODE_SIGNING_ALLOWED=NO
```

The suite is 107 tests today and grows in Task 1.

---

### Task 1: The merge and the promotion

**Files:**
- Create: `Shared/Models/ScheduleDeferral.swift`
- Modify: `Shared/Models/PaperweightConfig.swift`
- Test: `PaperweightTests/Models/ScheduleDeferralTests.swift`

**Interfaces:**
- Produces:
  - `PaperweightSchedule.merging(tighteningFrom:)` — returns the immediately-active schedule.
  - `PaperweightConfig.pendingSchedule: PaperweightSchedule?` and `pendingScheduleEffectiveAt: Date?`
  - `PaperweightConfig.applyScheduleEdit(_:now:calendar:)` — the whole rule in one call.
  - `PaperweightConfig.promotePendingScheduleIfDue(now:calendar:)` — swaps a due pending schedule in.
  - `PaperweightConfig.pendingOpeningSlots` — slots quiet now that open when the pending schedule lands, for the grid to mark.

- [ ] **Step 1: Write the failing tests**

Create `PaperweightTests/Models/ScheduleDeferralTests.swift`:

```swift
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
```

- [ ] **Step 2: Run the tests to verify they fail**

Run the test command. Expected: compile failure — no `merging(tighteningFrom:)`.

- [ ] **Step 3: Write the implementation**

Create `Shared/Models/ScheduleDeferral.swift`:

```swift
import Foundation

extension PaperweightSchedule {

    /// The schedule that takes effect immediately when `edit` is saved over this
    /// one: every tightening applies, every loosening is withheld.
    ///
    /// A slot is open only if it was open before *and* the edit leaves it open,
    /// which is what stops a deferred edit from being used to slip today's lock.
    func merging(tighteningFrom edit: PaperweightSchedule) -> PaperweightSchedule {
        PaperweightSchedule(freeSlots: freeSlots.intersection(edit.freeSlots))
    }
}

extension PaperweightConfig {

    /// Saves a schedule edit under the deferral rule: tightening now, loosening
    /// at the next calendar day boundary.
    mutating func applyScheduleEdit(_ edit: PaperweightSchedule,
                                    now: Date = Date(),
                                    calendar: Calendar = .current) {
        let active = schedule ?? PaperweightSchedule()
        let immediate = active.merging(tighteningFrom: edit)
        schedule = immediate

        if immediate == edit {
            // Pure tightening — nothing left to wait for.
            pendingSchedule = nil
            pendingScheduleEffectiveAt = nil
        } else {
            pendingSchedule = edit
            pendingScheduleEffectiveAt = calendar.startOfDay(for: now).addingTimeInterval(86_400)
        }
    }

    /// Swaps in a pending schedule once its day boundary has passed.
    mutating func promotePendingScheduleIfDue(now: Date = Date(),
                                              calendar: Calendar = .current) {
        guard let pending = pendingSchedule,
              let effective = pendingScheduleEffectiveAt,
              now >= effective else { return }
        schedule = pending
        pendingSchedule = nil
        pendingScheduleEffectiveAt = nil
    }

    /// Slots that are quiet under the active schedule but open under the pending
    /// one — what the grid marks as "leaving".
    var pendingOpeningSlots: Set<Int> {
        guard let pending = pendingSchedule else { return [] }
        let active = schedule ?? PaperweightSchedule()
        return pending.freeSlots.subtracting(active.freeSlots)
    }
}
```

Then in `Shared/Models/PaperweightConfig.swift`, add the two stored properties after `quietTheme`:

```swift
    /// A schedule edit whose loosening has not taken effect yet.
    var pendingSchedule: PaperweightSchedule? = nil
    /// When `pendingSchedule` becomes the active one.
    var pendingScheduleEffectiveAt: Date? = nil
```

and in `init(from decoder:)`, after the `quietTheme` line, following the file's tolerant pattern exactly:

```swift
        pendingSchedule = (try? c.decodeIfPresent(PaperweightSchedule.self, forKey: .pendingSchedule)) ?? nil
        pendingScheduleEffectiveAt = try c.decodeIfPresent(Date.self, forKey: .pendingScheduleEffectiveAt)
```

- [ ] **Step 4: Run the tests to verify they pass**

Run the test command. Expected: all `ScheduleDeferralTests` PASS and the existing 107 still pass.

- [ ] **Step 5: Commit**

```bash
git add Shared/Models/ScheduleDeferral.swift Shared/Models/PaperweightConfig.swift PaperweightTests/Models/ScheduleDeferralTests.swift
git commit -m "feat: defer a schedule's loosening to the next day"
```

---

### Task 2: Promote on load, and save through the rule

**Files:**
- Modify: `Shared/Store/ConfigStore.swift`
- Modify: `Shared/ViewModels/HomeViewModel.swift`

Promotion belongs in `load()` so that the app, the widget, and the DeviceActivity monitor all see a promoted schedule without each keeping its own clock.

- [ ] **Step 1: Promote in `load()`**

In `ConfigStore.load()`, after decoding and before returning, call `promotePendingScheduleIfDue()` on the config and, if it changed anything, persist it back so the promotion is not recomputed forever. Read the existing method and match its error handling — a failure to persist must not prevent returning the promoted config.

- [ ] **Step 2: Add the view-model entry point**

In `Shared/ViewModels/HomeViewModel.swift`, add:

```swift
    /// Saves a schedule edit. While armed this defers loosening to tomorrow;
    /// while off it simply replaces the schedule, since there is no lock to slip.
    func saveScheduleEdit(_ edit: PaperweightSchedule) {
        if config.isEnabled {
            config.applyScheduleEdit(edit)
        } else {
            config.schedule = edit.isEmpty ? nil : edit
            config.pendingSchedule = nil
            config.pendingScheduleEffectiveAt = nil
        }
        try? configStore.save(config)
        syncRestrictions()
    }
```

Also call `promotePendingScheduleIfDue()` at the top of `syncRestrictions()`, before it decides what to shield, so a promotion that falls due while the app is open takes effect at the next sync rather than the next launch.

- [ ] **Step 3: Build and run the suite** — expect `BUILD SUCCEEDED` and all tests passing, including the existing `ConfigStoreTests` and `HomeViewModelTests`.

- [ ] **Step 4: Commit** — `git commit -m "feat: promote a due schedule on load and on sync"`

---

### Task 3: Let the grid be edited while armed

**Files:**
- Modify: `Paperweight/Views/ScheduleView.swift`

Read the file first. It currently sets `private var locked: Bool { vm.config.isEnabled }` and makes the whole grid read-only when armed, with a banner saying so. That restriction is what this change removes.

Target:

- **Delete the read-only behaviour.** Painting works whether or not Paperweight is armed. Remove `locked` and the "Turn Paperweight off to change your schedule." line; keep the preset menu available in both states.
- **Three cell states**, not two:
  1. Quiet now and quiet after the pending change — solid `PW.moss`.
  2. Quiet now but opening when the pending change lands — `PW.moss.opacity(0.35)` with a dashed `PW.moss` border, so it reads as leaving rather than as a third unrelated category.
  3. Open now — the existing faint `Color.white.opacity(0.04)`.
  The "now" highlight (`PW.dawnGlow` border, glow) is unchanged and still marks the current hour in every state.
- **Extend the legend** to three entries when a pending change exists, adding "Opens tomorrow" with a swatch matching state 2. With nothing pending, keep the existing two.
- **Saving** calls `vm.saveScheduleEdit(freeSlots.isEmpty ? PaperweightSchedule() : PaperweightSchedule(freeSlots: freeSlots))` instead of writing `vm.config.schedule` directly. Keep the existing arm-time guards (apps chosen, unlock method set) exactly as they are for the not-yet-armed path.
- **Copy.** Keep "Paint your quiet hours." Below the quiet-hours total, when armed, add: "Loosening takes effect tomorrow." When a pending change exists, instead show how much opens and when, e.g. "3 hours open up at midnight."

- [ ] **Step 1: Restyle and re-wire the view.**
- [ ] **Step 2: Build and run the suite** — 107 + Task 1's new tests, all passing.
- [ ] **Step 3: Verify on the simulator.** Turn on the debug "Show armed-only screens" toggle so the armed paths are reachable, paint a loosening edit, save, and screenshot the grid. Read the image back before describing it. Confirm the pending cells render distinctly from both solid-quiet and open, the legend gained its third entry, and the footer names when the change lands. Save to `.superpowers/sdd/schedule-pending.png`.
- [ ] **Step 4: Commit** — `git commit -m "feat: allow editing the schedule while armed"`

---

### Task 4: Open the pull request

- [ ] **Step 1: Run the full suite and both the Debug and Release builds.**
- [ ] **Step 2: Create the issue**

```bash
gh issue create --title "Let the schedule be edited while Paperweight is armed" --body "Today the schedule is completely read-only while armed, so changing it means turning Paperweight off — which needs the NFC token. That is more friction than the lock requires.

Tightening should apply immediately: adding quiet hours can never be used to escape a lock. Only loosening needs to wait, until the next calendar day, so nobody can repaint the current hour as open and slip today's lock.

Spec: docs/superpowers/specs/2026-08-01-app-screens-v2-design.md section 6(b)"
```

- [ ] **Step 3: Push and open the PR**, closing that issue and stating the rule plainly: tightening now, loosening at the next calendar day, and why the asymmetry is what makes the deferral safe rather than a loophole.
