# Localization — design

Date: 2026-09-12. Status: approved in conversation, awaiting written review.

## Goal

Make every user-facing string in Paperweight translatable, make the formatting that is
currently hand-built in English locale-correct, and ship the first four languages
(Spanish, Dutch, Japanese, Korean) with machine translations produced by a repo script and
marked for review. The app's own voice rules carry into every language.

Two phases, one spec, two implementation plans:

- **Phase 1 — Framework.** Shared String Catalog, project wiring, every string localizable,
  locale-correct formatting, tests pinned to English, CI checks. Ships with English only;
  no visible change on an English device except the copy fixes in §6.
- **Phase 2 — Translations.** The Claude translation script, the four languages, a
  back-translation verify pass, and the per-language CI check.

Out of scope: App Store Connect metadata (description, What's New, screenshots) in other
languages; right-to-left layout; the support website.

## Facts the design rests on

Established by survey and a build spike on 2026-09-12:

- The repo has no localization infrastructure: no catalogs, no `String(localized:)`, no
  `CFBundleDevelopmentRegion`. About 250 user-facing strings, all inline literals.
- `Calendar` is injected everywhere (`calendar: Calendar = .current`); nothing hardcodes a
  locale in production code. `Locale` is injected only in `DayException+Labels.swift`.
- With `SWIFT_EMIT_LOC_STRINGS = YES`, the compiler writes one `.stringsdata` file per
  Swift source file into DerivedData for the app target (118 files). Xcode's
  `xcstringstool sync <catalog> --stringsdata …` merges them into a catalog from the
  command line, marking absent keys stale. This is the CLI and CI extraction path; the
  IDE's automatic sync is not required.
- Interpolated SwiftUI `Text` already extracts as a key with positional placeholders
  (`Lifts %@ (%@).`). Interpolated plain `String`s do not; they need `String(localized:)`.
- The sync of the current source produced 114 keys, of which 11 break the copy rule
  (contain "block", "restrict" as a verb, or "!") and 4 are sentence fragments.

## 1. Where strings live

**One catalog.** `Shared/Resources/Localizable.xcstrings`, source language `en`. It is a
resource of the app, the monitor, and the widget:

- App and monitor take all of `Shared`, so they pick it up by path.
- The widget's file-by-file source list in `project.yml` gains the explicit entry
  `Shared/Resources/Localizable.xcstrings`. The widget still never sees FamilyControls.
- Only the app target sets `SWIFT_EMIT_LOC_STRINGS: YES`. The app compiles every view and
  every shared file, so its build sees every string. The monitor has no strings. The
  widget's two own strings (`configurationDisplayName`, `description`) move into
  `WidgetCopy` in `Shared/Models/WidgetSnapshot.swift` so the app's build extracts them.

**Info.plist.** Three `InfoPlist.xcstrings` files, one per target directory, holding
`CFBundleDisplayName` and (app only) `NFCReaderUsageDescription`. `project.yml` gets
`options.developmentLanguage: en`.

**Sync script.** `Scripts/strings-sync.sh`:

1. `xcodegen generate` if the project is missing.
2. Build the `Paperweight` target for the simulator into a DerivedData path under
   `.build/` (git-ignored), `CODE_SIGNING_ALLOWED=NO`.
3. Run `xcstringstool sync Shared/Resources/Localizable.xcstrings --stringsdata` with every
   `Paperweight.build/**/*.stringsdata` (never the widget's or monitor's, whose extraction
   would mark shared keys stale).
4. Print keys that became stale, so the author deletes dead keys deliberately.

The catalog is committed. Running the sync is part of any PR that adds or changes copy.

## 2. Code conventions

Rules for source code, enforced by review and by the tests in §4:

- **Whole sentences, one key.** Never build a sentence from fragments. `Text("a ") +
  Text("b")` becomes one key; where styling was the reason, use Markdown in the key
  (`Text("Tap your token to lift restrictions for **\(m) minutes**. …")`) or drop it.
  Lines joined with " · " (`DayExceptionsView.swift:133-145`) become separate keys
  joined by a localized separator key `" · "` with a comment.
- **Interpolated plain strings** use `String(localized: "… \(x) …", comment:)`. Copy in
  `Shared` (`WidgetSnapshot.swift`, `HomeCopy.swift`, `DayException+Labels.swift`,
  `NFCError.swift`, `UnlockError.swift`, `NFCService.swift` alert messages, quick-action
  titles, `FamilyActivityPicker` header and footer) all go through it.
- **Locale is a parameter.** Every copy function in `Shared` that produces text takes
  `locale: Locale = .current` beside its existing `calendar:`. `String(localized:…,
  locale:)` and `Date.FormatStyle(locale:)` receive it. Views pass nothing (they use
  `.current`); tests pass `en_US`.
- **Plurals** use catalog plural variations, never `"\(n) app\(n == 1 ? "" : "s")"`.
  Sites: `FamilyActivitySelection+Summary.swift:10-12`, `HomeView.swift:379`,
  `NFCSetupView.swift:177`, `DisablePaperweightSheet.swift:90-130`,
  `WidgetSnapshot.swift:328`, `DayExceptionsView.swift` day count, `AddDayExceptionSheet`
  "%lld upcoming". The sync creates the key; the variation is added in the catalog by hand
  once and preserved by every later sync and by the translator.
- **Weekdays** come from the calendar: `calendar.weekdaySymbols`, `shortWeekdaySymbols`,
  `veryShortWeekdaySymbols`, indexed by the app's Sunday-based `weekdayIndex`. Replaces the
  three hardcoded arrays (`DayException+Labels.swift:16`, `WeekStrip.swift:16`,
  `AddDayExceptionSheet.swift:23`).
- **Week start.** The Schedule grid and the day-exception weekday picker display days in
  the order starting at `calendar.firstWeekday`. Storage, `weekdayIndex`, `DayKey`, the
  resolver, and every existing index stay Sunday-based; only the view's column order maps
  through a `displayOrder(calendar:) -> [Int]` helper on `PaperweightSchedule`. The Home
  week strip is unaffected: it already runs from today.
- **Hours and clock labels.** `PaperweightSchedule.hourLabel`/`timeLabel` ("12a", "6:30p")
  are replaced by `Date.FormatStyle` with `.hour(.defaultDigits(amPM: .abbreviated))` and
  `.minute()` where non-zero, given a date built from the slot in the injected calendar.
  English renders "12 AM" / "6:30 PM"; Dutch, Japanese and Korean render 24-hour forms.
  The grid's label column widens to fit the widest label of the current locale, measured
  once per layout.
- **Durations.** Under 24 hours, `Duration.UnitsFormatStyle` with hours and minutes at
  narrow width, localized units everywhere. Plan step: check what English renders; if it
  is not the house "3h 20m" / "42m", keep those as localized keys `"%lldh %lldm"`,
  `"%lldh"`, `"%lldm"` instead, and let each language rewrite them. At and above
  24 hours the house style stays: keys `"%lld days"`, `"%lld½ days"` with plural
  variations (the ½ glyph is part of the key and travels untranslated; a language may
  rewrite it). `HomeCopy.countdown`'s "2:14" clock form stays numeric.
- **Time plus day** ("09:00 Tuesday", "09:00 tomorrow") become the keys `"%@ tomorrow"`,
  `"%@ tmrw"` and `"%1$@ %2$@"` (time, weekday) with comments, so a translator can reorder.
- **Numbers** use `.formatted()`; no `String(format: "%g …")`.
- **Uppercase** copy: literal eyebrows like `"QUIET"`, `"OPEN"` stay literal keys (a
  translator chooses the emphasis form for their language). Programmatic uppercasing
  uses `.uppercased(with: locale)` or SwiftUI `.textCase(.uppercase)`.
- **Comments.** Any key that is a single word, an eyebrow, a placeholder-only key, or has a
  layout budget gets a `comment:`. Lock Screen accessory keys carry
  `comment: "Lock Screen; keep under 24 characters"`.

## 3. Copy rules across languages

The house rules in `WidgetSnapshot.swift:180-186` become the first section of
`docs/LOCALIZATION.md` and the system prompt of the translator:

- The state words are **quiet** and **open**. Never "blocked", "free", "banned", "locked
  out". "Restricted apps" is the established name of the chosen set and stays.
- No exclamation marks. Calm, plain, second person. No streaks, no shame.
- "Paperweight" is never translated. "token" means the physical NFC tag. "cool-off" is the
  multi-day tokenless unlock. "day off" loosens; "quiet day" tightens.
- Register: Spanish informal "tú"; Dutch "je"; Japanese polite です/ます; Korean 해요체.

## 4. Tests

- `HomeCopyTests`, `WidgetSnapshotTests`, `DayExceptionLabelTests` pin `Locale("en_US")`,
  a Gregorian calendar with `firstWeekday = 1`, and `TimeZone("America/New_York")`
  through the new `locale:` parameters. Expected strings update where the formatter
  changes the English ("12 AM" for "12a"; "3h 20m" is unchanged).
- The voice guard (`WidgetSnapshotTests:196-206`) stays as a test of the English source.
- The 24-character Lock Screen test stays for English; other languages are checked by
  the lint (§5), not by XCTest.
- New tests: `displayOrder(calendar:)` for Sunday-first and Monday-first calendars; hour
  labels for `en_US` and `nl_NL`; plural keys resolve for 1 and 2 in English; the weekday
  symbols path for `ja_JP` returns non-Latin names (proves the array is gone).
- Unit tests never depend on the simulator's current locale.

## 5. CI

Two additions to `.github/workflows/ci.yml`:

- **Extraction drift** (existing macOS `test` job, after the build): copy the catalog to
  a temp path, run `xcstringstool sync` on the copy with the app target's stringsdata,
  and `diff` against the committed catalog. Any difference (a new key, a key gone stale)
  fails with the list: the author ran code without running the sync.
- **Catalog lint** (new cheap Ubuntu job, beside `no-committed-team`):
  `Scripts/strings-check.py`, standard library only. Fails on: any key with
  `extractionState: stale`; any translation whose placeholders (`%lld`, `%@`, positional
  forms) do not match the source; any translation containing "!"; and, once Phase 2 lands,
  any key lacking a translation for a language listed in `Scripts/languages.txt`
  (`es nl ja ko`). Translations in state `needs_review` count as present. Warns (does
  not fail) when a key whose comment names a 24-character budget exceeds it.

## 6. English copy fixes (Phase 1)

The 11 rule-breaking English strings are rewritten in the app's voice before extraction so
they are translated once, correctly. "Copied!" → "Copied". "Choose apps to block first" →
"Choose apps to quiet first". "It never changes what's blocked." → "It never changes what
goes quiet." "…saving locks restricted apps immediately." → "…saving makes restricted apps
quiet at once." "Pick the apps or categories to restrict first." → "…to make quiet first."
"Nothing is armed and nothing is blocked." → "Nothing is armed and nothing is quiet." The
full before/after list is in the Phase 1 plan; each is a one-line change.

## 7. Translator (Phase 2)

`Scripts/translate.py`, Python 3 standard library, reads `ANTHROPIC_API_KEY` from the
environment. It never runs in CI and the key is never in the repo.

- Reads the catalog; for each language in `Scripts/languages.txt`, collects keys with no
  localization or with state `new`. Plural variations are sent as separate units and
  written back as variations.
- Sends batches of about 40 units as JSON with the §3 rules, the glossary, each key's
  comment, and any layout budget. Asks for JSON back keyed by source string; validates
  placeholder parity before writing; writes with state `needs_review`.
- Idempotent: re-running translates only what is missing. `--retranslate KEY` and
  `--language ja` narrow the run. `--dry-run` prints the batches.
- `--verify LANG` back-translates existing translations to English in a separate call and
  prints source, back-translation and a one-line judgement per key, so the languages you
  cannot read get a review pass. It changes nothing.
- Model: `claude-sonnet-5`. Temperature 0. Cost at 250 keys × 4 languages is negligible.

`docs/LOCALIZATION.md` documents the loop: change copy → `Scripts/strings-sync.sh` →
commit the catalog → `Scripts/translate.py` → review (Xcode's catalog editor shows
`needs_review` rows) → mark reviewed → CI keeps it honest.

## 8. Files

Phase 1 creates `Shared/Resources/Localizable.xcstrings`, `Paperweight/InfoPlist.xcstrings`,
`PaperweightMonitor/InfoPlist.xcstrings`, `PaperweightWidget/InfoPlist.xcstrings`,
`Scripts/strings-sync.sh`, `Scripts/strings-check.py`, `docs/LOCALIZATION.md`; modifies
`project.yml`, `.github/workflows/ci.yml`, `.gitignore` (`.build/`), and the source files
named in §2 plus their tests. Phase 2 creates `Scripts/translate.py`,
`Scripts/languages.txt` and adds four languages to the catalog.
