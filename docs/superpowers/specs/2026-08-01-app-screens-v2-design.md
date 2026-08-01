# Paperweight — App Screens v2 ("The app, clarified")

**Date:** 2026-08-01
**Source:** Claude Design project `3acc771c-772c-44b0-86c2-fad67e8c2ccf`
— `Paperweight App Screens v2.dc.html`, `Paperweight Motion Study.dc.html`, `MotionStudy.jsx`.
**Supersedes:** the v1 "Quiet Glass" handoff (already shipped; see `design_handoff_paperweight/`,
which is gitignored — this spec is the committed record of what v2 asks for).

---

## 1. What v2 is

v1 was a restyle: the same screens, dressed in Quiet Glass. v2 is a **clarification of the
information architecture**. Its own summary:

> State is a headline banner on every screen, never inferred. The timer says what it counts
> ("left · unlocks at"). Green now always means quiet — the schedule paints locked hours, and
> "free" is banned from copy. No top-level start/stop: the schedule drives, deviation lives deep
> and wears clay `#C8A27B`. Text floors: 13px / 4.6:1 minimum. The locked home carries the
> Diorama scene (user pref: Simple / Diorama / Overgrown).

Design language and tokens are unchanged (the v2 header reads "Paperweight DS v1"). All
services, view-models, and stores stay as they are, with the two exceptions in §6.

## 2. Architecture

Home stops being a settings list. Today `HomeView` is a `NavigationStack` around a settings
list with a full-screen `QuietScreen` orb layered over it while quiet. v2 makes Home a real
screen with two states and moves the list behind a gear.

```
HomeView (nav root)                          ← screens 01 (locked) / 02 (open)
 ├ nav-bar gear → SettingsView                 ← the old settings list, now its own screen
 │    ├ Restricted apps        (familyActivityPicker)
 │    ├ Schedule               → ScheduleView              ← 03
 │    ├ NFC Token & Recovery   → NFCSetupView              ← 04
 │    ├ Emergency unlock       → UnlockView                ← 05
 │    ├ Locked screen          → LockedScenePicker         ← new
 │    └ Turn off Paperweight   → DisablePaperweightSheet   ← 06
 └ "View schedule" / "Edit schedule" → ScheduleView
```

`QuietScreen` and `HoldToUnlockButton` are **deleted**. v2 has no hold-to-unlock control, and
the locked state is Home itself rather than a cover over it.

### The locked-Home escape route

Screen 01 shows only "View schedule" plus the footer "Emergency unlock lives in Settings —
never here", and draws no route to Settings. Taken literally that leaves no in-app path to the
escape hatch while locked, which is unacceptable for a lock whose whole promise is that you are
never stranded.

**Resolution:** the locked Home carries a small settings glyph in the nav bar. This honors
"never here" — no unlock control on the Home surface — while keeping Settings, and therefore
Emergency unlock, one tap away in every state.

## 3. Screens

### 01 · Home — locked
- Banner card: `● LOCKED` (10px/`.24em`/`#BCE890`, 700) over `Down until **7:00 AM**` in
  Spectral Light 26. Card is `#0C100C` with a top radial wash of `rgba(188,232,144,.16)` and a
  `rgba(188,232,144,.4)` border.
- Countdown: `2:14` at 44/700 with a `left` suffix; 6px progress bar filled
  `linear-gradient(90deg, #5E8C4F, #BCE890)`; `Unlocks at **7:00 AM**` beneath.
- The scene (§4) fills the remaining space.
- Secondary button "View schedule": `#16251A` / `#BCE890`, 14px radius, 48pt.
- Footer, `#5A6356`: "Emergency unlock lives in Settings — never here."

### 02 · Home — open
- Banner: `○ OPEN` over `In your hands.` and `Locks tonight at **9:00 PM** · in 4h 32m`.
- "This week" strip: seven rows, each a 15pt proportional bar of locked (`#5E8C4F`) vs open
  (`rgba(255,255,255,.04)`) segments; a fully-open day renders as a dashed outline reading
  `OPEN ALL DAY`. Legend: "Locked — quiet" / "Open".
- "Restricted apps · N apps" row → picker.
- Primary button "Edit schedule": `#9DC47B` on `#0A140B`, 52pt, 15px radius.

### 03 · Schedule
- Day-across / hour-down grid, unchanged in layout — but **inverted in meaning**: painted
  (`#5E8C4F`) = locked, unpainted (`rgba(255,255,255,.04)`) = open.
- Hour axis labels at 12a / 6a / 12p / 6p / 12a; hour rules every 1/8 of height.
- Copy: title "Schedule", subtitle "Paint your quiet hours.", footer "N quiet hours this week"
  (= `168 - freeHourCount`), then "Loosening today's lock takes effect tomorrow." (§6b)
- Primary "Save schedule".

### 04 · NFC Token & Recovery
Sections: **Physical token** (registered UID, "Replace token…" in clay) · **Unlock duration**
as a four-up segmented control (5m / 15m / 30m / 1h; selected = 2px `#9DC47B` border,
`rgba(157,196,123,.08)` fill, `#BCE890` text) · **Require Watch tap** toggle · **Recovery
codes** (codes remaining, cool-off duration).

### 05 · Emergency unlock
Clay throughout. Centered dim orb (`gOrbDim`) with a padlock glyph and two ripple rings on a
2.6s expand-and-fade, 1.3s apart. Spectral 26 "A way out, briefly." over "Tap your NFC token to
lift restrictions for **15 minutes**. The quiet returns on its own." Action "Scan token…" is
`rgba(200,162,123,.12)` / `#C8A27B`. Footer links to a recovery code.

### 06 · Turn off (sheet)
Dimmed orb backdrop at 0.32 under a `rgba(0,0,0,0.55)` scrim; sheet is `#0C100C` with 30px top
corners and a drag indicator. Broken-padlock clay glyph, "Turn off Paperweight", "Scan your NFC
token to remove all restrictions. The forest stops growing." Actions: Scan NFC token… (clay
fill) / Use a recovery code (outline) / Not now (plain). Divider, then the clay timed-unlock
affordance: "Lost your token? Start timed unlock" + "Releases on its own after a 1-day cool-off."

### 07 · Recovery codes
Magnifier-over-orb glyph, "Save your codes", "Each works once. Keep them somewhere you can reach
without your phone." Four code cards at 15/600 with `.14em` tracking, formatted `4K9F2 · X7M3Q`.
"Copy all codes" in the `#16251A`/`#BCE890` secondary style. Closing line in the single warn
tone `#9A6A6A`: "These codes will not be shown again."

## 4. The locked-Home scene

Three styles, user-selectable, defaulting to Diorama. All geometry below is lifted from
`MotionStudy.jsx`; the study's card is 780×430 and coordinates scale to the phone frame.

### Motion grammar (`PWMotion`)

Four verbs, and every easing in the design is one of them:

| Verb | Definition | Meaning |
|---|---|---|
| `settle(u)` | `1 - (1-u)³` | weight lands: fast in, soft stop, never a bounce |
| `grow(u)` | back-out, `c1 = 0.16·7`, `c3 = c1+1`, `1 + c3x³ + c1x²` where `x = u-1` | sprout: overshoot, then rest |
| `rest(t, φ)` | `3.6° · sin(2πt/14 + φ)` | nothing is ever still — a slow sway |
| `release` | the reverse at double speed, half the light | leaving is not celebrated |

Phase map, as fractions of a transition: `openEnd .10`, `settleEnd .28`, `growStart .24`,
`growEnd .58`, `restEnd .78`, `releaseEnd .90`. Lock amount
`L = settle(ramp(p, .10, .28)) · (1 - settle(ramp(p, .78, .90)))`. Per-element sprout is
staggered across `[growStart, growEnd - .14]` with a `.14` window each; foliage folds first and
fast (`.07`) on release. `crawlAt` is the same with a `.26` window, used by Overgrown.

`swayDeg 3.6` / `swayPeriod 14` are the locked values — they match the `pwSway 14s` keyframes in
App Screens v2. (The fallback literals in `MotionStudy.jsx` are 1.6/8 and are *not* the intended
values; `TWEAK_DEFAULTS` in the study's HTML wins.)

**In-app, the choreography is a state transition, not a loop.** Growth plays once on entering
locked; `rest` runs continuously while locked; release plays on unlock.

### Simple
State text only, plus a centered Spectral italic line, `#A9B5A1`, fading in with `L`:
"Somewhere, a forest is filling in."

### Diorama
"A forest sprouts behind the words." Back-to-front, on `growAt(i, 8)`:
- Two ground ellipses, `#0E1810` (rx 470, ry 50) and `#0B140C` (rx 430, ry 30), opacity `L`.
- Four pines (flat triangles, `#101c12`, stroked 12 with round joins) at x 70/140/636/716,
  heights 140/104/128/94.
- Three blob trees at x 250 (s 1.3, dark), 580 (s 0.8, dark), 420 (s 1.5, front, bearing one
  `#BCE890` fruit). Trunk `#1a2c1c`; canopy `#1d3322` dark / `#2E4A30` front; highlight blobs
  one step lighter. Each canopy sways on `rest(t, φ)·g` about the trunk top, φ = 0 / 2.1 / 1.1.
- Five fireflies, `#BCE890`, on meandering paths (two incommensurate sines per axis) with a
  three-point fading trail and a 3.2r halo. Blink is *infrequent*: per-fly period
  `6.5 + (φ mod 2.4)`s, lit for 22% of it on a half-sine. Fireflies only appear once the front
  trees have grown.

### Overgrown
"The card is claimed at its corners." Procedural fir-frond sprigs on quadratic Béziers, five
front + three back at the top-right and two front + one back at the bottom-left, on
`crawlAt(i, 11)`. Each sprig: the stem draws in by dash-offset over the first 70% of its growth,
then `n` tapered leaflets (`ellipse rx=s ry=0.34s`) pop in order along it, alternating sides at
±52° off the curve tangent and shrinking to half size at the tip; front sprigs finish with a
`#BCE890` bud pulsing on a 4.2s sine. Back groups sit at 0.85 opacity and sway at 0.6× the front
groups, which rotate about the corner anchors.

### Plumbing
- `LockedScene: String, Codable, CaseIterable { simple, diorama, overgrown }` added to
  `PaperweightConfig`, default `.diorama`. The existing tolerant decoder means no migration.
- Picker row in `SettingsView`.
- Scenes are `Canvas`-drawn, take `(lock: Double, time: Double)`, hold no state, and know
  nothing about the schedule.
- Driven by `TimelineView(.animation(minimumInterval: 1/30))`, paused on `scenePhase != .active`
  so an idle locked Home is not redrawing at display rate.

## 5. Token and type updates

- `textMuted` `#8E9A86` → `#A3AF9B` (v2's secondary text).
- New `textLabel` `#7d8a75` for uppercase section labels.
- **13px floor, 4.6:1 minimum.** Today's `grotesk(11)` section headers, `grotesk(12)` captions,
  and `11.5` footnotes all come up to at least 13.

## 6. The two behavior changes

Everything else is presentation. These two are not, and are called out so they are not merged by
accident.

**(a) Green inverts meaning.** `ScheduleView` currently paints green for *free*; v2 paints green
for *locked* and bans "free" from copy. `freeSlots` remains the stored truth, so this is
presentation-only and existing saved schedules are untouched — but the same grid will read
inverted on first open. No migration, no data change.

**(b) Loosening is deferred to tomorrow.** The footer line on screen 03 describes behavior the
app does not have. Today the schedule is flatly read-only while armed
(`locked = vm.config.isEnabled`). v2 implies the schedule is editable while armed, with
*tightening* applying immediately and *loosening* deferred until tomorrow — which is a strictly
better property than read-only, because it cannot be used to slip a lock without the token. This
needs a pending-schedule concept in `ConfigStore`: the edited schedule is stored alongside the
active one and promoted at the next day boundary, while any slot the edit *adds* to the locked
set takes effect at once.

## 7. New units

| Unit | Responsibility |
|---|---|
| `Shared/Views/Motion/PWMotion.swift` | The four verbs and the phase map as pure functions. No SwiftUI; directly testable. |
| `Shared/Views/Scenes/LockedScene.swift` | The enum and a `view(lock:time:)` factory. |
| `…/SimpleScene.swift`, `DioramaScene.swift`, `OvergrownScene.swift` | One scene each, `Canvas`-drawn from §4. |
| `…/WeekStrip.swift` | Screen 02's seven-row summary; a pure function of a `PaperweightSchedule`. |
| `Paperweight/Views/SettingsView.swift` | The settings root that Home's gear pushes. |

## 8. Delivery

Four PRs, each closing its own plain-English issue, per the repo's convention.

| PR | Contents |
|---|---|
| 1 | Home restructured (01/02), new `SettingsView`, nav gear, `QuietScreen`/`HoldToUnlockButton` removed, token + type-floor updates. Scene slot renders **Simple** only. |
| 2 | `PWMotion` + all three scenes + `lockedScene` on config + picker row. |
| 3 | Schedule inverted (03), quiet-hours count, legend, hour axis — **and** deferred loosening (§6b). |
| 4 | Escape hatch: NFC/Recovery (04), Emergency unlock (05), Turn-off sheet (06), Recovery codes (07). |

PR 1 leaves the app briefly mixed — v2 Home over a v1 Schedule — which is the accepted cost of
staging.

## 9. Testing

- `PWMotion` verbs: endpoint identities (`f(0)=0`, `f(1)=1`), monotonicity of `settle`, and that
  `grow` actually overshoots above 1 before resting.
- `WeekStrip` segmentation and the "open all day" case, from fixed `freeSlots` sets.
- Quiet-hour arithmetic: `168 - freeHourCount` against known schedules.
- Deferred loosening: tightening applies at once; loosening does not take effect until the day
  boundary; a pending schedule survives a store round-trip.
- Scenes are visual and are verified by running the app, not by assertion.
