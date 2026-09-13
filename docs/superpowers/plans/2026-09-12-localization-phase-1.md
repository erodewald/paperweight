# Localization Phase 1 (Framework) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Every user-facing string in Paperweight is translatable through one shared String Catalog, every hand-built English formatting path is locale-correct, tests are pinned to English, and CI fails when the catalog drifts from the code. Ships English only.

**Architecture:** One `Shared/Resources/Localizable.xcstrings` carried by the app, monitor and widget; only the app target emits `.stringsdata`, and `Scripts/strings-sync.sh` merges it into the catalog with `xcstringstool sync`. Shared copy functions take `calendar:` and `locale:` and look strings up in `L10n.bundle`, which unit tests point at the test bundle. Weekdays, hours and durations come from Foundation formatters; plurals come from catalog variations.

**Tech Stack:** Swift 5.9, SwiftUI, iOS 17, XcodeGen, Xcode 26 `xcstringstool`, XCTest, Python 3.9 standard library (lint), GitHub Actions.

Spec: `docs/superpowers/specs/2026-09-12-localization-design.md`. Branch: `feat/localization` (already exists with the spec).

## Global Constraints

- Copy rules: the state words are **quiet** and **open**; never "blocked", "free", "banned", "locked out". "Restricted apps" as the name of the chosen set stays. No exclamation marks. Calm, second person.
- "Paperweight" is never translated. "token" is the NFC tag. "cool-off" is the multi-day tokenless unlock.
- One key per sentence; never build a sentence from fragments. Interpolated plain `String`s go through `String(localized:bundle:locale:comment:)`.
- Every shared copy function takes `calendar: Calendar = .current, locale: Locale = .current`; views pass nothing; tests pass `TestLocale.en` and `TestLocale.calendar`.
- Storage stays Sunday-based (`weekdayIndex` 0 = Sunday); only display order follows `calendar.firstWeekday`.
- Lock Screen accessory strings stay ≤ 24 characters in English; their keys carry `comment: "Lock Screen; keep under 24 characters"`.
- Only the app target sets `SWIFT_EMIT_LOC_STRINGS = YES`. The sync feeds `xcstringstool` only `Debug-iphonesimulator/Paperweight.build/**/*.stringsdata`.
- No new dependencies. Python scripts use the standard library only.
- Widget target must never link FamilyControls; its source list stays file-by-file.
- Tests: `xcodebuild test -project Paperweight.xcodeproj -scheme PaperweightTests -destination "platform=iOS Simulator,name=iPhone 17 Pro" CODE_SIGNING_ALLOWED=NO` (regenerate with `xcodegen generate` after any `project.yml` change). 223 tests pass at the start.
- Commit messages end with `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`.

---

## File map

Create:
- `Shared/Resources/Localizable.xcstrings` — the one catalog, committed, synced by script.
- `Paperweight/InfoPlist.xcstrings`, `PaperweightMonitor/InfoPlist.xcstrings`, `PaperweightWidget/InfoPlist.xcstrings` — display names and the NFC usage text.
- `Shared/Localization.swift` — `L10n.bundle`.
- `PaperweightTests/TestSupport/TestLocale.swift` — pinned locale, calendar, bundle hook.
- `PaperweightTests/Models/L10nTests.swift`, `PaperweightTests/Models/ScheduleLabelTests.swift`.
- `Scripts/strings-sync.sh` — build app target, `xcstringstool sync`, `--check` mode for CI.
- `Scripts/strings-check.py` + `Scripts/tests/test_strings_check.py` — catalog lint.
- `docs/LOCALIZATION.md`.

Modify:
- `project.yml`, `.github/workflows/ci.yml`.
- Shared: `Models/WidgetSnapshot.swift`, `Models/HomeCopy.swift`, `Models/DayException+Labels.swift`, `Models/PaperweightSchedule.swift`, `Models/NFCError.swift`, `Models/UnlockError.swift`.
- App: `Views/ScheduleView.swift`, `Views/AddDayExceptionSheet.swift`, `Views/Components/WeekStrip.swift`, `Views/DayExceptionsView.swift`, `Views/HomeView.swift`, `Views/UnlockView.swift`, `Views/NFCSetupView.swift`, `Views/DisablePaperweightSheet.swift`, `Views/RecoveryCodesView.swift`, `Views/SettingsView.swift`, `Views/QuietThemePicker.swift`, `Views/NFCBuyingGuideView.swift`, `Views/Components/QuietGlassControls.swift`, `Extensions/FamilyActivitySelection+Summary.swift`, `Services/NFCService.swift`.
- Widget: `PaperweightWidgetBundle.swift`, `PaperweightWidgetViews.swift`.
- Tests: `Models/HomeCopyTests.swift`, `Models/WidgetSnapshotTests.swift`, `Models/DayExceptionLabelTests.swift`.

---

### Task 1: Catalog, project wiring, sync script, bundle hook

**Files:**
- Create: `Shared/Resources/Localizable.xcstrings`, `Paperweight/InfoPlist.xcstrings`, `PaperweightMonitor/InfoPlist.xcstrings`, `PaperweightWidget/InfoPlist.xcstrings`, `Shared/Localization.swift`, `PaperweightTests/TestSupport/TestLocale.swift`, `PaperweightTests/Models/L10nTests.swift`, `Scripts/strings-sync.sh`
- Modify: `project.yml:3-13` (options), `project.yml:65-70` (app settings), `project.yml:117-131` (widget sources)

**Interfaces:**
- Produces: `enum L10n { static var bundle: Bundle }` in Shared; `enum TestLocale { static let en: Locale; static var calendar: Calendar; static func useTestBundle() }` in tests; `Scripts/strings-sync.sh [--check]`.

- [ ] **Step 1: Write the failing test**

Create `PaperweightTests/TestSupport/TestLocale.swift`:

```swift
import Foundation

/// The fixed frame every copy test uses, so nothing depends on the simulator's
/// language. The time zone stays the simulator's on purpose: `state(at:)` and
/// friends default to `Calendar.current`, and a test date built in another zone
/// would land on a different half-hour than the one the test names.
enum TestLocale {
    static let en = Locale(identifier: "en_US")

    static var calendar: Calendar {
        var c = Calendar.current
        c.locale = en
        c.firstWeekday = 1
        return c
    }

    /// Unit tests have no host app, so `Bundle.main` is the test runner. Point
    /// string lookups at the test bundle, which carries the compiled catalog.
    static func useTestBundle() {
        L10n.bundle = Bundle(for: BundleAnchor.self)
    }

    private final class BundleAnchor {}
}
```

Create `PaperweightTests/Models/L10nTests.swift`:

```swift
import XCTest

final class L10nTests: XCTestCase {
    override func setUp() { TestLocale.useTestBundle() }

    /// The shared catalog must compile into the test bundle, or every plural
    /// and every translated string silently falls back to its key.
    func test_testBundleCarriesTheCompiledCatalog() {
        let bundle = L10n.bundle
        let strings = bundle.url(forResource: "Localizable", withExtension: "strings", subdirectory: "en.lproj")
        let loctable = bundle.url(forResource: "Localizable", withExtension: "loctable")
        XCTAssertTrue(strings != nil || loctable != nil, "no compiled Localizable table in \(bundle.bundlePath)")
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `xcodegen generate && xcodebuild test -project Paperweight.xcodeproj -scheme PaperweightTests -destination "platform=iOS Simulator,name=iPhone 17 Pro" -only-testing:PaperweightTests/L10nTests CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "error:|passed|failed"`
Expected: compile error `cannot find 'L10n' in scope`.

- [ ] **Step 3: Add the bundle hook**

Create `Shared/Localization.swift`:

```swift
import Foundation

/// Where localized strings are looked up. The app and its extensions use their
/// own main bundle, which carries the shared catalog. Unit tests have no host
/// app, so they point this at the test bundle in `setUp`.
enum L10n {
    static var bundle: Bundle = .main
}
```

- [ ] **Step 4: Create the catalogs**

`Shared/Resources/Localizable.xcstrings`:

```json
{
  "sourceLanguage" : "en",
  "strings" : {

  },
  "version" : "1.0"
}
```

`Paperweight/InfoPlist.xcstrings`:

```json
{
  "sourceLanguage" : "en",
  "strings" : {
    "CFBundleDisplayName" : {
      "extractionState" : "manual",
      "localizations" : {
        "en" : { "stringUnit" : { "state" : "translated", "value" : "Paperweight" } }
      }
    },
    "NFCReaderUsageDescription" : {
      "extractionState" : "manual",
      "localizations" : {
        "en" : { "stringUnit" : { "state" : "translated", "value" : "Paperweight uses NFC to read your unlock token." } }
      }
    }
  },
  "version" : "1.0"
}
```

`PaperweightMonitor/InfoPlist.xcstrings` (value `Paperweight Monitor`) and `PaperweightWidget/InfoPlist.xcstrings` (value `Paperweight`): same shape with only the `CFBundleDisplayName` entry.

- [ ] **Step 5: Wire project.yml**

In `options:` add after `groupSortPosition: top`:

```yaml
  developmentLanguage: en
```

In the `Paperweight` target's `settings.base`, after `ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon`:

```yaml
        # The app compiles every view and every shared file, so its build alone
        # sees every string. Scripts/strings-sync.sh merges the .stringsdata it
        # emits into Shared/Resources/Localizable.xcstrings. The extensions only
        # carry the catalog; they never extract.
        SWIFT_EMIT_LOC_STRINGS: YES
```

In the `PaperweightWidget` target's `sources`, after `- path: Shared/Store/WidgetSnapshotStore.swift`:

```yaml
      - path: Shared/Resources/Localizable.xcstrings
```

and after `- path: Shared/Constants.swift` (the widget compiles `WidgetSnapshot.swift`, which reads `L10n.bundle`; `Localization.swift` is Foundation-only):

```yaml
      - path: Shared/Localization.swift
```

- [ ] **Step 6: Write the sync script**

Create `Scripts/strings-sync.sh` and `chmod +x` it:

```bash
#!/usr/bin/env bash
# Merges the strings the compiler saw into the shared String Catalog.
#
#   Scripts/strings-sync.sh          rebuild the app target, update the catalog
#   Scripts/strings-sync.sh --check  same, but into a copy; fail if it differs
#                                    from the committed catalog (CI)
#
# Only the app target's .stringsdata is used: it compiles every view and every
# shared file. Feeding the widget's or monitor's would mark every shared key
# they don't compile as stale.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

CATALOG=Shared/Resources/Localizable.xcstrings
DERIVED=.build/strings-sync
TOOL="$(xcode-select -p)/usr/bin/xcstringstool"
MODE="${1:-sync}"

[ -d Paperweight.xcodeproj ] || xcodegen generate

sim=$(xcrun simctl list devices available \
      | grep -oE 'iPhone [A-Za-z0-9][A-Za-z0-9 ]*' | sed 's/ *$//' | head -1 || true)
[ -n "$sim" ] || { echo "No iPhone simulator available" >&2; exit 1; }

xcodebuild build \
  -project Paperweight.xcodeproj -scheme Paperweight \
  -destination "platform=iOS Simulator,name=$sim" \
  -derivedDataPath "$DERIVED" CODE_SIGNING_ALLOWED=NO -quiet

files=()
while IFS= read -r f; do files+=("$f"); done < <(
  find "$DERIVED/Build/Intermediates.noindex" \
       -path "*/Debug-iphonesimulator/Paperweight.build/*" -name "*.stringsdata" | sort)
[ "${#files[@]}" -gt 0 ] || { echo "No .stringsdata found; is SWIFT_EMIT_LOC_STRINGS on?" >&2; exit 1; }

target="$CATALOG"
if [ "$MODE" = "--check" ]; then
  target="$(mktemp -d)/Localizable.xcstrings"
  cp "$CATALOG" "$target"
fi

"$TOOL" sync "$target" --stringsdata "${files[@]}"

python3 - "$target" <<'EOF'
import json, sys
d = json.load(open(sys.argv[1]))
stale = sorted(k for k, v in d["strings"].items() if v.get("extractionState") == "stale")
print(f"{len(d['strings'])} keys, {len(stale)} stale")
for k in stale: print(f"  stale: {k!r}")
EOF

if [ "$MODE" = "--check" ]; then
  if ! diff -u "$CATALOG" "$target"; then
    echo "::error::Localizable.xcstrings is out of date. Run Scripts/strings-sync.sh and commit." >&2
    exit 1
  fi
  echo "Catalog is in sync with the code."
fi
```

- [ ] **Step 7: Sync and run the test**

Run: `xcodegen generate && Scripts/strings-sync.sh`
Expected: `NNN keys, 0 stale` (about 114), and `git diff --stat` shows the catalog grew.

Run the L10n test from Step 2. Expected: PASS.

Run the full suite. Expected: 224 tests pass (223 + 1).

- [ ] **Step 8: Build all three targets**

Run: `xcodebuild build -project Paperweight.xcodeproj -scheme Paperweight -destination "platform=iOS Simulator,name=iPhone 17 Pro" CODE_SIGNING_ALLOWED=NO -quiet && echo BUILD OK`
Expected: `BUILD OK`. Then confirm the widget carries the catalog: `ls ~/Library/Developer/Xcode/DerivedData/Paperweight-*/Build/Products/Debug-iphonesimulator/Paperweight.app/PlugIns/PaperweightWidget.appex/en.lproj/` lists `Localizable.strings`.

- [ ] **Step 9: Commit**

```bash
git add project.yml Shared/Resources Shared/Localization.swift Paperweight/InfoPlist.xcstrings PaperweightMonitor/InfoPlist.xcstrings PaperweightWidget/InfoPlist.xcstrings Scripts/strings-sync.sh PaperweightTests/TestSupport PaperweightTests/Models/L10nTests.swift
git commit -m "feat(l10n): one shared String Catalog, synced from the app target's build

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 2: Widget and Home copy through the catalog

**Files:**
- Modify: `Shared/Models/WidgetSnapshot.swift:201-377`, `Shared/Models/HomeCopy.swift`
- Test: `PaperweightTests/Models/WidgetSnapshotTests.swift`, `PaperweightTests/Models/HomeCopyTests.swift`
- Modify: `Shared/Resources/Localizable.xcstrings` (plural variation, by hand then re-synced)

**Interfaces:**
- Produces: `WidgetState.copy(at:calendar:locale:)`, `WidgetState.compactDuration(_:locale:)`, `WidgetState.clock(_:calendar:locale:)`, `WidgetState.dayClock(_:from:calendar:locale:abbreviated:)`, `WidgetState.relative(_:from:locale:)`, `HomeCopy.countdown(_:locale:)`, `WidgetCopy.displayName`, `WidgetCopy.widgetDescription`. All new parameters default to `.current`, so existing call sites compile unchanged.

- [ ] **Step 1: Pin the tests to English and add the plural case**

In `PaperweightTests/Models/WidgetSnapshotTests.swift`, add at the top of the class:

```swift
    private let en = TestLocale.en
    private let cal = TestLocale.calendar

    override func setUp() { TestLocale.useTestBundle() }
```

Then change every `state.copy(at: reference)` / `.copy(at: lateSunday)` to pass `calendar: cal, locale: en`, every `WidgetState.compactDuration(x)` to `WidgetState.compactDuration(x, locale: en)`, and line 266 to:

```swift
        XCTAssertEqual(copy.boundaryLine, "Open until \(WidgetState.clock(ends, calendar: cal, locale: en)), then quiet")
```

Add a test that proves the plural rule comes from the catalog, not from code:

```swift
    /// "1 day" and "2 days" are a catalog plural rule, so other languages can
    /// have their own. Fails if the variation is missing from the catalog.
    func test_dayDurations_usePluralRules() {
        XCTAssertEqual(WidgetState.compactDuration(24 * 3600, locale: en), "1 day")
        XCTAssertEqual(WidgetState.compactDuration(48 * 3600, locale: en), "2 days")
        XCTAssertEqual(WidgetState.compactDuration(36 * 3600, locale: en), "1½ days")
    }
```

In `PaperweightTests/Models/HomeCopyTests.swift` add `override func setUp() { TestLocale.useTestBundle() }` and pass `locale: TestLocale.en` to every `HomeCopy.countdown(...)` call.

- [ ] **Step 2: Run the tests to verify they fail**

Run the suite filtered: `-only-testing:PaperweightTests/WidgetSnapshotTests -only-testing:PaperweightTests/HomeCopyTests`
Expected: compile errors (`extra argument 'locale'`).

- [ ] **Step 3: Rewrite the copy section**

Replace `Shared/Models/WidgetSnapshot.swift` lines 201-377 with:

```swift
extension WidgetState {
    func copy(at date: Date, calendar: Calendar = .current, locale: Locale = .current) -> WidgetCopy {
        let b = L10n.bundle
        switch self {
        case .quietBounded(let ends, _):
            let d = WidgetState.compactDuration(ends.timeIntervalSince(date), locale: locale)
            let short = WidgetState.dayClock(ends, from: date, calendar: calendar, locale: locale, abbreviated: true)
            let long = WidgetState.dayClock(ends, from: date, calendar: calendar, locale: locale)
            return WidgetCopy(
                eyebrow: String(localized: "QUIET", bundle: b, locale: locale, comment: "Widget eyebrow, emphasis form"),
                value: .word(d),
                caption: String(localized: "of quiet left", bundle: b, locale: locale, comment: "Follows a duration: '3h 20m of quiet left'"),
                accessoryValue: d,
                accessoryLine: String(localized: "until \(short)", bundle: b, locale: locale, comment: "Lock Screen; keep under 24 characters"),
                boundaryLine: String(localized: "Quiet until \(long)", bundle: b, locale: locale))

        case .quietOpen:
            return WidgetCopy(
                eyebrow: String(localized: "QUIET", bundle: b, locale: locale, comment: "Widget eyebrow, emphasis form"),
                value: .word(String(localized: "Quiet", bundle: b, locale: locale)),
                caption: String(localized: "until you say otherwise", bundle: b, locale: locale),
                accessoryValue: String(localized: "Quiet", bundle: b, locale: locale, comment: "Lock Screen; keep under 24 characters"),
                accessoryLine: String(localized: "no open hours set", bundle: b, locale: locale, comment: "Lock Screen; keep under 24 characters"),
                boundaryLine: String(localized: "Quiet — no open hours set", bundle: b, locale: locale))

        case .freeWindow(let ends, _):
            let d = WidgetState.compactDuration(ends.timeIntervalSince(date), locale: locale)
            let short = WidgetState.dayClock(ends, from: date, calendar: calendar, locale: locale, abbreviated: true)
            let long = WidgetState.dayClock(ends, from: date, calendar: calendar, locale: locale)
            return WidgetCopy(
                eyebrow: String(localized: "OPEN", bundle: b, locale: locale, comment: "Widget eyebrow, emphasis form"),
                value: .word(d),
                caption: String(localized: "before it goes quiet", bundle: b, locale: locale),
                accessoryValue: d,
                accessoryLine: String(localized: "quiet at \(short)", bundle: b, locale: locale, comment: "Lock Screen; keep under 24 characters"),
                boundaryLine: String(localized: "Open until \(long), then quiet", bundle: b, locale: locale))

        case .timedUnlock(let ends, _):
            let short = WidgetState.dayClock(ends, from: date, calendar: calendar, locale: locale, abbreviated: true)
            let long = WidgetState.dayClock(ends, from: date, calendar: calendar, locale: locale)
            return WidgetCopy(
                eyebrow: String(localized: "UNLOCKED", bundle: b, locale: locale, comment: "Widget eyebrow, emphasis form"),
                value: .countdown(to: ends),
                caption: String(localized: "then it closes on its own", bundle: b, locale: locale),
                accessoryValue: WidgetState.compactDuration(ends.timeIntervalSince(date), locale: locale),
                accessoryLine: String(localized: "re-locks \(short)", bundle: b, locale: locale, comment: "Lock Screen; keep under 24 characters"),
                boundaryLine: String(localized: "Unlocked — re-locks at \(long)", bundle: b, locale: locale))

        case .coolOff(let ends, _):
            let d = WidgetState.compactDuration(ends.timeIntervalSince(date), locale: locale)
            let rel = WidgetState.relative(ends, from: date, locale: locale)
            return WidgetCopy(
                eyebrow: String(localized: "COOL-OFF", bundle: b, locale: locale, comment: "Widget eyebrow, emphasis form; the multi-day tokenless unlock"),
                value: .word(d),
                caption: String(localized: "still quiet until then", bundle: b, locale: locale),
                accessoryValue: d,
                accessoryLine: String(localized: "unlocks \(rel)", bundle: b, locale: locale, comment: "Lock Screen; keep under 24 characters; a relative time follows ('in 2 days')"),
                boundaryLine: String(localized: "Quiet until the cool-off lifts \(rel)", bundle: b, locale: locale))

        case .off:
            return WidgetCopy(
                eyebrow: String(localized: "PAPERWEIGHT", bundle: b, locale: locale, comment: "Widget eyebrow; the app name, never translated"),
                value: .word(String(localized: "Off", bundle: b, locale: locale)),
                caption: String(localized: "set it down when you're ready", bundle: b, locale: locale),
                accessoryValue: String(localized: "Off", bundle: b, locale: locale, comment: "Lock Screen; keep under 24 characters"),
                accessoryLine: String(localized: "nothing is quiet", bundle: b, locale: locale, comment: "Lock Screen; keep under 24 characters"),
                boundaryLine: String(localized: "Nothing is quiet right now", bundle: b, locale: locale))

        case .nothingChosen:
            return WidgetCopy(
                eyebrow: String(localized: "PAPERWEIGHT", bundle: b, locale: locale, comment: "Widget eyebrow; the app name, never translated"),
                value: .word(String(localized: "Nothing", bundle: b, locale: locale, comment: "Widget headline: no apps chosen yet")),
                caption: String(localized: "pick what to quiet", bundle: b, locale: locale),
                accessoryValue: String(localized: "Nothing chosen", bundle: b, locale: locale, comment: "Lock Screen; keep under 24 characters"),
                accessoryLine: String(localized: "pick what to quiet", bundle: b, locale: locale, comment: "Lock Screen; keep under 24 characters"),
                boundaryLine: String(localized: "Nothing chosen yet", bundle: b, locale: locale))

        case .noWayBack:
            return WidgetCopy(
                eyebrow: String(localized: "PAPERWEIGHT", bundle: b, locale: locale, comment: "Widget eyebrow; the app name, never translated"),
                value: .word(String(localized: "Not yet", bundle: b, locale: locale, comment: "Widget headline: cannot arm until an unlock method exists")),
                caption: String(localized: "set up a way back first", bundle: b, locale: locale),
                accessoryValue: String(localized: "Not armed", bundle: b, locale: locale, comment: "Lock Screen; keep under 24 characters"),
                accessoryLine: String(localized: "set up a way back", bundle: b, locale: locale, comment: "Lock Screen; keep under 24 characters"),
                boundaryLine: String(localized: "Set up a way back first", bundle: b, locale: locale))

        case .notAuthorized:
            return WidgetCopy(
                eyebrow: String(localized: "PAPERWEIGHT", bundle: b, locale: locale, comment: "Widget eyebrow; the app name, never translated"),
                value: .word(String(localized: "Waiting", bundle: b, locale: locale, comment: "Widget headline: Screen Time permission missing")),
                caption: String(localized: "Screen Time access is off", bundle: b, locale: locale),
                accessoryValue: String(localized: "Waiting", bundle: b, locale: locale, comment: "Lock Screen; keep under 24 characters"),
                accessoryLine: String(localized: "Screen Time is off", bundle: b, locale: locale, comment: "Lock Screen; keep under 24 characters"),
                boundaryLine: String(localized: "Screen Time access is off", bundle: b, locale: locale))

        case .unwritten:
            return WidgetCopy(
                eyebrow: String(localized: "PAPERWEIGHT", bundle: b, locale: locale, comment: "Widget eyebrow; the app name, never translated"),
                value: .none,
                caption: String(localized: "open Paperweight to begin", bundle: b, locale: locale),
                accessoryValue: "—",
                accessoryLine: String(localized: "open Paperweight", bundle: b, locale: locale, comment: "Lock Screen; keep under 24 characters"),
                boundaryLine: String(localized: "Open Paperweight to begin", bundle: b, locale: locale))
        }
    }

    /// The ring's progress value, or nil for states that draw an empty track.
    var ringProgress: Double? {
        switch self {
        case .quietBounded(_, let f), .freeWindow(_, let f),
             .timedUnlock(_, let f), .coolOff(_, let f): return f
        case .quietOpen: return 1
        case .off, .nothingChosen, .noWayBack, .notAuthorized, .unwritten: return nil
        }
    }

    /// SF Symbol shown in place of the leaf, when the state calls for one.
    /// Lock Screen accessories render in `vibrant` mode where colour flattens to
    /// luminance, so glyph and arc geometry — never tint — are what tell states
    /// apart there. The running states keep the leaf and are distinguished by
    /// their arc; every other state gets a glyph of its own.
    var glyph: String? {
        switch self {
        case .timedUnlock: return "lock.open"
        case .coolOff: return "hourglass"
        case .off: return "lock.slash"
        case .nothingChosen: return "app.badge.checkmark"
        case .noWayBack: return "key"
        case .notAuthorized: return "exclamationmark.triangle"
        case .unwritten, .quietBounded, .quietOpen, .freeWindow: return nil
        }
    }

    /// Deep link opened on tap. One target per widget — no sub-regions.
    var url: URL? {
        switch self {
        case .timedUnlock: return URL(string: "paperweight://unlock")
        case .nothingChosen: return URL(string: "paperweight://choose-apps")
        case .noWayBack: return URL(string: "paperweight://unlock-setup")
        default: return URL(string: "paperweight://home")
        }
    }

    // MARK: Formatting

    /// "3h 20m", "3h", "42m" — never zero, since a boundary that has arrived is
    /// a different state, not a zero-length one. Under a day the units come
    /// from Foundation in the locale's own words; past a day it is the app's
    /// day-speak, rounded to the nearest half day, with the plural rule in the
    /// catalog.
    static func compactDuration(_ interval: TimeInterval, locale: Locale = .current) -> String {
        let total = max(60, interval)
        if total >= 24 * 3600 {
            let halves = Int((total / (12 * 3600)).rounded())
            let whole = halves / 2
            if halves % 2 == 1 {
                return String(localized: "\(whole)½ days", bundle: L10n.bundle, locale: locale,
                              comment: "Duration rounded to a half day; ½ is part of the value")
            }
            return String(localized: "\(whole) days", bundle: L10n.bundle, locale: locale,
                          comment: "Duration in whole days; has a plural rule")
        }
        let hours = Int(total) / 3600
        let minutes = max(hours > 0 ? 0 : 1, (Int(total) % 3600) / 60)
        return Duration.seconds(hours * 3600 + minutes * 60)
            .formatted(.units(allowed: [.hours, .minutes], width: .narrow).locale(locale))
    }

    static func clock(_ date: Date, calendar: Calendar = .current, locale: Locale = .current) -> String {
        date.formatted(Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone).hour().minute())
    }

    /// `clock`, qualified by day whenever the boundary isn't today.
    ///
    /// A bare "02:00" is read as *tonight* — which is right most of the time and
    /// wrong in exactly the case that matters: a Friday evening looking down the
    /// barrel of a free window that runs until Sunday. "Open until 02:00" then
    /// promises quiet in three hours when it's really two and a half days out.
    ///
    /// The comparison is calendar days, not elapsed hours, so 23:50 → 00:10 is
    /// "tomorrow" (it is) while 09:00 → 22:00 stays bare (it's still today).
    /// `abbreviated` is for the Lock Screen rectangular line, which has room for
    /// about 24 characters and no more.
    static func dayClock(_ date: Date, from now: Date,
                         calendar: Calendar = .current,
                         locale: Locale = .current,
                         abbreviated: Bool = false) -> String {
        let time = clock(date, calendar: calendar, locale: locale)
        let days = calendar.dateComponents([.day],
                                           from: calendar.startOfDay(for: now),
                                           to: calendar.startOfDay(for: date)).day ?? 0
        switch days {
        case ..<1:
            return time
        case 1:
            return abbreviated
                ? String(localized: "\(time) tmrw", bundle: L10n.bundle, locale: locale,
                         comment: "Lock Screen; a time then 'tomorrow' shortened; keep under 24 characters")
                : String(localized: "\(time) tomorrow", bundle: L10n.bundle, locale: locale,
                         comment: "A time, then the word tomorrow")
        default:
            // A weekly schedule never points more than 7 days out, so the
            // weekday alone is unambiguous.
            let style = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
                .weekday(abbreviated ? .abbreviated : .wide)
            let weekday = date.formatted(style)
            return String(localized: "\(time) \(weekday)", bundle: L10n.bundle, locale: locale,
                          comment: "A time and a weekday name; reorder freely")
        }
    }

    static func relative(_ date: Date, from now: Date, locale: Locale = .current) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = locale
        formatter.dateTimeStyle = .named
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: now)
    }
}
```

Then add to the `WidgetCopy` struct (after `var boundaryLine: String`):

```swift
    /// The widget gallery's name and one-line description. Kept here, in a file
    /// the app compiles, so the app target's build extracts them; the widget
    /// target never extracts.
    static var displayName: String {
        String(localized: "Paperweight", bundle: L10n.bundle, comment: "Widget gallery name; the app name, never translated")
    }
    static var widgetDescription: String {
        String(localized: "How long the quiet lasts.", bundle: L10n.bundle, comment: "Widget gallery description")
    }
```

Replace `Shared/Models/HomeCopy.swift` lines 8-18 with:

```swift
    /// A remaining interval as `h:mm`, or `Nm` under an hour.
    static func countdown(_ remaining: TimeInterval, locale: Locale = .current) -> String {
        // Past a day the widget's day-speak applies here too: "51:30" is not a
        // countdown anyone reads.
        if remaining >= 24 * 3600 { return WidgetState.compactDuration(remaining, locale: locale) }
        let total = max(0, Int(remaining))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        guard hours > 0 else {
            return String(localized: "\(minutes)m", bundle: L10n.bundle, locale: locale,
                          comment: "Big countdown under an hour: a number and a one-letter minutes unit")
        }
        return String(format: "%d:%02d", hours, minutes)
    }
```

- [ ] **Step 4: Sync, then add the plural variation by hand**

Run: `Scripts/strings-sync.sh`. Expected: the key `%lld days` now exists.

Open `Shared/Resources/Localizable.xcstrings` and replace the `"%lld days"` entry with:

```json
    "%lld days" : {
      "comment" : "Duration in whole days; has a plural rule",
      "localizations" : {
        "en" : {
          "variations" : {
            "plural" : {
              "one" : { "stringUnit" : { "state" : "translated", "value" : "%lld day" } },
              "other" : { "stringUnit" : { "state" : "translated", "value" : "%lld days" } }
            }
          }
        }
      }
    },
```

Run `Scripts/strings-sync.sh` again so the file is in the tool's canonical formatting (the variation survives a sync).

- [ ] **Step 5: Run the tests to verify they pass**

Run the two test classes. Expected: PASS, including `test_dayDurations_usePluralRules` and every existing `compactDuration` assertion ("3h 20m", "3h", "42m", "1m", "23h 59m" come from the Foundation formatter in `en_US`).

Run the full suite. Expected: 225 pass.

- [ ] **Step 6: Commit**

```bash
git add Shared/Models/WidgetSnapshot.swift Shared/Models/HomeCopy.swift Shared/Resources/Localizable.xcstrings PaperweightTests/Models/WidgetSnapshotTests.swift PaperweightTests/Models/HomeCopyTests.swift
git commit -m "feat(l10n): widget and Home copy resolve through the catalog with locale

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 3: Day-exception labels and schedule labels in Shared

**Files:**
- Modify: `Shared/Models/DayException+Labels.swift`, `Shared/Models/PaperweightSchedule.swift:174-207`
- Test: `PaperweightTests/Models/DayExceptionLabelTests.swift`, create `PaperweightTests/Models/ScheduleLabelTests.swift`

**Interfaces:**
- Produces: `DayException.Treatment.title(calendar:locale:) -> String` (was a property), `DayException.weekdayName(_:calendar:locale:)`, `PaperweightSchedule.hourLabel(_:calendar:locale:)`, `PaperweightSchedule.displayOrder(calendar:) -> [Int]`. Removes `summary(forDay:)`, `timeLabel(halfHour:)`, `DayException.weekdayNames`.
- Consumes: `L10n.bundle`, `TestLocale`.

- [ ] **Step 1: Write the failing tests**

In `PaperweightTests/Models/DayExceptionLabelTests.swift` replace lines 5-15 with:

```swift
    private let cal = TestLocale.calendar
    private let us = TestLocale.en
    private func key(_ m: Int, _ d: Int) -> DayKey { DayKey(year: 2026, month: m, day: d) }
    /// Saturday 2026-09-12 10:00.
    private var now: Date { cal.date(from: DateComponents(year: 2026, month: 9, day: 12, hour: 10))! }

    override func setUp() { TestLocale.useTestBundle() }

    func test_treatmentTitles() {
        XCTAssertEqual(DayException.Treatment.openAllDay.title(calendar: cal, locale: us), "Open all day")
        XCTAssertEqual(DayException.Treatment.quietAllDay.title(calendar: cal, locale: us), "Quiet all day")
        XCTAssertEqual(DayException.Treatment.likeWeekday(6).title(calendar: cal, locale: us), "Like Saturday")
    }

    /// Weekday names come from the calendar, so a Japanese device says 土曜日,
    /// not Saturday. Proves the English array is gone.
    func test_weekdayNamesFollowTheLocale() {
        let ja = Locale(identifier: "ja_JP")
        XCTAssertEqual(DayException.weekdayName(6, calendar: cal, locale: ja), "土曜日")
        XCTAssertEqual(DayException.weekdayName(0, calendar: cal, locale: us), "Sunday")
    }
```

Create `PaperweightTests/Models/ScheduleLabelTests.swift`:

```swift
import XCTest

final class ScheduleLabelTests: XCTestCase {
    private let en = TestLocale.en
    private let cal = TestLocale.calendar

    /// iOS separates the hour from AM/PM with a narrow no-break space
    /// (U+202F); Dutch pads to two digits.
    func test_hourLabels_useTheLocalesClock() {
        XCTAssertEqual(PaperweightSchedule.hourLabel(0, calendar: cal, locale: en), "12\u{202F}AM")
        XCTAssertEqual(PaperweightSchedule.hourLabel(6, calendar: cal, locale: en), "6\u{202F}AM")
        XCTAssertEqual(PaperweightSchedule.hourLabel(12, calendar: cal, locale: en), "12\u{202F}PM")
        XCTAssertEqual(PaperweightSchedule.hourLabel(18, calendar: cal, locale: en), "6\u{202F}PM")
        XCTAssertEqual(PaperweightSchedule.hourLabel(24, calendar: cal, locale: en), "12\u{202F}AM")
        let nl = Locale(identifier: "nl_NL")
        XCTAssertEqual(PaperweightSchedule.hourLabel(18, calendar: cal, locale: nl), "18")
        XCTAssertEqual(PaperweightSchedule.hourLabel(6, calendar: cal, locale: nl), "06")
    }

    /// Display order follows the calendar's first weekday; the indexes
    /// themselves stay Sunday-based so storage never moves.
    func test_displayOrder_startsAtTheCalendarsFirstWeekday() {
        var sunday = cal; sunday.firstWeekday = 1
        XCTAssertEqual(PaperweightSchedule.displayOrder(calendar: sunday), [0, 1, 2, 3, 4, 5, 6])
        var monday = cal; monday.firstWeekday = 2
        XCTAssertEqual(PaperweightSchedule.displayOrder(calendar: monday), [1, 2, 3, 4, 5, 6, 0])
        var saturday = cal; saturday.firstWeekday = 7
        XCTAssertEqual(PaperweightSchedule.displayOrder(calendar: saturday), [6, 0, 1, 2, 3, 4, 5])
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `-only-testing:PaperweightTests/DayExceptionLabelTests -only-testing:PaperweightTests/ScheduleLabelTests`
Expected: compile errors (`title` is not a function; no `weekdayName`, `displayOrder`; `hourLabel` takes one argument).

- [ ] **Step 3: Rewrite the labels file**

Replace `Shared/Models/DayException+Labels.swift` entirely:

```swift
import Foundation

extension DayException.Treatment {
    /// The pill text. Sentence case; the word is "quiet", never "blocked".
    func title(calendar: Calendar = .current, locale: Locale = .current) -> String {
        switch self {
        case .openAllDay:
            return String(localized: "Open all day", bundle: L10n.bundle, locale: locale,
                          comment: "Day treatment: apps open the whole day")
        case .quietAllDay:
            return String(localized: "Quiet all day", bundle: L10n.bundle, locale: locale,
                          comment: "Day treatment: apps quiet the whole day")
        case .likeWeekday(let w):
            let name = DayException.weekdayName(w, calendar: calendar, locale: locale)
            return String(localized: "Like \(name)", bundle: L10n.bundle, locale: locale,
                          comment: "Day treatment: use another weekday's schedule; a weekday name follows")
        }
    }
}

extension DayException {
    /// Full weekday name for the app's Sunday-based index, in the locale's own
    /// words, for any integer (negative or over 6 wraps).
    static func weekdayName(_ index: Int, calendar: Calendar = .current, locale: Locale = .current) -> String {
        var c = calendar
        c.locale = locale
        return c.weekdaySymbols[((index % 7) + 7) % 7]
    }

    /// "Fri, Sep 18" or "Mon, Sep 21 – Fri, Sep 25".
    func dateLabel(calendar: Calendar = .current, locale: Locale = .current) -> String {
        let style = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
            .weekday(.abbreviated).month(.abbreviated).day()
        let first = firstDay.date(calendar: calendar).formatted(style)
        guard firstDay != lastDay else { return first }
        let last = lastDay.date(calendar: calendar).formatted(style)
        return String(localized: "\(first) – \(last)", bundle: L10n.bundle, locale: locale,
                      comment: "A date range: first day, en dash, last day")
    }

    /// Compact form for the Home row value: a bare weekday when the day is
    /// within the next six days ("Fri"), otherwise "Sep 18"; ranges as
    /// "Sep 21–25" or "Sep 28 – Oct 2".
    func shortDateLabel(now: Date = Date(), calendar: Calendar = .current, locale: Locale = .current) -> String {
        let base = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
        let monthDay = base.month(.abbreviated).day()
        let firstDate = firstDay.date(calendar: calendar)
        if firstDay == lastDay {
            let today = DayKey(now, calendar: calendar)
            let days = calendar.dateComponents([.day], from: today.date(calendar: calendar), to: firstDate).day ?? 7
            if (0...6).contains(days) {
                return firstDate.formatted(base.weekday(.abbreviated))
            }
            return firstDate.formatted(monthDay)
        }
        let lastDate = lastDay.date(calendar: calendar)
        if firstDay.month == lastDay.month && firstDay.year == lastDay.year {
            let first = firstDate.formatted(monthDay)
            return String(localized: "\(first)–\(lastDay.day)", bundle: L10n.bundle, locale: locale,
                          comment: "A range inside one month: 'Sep 21' then the last day's number")
        }
        let first = firstDate.formatted(monthDay)
        let last = lastDate.formatted(monthDay)
        return String(localized: "\(first) – \(last)", bundle: L10n.bundle, locale: locale,
                      comment: "A date range across months")
    }
}

extension PaperweightConfig {
    /// The Home row's trailing value: the next planned day and how many are
    /// upcoming, or nil when there are none.
    func dayExceptionsRowValue(now: Date = Date(), calendar: Calendar = .current,
                               locale: Locale = .current) -> String? {
        let upcoming = upcomingDayExceptions(now: now, calendar: calendar)
        guard let next = upcoming.first else { return nil }
        let day = next.shortDateLabel(now: now, calendar: calendar, locale: locale)
        let count = String(localized: "\(upcoming.count) upcoming", bundle: L10n.bundle, locale: locale,
                           comment: "How many planned days are ahead; has a plural rule")
        return String(localized: "\(day) · \(count)", bundle: L10n.bundle, locale: locale,
                      comment: "Two short phrases joined by a middle dot")
    }
}
```

Note: the key for `"\(first) – \(last)"` is shared by `dateLabel` and `shortDateLabel`; two comments on one key are fine, the sync keeps the first.

- [ ] **Step 4: Rewrite the schedule labels**

In `Shared/Models/PaperweightSchedule.swift` replace lines 174-207 (`summary(forDay:)`, `hourLabel`, `timeLabel`) with:

```swift
    /// Label for the top of a clock hour in the locale's own clock: "6 AM" and
    /// "12 PM" where the day has halves, "6" and "18" where it doesn't. Hour 24
    /// is the end of the day, shown as hour 0.
    static func hourLabel(_ hour: Int, calendar: Calendar = .current, locale: Locale = .current) -> String {
        var comps = DateComponents()
        comps.year = 2001; comps.month = 1; comps.day = 1; comps.hour = hour % 24
        guard let date = calendar.date(from: comps) else { return "\(hour % 24)" }
        let style = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
            .hour(.defaultDigits(amPM: .abbreviated))
        return date.formatted(style)
    }

    /// Day indexes (0 = Sunday … 6 = Saturday) in the order a locale reads a
    /// week, starting at the calendar's first weekday. Display only: storage,
    /// `weekdayIndex` and every slot index stay Sunday-based.
    static func displayOrder(calendar: Calendar = .current) -> [Int] {
        let first = ((calendar.firstWeekday - 1) % 7 + 7) % 7
        return (0..<7).map { (first + $0) % 7 }
    }
```

`summary(forDay:)` and `timeLabel(halfHour:)` have no callers (`git grep -n "summary(forDay\|timeLabel(halfHour"` returns only their definitions); they are deleted, not localized.

- [ ] **Step 5: Fix the three call sites that break**

- `Paperweight/Views/AddDayExceptionSheet.swift:187`: `other.dateLabel()` still compiles (defaults).
- Any `.title` on a `DayException.Treatment` in `Paperweight/Views/DayExceptionsView.swift` becomes `.title()`. Find them with `git grep -n "\.title" Paperweight/Views/DayExceptionsView.swift`.
- `git grep -n "weekdayNames"` must return nothing.

- [ ] **Step 6: Sync, add the plural variation, run tests**

Run `Scripts/strings-sync.sh`. Edit the `"%lld upcoming"` entry to a plural variation exactly like Task 2 Step 4, with `one` = `%lld upcoming` and `other` = `%lld upcoming` (English has no change; the rule exists so other languages can differ). Run the sync again.

Run the two test classes. Expected: PASS. Run the full suite. Expected: 227 pass.

- [ ] **Step 7: Commit**

```bash
git add Shared/Models/DayException+Labels.swift Shared/Models/PaperweightSchedule.swift Shared/Resources/Localizable.xcstrings Paperweight/Views/DayExceptionsView.swift PaperweightTests/Models/DayExceptionLabelTests.swift PaperweightTests/Models/ScheduleLabelTests.swift
git commit -m "feat(l10n): weekday names, hour labels and date ranges follow the locale

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 4: Schedule, day-exception and week-strip views

**Files:**
- Modify: `Paperweight/Views/ScheduleView.swift`, `Paperweight/Views/AddDayExceptionSheet.swift`, `Paperweight/Views/Components/WeekStrip.swift`, `Paperweight/Views/DayExceptionsView.swift:131-146`

**Interfaces:**
- Consumes: `PaperweightSchedule.hourLabel(_:calendar:locale:)`, `PaperweightSchedule.displayOrder(calendar:)`, `L10n.bundle`.

No unit tests cover these views (they are SwiftUI bodies); the check is the build, the simulator walk-through in Step 5, and the catalog diff.

- [ ] **Step 1: ScheduleView**

Replace line 16 (`private let dayLabels …`) and lines 17-22 with:

```swift
    private let hours = 24
    private let colGap: CGFloat = 3
    private let rowGap: CGFloat = 3
    private let headerHeight: CGFloat = 18
    private let stackSpacing: CGFloat = 8

    /// Columns in the locale's week order; `order[column]` is the Sunday-based
    /// day index the model uses.
    private let order = PaperweightSchedule.displayOrder()
    private let dayLabels = Calendar.current.veryShortWeekdaySymbols
    private let hourLabels = (0..<24).map { PaperweightSchedule.hourLabel($0) }

    /// Wide enough for the widest hour label in this locale ("12 AM", "오후 12시"),
    /// never narrower than the original 30pt.
    private var leftInset: CGFloat {
        let font = UIFont.systemFont(ofSize: 9, weight: .semibold)
        let widest = hourLabels.map { ($0 as NSString).size(withAttributes: [.font: font]).width }.max() ?? 0
        return max(30, ceil(widest) + 4)
    }
```

Replace lines 54-59 (`pendingFooterText`) with:

```swift
    private var pendingFooterText: String? {
        guard vm.config.isEnabled else { return nil }
        guard hasPendingChange else {
            return String(localized: "Loosening takes effect tomorrow.", bundle: L10n.bundle)
        }
        let hours = (Double(openingSlots.count) / 2.0).formatted()
        return String(localized: "\(hours) hours open up at midnight.", bundle: L10n.bundle,
                      comment: "A number of hours (may be 2.5) that become open at the day boundary")
    }
```

Replace lines 72-73 (the two legends) with:

```swift
                    legend(color: PW.moss, label: String(localized: "Locked — quiet", bundle: L10n.bundle, comment: "Legend swatch"))
                    legend(color: nil, label: String(localized: "Open", bundle: L10n.bundle, comment: "Legend swatch"))
```

and line 75 with `legend(color: PW.moss.opacity(0.35), label: String(localized: "Opens tomorrow", bundle: L10n.bundle, comment: "Legend swatch"), dashed: true)`.

Replace lines 103-104 with:

```swift
            Text("\(PaperweightSchedule(freeSlots: freeSlots).quietHourCount.formatted()) quiet hours this week")
```

Replace line 114 with `AccentButton(title: String(localized: "Save schedule", bundle: L10n.bundle)) { Task { await save() } }`.

Copy fixes: line 132 → `.alert("Choose apps to quiet first", …`; line 136 → `Text("Paperweight has nothing to quiet yet. Pick the apps or categories to make quiet, then save again to arm.")`; line 158 → `Text("Now is a quiet period — saving makes restricted apps quiet at once.")`.

`dayHeader` (lines 187-198): iterate columns and map through `order`:

```swift
    private func dayHeader(cellW: CGFloat) -> some View {
        HStack(spacing: colGap) {
            Color.clear.frame(width: leftInset, height: 1)
            ForEach(0..<7, id: \.self) { column in
                Text(dayLabels[order[column]])
                    .font(.grotesk(13, weight: .semibold))
                    .foregroundStyle(PW.textFaint)
                    .frame(width: cellW)
            }
        }
        .frame(height: headerHeight)
    }
```

In `gridBody`: line 204 → `Text(hourLabels[hour])`; lines 214-217 →

```swift
                        ForEach(0..<7, id: \.self) { column in
                            let day = order[column]
                            cell(day: day, hour: hour, w: cellW, h: cellH,
                                 isNow: day == nowCell.day && hour == nowCell.hour)
                        }
```

In `cellAt` (line 310) → `let day = order[min(max(Int(xInCells / (cellW + colGap)), 0), 6)]`.

- [ ] **Step 2: AddDayExceptionSheet**

Replace lines 23-26 with:

```swift
    private static let kinds: [(value: Kind, label: String)] = [
        (.open, String(localized: "Open all day", bundle: L10n.bundle, comment: "Day treatment: apps open the whole day")),
        (.quiet, String(localized: "Quiet all day", bundle: L10n.bundle, comment: "Day treatment: apps quiet the whole day")),
        (.like, String(localized: "Like a weekday…", bundle: L10n.bundle, comment: "Day treatment: pick a weekday to copy"))]
    /// Weekday initials in the locale's week order; the value stays the app's
    /// Sunday-based index.
    private static let weekdays: [(value: Int, label: String)] = {
        let symbols = Calendar.current.veryShortWeekdaySymbols
        return PaperweightSchedule.displayOrder().map { ($0, symbols[$0]) }
    }()
```

Lines 75 and 78: replace `.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())` with `.formatted(Date.FormatStyle(locale: .current, calendar: .current).weekday(.abbreviated).month(.abbreviated).day())` (unchanged behaviour, explicit locale), and wrap the literals: `fieldRow(String(localized: "From", bundle: L10n.bundle, comment: "First day of a range"), …`, `fieldRow(String(localized: "To", bundle: L10n.bundle, comment: "Last day of a range"), …`, and `?? String(localized: "Same day", bundle: L10n.bundle, comment: "Range end when the range is a single day")`.

Lines 187, 189, 191:

```swift
            case .overlaps(let other):
                errorText = String(localized: "Overlaps \(other.dateLabel()). Remove that one first.", bundle: L10n.bundle,
                                   comment: "A date or date range follows 'Overlaps'")
            case .loosensToday:
                errorText = String(localized: "Opening up takes effect from tomorrow.", bundle: L10n.bundle)
            case .endsBeforeStart:
                errorText = String(localized: "The last day is before the first.", bundle: L10n.bundle)
```

- [ ] **Step 3: WeekStrip**

Replace line 16 with `private static let dayNames = Calendar.current.shortWeekdaySymbols` and line 27 with:

```swift
                            Text("\(Self.dayNames[day.weekdayIndex()]) \(day.day)")
```

(unchanged text, now a locale symbol). Lines 41-42 and 45:

```swift
                legend(color: PW.moss, label: String(localized: "Locked — quiet", bundle: L10n.bundle, comment: "Legend swatch"))
                legend(color: nil, label: String(localized: "Open", bundle: L10n.bundle, comment: "Legend swatch"))
```

`Text("Planned")` and `Text("OPEN ALL DAY")` are `Text` literals and extract already; add nothing.

- [ ] **Step 4: DayExceptionsView second line**

Replace lines 131-146 with:

```swift
    /// Short facts under the date, joined by a middle dot. Each fact is its own
    /// key so nothing is glued from fragments.
    private func secondLine(_ e: DayException) -> String? {
        let b = L10n.bundle
        var parts: [String] = []
        if e.lastDay == today {
            parts.append(String(localized: "Ends tonight", b: b))
            if vm.truncatedDayExceptionIDs.contains(e.id) {
                parts.append(String(localized: "the change lands tomorrow", bundle: b,
                                    comment: "After 'Ends tonight': an edit or removal applies from tomorrow"))
            } else if !e.note.isEmpty {
                parts.append(e.note)
            }
        } else if !e.note.isEmpty {
            parts.append(e.note)
        }
        if e.dayCount() > 1 {
            parts.append(String(localized: "\(e.dayCount()) days", bundle: b,
                                comment: "Length of a planned range; has a plural rule"))
        }
        guard !parts.isEmpty else { return nil }
        let separator = String(localized: " · ", bundle: b, comment: "Joins short facts on one line; keep the spaces")
        return parts.joined(separator: separator)
    }
```

Correct the typo in the first append: `String(localized: "Ends tonight", bundle: b, comment: "A planned day whose last day is today")`.

- [ ] **Step 5: Build, sync, walk through**

Run `Scripts/strings-sync.sh`. Expected: new keys include `Locked — quiet`, `Open`, `Opens tomorrow`, `%@ hours open up at midnight.`, `Like a weekday…`, `From`, `To`, `Same day`, `Ends tonight`, `the change lands tomorrow`, ` · `; `Choose apps to block first` is gone from `ScheduleView` (it may remain until Task 5 removes it from `HomeView`).

Install on the simulator and open Schedule: the hour column reads "12 AM … 11 PM", columns S M T W T F S. Then run with Dutch: `xcrun simctl launch booted media.baltar.paperweight -AppleLanguages "(nl)" -AppleLocale nl_NL` and confirm columns read M D W D V Z Z (Monday first) and hours read 0 … 23, while copy stays English. Screenshot both for the PR.

- [ ] **Step 6: Commit**

```bash
git add Paperweight/Views/ScheduleView.swift Paperweight/Views/AddDayExceptionSheet.swift Paperweight/Views/Components/WeekStrip.swift Paperweight/Views/DayExceptionsView.swift Shared/Resources/Localizable.xcstrings
git commit -m "feat(l10n): schedule grid and planned-day screens follow the locale's week and clock

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 5: Home, unlock, NFC, cool-off, settings, services, errors, widget

**Files:**
- Modify: `Paperweight/Views/HomeView.swift`, `Paperweight/Views/UnlockView.swift:39-41`, `Paperweight/Extensions/FamilyActivitySelection+Summary.swift`, `Paperweight/Views/NFCSetupView.swift:15-17,79,176-178`, `Paperweight/Views/DisablePaperweightSheet.swift:90,93,130`, `Paperweight/Views/RecoveryCodesView.swift:72,120`, `Paperweight/Views/SettingsView.swift:85,102`, `Paperweight/Views/QuietThemePicker.swift:22`, `Paperweight/Views/NFCBuyingGuideView.swift:88`, `Paperweight/Views/Components/QuietGlassControls.swift`, `Paperweight/Services/NFCService.swift:25,57,63,74,78`, `Shared/Models/NFCError.swift`, `Shared/Models/UnlockError.swift`, `PaperweightWidget/PaperweightWidgetBundle.swift:19-20`, `PaperweightWidget/PaperweightWidgetViews.swift:172,218-220`

**Interfaces:**
- Consumes: `WidgetCopy.displayName`, `WidgetCopy.widgetDescription`, `L10n.bundle`.

**The rule for helper parameters.** A literal passed to a parameter typed `String` is invisible to extraction. Two fixes, chosen per parameter:
- If every caller passes a literal, change the parameter to `LocalizedStringKey` and render it with `Text(...)`. Callers stay as they are.
- If any caller passes a computed value, keep `String` and wrap each literal caller in `String(localized:bundle:)`.

- [ ] **Step 1: Components**

In `Paperweight/Views/Components/QuietGlassControls.swift`, read the four structs whose properties are `String` (lines 15, 44/48, 84, 111). For `NavRow.title`, `AccentButton.title`, and the `title`/`text` at lines 15 and 111: if the property is only ever passed to `Text(...)` inside the body, change its type to `LocalizedStringKey`. `NavRow.value` stays `String?` (callers pass computed values). If a caller of a changed property passes a computed `String`, that call site changes to pass `LocalizedStringKey(theString)` only when the string is a key; otherwise leave the property as `String` and wrap the literal callers instead. Record which you chose in the report.

`PWSegmented.options` labels stay `String`; every caller building an options array wraps literals in `String(localized:bundle:)` (AddDayExceptionSheet was done in Task 4; `NFCSetupView` is Step 4 below).

- [ ] **Step 2: HomeView**

Line 92-93:

```swift
            headerText: String(localized: "Choose apps and categories to make quiet.", bundle: L10n.bundle),
            footerText: String(localized: "Do not select Paperweight itself — quieting it could lock you out of these controls.", bundle: L10n.bundle),
```

Line 127 → `.alert("Choose apps to quiet first", …`; line 131 → `Text("Paperweight has nothing to quiet yet. Pick the apps or categories to make quiet first.")`.

Lines 155-157 and 175 stay as `Text`/interpolation but 156-157 are a `String` passed to `banner(headline:)`, so:

```swift
                    headline: status.map {
                        String(localized: "Down until \(WidgetState.dayClock($0.ends, from: context.date))", bundle: L10n.bundle,
                               comment: "A time (maybe with a day) follows")
                    } ?? String(localized: "Down until you say otherwise", bundle: L10n.bundle),
```

Line 153 `eyebrow: "● Locked"` → `eyebrow: String(localized: "● Locked", bundle: L10n.bundle, comment: "Banner eyebrow; keep the dot")`; line 241 `eyebrow: "○ Open"` likewise; line 243 `headline: String(localized: "In your hands.", bundle: L10n.bundle)`; lines 246-248:

```swift
                        detail: status.map {
                            let at = WidgetState.dayClock($0.ends, from: context.date)
                            let inn = WidgetState.compactDuration($0.remaining)
                            return String(localized: "Locks at \(at) · in \(inn)", bundle: L10n.bundle,
                                          comment: "A time, then a duration")
                        })
```

Line 166 `Text("left")` extracts as is. Lines 376-380:

```swift
    private var restrictedCountText: String {
        let s = vm.config.selection
        let total = s.applicationTokens.count + s.categoryTokens.count + s.webDomainTokens.count
        return String(localized: "\(total) apps", bundle: L10n.bundle, comment: "How many apps are chosen; has a plural rule")
    }
```

Line 411 → `selectionRevertMessage = String(localized: "Removing a quiet app needs your NFC token. Your list is unchanged.", bundle: L10n.bundle)`.

Lines 460-465:

```swift
                type: "disable-paperweight",
                localizedTitle: String(localized: "Turn Off Paperweight", bundle: L10n.bundle, comment: "Home Screen quick action"),
                localizedSubtitle: String(localized: "Requires NFC token", bundle: L10n.bundle, comment: "Home Screen quick action subtitle"),
```

and `localizedTitle: String(localized: "Turn On Paperweight", bundle: L10n.bundle, comment: "Home Screen quick action")`.

Line 497 stays (`Text("+\(total - limit) more")` extracts as `+%lld more`).

Any other `banner(…)`, `NavRow(title:…)`, `AccentButton(title:…)` call in `HomeView.swift` with a literal follows Step 1's rule.

- [ ] **Step 3: UnlockView**

Replace lines 39-41 with one key, styled with Markdown:

```swift
                Text("Tap your NFC token to lift restrictions for **\(unlockMinutes) minutes**. The quiet returns on its own.")
                    .foregroundStyle(PW.textMuted)
```

(`Text` renders `**…**` bold; the previous colour split becomes weight. If the design must keep the colour, use `Text(AttributedString(localized: …))` with a `foregroundColor` attribute on the bold range; weight is acceptable here.)

- [ ] **Step 4: Plurals and picker labels**

`Paperweight/Extensions/FamilyActivitySelection+Summary.swift` lines 9-13:

```swift
        var parts: [String] = []
        if appCount > 0 { parts.append(String(localized: "\(appCount) apps", bundle: L10n.bundle, comment: "How many apps are chosen; has a plural rule")) }
        if catCount > 0 { parts.append(String(localized: "\(catCount) categories", bundle: L10n.bundle, comment: "How many app categories are chosen; has a plural rule")) }
        if domainCount > 0 { parts.append(String(localized: "\(domainCount) domains", bundle: L10n.bundle, comment: "How many web domains are chosen; has a plural rule")) }
        return parts.joined(separator: String(localized: ", ", bundle: L10n.bundle, comment: "List separator"))
```

`Paperweight/Views/NFCSetupView.swift` lines 15-17:

```swift
    private let durations: [(value: TimeInterval, label: String)] = [300, 900, 1800, 3600].map {
        ($0, Duration.seconds($0).formatted(.units(allowed: [.hours, .minutes], width: .narrow)))
    }
    private let coolOffs: [(value: Int, label: String)] = [1, 2, 3].map {
        ($0, String(localized: "\($0) days", bundle: L10n.bundle, comment: "Duration in whole days; has a plural rule"))
    }
```

Line 79 → `Text("\(unused) of \(RecoveryCodeService.codeCount)")` already extracts as `%lld of %lld`; leave it. Lines 176-178:

```swift
    private var coolOffLabel: String {
        String(localized: "\(vm.config.coolOffDays) days", bundle: L10n.bundle, comment: "Duration in whole days; has a plural rule")
    }
```

`Paperweight/Views/DisablePaperweightSheet.swift`: line 90 → `Button("Start \(vm.config.coolOffDays)-day Cool-off")` extracts as `Start %lld-day Cool-off`; leave it. Line 93:

```swift
                Text("Paperweight stays on and keeps enforcing your schedule. After \(coolOffLabel) it lifts automatically. Use this only if your token is lost — scanning it or a recovery code unlocks immediately.")
```

with a private helper in that view:

```swift
    private var coolOffLabel: String {
        String(localized: "\(vm.config.coolOffDays) days", bundle: L10n.bundle, comment: "Duration in whole days; has a plural rule")
    }
```

Line 130 stays (`%lld-day cool-off` is one key).

- [ ] **Step 5: Copy fixes and remaining String parameters**

- `RecoveryCodesView.swift:72` → `Text(copiedAll ? "Copied" : "Copy all codes")`. Both branches are literals inside `Text`, so they extract. Line 120 `exportLabel(systemName:title:)`: apply Step 1's rule to `title`.
- `SettingsView.swift:85` → `Text("Reveals Emergency unlock and Turn off. Nothing is armed and nothing is quiet.")`; `:102` → `Text("Shows the quiet screen without arming anything. Nothing actually goes quiet.")`.
- `QuietThemePicker.swift:22` → `Text("Changes only what you see while apps are quiet. It never changes what goes quiet.")`.
- `NFCBuyingGuideView.swift:88` `infoRow(icon:iconColor:title:body:)`: `title` and `body` become `LocalizedStringKey`; `buyRow(title:subtitle:url:)` stays `String` (remote-config values).
- Every `NavRow(title: "…")`, `AccentButton(title: "…")`, `legend(label:)`, `fieldRow` and similar literal caller across `Paperweight/Views` follows Step 1's rule. Find them: `git grep -n -E '(title|label|headline|eyebrow|detail|subtitle|body): "' Paperweight/Views`.

- [ ] **Step 6: Services and errors**

`Paperweight/Services/NFCService.swift`:

```swift
            session?.alertMessage = String(localized: "Hold your Paperweight token near the top of your iPhone.", bundle: L10n.bundle, comment: "System NFC sheet")
…
            session.invalidate(errorMessage: String(localized: "No token found.", bundle: L10n.bundle, comment: "System NFC sheet"))
…
                session.invalidate(errorMessage: String(localized: "Couldn't read the token.", bundle: L10n.bundle, comment: "System NFC sheet"))
…
                session.invalidate(errorMessage: String(localized: "Unsupported token.", bundle: L10n.bundle, comment: "System NFC sheet"))
…
            session.alertMessage = String(localized: "Token recognized.", bundle: L10n.bundle, comment: "System NFC sheet")
```

`Shared/Models/NFCError.swift` lines 11-19:

```swift
    var errorDescription: String? {
        let b = L10n.bundle
        switch self {
        case .notSupported: return String(localized: "NFC is not supported on this device.", bundle: b)
        case .sessionFailed(let e): return String(localized: "NFC session failed: \(e.localizedDescription)", bundle: b, comment: "A system error message follows")
        case .noTagFound: return String(localized: "No NFC tag found.", bundle: b)
        case .readFailed: return String(localized: "Could not read the NFC tag.", bundle: b)
        case .busy: return String(localized: "A scan is already in progress. Try again in a moment.", bundle: b)
        }
    }
```

`Shared/Models/UnlockError.swift` lines 8-13:

```swift
    var errorDescription: String? {
        switch self {
        case .noTagRegistered: return String(localized: "No NFC token registered. Set one up in settings.", bundle: L10n.bundle)
        case .tagMismatch: return String(localized: "That token wasn't recognized.", bundle: L10n.bundle)
        }
    }
```

- [ ] **Step 7: Widget**

`PaperweightWidget/PaperweightWidgetBundle.swift` lines 19-20:

```swift
        .configurationDisplayName(WidgetCopy.displayName)
        .description(WidgetCopy.widgetDescription)
```

`PaperweightWidget/PaperweightWidgetViews.swift` line 172 stays (`hourLabel(hour)` now uses defaults); lines 218-220:

```swift
    private static func weekdayName(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.wide)).uppercased(with: .current)
    }
```

- [ ] **Step 8: Build everything, sync, add plural variations, test**

Run the full build (all three targets). Expected: BUILD OK, and `git grep -n -i -E '"[^"]*(block|Copied!)' Paperweight Shared PaperweightWidget -- '*.swift'` returns only comments and the `blockedRightNow` identifier.

Run `Scripts/strings-sync.sh`. Add plural variations (as in Task 2 Step 4) for: `%lld apps` (one `%lld app`), `%lld categories` (one `%lld category`), `%lld domains` (one `%lld domain`), `+%lld more` (one and other identical). `%lld days` already has one. Run the sync again.

Run the full suite. Expected: 227 pass. Install on the simulator, English: Home, Restricted apps count ("1 app" / "3 apps"), Unlock screen sentence, NFC setup picker ("5m 15m 30m 1h", "1 day 2 days 3 days"), Settings. Screenshot the Unlock screen for the PR.

- [ ] **Step 9: Commit**

```bash
git add Paperweight Shared PaperweightWidget
git commit -m "feat(l10n): every remaining string goes through the catalog; copy says quiet, not blocked

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 6: Catalog lint and CI

**Files:**
- Create: `Scripts/strings-check.py`, `Scripts/tests/test_strings_check.py`
- Modify: `.github/workflows/ci.yml`

**Interfaces:**
- Produces: `python3 Scripts/strings-check.py [--catalog PATH] [--languages CODES]` exits 1 with a list on failure. `Scripts/strings-sync.sh --check` (from Task 1) is the drift check.

- [ ] **Step 1: Write the failing tests**

Create `Scripts/tests/test_strings_check.py`:

```python
import json, os, sys, tempfile, unittest
sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
import strings_check  # noqa: E402


def unit(value, state="translated"):
    return {"stringUnit": {"state": state, "value": value}}


def catalog(strings):
    return {"sourceLanguage": "en", "version": "1.0", "strings": strings}


class Findings(unittest.TestCase):
    def check(self, strings, languages=()):
        return strings_check.problems(catalog(strings), list(languages))

    def test_clean_catalog_has_no_problems(self):
        self.assertEqual(self.check({"Open all day": {"localizations": {"en": unit("Open all day")}}}), [])

    def test_stale_key_is_a_problem(self):
        p = self.check({"Old": {"extractionState": "stale", "localizations": {"en": unit("Old")}}})
        self.assertIn("stale: 'Old'", p)

    def test_placeholder_mismatch_is_a_problem(self):
        p = self.check({"%lld apps": {"localizations": {
            "en": unit("%lld apps"), "nl": unit("apps")}}}, ["nl"])
        self.assertIn("placeholders differ in nl: '%lld apps'", p)

    def test_exclamation_mark_is_a_problem(self):
        p = self.check({"Copied": {"localizations": {"en": unit("Copied"), "es": unit("¡Copiado!")}}}, ["es"])
        self.assertIn("exclamation mark in es: 'Copied'", p)

    def test_missing_language_is_a_problem(self):
        p = self.check({"Open": {"localizations": {"en": unit("Open")}}}, ["ja"])
        self.assertIn("missing ja: 'Open'", p)

    def test_needs_review_counts_as_present(self):
        p = self.check({"Open": {"localizations": {"en": unit("Open"), "ja": unit("開放", "needs_review")}}}, ["ja"])
        self.assertEqual(p, [])

    def test_plural_variations_are_checked_per_form(self):
        p = self.check({"%lld days": {"localizations": {
            "en": {"variations": {"plural": {"one": unit("%lld day"), "other": unit("%lld days")}}},
            "nl": {"variations": {"plural": {"one": unit("dag"), "other": unit("%lld dagen")}}}}}}, ["nl"])
        self.assertIn("placeholders differ in nl: '%lld days'", p)

    def test_budget_comment_warns_but_does_not_fail(self):
        strings = {"until %@": {"comment": "Lock Screen; keep under 24 characters",
                                "localizations": {"en": unit("until %@"),
                                                  "nl": unit("tot en met het moment dat %@")}}}
        self.assertEqual(self.check(strings, ["nl"]), [])
        self.assertIn("over 24 characters in nl: 'until %@'", strings_check.warnings(catalog(strings), ["nl"]))


class Cli(unittest.TestCase):
    def test_exit_code_reflects_problems(self):
        with tempfile.TemporaryDirectory() as d:
            path = os.path.join(d, "c.xcstrings")
            json.dump(catalog({"Old": {"extractionState": "stale", "localizations": {"en": unit("Old")}}}), open(path, "w"))
            self.assertEqual(strings_check.main(["--catalog", path]), 1)
            json.dump(catalog({"Ok": {"localizations": {"en": unit("Ok")}}}), open(path, "w"))
            self.assertEqual(strings_check.main(["--catalog", path]), 0)


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `python3 -m unittest Scripts/tests/test_strings_check.py -v`
Expected: `ModuleNotFoundError: No module named 'strings_check'`.

- [ ] **Step 3: Write the lint**

Create `Scripts/strings_check.py` (underscore, so it imports; `Scripts/strings-check.py` is a two-line shim below):

```python
#!/usr/bin/env python3
"""Lint Shared/Resources/Localizable.xcstrings.

Fails on: stale keys, placeholder mismatches between the English source and
any translation, exclamation marks in any translation, and (when languages are
given) keys with no translation in a required language. Warns, without
failing, when a key whose comment names a 24-character budget exceeds it.

Standard library only; runs on the Ubuntu CI job.
"""
import argparse
import json
import re
import sys

PLACEHOLDER = re.compile(r"%(\d+\$)?(@|lld|ld|d|f|g|s|u|llu|lf)")
BUDGET = re.compile(r"keep under (\d+) characters")


def _units(localization):
    """Every (form, value, state) in one language: the plain unit, or each plural form."""
    if "stringUnit" in localization:
        u = localization["stringUnit"]
        yield "", u.get("value", ""), u.get("state", "")
    for kind, forms in localization.get("variations", {}).items():
        for form, entry in forms.items():
            u = entry.get("stringUnit", {})
            yield f"{kind}.{form}", u.get("value", ""), u.get("state", "")


def _placeholders(value):
    return sorted(m.group(0) for m in PLACEHOLDER.finditer(value))


def problems(catalog, languages):
    out = []
    source = catalog.get("sourceLanguage", "en")
    for key, entry in catalog.get("strings", {}).items():
        if entry.get("extractionState") == "stale":
            out.append(f"stale: {key!r}")
        locs = entry.get("localizations", {})
        source_units = list(_units(locs.get(source, {}))) or [("", key, "translated")]
        source_ph = _placeholders(source_units[0][1])
        for lang in languages:
            if lang not in locs:
                out.append(f"missing {lang}: {key!r}")
        for lang, loc in locs.items():
            if lang == source:
                continue
            for _, value, _ in _units(loc):
                if "!" in value:
                    out.append(f"exclamation mark in {lang}: {key!r}")
                if _placeholders(value) != source_ph:
                    out.append(f"placeholders differ in {lang}: {key!r}")
    return sorted(set(out))


def warnings(catalog, languages):
    out = []
    for key, entry in catalog.get("strings", {}).items():
        m = BUDGET.search(entry.get("comment", "") or "")
        if not m:
            continue
        budget = int(m.group(1))
        for lang, loc in entry.get("localizations", {}).items():
            for _, value, _ in _units(loc):
                if len(value) > budget:
                    out.append(f"over {budget} characters in {lang}: {key!r}")
    return sorted(set(out))


def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--catalog", default="Shared/Resources/Localizable.xcstrings")
    p.add_argument("--languages", default="", help="space-separated codes that must be fully translated")
    a = p.parse_args(argv)
    catalog = json.load(open(a.catalog, encoding="utf-8"))
    languages = a.languages.split()
    for w in warnings(catalog, languages):
        print(f"::warning::{w}")
    found = problems(catalog, languages)
    for f in found:
        print(f"::error::{f}")
    print(f"{len(catalog.get('strings', {}))} keys checked, {len(found)} problems, {len(warnings(catalog, languages))} warnings")
    return 1 if found else 0


if __name__ == "__main__":
    sys.exit(main())
```

Create `Scripts/strings-check.py` (executable):

```python
#!/usr/bin/env python3
import sys, strings_check
sys.exit(strings_check.main())
```

Because the shim imports `strings_check` from its own directory, run it as `python3 Scripts/strings-check.py` from the repo root; Python puts the script's directory on the path.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `python3 -m unittest Scripts/tests/test_strings_check.py -v`
Expected: 9 tests OK.

Run against the real catalog: `python3 Scripts/strings-check.py`
Expected: `NNN keys checked, 0 problems, 0 warnings`.

- [ ] **Step 5: CI**

In `.github/workflows/ci.yml`, after the `Run unit tests` step (before `Upload test results`), add:

```yaml
      # The catalog is committed and synced by hand. If the code gained or lost
      # a string since the last sync, the copy in temp differs from the file.
      - name: Check the String Catalog is in sync with the code
        run: Scripts/strings-sync.sh --check
```

Add a job after `no-committed-team`:

```yaml
  # Cheap catalog lint: stale keys, placeholder mismatches, exclamation marks,
  # and (once languages are listed in Scripts/languages.txt) missing
  # translations. Runs on Ubuntu; needs no Xcode.
  string-catalog:
    name: String Catalog lint
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Lint the catalog
        run: |
          set -euo pipefail
          languages=""
          [ -f Scripts/languages.txt ] && languages="$(tr '\n' ' ' < Scripts/languages.txt)"
          python3 -m unittest Scripts/tests/test_strings_check.py
          python3 Scripts/strings-check.py --languages "$languages"
```

Note `strings-sync.sh --check` rebuilds the app; on the CI runner that reuses nothing from the earlier build step because it uses its own `-derivedDataPath`. Acceptable: it adds about two minutes. If that proves slow, point `DERIVED` at the default DerivedData in a follow-up.

- [ ] **Step 6: Verify the drift check catches drift**

Locally: add `Text("Probe")` to any view, run `Scripts/strings-sync.sh --check`. Expected: exit 1 with a diff showing `"Probe"`. Remove the line. Run `--check` again. Expected: `Catalog is in sync with the code.`

- [ ] **Step 7: Commit**

```bash
git add Scripts/strings_check.py Scripts/strings-check.py Scripts/tests .github/workflows/ci.yml
git commit -m "ci: String Catalog lint and extraction drift check

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 7: Docs and the pull request

**Files:**
- Create: `docs/LOCALIZATION.md`
- Modify: `README.md` (one line under Architecture), `docs/superpowers/specs/2026-09-12-localization-design.md` §4 (tests pin the simulator's time zone, not New York; see Task 1's `TestLocale`)

- [ ] **Step 1: Write the doc**

Create `docs/LOCALIZATION.md`:

```markdown
# Localization

Every user-facing string lives in one String Catalog,
`Shared/Resources/Localizable.xcstrings`, carried by the app, the monitor and the
widget. English is the source language.

## The loop

1. Write copy in code: SwiftUI `Text("…")` literals, or `String(localized: "…",
   bundle: L10n.bundle, comment: "…")` for anything that is a plain `String`.
   One key per sentence; never glue fragments. Interpolate values, never words.
2. Run `Scripts/strings-sync.sh`. It builds the app target and merges what the
   compiler saw into the catalog. Review the diff; delete keys it marked stale.
3. Plurals: the sync creates the key (`%lld apps`); add the `one`/`other`
   variation in the catalog once (Xcode's editor, or the JSON by hand), then run
   the sync again so the file is in canonical form.
4. Commit the catalog with the code. CI fails if they disagree.

## Rules the code follows

- The state words are quiet and open. Never blocked, free, banned, locked out.
  "Restricted apps" names the chosen set and stays. No exclamation marks.
- Shared copy functions take `calendar:` and `locale:`; views pass nothing,
  tests pass `TestLocale.en` and `TestLocale.calendar` and call
  `TestLocale.useTestBundle()` in `setUp`.
- Weekday names come from `Calendar` symbols. Hours come from
  `PaperweightSchedule.hourLabel`. Durations under a day come from
  `Duration.UnitsFormatStyle`; past a day from the `%lld days` keys.
- Display order of a week follows `calendar.firstWeekday` through
  `PaperweightSchedule.displayOrder`. Storage stays Sunday-based.
- Lock Screen accessory keys carry `comment: "Lock Screen; keep under 24
  characters"`; the lint warns when a translation exceeds it.
- Only the app target extracts strings (`SWIFT_EMIT_LOC_STRINGS`). The widget's
  own strings live in `WidgetCopy` so the app's build sees them.

## Checks

- `Scripts/strings-sync.sh --check` — the catalog matches the code (macOS job).
- `python3 Scripts/strings-check.py` — no stale keys, placeholder parity, no
  exclamation marks, every language in `Scripts/languages.txt` complete
  (Ubuntu job). Tests: `python3 -m unittest Scripts/tests/test_strings_check.py`.

## Trying another language

`xcrun simctl launch booted media.baltar.paperweight -AppleLanguages "(nl)"
-AppleLocale nl_NL` runs the installed build in Dutch: formatting follows the
locale immediately; copy follows once translations exist (Phase 2).
```

Add to `README.md` under Architecture: `- **Localization** — one String Catalog in \`Shared/Resources\`, synced by \`Scripts/strings-sync.sh\`; see [docs/LOCALIZATION.md](docs/LOCALIZATION.md).`

In the spec §4, change "a Gregorian calendar with `firstWeekday = 1`, and `TimeZone("America/New_York")`" to "the current calendar with locale `en_US` and `firstWeekday = 1` (the time zone stays the simulator's, because `state(at:)` and its callers default to `Calendar.current`)".

- [ ] **Step 2: Full verification**

Run: `xcodegen generate`, the three-target build, the full test suite (expected 227 pass), `Scripts/strings-sync.sh --check`, `python3 Scripts/strings-check.py`. All green.

- [ ] **Step 3: Commit and open the PR**

```bash
git add docs/LOCALIZATION.md README.md docs/superpowers/specs/2026-09-12-localization-design.md
git commit -m "docs: how localization works and how to keep the catalog honest

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
git push -u origin feat/localization
```

PR title: `Localization framework: one String Catalog, locale-correct formatting, CI checks`. Body: what changed (catalog, sync, formatting, copy fixes), what did not (no translations yet), the on-device checks (Schedule grid in Dutch, Unlock sentence, widget gallery name), and the two screenshots from Tasks 4 and 5. End with `🤖 Generated with [Claude Code](https://claude.com/claude-code)`.

---

## Self-review

**Spec coverage.** §1 catalog and sync → Task 1. §2 conventions: whole sentences (Tasks 4, 5), interpolated strings (2, 3, 5), locale parameter (2, 3), plurals (2, 3, 5), weekdays (3, 4), week start (3, 4), hours (3, 4), durations (2, 5), time plus day (2), numbers (4), uppercase (5), comments (all). §3 copy rules → Global Constraints; the doc in Task 7. §4 tests → Tasks 1, 2, 3 (pinned locale, plural test, `ja_JP` weekday, `nl_NL` hours, display order). §5 CI → Task 6. §6 copy fixes → Tasks 4, 5 (all eleven: ScheduleView 132/136/158, HomeView 92/93/127/131/411, RecoveryCodesView 72, SettingsView 85/102, QuietThemePicker 22). §7 and §8 are Phase 2. §9 files → file map.

**Placeholders.** None; every code step shows the code. Task 5 Step 1 delegates one type decision per component with a rule and asks for it to be recorded.

**Type consistency.** `copy(at:calendar:locale:)`, `compactDuration(_:locale:)`, `clock(_:calendar:locale:)`, `dayClock(_:from:calendar:locale:abbreviated:)`, `relative(_:from:locale:)`, `HomeCopy.countdown(_:locale:)`, `Treatment.title(calendar:locale:)`, `DayException.weekdayName(_:calendar:locale:)`, `hourLabel(_:calendar:locale:)`, `displayOrder(calendar:)`, `WidgetCopy.displayName`, `WidgetCopy.widgetDescription`, `L10n.bundle`, `TestLocale.en/.calendar/.useTestBundle()`, `strings_check.problems/warnings/main` are used with the same names and shapes throughout.
