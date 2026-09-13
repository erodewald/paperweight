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
  (Ubuntu job). Tests: `python3 -m unittest Scripts/tests/test_strings_check.py`,
  run with `-W error` in CI.

## Trying another language

`xcrun simctl launch booted media.baltar.paperweight -AppleLanguages "(nl)"
-AppleLocale nl_NL` runs the installed build in Dutch: formatting follows the
locale immediately; copy follows once translations exist (Phase 2).
