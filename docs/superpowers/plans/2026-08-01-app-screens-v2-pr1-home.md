# App Screens v2 — PR 1: Home restructured

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn Home into the v2 two-state screen (locked / open) and move the settings list behind a nav-bar gear, deleting the full-screen Quiet cover.

**Architecture:** `HomeView` becomes the navigation root and renders one of two states driven by the schedule. The old settings list moves verbatim into a new `SettingsView` pushed from a gear. Week-strip segmentation lands in `Shared/` as pure model code so it is testable; the drawing stays in `Paperweight/Views/`. `QuietScreen` and `HoldToUnlockButton` are deleted.

**Tech Stack:** Swift 5.9, SwiftUI, iOS 17+, XcodeGen, XCTest.

**Spec:** `docs/superpowers/specs/2026-08-01-app-screens-v2-design.md` §2, §3 (01/02), §5.

## Global Constraints

- Deployment target iOS 17.0; Swift 5.9. No new dependencies.
- The `.xcodeproj` is generated and gitignored — run `xcodegen generate` before any build. `Paperweight/` and `Shared/` are directory globs, so new files under them need no `project.yml` edit.
- `PaperweightTests` compiles `PaperweightTests` + `Shared` only. **Anything that needs a unit test must live in `Shared/`.**
- Views live under `Paperweight/Views/`; model and math live under `Shared/Models/`. Follow the existing split.
- Copy rule: the word **"free"** is banned from user-facing strings. Locked hours are "quiet"; unrestricted time is "open".
- Text floor for app screens: **13px minimum**. This does **not** apply to widget surfaces (see Task 1).
- Named colors come from the `PW` enum — no literal hex in views. Neutral hairlines and fills follow the codebase's existing `Color.white.opacity(…)` pattern (see `ScheduleView.swift`).
- Services, `HomeViewModel`, and `ConfigStore` are not modified in this PR.

**Test command** (used verbatim throughout; `iPhone 17` is installed on this machine — if it is ever absent, pick another from `xcrun simctl list devices available`):

```bash
xcodegen generate && xcodebuild test -project Paperweight.xcodeproj -scheme PaperweightTests -destination 'platform=iOS Simulator,name=iPhone 17' CODE_SIGNING_ALLOWED=NO
```

**Build command:**

```bash
xcodegen generate && xcodebuild build -project Paperweight.xcodeproj -scheme Paperweight -destination 'platform=iOS Simulator,name=iPhone 17' CODE_SIGNING_ALLOWED=NO
```

---

### Task 1: Tokens and the app-screen text floor

The spec lightens secondary text and sets a 13px floor. The floor is an *app screens* rule: `pwSectionLabel()` sits at 11 and is used by the widget, where `2af5ae2` specifically fixed overflow. Raising it would regress that. So add a second helper for app screens and leave the widget's alone.

**Files:**
- Modify: `Shared/Theme.swift:27` (`textMuted`), `Shared/Theme.swift:54-62` (label helpers)

**Interfaces:**
- Produces: `PW.textLabel` (`Color`), `View.pwScreenLabel() -> some View`. Later tasks use `pwScreenLabel()` for uppercase section labels on app screens.

- [ ] **Step 1: Update the muted token and add the label token**

In `Shared/Theme.swift`, change the `textMuted` line and add `textLabel` directly beneath it:

```swift
    static let textMuted     = Color(pwHex: 0xA3AF9B)   // v2 secondary text
    static let textLabel     = Color(pwHex: 0x7D8A75)   // v2 uppercase section labels
```

- [ ] **Step 2: Add the app-screen label helper**

In the `extension View` block at the bottom of `Shared/Theme.swift`, leave `pwSectionLabel()` exactly as it is (the widget depends on its 11pt size) and add:

```swift
    /// Uppercase section label for **app screens**, at the v2 13px text floor.
    /// Widgets keep `pwSectionLabel()` — they have their own space budget, and
    /// raising the floor there overflows the small widget.
    func pwScreenLabel() -> some View {
        self.font(.grotesk(13, weight: .semibold))
            .tracking(2.4)
            .foregroundStyle(PW.textLabel)
            .textCase(.uppercase)
    }
```

- [ ] **Step 3: Build to verify nothing broke**

Run the build command above.
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 4: Commit**

```bash
git add Shared/Theme.swift
git commit -m "feat: add v2 text tokens and an app-screen label at the 13px floor"
```

---

### Task 2: Week segmentation

Screen 02's strip needs, per day, the runs of locked vs open time as fractions of the day. This is pure math over `freeSlots`, so it goes in `Shared/` and gets real tests.

**Files:**
- Create: `Shared/Models/PaperweightSchedule+Week.swift`
- Test: `PaperweightTests/Models/WeekSegmentTests.swift`

**Interfaces:**
- Consumes: `PaperweightSchedule` (`freeSlots`, `isFreeSlot(day:halfHour:)`, `halfHoursPerDay`, `slotCount`, `freeHourCount`).
- Produces:
  - `PaperweightSchedule.DaySegment` — `struct { let isLocked: Bool; let fraction: Double }`, `Equatable`.
  - `func daySegments(day: Int) -> [DaySegment]`
  - `func isOpenAllDay(day: Int) -> Bool`
  - `var quietHourCount: Double`

- [ ] **Step 1: Write the failing tests**

Create `PaperweightTests/Models/WeekSegmentTests.swift`:

```swift
import XCTest

final class WeekSegmentTests: XCTestCase {

    /// A day with nothing marked open is one full locked run.
    func test_emptyScheduleIsOneLockedRun() {
        let segments = PaperweightSchedule().daySegments(day: 0)
        XCTAssertEqual(segments, [.init(isLocked: true, fraction: 1)])
    }

    /// An all-open day is one full open run.
    func test_alwaysFreeIsOneOpenRun() {
        let segments = PaperweightSchedule.alwaysFree().daySegments(day: 3)
        XCTAssertEqual(segments, [.init(isLocked: false, fraction: 1)])
    }

    /// Open 07:00–21:00 on Monday: locked 7h, open 14h, locked 3h.
    func test_runsAreOrderedFromMidnightAndSumToOne() {
        var s = PaperweightSchedule()
        for hour in 7..<21 { s.setFree(day: 1, hour: hour, true) }
        let segments = s.daySegments(day: 1)

        XCTAssertEqual(segments.count, 3)
        XCTAssertEqual(segments[0].isLocked, true)
        XCTAssertEqual(segments[0].fraction, 7.0 / 24.0, accuracy: 0.0001)
        XCTAssertEqual(segments[1].isLocked, false)
        XCTAssertEqual(segments[1].fraction, 14.0 / 24.0, accuracy: 0.0001)
        XCTAssertEqual(segments[2].isLocked, true)
        XCTAssertEqual(segments[2].fraction, 3.0 / 24.0, accuracy: 0.0001)
        XCTAssertEqual(segments.reduce(0) { $0 + $1.fraction }, 1, accuracy: 0.0001)
    }

    /// Half-hour resolution survives — a 30-minute open run is its own segment.
    func test_halfHourRunsAreNotRoundedAway() {
        var s = PaperweightSchedule()
        s.setFree(day: 2, halfHour: 20, true)   // 10:00–10:30
        let segments = s.daySegments(day: 2)

        XCTAssertEqual(segments.count, 3)
        XCTAssertEqual(segments[1].isLocked, false)
        XCTAssertEqual(segments[1].fraction, 0.5 / 24.0, accuracy: 0.0001)
    }

    func test_isOpenAllDayOnlyWhenEverySlotIsOpen() {
        var s = PaperweightSchedule.alwaysFree()
        XCTAssertTrue(s.isOpenAllDay(day: 6))

        s.setFree(day: 6, hour: 3, false)
        XCTAssertFalse(s.isOpenAllDay(day: 6))
        XCTAssertTrue(s.isOpenAllDay(day: 5))
    }

    /// Quiet hours are the inverse of open hours across the 168-hour week.
    func test_quietHourCountIsTheInverseOfOpenHours() {
        XCTAssertEqual(PaperweightSchedule().quietHourCount, 168)
        XCTAssertEqual(PaperweightSchedule.alwaysFree().quietHourCount, 0)

        var s = PaperweightSchedule()
        for day in 1...5 { for hour in 17..<21 { s.setFree(day: day, hour: hour, true) } }
        XCTAssertEqual(s.quietHourCount, 168 - 20)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run the test command.
Expected: compile failure — `value of type 'PaperweightSchedule' has no member 'daySegments'`.

- [ ] **Step 3: Write the implementation**

Create `Shared/Models/PaperweightSchedule+Week.swift`:

```swift
import Foundation

extension PaperweightSchedule {

    /// One contiguous run within a single day, as a share of that day.
    ///
    /// `isLocked` is the v2 reading of the grid: painted means *quiet*. The
    /// stored truth is still `freeSlots`, so this is a presentation flip only.
    struct DaySegment: Equatable {
        let isLocked: Bool
        let fraction: Double
    }

    /// The day's runs in clock order from midnight. Always at least one segment,
    /// and the fractions always sum to 1.
    func daySegments(day: Int) -> [DaySegment] {
        var segments: [DaySegment] = []
        var half = 0
        while half < Self.halfHoursPerDay {
            let locked = !isFreeSlot(day: day, halfHour: half)
            var end = half
            while end < Self.halfHoursPerDay,
                  (!isFreeSlot(day: day, halfHour: end)) == locked {
                end += 1
            }
            segments.append(DaySegment(
                isLocked: locked,
                fraction: Double(end - half) / Double(Self.halfHoursPerDay)))
            half = end
        }
        return segments
    }

    /// True when no part of the day is quiet — screen 02's "OPEN ALL DAY" row.
    func isOpenAllDay(day: Int) -> Bool {
        (0..<Self.halfHoursPerDay).allSatisfy { isFreeSlot(day: day, halfHour: $0) }
    }

    /// Hours the week is quiet — the number screen 03 reports.
    var quietHourCount: Double {
        Double(Self.slotCount - freeSlots.count) / 2.0
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run the test command.
Expected: all `WeekSegmentTests` PASS.

- [ ] **Step 5: Commit**

```bash
git add Shared/Models/PaperweightSchedule+Week.swift PaperweightTests/Models/WeekSegmentTests.swift
git commit -m "feat: derive per-day locked/open runs from the schedule"
```

---

### Task 3: The countdown format

Screen 01 shows `2:14` with a separate `left`. The existing `WidgetState.compactDuration` renders `2h 14m`, which is the widget's format, not this one. Add a small formatter rather than overloading `WidgetCopy`.

**Files:**
- Create: `Shared/Models/HomeCopy.swift`
- Test: `PaperweightTests/Models/HomeCopyTests.swift`

**Interfaces:**
- Produces: `enum HomeCopy { static func countdown(_ remaining: TimeInterval) -> String }`

- [ ] **Step 1: Write the failing tests**

Create `PaperweightTests/Models/HomeCopyTests.swift`:

```swift
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
```

- [ ] **Step 2: Run the tests to verify they fail**

Run the test command.
Expected: compile failure — `cannot find 'HomeCopy' in scope`.

- [ ] **Step 3: Write the implementation**

Create `Shared/Models/HomeCopy.swift`:

```swift
import Foundation

/// Copy helpers for the v2 Home screen. Deliberately separate from `WidgetCopy`:
/// the widget's "2h 14m" reads well in a small tile, while Home wants the bare
/// numeral "2:14" carrying its unit in a separate label.
enum HomeCopy {

    /// A remaining interval as `h:mm`, or `Nm` under an hour.
    static func countdown(_ remaining: TimeInterval) -> String {
        let total = max(0, Int(remaining))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        guard hours > 0 else { return "\(minutes)m" }
        return String(format: "%d:%02d", hours, minutes)
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run the test command.
Expected: all `HomeCopyTests` PASS.

- [ ] **Step 5: Commit**

```bash
git add Shared/Models/HomeCopy.swift PaperweightTests/Models/HomeCopyTests.swift
git commit -m "feat: add the Home countdown format"
```

---

### Task 4: The week strip

**Files:**
- Create: `Paperweight/Views/Components/WeekStrip.swift`

**Interfaces:**
- Consumes: `PaperweightSchedule.daySegments(day:)`, `isOpenAllDay(day:)`, `PW.moss`, `PW.textLabel`, `View.pwScreenLabel()`.
- Produces: `WeekStrip(schedule: PaperweightSchedule)` — a `View`. Used by Task 7.

- [ ] **Step 1: Write the view**

Create `Paperweight/Views/Components/WeekStrip.swift`:

```swift
import SwiftUI

/// Screen 02's "This week": one row per day, each a proportional bar of quiet
/// (moss) and open (faint) runs. A day with nothing quiet reads as a dashed
/// outline rather than an empty bar, so "no lock at all" can't be mistaken for
/// a rendering failure.
struct WeekStrip: View {
    let schedule: PaperweightSchedule

    private static let dayNames = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
    private static let barHeight: CGFloat = 15

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("This week").pwScreenLabel()

            VStack(spacing: 6) {
                ForEach(0..<7, id: \.self) { day in
                    HStack(spacing: 8) {
                        Text(Self.dayNames[day])
                            .font(.grotesk(13, weight: .semibold))
                            .foregroundStyle(PW.textMuted)
                            .frame(width: 32, alignment: .leading)
                        row(day: day)
                    }
                }
            }

            HStack(spacing: 12) {
                legend(color: PW.moss, label: "Locked — quiet")
                legend(color: nil, label: "Open")
            }
        }
    }

    @ViewBuilder
    private func row(day: Int) -> some View {
        if schedule.isOpenAllDay(day: day) {
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
                    ForEach(Array(schedule.daySegments(day: day).enumerated()), id: \.offset) { _, segment in
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

- [ ] **Step 2: Build to verify it compiles**

Run the build command.
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 3: Commit**

```bash
git add Paperweight/Views/Components/WeekStrip.swift
git commit -m "feat: add the week strip for the open Home state"
```

---

### Task 5: The Simple scene

PR 2 adds `PWMotion`, Diorama, and Overgrown behind a picker. PR 1 needs only the slot and the Simple style, which is a single line of type.

**Files:**
- Create: `Paperweight/Views/Scenes/SimpleScene.swift`

**Interfaces:**
- Produces: `SimpleScene(lock: Double)` — a `View`. `lock` is 0…1; PR 2's scenes take the same first parameter so the call site does not change.

- [ ] **Step 1: Write the view**

Create `Paperweight/Views/Scenes/SimpleScene.swift`:

```swift
import SwiftUI

/// The "Simple" locked-Home style: the words carry the weight.
///
/// `lock` is the 0…1 lock amount from the motion grammar. PR 2 adds the Diorama
/// and Overgrown styles with the same leading parameter, so this call site is
/// stable.
struct SimpleScene: View {
    var lock: Double = 1

    var body: some View {
        Text("Somewhere, a forest is filling in.")
            .font(.spectral(16, italic: true))
            .foregroundStyle(PW.encourage)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .opacity(lock)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .padding(.horizontal, 30)
    }
}
```

- [ ] **Step 2: Build to verify it compiles**

Run the build command.
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 3: Commit**

```bash
git add Paperweight/Views/Scenes/SimpleScene.swift
git commit -m "feat: add the Simple locked-Home scene"
```

---

### Task 6: Extract SettingsView

Move the settings list out of `HomeView` **without changing its behavior**. The `familyActivityPicker` modifier and its selection-gating logic stay on `HomeView` (Task 7 keeps them) because deep links target the picker from the root; `SettingsView` triggers it through a binding.

**Files:**
- Create: `Paperweight/Views/SettingsView.swift`
- Modify: `Paperweight/Views/HomeView.swift` (removal only — Task 7 rewrites the rest)

**Interfaces:**
- Consumes: `HomeViewModel`, `ScheduleView`, `NFCSetupView`, `UnlockView`, `GroupedCard`, `NavRow`, `CardDivider`, `SectionHeader`, `View.pwScreenLabel()`.
- Produces: `SettingsView(vm: HomeViewModel, showingPicker: Binding<Bool>, onTurnOff: () -> Void)`.

- [ ] **Step 1: Create the settings screen**

Create `Paperweight/Views/SettingsView.swift`:

```swift
import SwiftUI
import FamilyControls

/// Everything Home used to be. v2 moves the list behind a gear so Home can be a
/// state, not a menu — and this is where the escape hatch lives, which is why
/// the locked Home still carries a route here.
struct SettingsView: View {
    @ObservedObject var vm: HomeViewModel
    @Binding var showingPicker: Bool
    var onTurnOff: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Restricted apps").pwScreenLabel()
                    .padding(.top, 6).padding(.bottom, 10)
                GroupedCard {
                    Button { showingPicker = true } label: {
                        NavRow(title: "Choose apps & categories",
                               systemImage: "app.badge.checkmark", showsChevron: true)
                    }
                    .buttonStyle(.plain)
                    if !vm.config.selection.isEmpty {
                        CardDivider()
                        RestrictedTokensList(selection: vm.config.selection)
                    }
                }

                Text("Configure").pwScreenLabel()
                    .padding(.top, 22).padding(.bottom, 10)
                GroupedCard {
                    NavigationLink { ScheduleView(vm: vm) } label: {
                        NavRow(title: "Schedule", value: scheduleStatusText)
                    }
                    CardDivider()
                    NavigationLink { NFCSetupView(vm: vm) } label: {
                        NavRow(title: "NFC Token & Recovery")
                    }
                    CardDivider()
                    NavigationLink { UnlockView(vm: vm) } label: {
                        NavRow(title: "Emergency unlock",
                               titleColor: vm.config.isEnabled ? PW.textPrimary : PW.textFaint,
                               value: vm.config.isEnabled ? nil : "Off",
                               valueColor: PW.textFaint,
                               showsChevron: vm.config.isEnabled)
                    }
                    .disabled(!vm.config.isEnabled)
                }

                if vm.config.isEnabled {
                    Text("Deviation").pwScreenLabel()
                        .padding(.top, 22).padding(.bottom, 10)
                    GroupedCard {
                        Button(action: onTurnOff) {
                            NavRow(title: "Turn off Paperweight",
                                   titleColor: PW.clay,
                                   value: vm.isCoolOffPending ? "Cool-off running" : nil,
                                   valueColor: PW.clay,
                                   showsChevron: true)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 30)
        }
        .scrollContentBackground(.hidden)
        .pwScreen()
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var scheduleStatusText: String {
        guard let s = vm.config.schedule, !s.isEmpty else { return "Set up" }
        if vm.config.isEnabled && !s.isFree(at: Date()) { return "Quiet now" }
        return "Ready"
    }
}
```

- [ ] **Step 2: Make `RestrictedTokensList` visible to the new file**

`RestrictedTokensList` is declared `private` in `HomeView.swift`. In `Paperweight/Views/HomeView.swift`, change its declaration from:

```swift
private struct RestrictedTokensList: View {
```

to:

```swift
struct RestrictedTokensList: View {
```

- [ ] **Step 3: Build to verify it compiles**

Run the build command.
Expected: `BUILD SUCCEEDED`. `HomeView` still renders its own list at this point — that is expected and Task 7 removes it.

- [ ] **Step 4: Commit**

```bash
git add Paperweight/Views/SettingsView.swift Paperweight/Views/HomeView.swift
git commit -m "feat: add the settings screen Home's gear will push"
```

---

### Task 7: Home becomes the v2 two-state screen

The rewrite. `HomeView` keeps every non-list responsibility it has today — scene-phase sync, `onOpenURL`, home-screen shortcuts, selection gating, alerts — and swaps its body for the locked/open states. `QuietScreen` and `HoldToUnlockButton` are deleted.

**Files:**
- Modify: `Paperweight/Views/HomeView.swift`

**Interfaces:**
- Consumes: `WeekStrip`, `SimpleScene`, `SettingsView`, `HomeCopy.countdown`, `WidgetState.dayClock`, `WidgetState.compactDuration`, `PaperweightSchedule.quietStatus(at:)`, `PaperweightSchedule.freeStatus(at:)`.

- [ ] **Step 1: Delete the Quiet cover and the hold control**

In `Paperweight/Views/HomeView.swift`, delete the entire `// MARK: - Quiet screen` section (`private struct QuietScreen`) and the entire `// MARK: - Hold to unlock` section (`private struct HoldToUnlockButton`). Delete the `showQuiet` state property and every reference to it, including the `isQuiet` → `showQuiet` `onChange`, the `showQuiet = isQuiet` in `onAppear` and in the `scenePhase` handler, and the `showQuiet = false` lines in `handlePendingShortcut()` and `handleWidgetLink(_:)`.

Keep `isQuiet` — the body now switches on it directly.

- [ ] **Step 2: Replace the body**

Replace the `var body: some View` and the `settingsList` / `statusCard` / `onboardingLine` / `onboardingButton` / `scheduleStatusText` members with:

```swift
    var body: some View {
        NavigationStack {
            Group {
                if !vm.config.isEnabled {
                    setupState
                } else if isQuiet {
                    lockedState
                } else {
                    openState
                }
            }
            .pwScreen()
            .navigationTitle("")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationLink {
                        SettingsView(vm: vm,
                                     showingPicker: $showingPicker,
                                     onTurnOff: { showingDisableSheet = true })
                    } label: {
                        Image(systemName: "gearshape")
                            .font(.system(size: 17))
                            .foregroundStyle(PW.textMuted)
                    }
                }
            }
        }
        .tint(PW.sage)
        .familyActivityPicker(
            headerText: "Choose apps and categories to restrict.",
            footerText: "Do not select Paperweight itself — blocking it could lock you out of these controls.",
            isPresented: $showingPicker,
            selection: $vm.config.selection)
        .onChange(of: showingPicker) { _, isPresented in
            if isPresented {
                selectionSnapshot = vm.config.selection
            } else {
                commitSelectionChange()
            }
        }
        .onChange(of: vm.config.isEnabled) { _, isEnabled in
            updateShortcutItems(isEnabled: isEnabled)
        }
        .onAppear {
            handlePendingShortcut()
            updateShortcutItems(isEnabled: vm.config.isEnabled)
        }
        .onChange(of: shortcutManager.pendingShortcutType) { _, _ in handlePendingShortcut() }
        .onOpenURL { url in handleWidgetLink(url) }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                vm.syncRestrictions()
                ScheduleService.shared.updateSchedule(vm.config.schedule, enabled: vm.config.isEnabled)
            }
        }
        .sheet(isPresented: $showingDisableSheet) {
            DisablePaperweightSheet(vm: vm)
        }
        .alert("Error", isPresented: Binding(
            get: { vm.error != nil }, set: { if !$0 { vm.error = nil } }
        )) { Button("OK", role: .cancel) {} } message: { Text(vm.error?.localizedDescription ?? "") }
        .alert("Change reverted", isPresented: Binding(
            get: { selectionRevertMessage != nil }, set: { if !$0 { selectionRevertMessage = nil } }
        )) { Button("OK", role: .cancel) {} } message: { Text(selectionRevertMessage ?? "") }
        .alert("Choose apps to block first", isPresented: $showNeedsApps) {
            Button("Choose Apps") { showingPicker = true }
            Button("Not now", role: .cancel) {}
        } message: {
            Text("Paperweight has nothing to quiet yet. Pick the apps or categories to restrict first.")
        }
        .alert("Set up a way back first", isPresented: $showNeedsUnlock) {
            Button("Set It Up") { showUnlockSetup = true }
            Button("Not now", role: .cancel) {}
        } message: {
            Text("Before Paperweight can turn on, register an NFC token or generate recovery codes so you can always unlock.")
        }
        .sheet(isPresented: $showUnlockSetup) {
            NavigationStack { NFCSetupView(vm: vm) }
                .tint(PW.sage)
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Locked (screen 01)

    private var lockedState: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let status = vm.config.schedule?.quietStatus(at: context.date)
            VStack(alignment: .leading, spacing: 0) {
                banner(
                    eyebrow: "● Locked",
                    eyebrowColor: PW.dawnGlow,
                    headline: status.map {
                        "Down until \(WidgetState.dayClock($0.ends, from: context.date))"
                    } ?? "Down until you say otherwise",
                    borderColor: PW.dawnGlow.opacity(0.4),
                    glow: true)

                if let status {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(HomeCopy.countdown(status.remaining))
                            .font(.grotesk(44, weight: .bold))
                            .foregroundStyle(PW.textPrimary)
                        Text("left")
                            .font(.grotesk(14, weight: .medium))
                            .foregroundStyle(PW.textMuted)
                    }
                    .padding(.top, 22)

                    progressBar(elapsed: 1 - status.remainingFraction)
                        .padding(.top, 10)

                    Text("Unlocks at \(WidgetState.dayClock(status.ends, from: context.date))")
                        .font(.grotesk(13))
                        .foregroundStyle(PW.textMuted)
                        .padding(.top, 6)
                }

                SimpleScene()
                    .frame(maxHeight: .infinity)

                AccentButton(title: "View schedule") { showingSchedule = true }
                    .padding(.top, 8)

                Text("Emergency unlock lives in Settings — never here.")
                    .font(.grotesk(13))
                    .foregroundStyle(PW.textFaint)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 12)
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 24)
        }
        .navigationDestination(isPresented: $showingSchedule) { ScheduleView(vm: vm) }
    }

    // MARK: - Open (screen 02)

    private var openState: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let status = vm.config.schedule?.freeStatus(at: context.date)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    banner(
                        eyebrow: "○ Open",
                        eyebrowColor: PW.textLabel,
                        headline: "In your hands.",
                        borderColor: PW.hairline,
                        glow: false,
                        detail: status.map {
                            "Locks at \(WidgetState.dayClock($0.ends, from: context.date)) · in \(WidgetState.compactDuration($0.remaining))"
                        })

                    if let schedule = vm.config.schedule, !schedule.isEmpty {
                        WeekStrip(schedule: schedule)
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
                    }
                    .padding(.top, 18)

                    AccentButton(title: "Edit schedule") { showingSchedule = true }
                        .padding(.top, 18)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
            .scrollContentBackground(.hidden)
        }
        .navigationDestination(isPresented: $showingSchedule) { ScheduleView(vm: vm) }
    }

    // MARK: - Not armed yet

    private var setupState: some View {
        VStack(alignment: .leading, spacing: 0) {
            banner(eyebrow: "○ Off",
                   eyebrowColor: PW.textLabel,
                   headline: "Nothing is quiet yet.",
                   borderColor: PW.hairline,
                   glow: false,
                   detail: setupDetail)

            Spacer()

            if !vm.hasAppsSelected {
                AccentButton(title: "Choose apps") { showingPicker = true }
            } else if !vm.hasUnlockMethod {
                AccentButton(title: "Set up a way back") { showUnlockSetup = true }
            } else {
                AccentButton(title: "Set a schedule") { showingSchedule = true }
            }
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 24)
        .navigationDestination(isPresented: $showingSchedule) { ScheduleView(vm: vm) }
    }

    private var setupDetail: String {
        if !vm.hasAppsSelected {
            return "First, choose the apps and categories to quiet."
        }
        if !vm.hasUnlockMethod {
            return "Now set up a way back — an NFC token or recovery codes."
        }
        return "Paint a schedule and it arms itself. There is no switch to forget."
    }

    // MARK: - Shared pieces

    private func banner(eyebrow: String,
                        eyebrowColor: Color,
                        headline: String,
                        borderColor: Color,
                        glow: Bool,
                        detail: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(eyebrow)
                .font(.grotesk(13, weight: .bold))
                .tracking(2.4)
                .textCase(.uppercase)
                .foregroundStyle(eyebrowColor)
            Text(headline)
                .font(.spectral(26))
                .foregroundStyle(PW.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
            if let detail {
                Text(detail)
                    .font(.grotesk(13))
                    .foregroundStyle(PW.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 6)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 18)
                .fill(PW.surfaceRaised)
                .overlay {
                    if glow {
                        RoundedRectangle(cornerRadius: 18)
                            .fill(RadialGradient(
                                colors: [PW.dawnGlow.opacity(0.16), .clear],
                                center: .top, startRadius: 0, endRadius: 180))
                    }
                }
        }
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(borderColor, lineWidth: 1))
    }

    private func progressBar(elapsed: Double) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.12))
                Capsule()
                    .fill(LinearGradient(colors: [PW.moss, PW.dawnGlow],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(0, geo.size.width * min(max(elapsed, 0), 1)))
            }
        }
        .frame(height: 6)
    }

    private var restrictedCountText: String {
        let s = vm.config.selection
        let total = s.applicationTokens.count + s.categoryTokens.count + s.webDomainTokens.count
        return "\(total) app\(total == 1 ? "" : "s")"
    }
```

- [ ] **Step 3: Add the schedule-navigation state**

Alongside the other `@State` properties near the top of `HomeView`, add:

```swift
    @State private var showingSchedule = false
```

Delete the now-unused `footerLine` property and the `Phrases.homeFooter` reference.

- [ ] **Step 4: Route the widget deep link to the picker**

In `handleWidgetLink(_:)`, the `"choose-apps"` and `"unlock-setup"` cases no longer need to drop a cover. Replace the body of that function's switch with:

```swift
            switch url.host {
            case "choose-apps":
                showingPicker = true
            case "unlock-setup":
                showUnlockSetup = true
            case "unlock":
                showingDisableSheet = true
            default:
                break   // "home" — the root is already what's on screen
            }
```

- [ ] **Step 5: Build and run the full test suite**

Run the build command, then the test command.
Expected: `BUILD SUCCEEDED`, then all tests PASS. Existing `HomeViewModelTests` must be unaffected — this task changed no view-model behavior.

- [ ] **Step 6: Verify on the simulator**

Launch the app and confirm, in order:
1. With nothing configured, Home shows the "Off / Nothing is quiet yet." banner and a "Choose apps" button.
2. The gear pushes Settings, and Settings still reaches Schedule, NFC Token & Recovery, and Emergency unlock.
3. With a schedule armed and the current hour quiet, Home shows the locked banner, a countdown, a partly-filled bar, and "View schedule" — and **no** unlock control.
4. The gear is present in the locked state, and Settings → Emergency unlock is reachable from it. This is the escape hatch; it must work.
5. In an open window, Home shows the week strip with quiet runs in moss, and any fully-open day reads "OPEN ALL DAY".

- [ ] **Step 7: Commit**

```bash
git add Paperweight/Views/HomeView.swift
git commit -m "feat: make Home the v2 two-state screen"
```

---

### Task 8: Open the pull request

**Files:** none.

- [ ] **Step 1: Create the issue**

Per the repo convention, plain English — no templates or labels:

```bash
gh issue create --title "Rebuild Home as the v2 two-state screen" --body "The App Screens v2 design turns Home into a real screen with two states — locked and open — instead of a settings list with a full-screen Quiet cover over it. The settings list moves behind a gear in the nav bar, which is also how you reach Emergency unlock while locked. Spec: docs/superpowers/specs/2026-08-01-app-screens-v2-design.md"
```

- [ ] **Step 2: Push and open the PR**

Replace `<N>` with the issue number from Step 1:

```bash
git push -u origin design/app-screens-v2-spec
gh pr create --title "Rebuild Home as the v2 two-state screen" --body "$(cat <<'EOF'
Home becomes the v2 two-state screen: a headline banner that names the state, a countdown that says what it counts, and the week strip in the open state. The settings list moves into its own screen behind a nav-bar gear.

The full-screen Quiet cover and the hold-to-unlock control are gone — v2 has no unlock affordance on Home. The gear is deliberately present in the locked state so Settings, and therefore Emergency unlock, stays one tap away; the design draws no route there, and leaving it out would strand the escape hatch during a lock.

The scene slot renders the Simple style only. The Diorama and Overgrown scenes, the motion grammar, and the picker come in the next PR.

Closes #<N>

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

---

## Notes for later PRs

- **PR 2** adds `Shared/Views/Motion/PWMotion.swift`, the Diorama and Overgrown scenes, `lockedScene` on `PaperweightConfig`, and the picker row in `SettingsView`. `SimpleScene(lock:)` already has the signature the other two will share.
- **PR 3** inverts `ScheduleView` and adds deferred loosening. `quietHourCount` (Task 2) is the number its footer reports.
- **PR 4** restyles screens 04–07.
