# App Screens v2 — PR 2: The locked-Home scenes

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the locked Home its artwork — the motion grammar plus the Diorama and Overgrown scenes — selectable by a user preference that defaults to Diorama.

**Architecture:** The four-verb motion grammar lands in `Shared/` as pure math with no SwiftUI, so it is unit-testable. Each scene is a `Canvas` view taking `(lock:time:)` and nothing else — no schedule, no view-model, no state. `HomeView` drives them from one `TimelineView`, paused when the app is backgrounded.

**Tech Stack:** Swift 5.9, SwiftUI (`Canvas`, `TimelineView`), iOS 17+, XcodeGen, XCTest.

**Spec:** `docs/superpowers/specs/2026-08-01-app-screens-v2-design.md` §4.
**Geometry source:** `design_handoff_paperweight/designs/MotionStudy.jsx` (local, gitignored). All coordinates below are already extracted from it — you do not need to open it.

## Global Constraints

- Deployment target iOS 17.0; Swift 5.9. No new dependencies.
- The `.xcodeproj` is generated and gitignored — `xcodegen generate` is part of every command below. `Paperweight/` and `Shared/` are directory globs; new files under them need no `project.yml` edit.
- `PaperweightTests` compiles `PaperweightTests` + `Shared` only. **Anything that needs a unit test must live in `Shared/`.**
- `Shared/` is also compiled into the DeviceActivity monitor extension. Keep `Shared/` additions Foundation-only — no SwiftUI, no UIKit — except `Theme.swift`, which already imports SwiftUI.
- Scene views live under `Paperweight/Views/Scenes/`.
- Named colors come from the `PW` enum — no literal hex in views.
- Text floor for app screens: **13px minimum**.
- Copy rule: the word **"free"** is banned from user-facing strings. Locked hours are "quiet"; unrestricted time is "open".
- Services, `ConfigStore`, and `RestrictionService` are not modified in this PR. `HomeViewModel` gains exactly one method (Task 6) and nothing else.
- Motion constants are fixed by the design and must be used exactly: overshoot `0.16`, sway amplitude `3.6°`, sway period `14s`.

**On the phase map.** The spec's §4 choreography table (`openEnd .10`, `settleEnd .28`, `growStart .24`, `growEnd .58`, `restEnd .78`, `releaseEnd .90`) describes the motion study's *looping five-second scene*, where one clip has to show settle, growth, rest and release in sequence. In the app there is no loop: the lock lands when the quiet window begins and stays landed for hours. So the app collapses that timeline to a single `lock` value of 0…1, and `PWMotion.growth`/`crawl` derive the per-element stagger from it. This is what the spec means by "the choreography is a state transition, not a loop" — the phase constants deliberately do not appear in the app code.

**Test command:**

```bash
xcodegen generate && xcodebuild test -project Paperweight.xcodeproj -scheme PaperweightTests -destination 'platform=iOS Simulator,name=iPhone 17' CODE_SIGNING_ALLOWED=NO
```

**Build command:**

```bash
xcodegen generate && xcodebuild build -project Paperweight.xcodeproj -scheme Paperweight -destination 'platform=iOS Simulator,name=iPhone 17' CODE_SIGNING_ALLOWED=NO
```

---

### Task 1: The motion grammar

**Files:**
- Create: `Shared/Motion/PWMotion.swift`
- Test: `PaperweightTests/Motion/PWMotionTests.swift`

**Interfaces:**
- Produces: `enum PWMotion` with `settle(_:)`, `grow(_:)`, `sway(at:phase:)`, `ramp(_:_:_:)`, `growth(index:count:lock:)`, `crawl(index:count:lock:)`, and the constants `overshoot`, `swayDegrees`, `swayPeriod`. Every later task in this PR consumes these.

- [ ] **Step 1: Write the failing tests**

Create `PaperweightTests/Motion/PWMotionTests.swift`:

```swift
import XCTest

final class PWMotionTests: XCTestCase {

    // MARK: settle — weight lands: fast in, soft stop, never a bounce

    func test_settleSpansZeroToOne() {
        XCTAssertEqual(PWMotion.settle(0), 0, accuracy: 0.0001)
        XCTAssertEqual(PWMotion.settle(1), 1, accuracy: 0.0001)
    }

    func test_settleIsFastInSoftStop() {
        // 1 - (1-u)^3 at u = 0.5 is 0.875 — most of the distance is already covered.
        XCTAssertEqual(PWMotion.settle(0.5), 0.875, accuracy: 0.0001)
    }

    /// "Never a bounce" is the design's words — settle must never exceed 1.
    func test_settleNeverOvershoots() {
        for step in 0...100 {
            let value = PWMotion.settle(Double(step) / 100)
            XCTAssertLessThanOrEqual(value, 1.0)
            XCTAssertGreaterThanOrEqual(value, 0.0)
        }
    }

    func test_settleIsMonotonic() {
        var previous = -1.0
        for step in 0...100 {
            let value = PWMotion.settle(Double(step) / 100)
            XCTAssertGreaterThanOrEqual(value, previous)
            previous = value
        }
    }

    func test_settleClampsOutsideTheUnitRange() {
        XCTAssertEqual(PWMotion.settle(-5), 0, accuracy: 0.0001)
        XCTAssertEqual(PWMotion.settle(5), 1, accuracy: 0.0001)
    }

    // MARK: grow — sprout: overshoot, then rest

    func test_growSpansZeroToOne() {
        XCTAssertEqual(PWMotion.grow(0), 0, accuracy: 0.0001)
        XCTAssertEqual(PWMotion.grow(1), 1, accuracy: 0.0001)
    }

    /// The whole point of `grow` is that it passes 1 before settling back to it.
    func test_growActuallyOvershoots() {
        let peak = stride(from: 0.0, through: 1.0, by: 0.01)
            .map { PWMotion.grow($0) }
            .max() ?? 0
        XCTAssertGreaterThan(peak, 1.0)
    }

    func test_growClampsOutsideTheUnitRange() {
        XCTAssertEqual(PWMotion.grow(-1), 0, accuracy: 0.0001)
        XCTAssertEqual(PWMotion.grow(2), 1, accuracy: 0.0001)
    }

    // MARK: sway — nothing is ever still

    func test_swayIsZeroAtTheStartOfItsPeriod() {
        XCTAssertEqual(PWMotion.sway(at: 0), 0, accuracy: 0.0001)
    }

    /// A quarter period in, the sway is at full amplitude.
    func test_swayReachesFullAmplitudeAtAQuarterPeriod() {
        XCTAssertEqual(PWMotion.sway(at: 3.5), 3.6, accuracy: 0.0001)
    }

    func test_swayReturnsToZeroAtHalfPeriod() {
        XCTAssertEqual(PWMotion.sway(at: 7), 0, accuracy: 0.0001)
    }

    func test_swayStaysWithinAmplitude() {
        for step in 0...280 {
            let value = PWMotion.sway(at: Double(step) / 10)
            XCTAssertLessThanOrEqual(abs(value), 3.6 + 0.0001)
        }
    }

    /// Phase is what keeps two trees from swaying in lockstep.
    func test_phaseShiftsTheSway() {
        XCTAssertNotEqual(PWMotion.sway(at: 1), PWMotion.sway(at: 1, phase: 2.1), accuracy: 0.0001)
    }

    // MARK: ramp

    func test_rampMapsAWindowToZeroOne() {
        XCTAssertEqual(PWMotion.ramp(0.25, 0.25, 0.75), 0, accuracy: 0.0001)
        XCTAssertEqual(PWMotion.ramp(0.50, 0.25, 0.75), 0.5, accuracy: 0.0001)
        XCTAssertEqual(PWMotion.ramp(0.75, 0.25, 0.75), 1, accuracy: 0.0001)
        XCTAssertEqual(PWMotion.ramp(0.10, 0.25, 0.75), 0, accuracy: 0.0001)
        XCTAssertEqual(PWMotion.ramp(0.90, 0.25, 0.75), 1, accuracy: 0.0001)
    }

    // MARK: staggered growth — back to front

    func test_nothingHasGrownAtZeroLock() {
        for index in 0..<8 {
            XCTAssertEqual(PWMotion.growth(index: index, count: 8, lock: 0), 0, accuracy: 0.0001)
        }
    }

    /// Everything must be fully grown once the lock has landed, or elements
    /// would be stuck part-sprouted for the entire quiet window.
    func test_everythingIsGrownAtFullLock() {
        for index in 0..<8 {
            XCTAssertEqual(PWMotion.growth(index: index, count: 8, lock: 1), 1, accuracy: 0.0001)
        }
    }

    /// Earlier elements lead later ones — that is what "staggered, back to front" means.
    func test_earlierElementsLeadLaterOnes() {
        let first = PWMotion.growth(index: 0, count: 8, lock: 0.4)
        let last = PWMotion.growth(index: 7, count: 8, lock: 0.4)
        XCTAssertGreaterThan(first, last)
    }

    /// A single-element scene must not divide by zero.
    func test_singleElementIsSafe() {
        XCTAssertEqual(PWMotion.growth(index: 0, count: 1, lock: 1), 1, accuracy: 0.0001)
        XCTAssertEqual(PWMotion.crawl(index: 0, count: 1, lock: 1), 1, accuracy: 0.0001)
    }

    // MARK: crawl — the Overgrown variant, wider and unaccelerated

    func test_crawlSpansZeroToOne() {
        XCTAssertEqual(PWMotion.crawl(index: 3, count: 11, lock: 0), 0, accuracy: 0.0001)
        XCTAssertEqual(PWMotion.crawl(index: 3, count: 11, lock: 1), 1, accuracy: 0.0001)
    }

    func test_crawlEarlierElementsLeadLaterOnes() {
        let first = PWMotion.crawl(index: 0, count: 11, lock: 0.5)
        let last = PWMotion.crawl(index: 10, count: 11, lock: 0.5)
        XCTAssertGreaterThan(first, last)
    }

    /// Unlike `grow`, `crawl` is linear — a vine creeping, not a sprout popping.
    func test_crawlNeverOvershoots() {
        for step in 0...100 {
            let value = PWMotion.crawl(index: 0, count: 11, lock: Double(step) / 100)
            XCTAssertLessThanOrEqual(value, 1.0)
        }
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run the test command.
Expected: compile failure — `cannot find 'PWMotion' in scope`.

- [ ] **Step 3: Write the implementation**

Create `Shared/Motion/PWMotion.swift`:

```swift
import Foundation

/// The Paperweight motion grammar: four verbs, and every easing in the design is
/// one of them.
///
/// - `settle` — the state lands like a weight: fast in, soft stop, never a bounce.
/// - `grow` — life fills in: a slight overshoot, then rest.
/// - `sway` — nothing is ever still.
/// - Release is not a function: it is the same curves run backwards, which the
///   caller gets for free by driving `lock` back toward zero.
///
/// Pure math, no SwiftUI, so it can be tested directly. The constants are fixed
/// by the design and are not tuning knobs.
enum PWMotion {

    /// Back-out overshoot amount. From the motion study's locked tweak defaults.
    static let overshoot: Double = 0.16
    /// Sway amplitude in degrees.
    static let swayDegrees: Double = 3.6
    /// Seconds for one full sway cycle.
    static let swayPeriod: Double = 14

    /// Maps `value` within `[from, to]` onto `0…1`, clamped at both ends.
    static func ramp(_ value: Double, _ from: Double, _ to: Double) -> Double {
        guard to > from else { return value >= to ? 1 : 0 }
        return min(max((value - from) / (to - from), 0), 1)
    }

    /// Weight lands: fast in, soft stop, no bounce. `1 - (1-u)³`.
    static func settle(_ u: Double) -> Double {
        let t = min(max(u, 0), 1)
        return 1 - pow(1 - t, 3)
    }

    /// Sprout: overshoots past 1, then rests on it.
    static func grow(_ u: Double) -> Double {
        let t = min(max(u, 0), 1)
        guard t > 0 else { return 0 }
        guard t < 1 else { return 1 }
        let c1 = overshoot * 7
        let c3 = c1 + 1
        let x = t - 1
        return 1 + c3 * x * x * x + c1 * x * x
    }

    /// Perpetual sway, in degrees, for an element at the given phase offset.
    static func sway(at time: Double, phase: Double = 0) -> Double {
        swayDegrees * sin(2 * .pi * time / swayPeriod + phase)
    }

    /// How far element `index` of `count` has sprouted at the given lock amount.
    ///
    /// Elements start in order and each takes `window` of the lock to complete,
    /// so the scene fills in back to front and is fully grown by `lock == 1`.
    static func growth(index: Int, count: Int, lock: Double, window: Double = 0.4) -> Double {
        grow(stagger(index: index, count: count, lock: lock, window: window))
    }

    /// The Overgrown variant: a wider window and no overshoot — creeping, not popping.
    static func crawl(index: Int, count: Int, lock: Double, window: Double = 0.6) -> Double {
        stagger(index: index, count: count, lock: lock, window: window)
    }

    private static func stagger(index: Int, count: Int, lock: Double, window: Double) -> Double {
        let slots = max(count - 1, 1)
        let start = (Double(index) / Double(slots)) * (1 - window)
        return ramp(lock, start, start + window)
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run the test command.
Expected: all `PWMotionTests` PASS.

- [ ] **Step 5: Commit**

```bash
git add Shared/Motion/PWMotion.swift PaperweightTests/Motion/PWMotionTests.swift
git commit -m "feat: add the Paperweight motion grammar"
```

---

### Task 2: The scene preference

**Files:**
- Create: `Shared/Models/LockedScene.swift`
- Modify: `Shared/Models/PaperweightConfig.swift`
- Test: `PaperweightTests/Models/LockedSceneTests.swift`

**Interfaces:**
- Consumes: `PaperweightConfig`'s existing tolerant decoder.
- Produces: `enum LockedScene: String, Codable, CaseIterable, Identifiable { case simple, diorama, overgrown }` with `title` and `blurb`; and `PaperweightConfig.lockedScene`, defaulting to `.diorama`.

- [ ] **Step 1: Write the failing tests**

Create `PaperweightTests/Models/LockedSceneTests.swift`:

```swift
import XCTest

final class LockedSceneTests: XCTestCase {

    func test_allThreeStylesArePresentInDisplayOrder() {
        XCTAssertEqual(LockedScene.allCases, [.simple, .diorama, .overgrown])
    }

    func test_everyStyleHasATitleAndBlurb() {
        for scene in LockedScene.allCases {
            XCTAssertFalse(scene.title.isEmpty)
            XCTAssertFalse(scene.blurb.isEmpty)
        }
    }

    /// A config saved before this field existed must still decode, and must land
    /// on Diorama — the design's default — rather than throwing or resetting.
    func test_configWithoutTheKeyDefaultsToDiorama() throws {
        let json = Data(#"{"isEnabled":true,"coolOffDays":2}"#.utf8)
        let config = try JSONDecoder().decode(PaperweightConfig.self, from: json)

        XCTAssertEqual(config.lockedScene, .diorama)
        XCTAssertTrue(config.isEnabled)
        XCTAssertEqual(config.coolOffDays, 2)
    }

    func test_aStoredChoiceSurvivesARoundTrip() throws {
        var config = PaperweightConfig()
        config.lockedScene = .overgrown

        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(PaperweightConfig.self, from: data)

        XCTAssertEqual(decoded.lockedScene, .overgrown)
    }

    /// An unrecognised value — a config written by a newer build — must fall back
    /// rather than throw, since a thrown config decode wipes the user's setup.
    func test_anUnknownStyleFallsBackToDiorama() throws {
        let json = Data(#"{"lockedScene":"bioluminescent"}"#.utf8)
        let config = try JSONDecoder().decode(PaperweightConfig.self, from: json)

        XCTAssertEqual(config.lockedScene, .diorama)
    }

    func test_theDefaultConfigUsesDiorama() {
        XCTAssertEqual(PaperweightConfig().lockedScene, .diorama)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run the test command.
Expected: compile failure — `cannot find 'LockedScene' in scope`.

- [ ] **Step 3: Add the enum**

Create `Shared/Models/LockedScene.swift`:

```swift
import Foundation

/// What the locked Home draws behind its words. The wording comes from the
/// motion study, which names each style by what it does rather than how it looks.
enum LockedScene: String, Codable, CaseIterable, Identifiable {
    case simple
    case diorama
    case overgrown

    var id: String { rawValue }

    var title: String {
        switch self {
        case .simple: return "Simple"
        case .diorama: return "Diorama"
        case .overgrown: return "Overgrown"
        }
    }

    var blurb: String {
        switch self {
        case .simple: return "The words carry the weight."
        case .diorama: return "A forest sprouts behind the words."
        case .overgrown: return "The screen is claimed at its corners."
        }
    }
}
```

- [ ] **Step 4: Add the config field**

In `Shared/Models/PaperweightConfig.swift`, add the stored property immediately after `unlockExpiresAt`:

```swift
    /// Which artwork the locked Home draws. Purely cosmetic — it never affects
    /// what is restricted.
    var lockedScene: LockedScene = .diorama
```

Then in `init(from decoder:)`, add this line immediately after the `unlockExpiresAt` line and before the `#if os(iOS)` block:

```swift
        lockedScene = (try? c.decodeIfPresent(LockedScene.self, forKey: .lockedScene)) as? LockedScene ?? .diorama
```

- [ ] **Step 5: Run the tests to verify they pass**

Run the test command.
Expected: all `LockedSceneTests` PASS, and the existing `PaperweightConfigTests` and `ConfigStoreTests` still PASS.

- [ ] **Step 6: Commit**

```bash
git add Shared/Models/LockedScene.swift Shared/Models/PaperweightConfig.swift PaperweightTests/Models/LockedSceneTests.swift
git commit -m "feat: remember which locked-screen scene the user picked"
```

---

### Task 3: The forest palette

The scenes need seven colors the theme does not have yet. They belong in `PW` with everything else rather than in a scene-local table, so there stays one place colors are defined.

**Files:**
- Modify: `Shared/Theme.swift`

**Interfaces:**
- Produces: `PW.treeDark`, `PW.treeMid`, `PW.treeFront`, `PW.trunk`, `PW.bush`, `PW.groundBack`, `PW.groundFront`, `PW.stem`.

- [ ] **Step 1: Add the palette**

In `Shared/Theme.swift`, inside the `enum PW`, add immediately after the `warn` line:

```swift
    // Locked-screen forest palette. Depth is read entirely through value here —
    // the far trees are nearly the background, the near ones nearly the moss.
    static let treeDark      = Color(pwHex: 0x101C12)   // furthest pines
    static let treeMid       = Color(pwHex: 0x1D3322)   // mid-ground canopy
    static let treeFront     = Color(pwHex: 0x2E4A30)   // nearest canopy
    static let trunk         = Color(pwHex: 0x1A2C1C)
    static let bush          = Color(pwHex: 0x234026)
    static let stem          = Color(pwHex: 0x3D5C36)
    static let groundBack    = Color(pwHex: 0x0E1810)
    static let groundFront   = Color(pwHex: 0x0B140C)
```

- [ ] **Step 2: Build to verify it compiles**

Run the build command.
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 3: Commit**

```bash
git add Shared/Theme.swift
git commit -m "feat: add the locked-screen forest palette"
```

---

### Task 4: The Diorama scene

A forest sprouts behind the words: four pines, three blob trees, two ground ellipses, five fireflies.

**Files:**
- Create: `Paperweight/Views/Scenes/DioramaScene.swift`

**Interfaces:**
- Consumes: `PWMotion.growth(index:count:lock:)`, `PWMotion.sway(at:phase:)`, the `PW` forest palette.
- Produces: `DioramaScene(lock: Double, time: Double)` — a `View`. Task 7 renders it.

Design space is 780 wide × 250 tall with the ground line at y = 230, scaled to fit the view and pinned to the bottom.

- [ ] **Step 1: Write the view**

Create `Paperweight/Views/Scenes/DioramaScene.swift`:

```swift
import SwiftUI

/// "A forest sprouts behind the words."
///
/// Drawn in a fixed 780×250 design space with the ground line at y=230, then
/// scaled to whatever the locked Home can spare. `lock` drives the sprouting;
/// `time` drives the sway and the fireflies, which never stop.
struct DioramaScene: View {
    var lock: Double = 1
    var time: Double = 0

    private static let designSize = CGSize(width: 780, height: 250)
    private static let groundY: CGFloat = 230

    /// Pines: x, height, half-width, growth slot.
    private static let pines: [(x: CGFloat, h: CGFloat, w: CGFloat, slot: Int)] = [
        (70, 140, 26, 0), (140, 104, 22, 1), (636, 128, 26, 1), (716, 94, 21, 2),
    ]

    /// Blob trees: x, scale, phase, growth slot, is-near, bears-fruit.
    private static let blobs: [(x: CGFloat, scale: CGFloat, phase: Double, slot: Int, near: Bool, fruit: Bool)] = [
        (250, 1.3, 0.0, 3, false, false),
        (580, 0.8, 2.1, 4, false, false),
        (420, 1.5, 1.1, 6, true,  true),
    ]

    /// Fireflies: x, y, radius, phase, growth slot they wait on.
    private static let flies: [(x: CGFloat, y: CGFloat, r: CGFloat, phase: Double, slot: Int)] = [
        (120, 150, 4.0, 0.0, 6), (330, 110, 3.0, 2.2, 7), (540, 140, 3.5, 4.1, 7),
        (690, 170, 2.6, 1.3, 6), (220,  90, 3.0, 5.3, 7),
    ]

    var body: some View {
        Canvas { context, size in
            let scale = size.width / Self.designSize.width
            context.translateBy(x: 0, y: size.height - Self.designSize.height * scale)
            context.scaleBy(x: scale, y: scale)

            drawGround(&context, y: 256, rx: 470, ry: 50, color: PW.groundBack)
            for pine in Self.pines { drawPine(&context, pine) }
            for blob in Self.blobs where !blob.near { drawBlob(&context, blob) }
            for blob in Self.blobs where blob.near { drawBlob(&context, blob) }
            drawGround(&context, y: 250, rx: 430, ry: 30, color: PW.groundFront)
            for fly in Self.flies { drawFly(&context, fly) }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // MARK: Ground

    private func drawGround(_ context: inout GraphicsContext,
                            y: CGFloat, rx: CGFloat, ry: CGFloat, color: Color) {
        let rect = CGRect(x: 390 - rx, y: y - ry, width: rx * 2, height: ry * 2)
        context.opacity = lock
        context.fill(Path(ellipseIn: rect), with: .color(color))
        context.opacity = 1
    }

    // MARK: Pines

    private func drawPine(_ context: inout GraphicsContext,
                          _ pine: (x: CGFloat, h: CGFloat, w: CGFloat, slot: Int)) {
        let grown = PWMotion.growth(index: pine.slot, count: 8, lock: lock)
        guard grown > 0.001 else { return }

        var path = Path()
        path.move(to: CGPoint(x: -pine.w, y: 0))
        path.addLine(to: CGPoint(x: 0, y: -pine.h))
        path.addLine(to: CGPoint(x: pine.w, y: 0))
        path.closeSubpath()

        var layer = context
        layer.translateBy(x: pine.x, y: Self.groundY)
        layer.scaleBy(x: grown, y: grown)
        // Stroking with the fill colour is what rounds the pine's points.
        layer.fill(path, with: .color(PW.treeDark))
        layer.stroke(path, with: .color(PW.treeDark),
                     style: StrokeStyle(lineWidth: 12, lineJoin: .round))
    }

    // MARK: Blob trees

    private func drawBlob(_ context: inout GraphicsContext,
                          _ blob: (x: CGFloat, scale: CGFloat, phase: Double,
                                   slot: Int, near: Bool, fruit: Bool)) {
        let grown = PWMotion.growth(index: blob.slot, count: 8, lock: lock)
        guard grown > 0.001 else { return }

        let canopy = blob.near ? PW.treeFront : PW.treeMid
        let highlight = blob.near ? PW.moss : PW.treeFront

        var layer = context
        layer.translateBy(x: blob.x, y: Self.groundY)
        layer.scaleBy(x: blob.scale * grown, y: blob.scale * grown)

        layer.fill(
            Path(roundedRect: CGRect(x: -6, y: -64, width: 12, height: 64), cornerRadius: 5),
            with: .color(PW.trunk))

        // The canopy sways about the top of the trunk; the trunk itself does not.
        var crown = layer
        crown.translateBy(x: 0, y: -60)
        crown.rotate(by: .degrees(PWMotion.sway(at: time, phase: blob.phase) * grown))
        crown.translateBy(x: 0, y: 60)

        for (cx, cy, r) in [(0.0, -92.0, 40.0), (-26.0, -74.0, 25.0), (27.0, -75.0, 24.0)] {
            crown.fill(Self.circle(cx, cy, r), with: .color(canopy))
        }
        for (cx, cy, r) in [(-13.0, -104.0, 9.0), (16.0, -86.0, 6.0)] {
            crown.fill(Self.circle(cx, cy, r), with: .color(highlight))
        }
        if blob.fruit {
            crown.fill(Self.circle(6, -114, 4.5), with: .color(PW.dawnGlow))
        }
    }

    // MARK: Fireflies

    private func drawFly(_ context: inout GraphicsContext,
                         _ fly: (x: CGFloat, y: CGFloat, r: CGFloat, phase: Double, slot: Int)) {
        let grown = PWMotion.growth(index: fly.slot, count: 8, lock: lock)
        let brightness = min(lock, grown) * Self.blink(time: time, phase: fly.phase)
        guard brightness > 0.01 else { return }

        // Two incommensurate sines per axis, so the path meanders instead of looping.
        func position(_ lag: Double) -> CGPoint {
            let t = time - lag
            return CGPoint(
                x: fly.x + 46 * sin(t * 0.55 + fly.phase * 1.7) + 22 * sin(t * 1.31 + fly.phase * 3.1),
                y: fly.y + 30 * sin(t * 0.43 + fly.phase * 2.3) + 16 * sin(t * 1.07 + fly.phase))
        }

        var layer = context
        layer.opacity = brightness

        for (lag, radiusScale, alpha) in [(0.42, 0.50, 0.12), (0.28, 0.62, 0.20), (0.14, 0.78, 0.32)] {
            let point = position(lag)
            layer.fill(Self.circle(point.x, point.y, fly.r * radiusScale),
                       with: .color(PW.dawnGlow.opacity(alpha)))
        }
        let head = position(0)
        layer.fill(Self.circle(head.x, head.y, fly.r * 3.2),
                   with: .color(PW.dawnGlow.opacity(0.16)))
        layer.fill(Self.circle(head.x, head.y, fly.r), with: .color(PW.dawnGlow))
    }

    /// Lit for 22% of a per-fly period, dark the rest — fireflies blink rarely.
    private static func blink(time: Double, phase: Double) -> Double {
        let period = 6.5 + phase.truncatingRemainder(dividingBy: 2.4)
        let cycle = (time / period + phase * 0.37).truncatingRemainder(dividingBy: 1)
        let wrapped = cycle < 0 ? cycle + 1 : cycle
        guard wrapped < 0.22 else { return 0 }
        return sin(wrapped / 0.22 * .pi)
    }

    private static func circle(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
    }
}
```

- [ ] **Step 2: Build to verify it compiles**

Run the build command.
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 3: Commit**

```bash
git add Paperweight/Views/Scenes/DioramaScene.swift
git commit -m "feat: add the Diorama locked-Home scene"
```

---

### Task 5: The Overgrown scene

The screen is claimed at its corners by procedural fir-frond sprigs — a stem drawing itself in, then leaflets popping in order along it.

**Files:**
- Create: `Paperweight/Views/Scenes/OvergrownScene.swift`

**Interfaces:**
- Consumes: `PWMotion.crawl(index:count:lock:)`, `PWMotion.grow(_:)`, `PWMotion.ramp(_:_:_:)`, `PWMotion.sway(at:phase:)`, the `PW` forest palette.
- Produces: `OvergrownScene(lock: Double, time: Double)` — a `View`. Task 7 renders it.

Design space is 480 wide × 400 tall for the top-right cluster and 340 × 260 for the bottom-left, each anchored to its own corner. Both are drawn in one `Canvas` sized to the view.

- [ ] **Step 1: Write the view**

Create `Paperweight/Views/Scenes/OvergrownScene.swift`:

```swift
import SwiftUI

/// "The screen is claimed at its corners."
///
/// Each sprig is one quadratic Bézier stem that draws itself in, then sprouts
/// tapered leaflets in order along its length. Back groups sit dimmer and sway
/// less than the front ones, which is the whole depth cue.
struct OvergrownScene: View {
    var lock: Double = 1
    var time: Double = 0

    /// A single frond. `slot` is its place in the 11-step crawl order.
    private struct Sprig {
        let p0: CGPoint, p1: CGPoint, p2: CGPoint
        let leaflets: Int
        let size: CGFloat
        let slot: Int
        let phase: Double
        let flip: CGFloat
        let colors: [Color]
        let stem: Color
        let bud: Bool
    }

    private static let topRightSize = CGSize(width: 480, height: 400)
    private static let bottomLeftSize = CGSize(width: 340, height: 260)

    private static var topRightBack: [Sprig] {
        [
            Sprig(p0: .init(x: 484, y: -8), p1: .init(x: 370, y: 60), p2: .init(x: 250, y: 180),
                  leaflets: 11, size: 21, slot: 0, phase: 0.5, flip: 1,
                  colors: [PW.treeMid, PW.bush], stem: PW.trunk, bud: false),
            Sprig(p0: .init(x: 476, y: 40), p1: .init(x: 430, y: 180), p2: .init(x: 400, y: 320),
                  leaflets: 9, size: 18, slot: 1, phase: 2.8, flip: -1,
                  colors: [PW.treeMid, PW.bush], stem: PW.trunk, bud: false),
            Sprig(p0: .init(x: 460, y: 220), p1: .init(x: 370, y: 280), p2: .init(x: 260, y: 330),
                  leaflets: 9, size: 16, slot: 2, phase: 4.6, flip: 1,
                  colors: [PW.bush, PW.treeMid], stem: PW.trunk, bud: false),
        ]
    }

    private static var topRightFront: [Sprig] {
        [
            Sprig(p0: .init(x: 482, y: -4), p1: .init(x: 400, y: 40), p2: .init(x: 300, y: 120),
                  leaflets: 12, size: 17, slot: 3, phase: 0, flip: 1,
                  colors: [PW.treeFront, PW.moss], stem: PW.stem, bud: true),
            Sprig(p0: .init(x: 472, y: 0), p1: .init(x: 452, y: 120), p2: .init(x: 430, y: 244),
                  leaflets: 10, size: 14, slot: 4, phase: 2.1, flip: -1,
                  colors: [PW.moss, PW.mossLight], stem: PW.stem, bud: true),
            Sprig(p0: .init(x: 446, y: 152), p1: .init(x: 372, y: 202), p2: .init(x: 292, y: 240),
                  leaflets: 8, size: 12, slot: 5, phase: 4.0, flip: 1,
                  colors: [PW.mossLight, PW.moss], stem: PW.stem, bud: true),
            Sprig(p0: .init(x: 462, y: 58), p1: .init(x: 420, y: 84), p2: .init(x: 376, y: 106),
                  leaflets: 5, size: 9, slot: 6, phase: 1.1, flip: -1,
                  colors: [PW.mossLight, PW.sage], stem: PW.stem, bud: true),
            Sprig(p0: .init(x: 474, y: 262), p1: .init(x: 400, y: 312), p2: .init(x: 310, y: 346),
                  leaflets: 8, size: 12, slot: 7, phase: 5.2, flip: -1,
                  colors: [PW.moss, PW.treeFront], stem: PW.stem, bud: true),
        ]
    }

    private static var bottomLeftBack: [Sprig] {
        [
            Sprig(p0: .init(x: -8, y: 266), p1: .init(x: 90, y: 258), p2: .init(x: 204, y: 240),
                  leaflets: 9, size: 15, slot: 8, phase: 3.9, flip: -1,
                  colors: [PW.treeMid, PW.bush], stem: PW.trunk, bud: false),
        ]
    }

    private static var bottomLeftFront: [Sprig] {
        [
            Sprig(p0: .init(x: -4, y: 264), p1: .init(x: 70, y: 240), p2: .init(x: 152, y: 192),
                  leaflets: 10, size: 13, slot: 9, phase: 1.3, flip: -1,
                  colors: [PW.moss, PW.treeFront], stem: PW.stem, bud: true),
            Sprig(p0: .init(x: 0, y: 252), p1: .init(x: 40, y: 192), p2: .init(x: 82, y: 132),
                  leaflets: 7, size: 10, slot: 10, phase: 3.3, flip: 1,
                  colors: [PW.mossLight, PW.moss], stem: PW.stem, bud: true),
        ]
    }

    var body: some View {
        Canvas { context, size in
            let swayTopRight = PWMotion.sway(at: time, phase: 0.6) * lock
            let swayBottomLeft = PWMotion.sway(at: time, phase: 3.1) * lock

            // Top-right cluster, anchored to the top-right corner.
            var topRight = context
            topRight.translateBy(x: size.width - Self.topRightSize.width, y: 0)
            draw(&topRight, Self.topRightBack, opacity: 0.85,
                 rotation: swayTopRight * 0.6, about: CGPoint(x: 480, y: 0))
            draw(&topRight, Self.topRightFront, opacity: 1,
                 rotation: swayTopRight, about: CGPoint(x: 480, y: 0))

            // Bottom-left cluster, anchored to the bottom-left corner.
            var bottomLeft = context
            bottomLeft.translateBy(x: 0, y: size.height - Self.bottomLeftSize.height)
            draw(&bottomLeft, Self.bottomLeftBack, opacity: 0.85,
                 rotation: swayBottomLeft * 0.6, about: CGPoint(x: 0, y: 260))
            draw(&bottomLeft, Self.bottomLeftFront, opacity: 1,
                 rotation: swayBottomLeft, about: CGPoint(x: 0, y: 260))
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func draw(_ context: inout GraphicsContext, _ sprigs: [Sprig],
                      opacity: Double, rotation: Double, about pivot: CGPoint) {
        var layer = context
        layer.opacity = opacity
        layer.translateBy(x: pivot.x, y: pivot.y)
        layer.rotate(by: .degrees(rotation))
        layer.translateBy(x: -pivot.x, y: -pivot.y)
        for sprig in sprigs { drawSprig(&layer, sprig) }
    }

    private func drawSprig(_ context: inout GraphicsContext, _ sprig: Sprig) {
        let grown = PWMotion.crawl(index: sprig.slot, count: 11, lock: lock)
        guard grown > 0.001 else { return }

        // The stem draws itself in over the first 70% of the sprig's growth.
        let stemProgress = min(grown / 0.7, 1)
        var stem = Path()
        stem.move(to: sprig.p0)
        stem.addQuadCurve(to: sprig.p2, control: sprig.p1)
        context.stroke(
            stem.trimmedPath(from: 0, to: stemProgress),
            with: .color(sprig.stem),
            style: StrokeStyle(lineWidth: 3, lineCap: .round))

        let slots = max(sprig.leaflets - 1, 1)
        for index in 0..<sprig.leaflets {
            let u = 0.14 + 0.8 * (Double(index) / Double(slots))
            // Leaflets trail the stem tip and pop in order along it.
            let opened = PWMotion.grow(PWMotion.ramp(grown - 0.7 * u, 0, 0.3))
                * min(max((stemProgress - u) * 10, 0), 1)
            guard opened > 0.001 else { continue }

            let point = Self.point(sprig, at: u)
            let angle = Self.tangentDegrees(sprig, at: u)
            let side = (index % 2 == 1 ? 1 : -1) * sprig.flip
            let leafSize = sprig.size * (1 - 0.5 * CGFloat(Double(index) / Double(slots)))

            var leaf = context
            leaf.translateBy(x: point.x, y: point.y)
            leaf.rotate(by: .degrees(angle + Double(side) * 52))
            leaf.scaleBy(x: opened, y: opened)
            leaf.fill(
                Path(ellipseIn: CGRect(x: leafSize * 0.95 - leafSize, y: -leafSize * 0.34,
                                       width: leafSize * 2, height: leafSize * 0.68)),
                with: .color(sprig.colors[index % sprig.colors.count]))
        }

        if sprig.bud {
            let tip = PWMotion.grow(PWMotion.ramp(grown, 0.75, 1))
            let pulse = 0.55 + 0.45 * sin(2 * .pi * time / 4.2 + sprig.phase)
            let radius = sprig.size * 0.42
            context.fill(
                Path(ellipseIn: CGRect(x: sprig.p2.x - radius, y: sprig.p2.y - radius,
                                       width: radius * 2, height: radius * 2)),
                with: .color(PW.dawnGlow.opacity(tip * pulse)))
        }
    }

    /// Point on the quadratic Bézier at `u`.
    private static func point(_ sprig: Sprig, at u: Double) -> CGPoint {
        let t = CGFloat(u)
        let a = (1 - t) * (1 - t), b = 2 * (1 - t) * t, c = t * t
        return CGPoint(x: a * sprig.p0.x + b * sprig.p1.x + c * sprig.p2.x,
                       y: a * sprig.p0.y + b * sprig.p1.y + c * sprig.p2.y)
    }

    /// Tangent direction on the curve at `u`, in degrees.
    private static func tangentDegrees(_ sprig: Sprig, at u: Double) -> Double {
        let t = CGFloat(u)
        let dx = 2 * (1 - t) * (sprig.p1.x - sprig.p0.x) + 2 * t * (sprig.p2.x - sprig.p1.x)
        let dy = 2 * (1 - t) * (sprig.p1.y - sprig.p0.y) + 2 * t * (sprig.p2.y - sprig.p1.y)
        return atan2(Double(dy), Double(dx)) * 180 / .pi
    }
}
```

Note: the SVG original animated the stem with `strokeDasharray`/`strokeDashoffset` and therefore needed the curve's arc length. `Path.trimmedPath(from:to:)` does the same job without it, so no length calculation appears here.

- [ ] **Step 2: Build to verify it compiles**

Run the build command.
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 3: Commit**

```bash
git add Paperweight/Views/Scenes/OvergrownScene.swift
git commit -m "feat: add the Overgrown locked-Home scene"
```

---

### Task 6: The scene picker

**Files:**
- Modify: `Shared/ViewModels/HomeViewModel.swift`
- Modify: `Paperweight/Views/SettingsView.swift`
- Create: `Paperweight/Views/LockedScenePicker.swift`

**Interfaces:**
- Consumes: `LockedScene`, `HomeViewModel`, `GroupedCard`, `NavRow`, `CardDivider`, `pwScreenLabel()`, `pwScreen()`.
- Produces: `HomeViewModel.saveConfig()`, and `LockedScenePicker(vm: HomeViewModel)` — a pushed screen.

- [ ] **Step 1: Give the view-model a plain persist**

`HomeViewModel`'s only public persist today is `saveSelection()`, which also calls `syncRestrictions()` — reapplying the shield. That is wrong for a purely cosmetic setting, so add a persist that just writes.

In `Shared/ViewModels/HomeViewModel.swift`, add directly after `saveSelection()`:

```swift
    /// Persists a change that cannot affect what is restricted — unlike
    /// `saveSelection()`, this deliberately does not resync the shield.
    func saveConfig() {
        try? configStore.save(config)
        publishWidgetSnapshot()
    }
```

- [ ] **Step 2: Write the picker**

Create `Paperweight/Views/LockedScenePicker.swift`:

```swift
import SwiftUI

/// Picks the artwork the locked Home draws. Cosmetic only — nothing here changes
/// what is restricted, which is why it is editable even while Paperweight is on.
struct LockedScenePicker: View {
    @ObservedObject var vm: HomeViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Style").pwScreenLabel()
                    .padding(.top, 6).padding(.bottom, 10)

                GroupedCard {
                    ForEach(Array(LockedScene.allCases.enumerated()), id: \.element.id) { index, scene in
                        if index > 0 { CardDivider() }
                        Button {
                            vm.config.lockedScene = scene
                            vm.saveConfig()
                        } label: {
                            row(for: scene)
                        }
                        .buttonStyle(.plain)
                    }
                }

                Text("Shown only while apps are quiet.")
                    .font(.grotesk(13))
                    .foregroundStyle(PW.textFaint)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 18)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 30)
        }
        .scrollContentBackground(.hidden)
        .pwScreen()
        .navigationTitle("Locked screen")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(for scene: LockedScene) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(scene.title)
                    .font(.grotesk(15))
                    .foregroundStyle(PW.textPrimary)
                Text(scene.blurb)
                    .font(.grotesk(13))
                    .foregroundStyle(PW.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if vm.config.lockedScene == scene {
                Image(systemName: "checkmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(PW.sage)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }
}
```

- [ ] **Step 3: Add the row to Settings**

In `Paperweight/Views/SettingsView.swift`, inside the "Configure" `GroupedCard`, add after the `NFCSetupView` `NavigationLink` and its following `CardDivider()`:

```swift
                    NavigationLink { LockedScenePicker(vm: vm) } label: {
                        NavRow(title: "Locked screen", value: vm.config.lockedScene.title)
                    }
                    CardDivider()
```

Place it so the group reads: Schedule · NFC Token & Recovery · Locked screen · Emergency unlock.

- [ ] **Step 4: Build to verify it compiles**

Run the build command.
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 5: Commit**

```bash
git add Shared/ViewModels/HomeViewModel.swift Paperweight/Views/LockedScenePicker.swift Paperweight/Views/SettingsView.swift
git commit -m "feat: let the user pick the locked-screen scene"
```

---

### Task 7: Wire the scene into Home

**Files:**
- Modify: `Paperweight/Views/HomeView.swift`

**Interfaces:**
- Consumes: `LockedScene`, `SimpleScene`, `DioramaScene`, `OvergrownScene`, `PWMotion.settle(_:)`.

- [ ] **Step 1: Add the scene slot**

In `Paperweight/Views/HomeView.swift`, replace this line inside `lockedState`:

```swift
                SimpleScene()
                    .frame(maxHeight: .infinity)
```

with:

```swift
                lockedScene
                    .frame(maxHeight: .infinity)
```

- [ ] **Step 2: Add the scene renderer and its clock**

Add these members to `HomeView`, just below the `lockedState` property:

```swift
    /// The chosen artwork, driven by its own clock.
    ///
    /// `TimelineView(.animation)` is capped at 30fps and stops entirely when the
    /// app is not active — a scene that sways forever would otherwise redraw at
    /// display rate behind a locked phone, which is the opposite of the point.
    @ViewBuilder
    private var lockedScene: some View {
        if scenePhase == .active {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { context in
                scene(at: context.date.timeIntervalSince(sceneEpoch))
            }
        } else {
            scene(at: 0)
        }
    }

    @ViewBuilder
    private func scene(at time: Double) -> some View {
        // The lock has already landed by the time Home is on screen, so the
        // scene rests at full growth rather than replaying its sprout.
        let lock = PWMotion.settle(sceneLock)
        switch vm.config.lockedScene {
        case .simple:    SimpleScene(lock: lock)
        case .diorama:   DioramaScene(lock: lock, time: time)
        case .overgrown: OvergrownScene(lock: lock, time: time)
        }
    }
```

- [ ] **Step 3: Add the supporting state**

Alongside the other `@State` properties near the top of `HomeView`, add:

```swift
    /// Fixed origin for the scene clock, so sway and blink phases are stable
    /// across redraws rather than restarting whenever the body re-evaluates.
    @State private var sceneEpoch = Date()
    /// Drives the sprout. Animates 0 → 1 once when the quiet window begins.
    @State private var sceneLock: Double = 0
```

- [ ] **Step 4: Grow the scene in when the lock lands**

Add these two modifiers to the `Group` in `body`, directly after the existing `.navigationDestination(...)` line:

```swift
            .onAppear {
                // Already quiet at launch: show the grown scene without replaying
                // the sprout, which would look like the lock just happened.
                sceneLock = isQuiet ? 1 : 0
            }
            .onChange(of: isQuiet) { _, quiet in
                withAnimation(.easeOut(duration: quiet ? 1.6 : 0.8)) {
                    sceneLock = quiet ? 1 : 0
                }
            }
```

- [ ] **Step 5: Build and run the full test suite**

Run the build command, then the test command.
Expected: `BUILD SUCCEEDED`, then all tests PASS (the suite gained `PWMotionTests` and `LockedSceneTests` in this PR).

- [ ] **Step 6: Verify what you can on the simulator**

Interactive simulator control may not be available. Do what you can with `xcrun simctl` and report honestly which of these you actually observed and which you could not:
1. The app launches and Home renders without a crash.
2. Settings shows a "Locked screen" row whose value reads "Diorama".
3. Opening it lists Simple, Diorama, and Overgrown with a checkmark on Diorama.
4. Choosing a different style updates the row value and persists across a relaunch.

Do not claim a check passed unless you observed it.

- [ ] **Step 7: Commit**

```bash
git add Paperweight/Views/HomeView.swift
git commit -m "feat: draw the chosen scene on the locked Home"
```

---

### Task 8: Open the pull request

**Files:** none.

- [ ] **Step 1: Create the issue**

```bash
gh issue create --title "Draw the locked screen's scene, with a style to choose" --body "The locked Home currently shows one line of text where the design has artwork. App Screens v2 asks for three styles — Simple, Diorama and Overgrown — with the user picking which one, defaulting to Diorama.

The Motion Study defines all three and the motion grammar behind them: settle, growth, rest and release.

Spec: docs/superpowers/specs/2026-08-01-app-screens-v2-design.md section 4"
```

- [ ] **Step 2: Push and open the PR**

Replace `<N>` with the issue number from Step 1:

```bash
git push -u origin feat/app-screens-v2-scenes
gh pr create --title "Draw the locked screen's scene, with a style to choose" --body "$(cat <<'EOF'
Stage 2 of 4 of the App Screens v2 redesign. The locked Home gets its artwork.

The motion grammar lands first as pure math in `Shared/Motion/PWMotion.swift` — settle, grow, sway, and the staggered growth that makes a scene fill in back to front. It has no SwiftUI in it, so it is unit-tested directly rather than eyeballed.

Three styles, picked in Settings and defaulting to Diorama:

- **Simple** — the words carry the weight.
- **Diorama** — four pines, three blob trees and five fireflies, with the canopies swaying and the flies blinking on their own rare cycles.
- **Overgrown** — procedural fir-frond sprigs claiming the top-right and bottom-left corners, each stem drawing itself in before its leaflets pop in order along it.

Both drawn scenes are `Canvas` views taking only `(lock:time:)` — no schedule, no view-model, no state of their own.

### Worth a look during review

- **Battery.** The scenes never stop moving, so the clock is capped at 30fps and stops entirely when the app is not active. A sway that redraws at display rate behind a locked phone would be the opposite of the point.
- **The scene does not replay its sprout on every appearance.** If Home opens while already quiet, the scene starts grown. It only animates in when the quiet window actually begins.
- The stored preference is cosmetic and never affects what is restricted, so the picker stays editable while Paperweight is on.

Closes #<N>

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

---

## Notes for later PRs

- **PR 3** inverts `ScheduleView` to green-means-quiet and adds deferred loosening. `quietHourCount` already exists from PR 1.
- **PR 4** restyles the NFC/Recovery, Emergency unlock, Turn-off sheet, and Recovery codes screens.
