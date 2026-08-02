# App Screens v2 — PR 4: The escape hatch

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restyle the four screens a user reaches when they need out — NFC Token & Recovery, Emergency unlock, the turn-off sheet, and Recovery codes — to the v2 design.

**Architecture:** Every one of these screens already works. This is a view-layer restyle: the services, view-model, unlock flow, recovery-code redemption, and cool-off logic are untouched. Clay (`PW.clay`) marks every exit, and no exit is ever louder than the calm.

**Tech Stack:** Swift 5.9, SwiftUI, iOS 17+, XcodeGen, XCTest.

**Spec:** `docs/superpowers/specs/2026-08-01-app-screens-v2-design.md` §3, screens 04–07.

## Global Constraints

- Deployment target iOS 17.0; Swift 5.9. No new dependencies.
- The `.xcodeproj` is generated and gitignored — run `xcodegen generate` **after** creating or renaming files, then build.
- **Existing behaviour is inviolable.** `UnlockService`, `RecoveryCodeService`, `NFCService`, `HomeViewModel`, `ConfigStore`, and `RestrictionService` are not modified. Every button must keep calling exactly what it calls today. If a restyle seems to require a logic change, stop and report BLOCKED.
- Named colours from the `PW` enum — no literal hex.
- **Clay is the exit colour.** Every control that removes, lifts, or bypasses a restriction uses `PW.clay`. Never red, never sage. The single exception is `PW.warn`, used for exactly one line: the irreversible recovery-code reveal.
- Text floor: **13px minimum** on every `Text`.
- Copy rule: the word **"free"** is banned. Blocked time is "quiet", unrestricted time is "open".
- Reuse `GlyphOrb`, `NFCWaves`, `GlassOrb`, and `OrbGlow` from `Paperweight/Views/Components/QuietGlassMotifs.swift`. Do not write new orb or ripple drawing code.
- Any perpetual animation must respect `@Environment(\.accessibilityReduceMotion)`, matching the pattern already used by `HomeView` and `QuietThemePicker`.

## Do not build the Watch toggle

Screen 04 of the design shows a **"Require Watch tap — Confirm unlocks on your wrist"** toggle. **This app has no Watch support**: there is no watchOS target in `project.yml` and no `WatchConnectivity` anywhere in the source. Building the toggle would put a control on screen that claims to add a security confirmation and silently does nothing — in an app whose entire value is a lock you can trust, that is worse than omitting it.

Omit it. If Watch support is ever built, the toggle comes with it.

**Test command:**

```bash
xcodegen generate && xcodebuild test -project Paperweight.xcodeproj -scheme PaperweightTests -destination 'platform=iOS Simulator,name=iPhone 17' CODE_SIGNING_ALLOWED=NO
```

**Build command:**

```bash
xcodegen generate && xcodebuild build -project Paperweight.xcodeproj -scheme Paperweight -destination 'platform=iOS Simulator,name=iPhone 17' CODE_SIGNING_ALLOWED=NO
```

The suite is 107 tests and must stay there — this PR adds no testable logic.

---

### Task 1: Make these screens reachable in a simulator

Two of the four screens are gated behind `vm.config.isEnabled`, and the app can never arm in a simulator because Screen Time does not exist there. Without this, Tasks 3 and 4 cannot be verified at all.

**Files:**
- Modify: `Paperweight/DebugSettings.swift`
- Modify: `Paperweight/Views/SettingsView.swift`

**Interfaces:**
- Produces: `DebugSettings.forceArmed` — a presentation-only override, `#if DEBUG` only.

- [ ] **Step 1: Add the flag**

In `Paperweight/DebugSettings.swift`, inside the existing `#if DEBUG` block, add alongside `forceQuiet`:

```swift
    private static let forceArmedKey = "debug.forceArmed"

    /// Makes the UI show the screens that only appear once Paperweight is armed.
    /// Presentation only — it never arms anything and never restricts an app.
    @Published var forceArmed: Bool {
        didSet { UserDefaults.standard.set(forceArmed, forKey: Self.forceArmedKey) }
    }
```

and in `init()`:

```swift
        forceArmed = UserDefaults.standard.bool(forKey: Self.forceArmedKey)
```

- [ ] **Step 2: Gate the armed-only sections on it**

In `Paperweight/Views/SettingsView.swift`, add a computed property:

```swift
    /// Whether to show the sections that only exist once Paperweight is armed.
    private var showsArmedSections: Bool {
        #if DEBUG
        if debug.forceArmed { return true }
        #endif
        return vm.config.isEnabled
    }
```

Replace the two places that currently read `vm.config.isEnabled` for **display gating** with `showsArmedSections`: the `if vm.config.isEnabled` wrapping the "Deviation" section, and the Emergency unlock row's `titleColor` / `value` / `showsChevron` / `.disabled(...)`.

Do **not** change anything that reads `vm.config.isEnabled` to make a real decision — only display gating.

- [ ] **Step 3: Add the toggle to the Developer section**

In the `#if DEBUG` Developer section, add above the existing "Force quiet screen" toggle, followed by a `CardDivider()`:

```swift
                    Toggle(isOn: $debug.forceArmed) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Show armed-only screens")
                                .font(.grotesk(15))
                                .foregroundStyle(PW.textPrimary)
                            Text("Reveals Emergency unlock and Turn off. Nothing is armed and nothing is blocked.")
                                .font(.grotesk(13))
                                .foregroundStyle(PW.textMuted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .toggleStyle(PWToggleStyle())
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
```

- [ ] **Step 4: Verify Debug and Release both build**

Run the build command, then:

```bash
xcodebuild build -project Paperweight.xcodeproj -scheme Paperweight -configuration Release -destination 'platform=iOS Simulator,name=iPhone 17' CODE_SIGNING_ALLOWED=NO
```

Expected: both `BUILD SUCCEEDED`. The Release build proves nothing outside `#if DEBUG` touched the new flag.

- [ ] **Step 5: Commit**

```bash
git add Paperweight/DebugSettings.swift Paperweight/Views/SettingsView.swift
git commit -m "debug: reveal the armed-only screens without arming"
```

---

### Task 2: Screen 04 — NFC Token & Recovery

**Files:**
- Modify: `Paperweight/Views/NFCSetupView.swift`

Read the file first. Keep every action, binding, alert, and NFC call exactly as it is; change only presentation, structure, and copy.

Target, section by section, each headed by `Text(...).pwScreenLabel()`:

- **Physical token** — a `GroupedCard` with a row reading "Registered token" and, trailing, the stored tag UID in `PW.textMuted` with slight tracking. If no tag is registered, the row instead reads "No token registered" and its action registers one. Beneath, separated by a `CardDivider()`, a row whose title is "Replace token…" in `PW.clay`.
- **Unlock duration** — a four-up selector across the full width offering 5m / 15m / 30m / 1h, bound to the existing `unlockDuration` value. The selected option has a 2pt `PW.sage` border, a `PW.sage.opacity(0.08)` fill, and `PW.dawnGlow` semibold text; unselected options have a 1pt `Color.white.opacity(0.16)` border and `PW.textMuted` text. Corner radius 10. Do not use `PWSegmented` — its selected style is a filled sage pill, which is louder than this design wants for a control that governs an exit.
- **Recovery codes** — a `GroupedCard` with a row "Codes remaining" showing `N of M` (unused of total), then a `CardDivider()`, then a row "Cool-off if token lost" showing the current `coolOffDays` as e.g. "1 day" / "3 days", tapping through to whatever control exists today for changing it.

Omit the Watch toggle entirely (see Global Constraints).

- [ ] **Step 1: Restyle the view** — preserving every existing action and alert.
- [ ] **Step 2: Build** — expect `BUILD SUCCEEDED`.
- [ ] **Step 3: Screenshot it.** Home → gear → "NFC Token & Recovery". Read the image back before describing it. Confirm the three sections, the four-up duration selector with one option selected, and no Watch toggle. Save to `.superpowers/sdd/s04-nfc.png`.
- [ ] **Step 4: Commit** — `git commit -m "feat: restyle NFC Token & Recovery to v2"`

---

### Task 3: Screen 05 — Emergency unlock

**Files:**
- Modify: `Paperweight/Views/UnlockView.swift`

Read the file first. The unlock flow, NFC scan call, and timer behaviour stay exactly as they are.

Target — clay throughout, because this is an exit:

- Centred, a `GlyphOrb` in its dim variant carrying a closed-padlock glyph in `PW.clay`, with `NFCWaves` behind it — two rings expanding and fading on a 2.6s cycle, the second offset by half. Reuse the existing components; do not draw new rings. The animation must stop when `accessibilityReduceMotion` is on.
- Below it, `Text("A way out, briefly.")` in `.spectral(26)`, `PW.textPrimary`.
- Below that, centred body text: "Tap your NFC token to lift restrictions for **N minutes**. The quiet returns on its own." — where N comes from the configured unlock duration, rendered in `PW.textPrimary` against the surrounding `PW.textMuted`.
- Pinned at the bottom, the action: a 48pt control with `PW.clay.opacity(0.12)` fill, `PW.clay` semibold 15pt label reading "Scan token…", corner radius 14, with the existing NFC glyph leading it.
- Under it, centred at 13pt in `PW.textMuted`: "Lost your token?" followed by an underlined "Use a recovery code" in `PW.textMuted` that triggers the existing recovery-code path.

If the screen currently shows a live countdown while an unlock is running, keep it — that state is not in the design but removing it would lose information the user needs.

- [ ] **Step 1: Restyle the view.**
- [ ] **Step 2: Build.**
- [ ] **Step 3: Screenshot it.** Turn on the debug "Show armed-only screens" toggle from Task 1, then Home → gear → "Emergency unlock". Read the image back. Confirm the clay orb, the ripples, the headline, and the clay scan button. Save to `.superpowers/sdd/s05-unlock.png`.
- [ ] **Step 4: Commit** — `git commit -m "feat: restyle Emergency unlock to v2"`

---

### Task 4: Screen 06 — Turn off (sheet)

**Files:**
- Modify: `Paperweight/Views/DisablePaperweightSheet.swift`

Read the file first. Every disable path — NFC scan, recovery code, cool-off request — keeps its exact current behaviour.

Target:

- The sheet is `PW.surfaceRaised` with 30pt top corners and the drag indicator it already has.
- Centred at the top of the sheet, a `GlyphOrb` (dim) carrying a **broken** padlock glyph in `PW.clay` — a padlock with a stroke through it.
- `Text("Turn off Paperweight")` in `.spectral(25)`.
- Body, centred, `PW.textMuted`, max ~30 characters per line: "Scan your NFC token to remove all restrictions. The forest stops growing."
- Three actions, in this order and this visual weight:
  1. "Scan NFC token…" — filled `PW.clay.opacity(0.12)`, `PW.clay` label, 48pt, radius 14, NFC glyph leading.
  2. "Use a recovery code" — outlined, `Color.white.opacity(0.12)` border, `PW.textMuted` label, 46pt, radius 14.
  3. "Not now" — plain text, `PW.textMuted` semibold 15pt, 44pt tall, no border.
- Then a hairline divider, and beneath it the timed-unlock affordance: a clay 13pt line with a small clock glyph reading "Lost your token? Start timed unlock", and under it in `PW.textLabel` at 13pt: "Releases on its own after a N-day cool-off." — N from `coolOffDays`.
- If a cool-off is already pending, that block instead reports when it releases, as it does today.

- [ ] **Step 1: Restyle the sheet.**
- [ ] **Step 2: Build.**
- [ ] **Step 3: Screenshot it.** With "Show armed-only screens" on: Home → gear → "Turn off Paperweight". Read the image back. Confirm the broken-padlock orb, the three actions in descending weight, and the clay cool-off block. Save to `.superpowers/sdd/s06-turnoff.png`.
- [ ] **Step 4: Commit** — `git commit -m "feat: restyle the turn-off sheet to v2"`

---

### Task 5: Screen 07 — Recovery codes

**Files:**
- Modify: `Paperweight/Views/RecoveryCodesView.swift`

Read the file first. Code generation, persistence, and the one-time reveal all keep their current behaviour.

Target:

- Centred at the top, a small `GlyphOrb` carrying a magnifier-over-key glyph in `PW.dawnGlow`, about 46pt.
- `Text("Save your codes")` in `.spectral(24)`, centred.
- Centred body in `PW.textMuted` at 13pt: "Each works once. Keep them somewhere you can reach without your phone."
- The codes themselves, one per row, full width: `PW.surfaceRaised` fill, `Color.white.opacity(0.12)` border, radius 10, 12pt vertical padding, centred text at 15pt semibold with `.tracking(2)`, in `PW.textPrimary`. Format each code with a mid-point separator, e.g. `4K9F2 · X7M3Q`, splitting the existing code string in half rather than changing how codes are generated.
- Below them, "Copy all codes" as a secondary action: `PW.deepForest` fill, `PW.sage.opacity(0.25)` border, `PW.dawnGlow` semibold 14pt label with a copy glyph, 48pt, radius 14. Keep whatever clipboard call exists today.
- Closing line, centred, 13pt, in `PW.warn` — the one and only place this colour is used: "These codes will not be shown again."

- [ ] **Step 1: Restyle the view.**
- [ ] **Step 2: Build.**
- [ ] **Step 3: Screenshot it.** Home → gear → "NFC Token & Recovery" → generate codes. Read the image back. Confirm the code rows, the separator formatting, the copy action, and the single warn-coloured line. Save to `.superpowers/sdd/s07-codes.png`.
- [ ] **Step 4: Commit** — `git commit -m "feat: restyle Recovery codes to v2"`

---

### Task 6: Open the pull request

- [ ] **Step 1: Run the full suite** — expect 107 passing, unchanged.
- [ ] **Step 2: Create the issue**

```bash
gh issue create --title "Restyle the escape-hatch screens to the v2 design" --body "The four screens a user reaches when they need out — NFC Token & Recovery, Emergency unlock, the turn-off sheet, and Recovery codes — are still on the v1 styling.

Bring them to App Screens v2: clay for every exit, the state named plainly, and no control louder than it needs to be.

Spec: docs/superpowers/specs/2026-08-01-app-screens-v2-design.md section 3, screens 04-07"
```

- [ ] **Step 3: Push and open the PR**, closing that issue, and noting in the body that the design's Watch toggle was deliberately not built because the app has no Watch support.
