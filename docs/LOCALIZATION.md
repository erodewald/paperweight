# Localization

Every user-facing string lives in one String Catalog,
`Shared/Resources/Localizable.xcstrings`, carried by the app, the monitor and the
widget. English is the source language.

## The loop

1. Write copy in code: SwiftUI `Text("…")` literals, or `String(localized: "…",
   bundle: L10n.bundle, comment: "…")` for anything that is a plain `String`.
   One key per sentence; never glue fragments. Interpolate values, never words.
   Debug-only text uses `Text(verbatim:)` so it never enters the catalog.
2. Run `Scripts/strings-sync.sh`. It builds the app target, merges what the
   compiler saw into the catalog, and formats the file exactly as Xcode does, so
   an IDE build never dirties it. Review the diff; delete keys it marked stale.
3. Plurals: the sync creates the key (`%lld apps`); add the `one`/`other`
   variation in the catalog once, then run the sync again.
4. Commit the catalog with the code. CI fails if they disagree.
5. Merge. The **Translate** workflow (`.github/workflows/translate.yml`) sees the
   catalog change, asks Claude for every missing unit in the languages listed in
   `Scripts/languages.txt`, and opens a pull request labelled `translation` with
   the results marked *needs review*. It needs the `CLAUDE_PLATFORM_API_KEY` repository
   secret; without it the run says so and does nothing.
6. Review that PR: Xcode's String Catalog editor filters *Needs review*; for a
   language you cannot read, `python3 Scripts/translate.py --verify ko` prints a
   back-translation and a one-line judgement per string. Mark rows *Reviewed*
   (state `translated`) as you go, or leave them; the notice in the app's
   Language & translations screen stays until a language has no *needs review*
   rows left.

Locally, `python3 Scripts/translate.py --dry-run` shows what would be sent, and
with `CLAUDE_PLATFORM_API_KEY` in the environment the same script does the real run;
`--language ko --retranslate "Open until %@, then quiet"` redoes one key.

## Adding a language

Add its code on its own line in `Scripts/languages.txt` (and, if it has a single
plural category, to `PLURAL_FORMS` in `Scripts/catalog.py`). Merge; the Translate
workflow fills it in. iOS shows the app's per-app Language row once the second
language ships.

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
