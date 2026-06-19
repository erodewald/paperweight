# Handoff: Paperweight — "Quiet Glass" Design Language

## Overview
Paperweight ("Brick Mode") turns an iPhone into a paperweight: on a schedule, all distracting apps are shielded, and the only escape hatch is tapping a physical NFC token. This package is the **visual design language ("Quiet Glass")** and its application to every screen of the existing SwiftUI app, plus the App Icon and App Store screenshot designs.

The product feeling: *a heavy, calm object on a still desk.* True OLED black, one warm-green accent, a glass paperweight motif, and a calm/poetic voice. Nothing pulses for attention.

## About the Design Files
The files in `designs/` are **design references authored in HTML** (they open in any browser). They are prototypes of the intended look — **not** production code to copy. Your task is to **recreate this look in the existing SwiftUI codebase** (the app already exists — see "Mapping to the existing code" below), restyling the current `List`/`Form`-based views into the Quiet Glass language using native SwiftUI, while keeping all existing logic, view-models, and services intact.

`designs/support.js` is only the runtime that renders the HTML prototypes — **ignore it** for implementation.

## Fidelity
**High-fidelity.** Final colors, typography, spacing, and component treatments. Recreate pixel-faithfully with SwiftUI. The existing app logic (FamilyControls, ScheduleService, NFCService, UnlockService, ConfigStore, WatchConnectivity, recovery codes, cool-off) stays exactly as-is — this is a **restyle of the view layer only**.

---

## Design Tokens

### Color palette (exact hex)
| Token | Hex | Use |
|---|---|---|
| `black` | `#000000` | App background (OLED — true black) |
| `surface` | `#0B0F0B` | Cards, grouped rows |
| `surfaceRaised` | `#0C100C` | Sheets |
| `deepForest` | `#16251A` | Schedule "blocked" cells, base shadow |
| `moss` | `#5E8C4F` | Schedule "free" cells, toggle-on track |
| `mossLight` | `#6F9C5E` | Weekday free cells (slightly lighter) |
| `sage` | `#9DC47B` | **Primary action / accent.** Buttons, progress ring, active states |
| `dawnGlow` | `#BCE890` | Brightest accent — glints, NFC waves, glow |
| `clay` | `#C8A27B` | **Escape-hatch / destructive** (Replace token, lost-token, timed unlock, broken-lock glyph) |
| `textPrimary` | `#ECF1E6` | Primary text |
| `textMuted` | `#8E9A86` | Secondary text, body |
| `textFaint` | `#5A6356` | Captions, section labels, chevrons |
| `textFaintest` | `#4A5247` | Grid hour labels |
| `warn` | `#9A6A6A` | The one red-ish warning line (irreversible code reveal) |
| `onAccent` | `#0A140B` | Text/icon on top of a sage button |

Hairlines/strokes: `rgba(255,255,255,0.07)` (card borders), `rgba(255,255,255,0.06)` (row separators), `rgba(188,232,144,0.3–0.5)` (orb rim).

**Color rule:** Sage is the *only* action color — the way out is never louder than the calm. Escape/destructive steps use muted `clay`, not red. The only red (`warn`) is the single "codes won't be shown again" line.

```swift
// Theme.swift
import SwiftUI

extension Color {
    init(hex: UInt, alpha: Double = 1) {
        self.init(.sRGB,
            red:   Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue:  Double(hex & 0xFF) / 255,
            opacity: alpha)
    }
}

enum PW {
    static let black        = Color(hex: 0x000000)
    static let surface      = Color(hex: 0x0B0F0B)
    static let surfaceRaised = Color(hex: 0x0C100C)
    static let deepForest   = Color(hex: 0x16251A)
    static let moss         = Color(hex: 0x5E8C4F)
    static let mossLight    = Color(hex: 0x6F9C5E)
    static let sage         = Color(hex: 0x9DC47B)
    static let dawnGlow      = Color(hex: 0xBCE890)
    static let clay         = Color(hex: 0xC8A27B)
    static let textPrimary  = Color(hex: 0xECF1E6)
    static let textMuted    = Color(hex: 0x8E9A86)
    static let textFaint    = Color(hex: 0x5A6356)
    static let onAccent     = Color(hex: 0x0A140B)
    static let hairline     = Color.white.opacity(0.07)
    static let separator    = Color.white.opacity(0.06)
}
```
Set the app to dark only and the window/list background to `PW.black` (`.scrollContentBackground(.hidden)` + `.background(PW.black)` on `List`/`Form`).

### Typography
Two families do all the work:
- **Spectral** (serif, Light 300 + Light Italic) — display headings, time labels' caption, and **every poetic/encouragement line** (usually *italic*). Letter-spacing `-0.01em` to `-0.02em` on large sizes.
- **Schibsted Grotesk** (400/500/600/700) — all interface: nav titles, buttons, timers (big bold numerals), section labels, values, codes.

(Hanken Grotesk is used for small body in the prototype; in-app you can use Schibsted Grotesk or SF for body — Spectral + Schibsted is the essential pairing.)

Both are free Google Fonts (OFL). Add the `.ttf`s to the target, list them in Info.plist under `UIAppFonts`, and register a helper:
```swift
extension Font {
    static func spectral(_ size: CGFloat, italic: Bool = false) -> Font {
        .custom(italic ? "Spectral-LightItalic" : "Spectral-Light", size: size)
    }
    static func grotesk(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom("SchibstedGrotesk-\(weight.name)", size: size) // map weight→PostScript name
    }
}
```

**Type scale (pt ≈ the px in the mocks at @1x):**
| Role | Font | Size | Weight | Notes |
|---|---|---|---|---|
| Hero display | Spectral | 46–52 | 300 | line-height ~1.0, tracking −0.02em |
| Screen title (serif) | Spectral | 34 | 300 | e.g. Home "Paperweight" |
| Nav bar title | Schibsted | 16 | 600 | centered, inline |
| Timer numerals | Schibsted | 32–34 | 700 | "2h 14m" |
| Body / row label | Schibsted/Hanken | 14.5–15 | 400 | |
| Encouragement | Spectral italic | 16–18 | 300 | `PW.textMuted`/`#A9B5A1` |
| Section label | Schibsted | 11 | 600 | UPPERCASE, tracking 0.18em, `textFaint` |
| Eyebrow ("BRICK MODE") | Schibsted | 11–13 | — | UPPERCASE, tracking 0.28em, `sage`/`textFaint` |
| Caption / value | Schibsted | 12.5–13 | 400 | `textMuted`/`textFaint` |

### Spacing, radius, shadow
- Screen horizontal padding: **18px** (settings lists), **26–30px** (centered/hero screens).
- Card/grouped corner radius: **16**. Buttons/segmented: **12–14**. Sheets: **30** (top corners). Code chips: **9–10**. Schedule grid: **6**.
- Row vertical padding: **13–15**. Card inner padding: **18**.
- Card: `surface` fill + 1px `hairline` border. Separators between rows: 1px `separator`.
- Accent button glow: `shadow(color: sage.opacity(0.28), radius: 14)` (≈ `0 0 28px`).
- Orb glow: soft radial `sage @ 0.2 → clear`, optional 8s pulse (opacity .55→.92, scale 1→1.04).

---

## Signature components (build these as reusable SwiftUI views)

### 1. GlassOrb
The paperweight. A circle filled with a radial gradient (key light top-left) + a suspended leaf + a specular highlight. Used at many sizes (40 → 196).
- Radial fill stops (center→edge): `#F0FADA` → `#B0D68A @0.74` → `#5E8C4F @0.62` → `#28422A @0.7` → `#0A140C @0.86`. Gradient center at ~38–40% / 30% (top-left).
- Rim stroke: `dawnGlow.opacity(0.3–0.5)`, 1–3px.
- Leaf: vertical sage→moss gradient, centered, height ≈ 48% of orb diameter, with a faint `#2E4A30` spine.
- Highlight: white ellipse `opacity 0.5`, rotated −28°, upper-left.
- A "dim" variant (`gOrbDim`) for unlock/recovery: muted gray-green fill, used behind lock/key glyphs.

### 2. ProgressRing
Thin ring around the orb on the Home-quiet screen. Track `white.opacity(0.07)` 2px; progress stroke `sage` 2.5px, round cap, starts at top (−90°), `drop-shadow(sage 0.6, 6px)`. Represents time remaining in the current quiet window.

### 3. Grouped card + Row
Replaces iOS inset-grouped `List` sections. A `surface` rounded-16 container; each row 15px-padded `HStack` (icon? · label · trailing value · chevron). Chevron = 8×13 `>` stroke in `textFaint`. Section label above in the uppercase faint style.

### 4. Segmented control (unlock duration)
`surface` pill, 4px padding; selected segment = `sage` fill, `onAccent` 600 text, radius 9; unselected = `textMuted`.

### 5. Toggle (watch confirmation)
Custom: 44×26 track, on = `moss` with `sage` glow; 20px white knob.

### 6. Accent button & ghost button
- Primary: `sage` fill, `onAccent` 600 text, radius 14, sage glow. Optional leading icon (NFC waves) in `onAccent`.
- Ghost/secondary: transparent, 1px `hairline` (or `sage.opacity(0.3)`), `textMuted`/`sage` text.
- Escape link: plain text, `clay` for the destructive part.

### 7. NFC scan glyph + waves
Concentric expanding rings behind the dim orb (`pwWave`: scale .6→1.9, opacity .7→0, 2.6s, staggered). The wave-3 icon (`􀙫`-like) drawn as three nested arcs.

---

## Screens (mapping to the existing code)

Each maps to a current SwiftUI view. **Restyle only** — keep the logic/bindings.

### Home — `Views/HomeView.swift`
Two visual states from one screen:
- **Quiet (Paperweight active & currently blocking):** full-screen centered GlassOrb + ProgressRing; below it Schibsted 700 timer "2h 14m" + Spectral-italic "of quiet remaining"; a rotating Spectral-italic encouragement near the bottom; a hairline footer row "N apps quiet" (left) and a faint "Settings" gear (right) that opens the settings list. Eyebrow "BRICK MODE" (tracking 0.28em, `sage`) at top. *(New presentation of the existing "Paperweight Active" state — tapping the footer/gear leads to the list, and the disable flow is still the NFC-gated `DisablePaperweightSheet`.)*
- **Setup (off):** Spectral 34 "Paperweight" title; status card ("Paperweight is off" + the existing explainer copy); "RESTRICTED APPS" grouped card (Choose Apps & Categories row → `familyActivityPicker`, with the selection summary beneath); "CONFIGURE" grouped card with the three existing `NavigationLink`s — Schedule (trailing status), NFC Token & Recovery, Emergency Unlock. Footer: Spectral-italic "Put it down. The world keeps turning."

Copy is unchanged from the current `HomeView`.

### Schedule — `Views/ScheduleView.swift`
The existing 7-day × 48-half-hour paint grid, restyled: **free = `moss`/`mossLight`, blocked = `deepForest`** (replaces green/systemGray5), on black. Day header `S M T W T F S` in faint 11/600. Left hour-label column (`12a 6a 12p 6p 12a`) in `textFaintest` 8–9pt. Horizontal hour gridlines = `rgba(0,0,0,0.28)` overlay. Keep the drag-to-paint gesture, the "N free hours/week" caption, the wand presets menu (top-right, `sage`), and the blocked-now warning (restyle the orange warning to `clay`). Save button: full-width `sage` accent button "Save schedule".

### NFC Token & Recovery — `Views/NFCSetupView.swift`
Grouped cards replacing the `Form`:
- **PHYSICAL TOKEN:** "Registered Token" + UID value (`04:A2:9F:1C`), with a leading NFC-arc icon; "Replace Token" row in `clay`. (If none registered: single "Register NFC Token" `sage` row.)
- **UNLOCK DURATION:** segmented 5m / **15m** / 30m / 1h (tags 300/900/1800/3600).
- **WATCH CONFIRMATION:** custom toggle "Require Watch tap" + subtext.
- **RECOVERY CODES:** "Codes Remaining 8 of 10"; "Cool-off if token lost" picker row (1/2/3 days). Regenerate in `clay`.
All copy and bindings as in the current view.

### Emergency Unlock — `Views/UnlockView.swift`
Centered dim GlassOrb with a lock glyph (`dawnGlow` stroke) and animated NFC waves; Spectral 26 "Emergency unlock"; muted explainer; full-width `sage` "Scan token" button (NFC-wave leading icon) — disabled when `registeredNFCTagUID == nil`; faint "Lost your token? Use a recovery code" link below (the underlined part `textMuted`). Unlocked state: swap to the open-lock treatment + "Re-locks at …" + bordered "Re-lock Now".

### Turn Off (sheet) — `Views/DisablePaperweightSheet.swift`
Bottom sheet over a dimmed Home: grabber; **broken-lock orb in `clay`** (lock.slash); Spectral 25 "Turn off Paperweight"; explainer; primary `sage` "Scan NFC token"; ghost "Use a recovery code"; divider; `clay` "Lost your token? Start timed unlock" + faint "Releases on its own after a 1-day cool-off." Keep the two confirmationDialogs and the cool-off logic.

### Recovery Codes — `Views/RecoveryCodesView.swift`
Centered key-in-dim-orb glyph; Spectral 24 "Save your codes"; explainer; the codes as `surface` rounded chips, Schibsted 600 with 0.14em tracking; ghost "Copy all codes" (`sage` outline); the single `warn` line "These codes will not be shown again." "Done" in nav bar (`sage`).

### RecoveryCodeEntryView (sheet, in DisablePaperweightSheet.swift)
Same language: key glyph, centered monospace/Schibsted code field on `surface`, `sage` "Verify & Disable" button. (Not separately mocked — follow the Recovery Codes + sheet patterns.)

### watchOS (`PaperweightWatch/Views/*`)
Not separately mocked. Apply the same tokens: black background, `sage` status accent, Schibsted for labels, the dim-orb + waves motif for `ConfirmUnlockView`.

---

## Interactions & motion
- **Orb glow pulse:** opacity .55→.92, scale 1→1.04, 8s ease-in-out, infinite (Home-quiet, closing screen).
- **NFC waves:** expanding rings, 2.6s, 2 staggered (1.3s delay).
- **Unlock state change:** spring on lock→open (existing `.animation(.spring(), value: isUnlocked)`).
- **Schedule paint:** existing drag gesture — unchanged.
- Keep all existing navigation, alerts, confirmationDialogs, scenePhase re-sync, and Home-screen quick actions.

## State management
Unchanged. All state lives in the existing `HomeViewModel` (`@Published config`, error, cool-off helpers), `ConfigStore` (App Group), `UnlockService`, `ScheduleService`, `WatchConnectivityService`, `RecoveryCodeService`. This handoff adds **no** new state — only view styling. Color/Font live in a new `Theme.swift`; reusable views (`GlassOrb`, `ProgressRing`, grouped card/row, segmented control, toggle, buttons) in a new `Views/Components/` group.

---

## App Icon
`assets/AppIcon.svg` is the master (1024×1024). Pre-rendered PNGs: `AppIcon-1024/512/180/120.png`.
- Full-bleed; **no transparency, no rounded corners** (iOS masks). Canvas = radial near-black (`#101E12 → #000`).
- Glass orb at ~58% of canvas, centered, with the suspended leaf, warm-green through-light from below, `dawnGlow` rim, top-left specular highlight + a small bright glint.
- Generous dark margin so it survives the rounded mask and reads at 29pt.
- Create an **AppIcon** image set (or single 1024 for Xcode 14+ single-size). `ASSETCATALOG_COMPILER_APPICON_NAME` is already `AppIcon` in `project.yml`. Re-render other sizes from the SVG if needed.

## App Store screenshots
`designs/Paperweight App Store.dc.html` defines **5 captioned 6.7" frames (author size 1290 × 2796)**. Standard practice: capture the *real* screens from the running app (iPhone 15 Pro Max simulator) and composite the caption + background over them. Specs per frame:
1. **"Put it down."** — eyebrow BRICK MODE; caption over the Home-quiet orb screen. BG: radial `#142013 → #000`.
2. **"Lock the apps that own you."** — over the Schedule grid. BG: radial `#101a12 → #000`.
3. **"A way back, on your terms."** — over Emergency Unlock (orb + waves + Scan token). BG `#142013 → #000`.
4. **"Never truly locked out."** — over Recovery Codes + "Or wait out a 1-day cool-off" (`clay`). BG `#101a12 → #000`.
5. **"The quiet returns." / "Less screen. More of everything else."** — closing brand frame: glowing orb + icon + wordmark, no device. BG radial `#16271A → #000`.
Captions: Spectral Light 40–50pt headline (white `#ECF1E6`) + Spectral Light Italic 18–19pt subhead (`#A9B5A1`), centered, device screen anchored to the bottom.

---

## Files
- `designs/Paperweight Design Language.dc.html` — the system (color, type, forest illustration, voice, both explored directions; **Direction A "Quiet Glass" was chosen**).
- `designs/Paperweight App Screens.dc.html` — all 7 app screens in Quiet Glass (the primary implementation reference).
- `designs/Paperweight Icon.dc.html` — icon showcase + construction notes.
- `designs/Paperweight App Store.dc.html` — the 5 App Store frames.
- `assets/AppIcon.svg` + PNGs — icon master and exports.
- Open any `.html` in a browser to view. (`support.js` is just the prototype runtime — ignore.)

## Notes
- The design system is dark-only by design (OLED). Do not add a light theme.
- Do not introduce new accent hues. Sage for action, clay for the exit, one red warning line.
- Keep the copy verbatim from the existing views and these mocks — the calm/poetic voice is part of the product.
