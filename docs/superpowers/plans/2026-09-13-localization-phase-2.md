# Localization Phase 2 (Translations, Workflow, Settings feedback) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship Spanish, Dutch, Japanese and Korean as machine translations marked for review, produced by a repo script that also runs in a GitHub workflow, with a Settings screen where users can report a wrong translation or request a language through prefilled GitHub issue forms.

**Architecture:** Catalog writes go through `Scripts/catalog.py` (load, save, units, status) and are formatted byte-identically to Xcode by `Scripts/xcstrings-format.swift`, so IDE builds never dirty the tree. `Scripts/translate.py` collects untranslated units, batches them to the Claude Messages API with the rules in `Scripts/translation-rules.md`, validates placeholders, writes `needs_review` units and `TranslationStatus.json`. A macOS workflow runs it on catalog changes and opens a labelled PR. In the app, `TranslationStatus` and `TranslationFeedback` (Shared, tested) feed a `TranslationsView` reached from Settings.

**Tech Stack:** Swift 5.9 / SwiftUI / iOS 17, XcodeGen, Python 3.9 standard library (`urllib`), Swift scripting (`swift file.swift`), GitHub Actions (`macos-latest`, `ubuntu-latest`), GitHub issue forms, Claude Messages API (`claude-sonnet-5`).

Spec: `docs/superpowers/specs/2026-09-12-localization-design.md` §1 (Xcode syncs too), §3, §5, §7, §8. Branch: `feat/localization-phase-2` (exists; the spec amendment is its first commit). Phase 1 is merged: catalog `Shared/Resources/Localizable.xcstrings` (255 keys), `Scripts/strings-sync.sh`, `Scripts/strings_check.py`, `L10n.bundle`, `TestLocale`.

## Global Constraints

- Copy rules: the state words are **quiet** and **open**; never "blocked", "free", "banned", "locked out". No exclamation marks, in any language. "Paperweight" is never translated. "token" is the NFC tag; "cool-off" is the multi-day tokenless unlock; "day off" loosens, "quiet day" tightens.
- Register: Spanish informal "tú"; Dutch "je"; Japanese polite です/ます; Korean 해요체.
- Languages: `Scripts/languages.txt` lists `es`, `nl`, `ja`, `ko`, one per line. Plural categories: `ja`, `ko`, `zh` write only `other`; every other language writes `one` and `other`.
- Every catalog write is formatted by `Scripts/xcstrings-format.swift` when `swift` is on the path; `--check` compares parsed JSON, never bytes.
- Strings inside `#if DEBUG` use `Text(verbatim:)` and never enter the catalog.
- Translations are written with state `needs_review`; only a human sets `translated`.
- Placeholder parity uses `strings_check._placeholders` (positional and ordinal equivalent); any unit with "!" is rejected.
- Nothing in the app talks to a server: the two report actions are URLs opened by the system.
- Repository URL: `https://github.com/erodewald/paperweight`. Issue forms: `translation-fix.yml` (ids `language`, `device-languages`, `app-version`, `screen`, `wrong-text`, `better-text`) and `translation-request.yml` (ids `device-languages`, `requested-language`, `can-help`), both `labels: [translation]`.
- Python: standard library only; tests run with `python3 -W error -m unittest …` and must be clean.
- Tests: `xcodebuild test -project Paperweight.xcodeproj -scheme PaperweightTests -destination "platform=iOS Simulator,name=iPhone 17 Pro" CODE_SIGNING_ALLOWED=NO`; 229 pass at the start. Regenerate with `xcodegen generate` after any `project.yml` change.
- The translator reads `CLAUDE_PLATFORM_API_KEY` from the environment. Locally the key lives in 1Password; a real run is launched as `CLAUDE_PLATFORM_API_KEY="$(op read 'op://Private/Paperweight iOS/l10n/claude-platform-api-key')" python3 Scripts/translate.py …`. Never print, log, echo or commit the value; never pass it as a command-line argument. Tests use the fake transport. In CI the same name is a repository secret.
- Commit messages end with a `Co-Authored-By: … <noreply@anthropic.com>` line.

---

## File map

Create:
- `Scripts/xcstrings-format.swift` — Xcode-identical JSON formatting (Apple's serializer).
- `Scripts/catalog.py` — `load`, `save`, `units`, `status`, `PLURAL_FORMS`.
- `Scripts/translate.py` — collector, batcher, validator, Anthropic transport, CLI, `--verify`.
- `Scripts/translation-rules.md` — the system prompt: rules, glossary, register table.
- `Scripts/languages.txt` — `es nl ja ko`.
- `Scripts/tests/test_catalog.py`, `Scripts/tests/test_translate.py`, `Scripts/tests/fixtures/xcode-style.xcstrings`.
- `Shared/Resources/TranslationStatus.json` — written by the translator.
- `Shared/TranslationStatus.swift`, `Shared/TranslationFeedback.swift` — pure, tested.
- `Paperweight/Views/TranslationsView.swift` — the Settings screen.
- `.github/workflows/translate.yml`, `.github/ISSUE_TEMPLATE/translation-fix.yml`, `.github/ISSUE_TEMPLATE/translation-request.yml`.
- `PaperweightTests/Models/TranslationStatusTests.swift`, `PaperweightTests/Models/TranslationFeedbackTests.swift`.

Modify:
- `Scripts/strings-sync.sh` (format step, semantic `--check`), `Scripts/strings_check.py` (use `catalog.units`, `--status` check), `Scripts/tests/test_strings_check.py`.
- `Paperweight/InfoPlist.xcstrings`, `PaperweightMonitor/InfoPlist.xcstrings`, `PaperweightWidget/InfoPlist.xcstrings` (Xcode's `CFBundleName` entries).
- `Paperweight/Views/SettingsView.swift` (debug strings verbatim; new row), `Paperweight/Views/Components/QuietGlassControls.swift` (`NavRow(verbatim:)`).
- `Shared/Constants.swift` (repository URL), `.github/workflows/ci.yml` (formatter fixture check, status check), `docs/LOCALIZATION.md`, `README.md`.

---

### Task 1: Xcode-identical formatting and catalog hygiene

**Files:**
- Create: `Scripts/xcstrings-format.swift`, `Scripts/tests/fixtures/xcode-style.xcstrings`
- Modify: `Scripts/strings-sync.sh:52-55,87-89,129-135`, `Paperweight/InfoPlist.xcstrings`, `PaperweightMonitor/InfoPlist.xcstrings`, `PaperweightWidget/InfoPlist.xcstrings`, `Paperweight/Views/SettingsView.swift:76-129`, `Paperweight/Views/Components/QuietGlassControls.swift:43-51`, `.github/workflows/ci.yml` (macOS job)

**Interfaces:**
- Produces: `swift Scripts/xcstrings-format.swift IN [OUT]` (formats in place when OUT is omitted; exit 1 on invalid JSON). `NavRow(verbatim: String, …)`.

- [ ] **Step 1: Write the fixture and the failing check**

Create `Scripts/tests/fixtures/xcode-style.xcstrings` with exactly this content and **no trailing newline** (write it with `printf '%s' "$(cat <<'EOF' … EOF)"` or an editor that respects the missing newline; the test below checks bytes):

```json
{
  "sourceLanguage" : "en",
  "strings" : {
    "%lld days" : {
      "comment" : "Duration in whole days; has a plural rule",
      "localizations" : {
        "en" : {
          "variations" : {
            "plural" : {
              "one" : {
                "stringUnit" : {
                  "state" : "translated",
                  "value" : "%lld day"
                }
              },
              "other" : {
                "stringUnit" : {
                  "state" : "translated",
                  "value" : "%lld days"
                }
              }
            }
          }
        }
      }
    },
    "OPEN" : {
      "comment" : "Widget eyebrow, emphasis form"
    },
    "Quiet" : {

    },
    "Ready" : {
      "localizations" : {
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Ready"
          }
        }
      }
    }
  },
  "version" : "1.0"
}
```

Add to `.github/workflows/ci.yml`, in the macOS `test` job right after `Generate project`:

```yaml
      # The formatter must reproduce Xcode's catalog bytes exactly, or every
      # IDE build dirties the tree. The fixture is a catalog as Xcode wrote it.
      - name: Check the catalog formatter matches Xcode
        run: |
          set -euo pipefail
          swift Scripts/xcstrings-format.swift Scripts/tests/fixtures/xcode-style.xcstrings "$RUNNER_TEMP/formatted.xcstrings"
          cmp Scripts/tests/fixtures/xcode-style.xcstrings "$RUNNER_TEMP/formatted.xcstrings"
```

Run locally: `swift Scripts/xcstrings-format.swift Scripts/tests/fixtures/xcode-style.xcstrings /tmp/f.xcstrings`
Expected: `error: … no such file` (the script does not exist yet).

- [ ] **Step 2: Write the formatter**

Create `Scripts/xcstrings-format.swift`:

```swift
// Formats a String Catalog exactly the way Xcode writes it, so an IDE build
// never rewrites a file this repo's scripts produced. Apple's serializer with
// these three options is byte-identical to Xcode's output: two-space indent,
// `"key" : value`, empty objects on three lines, keys in Unicode collation
// order, no trailing newline.
//
//   swift Scripts/xcstrings-format.swift IN        # in place
//   swift Scripts/xcstrings-format.swift IN OUT
import Foundation

let args = CommandLine.arguments
guard args.count == 2 || args.count == 3 else {
    FileHandle.standardError.write("usage: xcstrings-format.swift IN [OUT]\n".data(using: .utf8)!)
    exit(2)
}
let input = URL(fileURLWithPath: args[1])
let output = URL(fileURLWithPath: args.count == 3 ? args[2] : args[1])
do {
    let data = try Data(contentsOf: input)
    let object = try JSONSerialization.jsonObject(with: data)
    let formatted = try JSONSerialization.data(withJSONObject: object,
                                               options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    try formatted.write(to: output)
} catch {
    FileHandle.standardError.write("xcstrings-format: \(error)\n".data(using: .utf8)!)
    exit(1)
}
```

Run the Step 1 command, then `cmp Scripts/tests/fixtures/xcode-style.xcstrings /tmp/f.xcstrings`. Expected: no output, exit 0.

- [ ] **Step 3: Use it in the sync script and make `--check` semantic**

In `Scripts/strings-sync.sh`, replace the comment block at lines 52-55 ("The Python json.dump below …") with:

```bash
# The Python block below rewrites the file, then xcstrings-format.swift puts it
# back into Xcode's own formatting, so a later IDE build finds nothing to change.
```

After the second Python block (the one that prints `N keys, N stale, N promoted`) and before the `--check` block, add:

```bash
swift Scripts/xcstrings-format.swift "$target"
```

Replace the `--check` block (lines 129-135) with a semantic comparison:

```bash
if [ "$MODE" = "--check" ]; then
  if ! python3 - "$CATALOG" "$target" <<'EOF'
import json, sys
with open(sys.argv[1], encoding="utf-8") as f: committed = json.load(f)
with open(sys.argv[2], encoding="utf-8") as f: synced = json.load(f)
sys.exit(0 if committed == synced else 1)
EOF
  then
    formatted="$(mktemp -d)/committed.xcstrings"
    swift Scripts/xcstrings-format.swift "$CATALOG" "$formatted"
    diff -u "$formatted" "$target" || true
    echo "::error::Localizable.xcstrings is out of date. Run Scripts/strings-sync.sh and commit." >&2
    exit 1
  fi
  echo "Catalog is in sync with the code."
fi
```

- [ ] **Step 4: Debug-only strings become verbatim**

In `Paperweight/Views/Components/QuietGlassControls.swift`, change `NavRow` so its title is a `Text` built by one of two initialisers. Replace `var title: LocalizedStringKey` and the `Text(title)` line with:

```swift
    private let titleText: Text
    var titleColor: Color = PW.textPrimary
    var systemImage: String? = nil
    var iconColor: Color = PW.sage
    var value: String? = nil
    var valueColor: Color = PW.textMuted
    var showsChevron: Bool = true

    init(title: LocalizedStringKey, titleColor: Color = PW.textPrimary, systemImage: String? = nil,
         iconColor: Color = PW.sage, value: String? = nil, valueColor: Color = PW.textMuted,
         showsChevron: Bool = true) {
        self.titleText = Text(title)
        self.titleColor = titleColor; self.systemImage = systemImage; self.iconColor = iconColor
        self.value = value; self.valueColor = valueColor; self.showsChevron = showsChevron
    }

    /// For text that must never enter the catalog (debug-only rows).
    init(verbatim: String, titleColor: Color = PW.textPrimary, systemImage: String? = nil,
         iconColor: Color = PW.sage, value: String? = nil, valueColor: Color = PW.textMuted,
         showsChevron: Bool = true) {
        self.titleText = Text(verbatim: verbatim)
        self.titleColor = titleColor; self.systemImage = systemImage; self.iconColor = iconColor
        self.value = value; self.valueColor = valueColor; self.showsChevron = showsChevron
    }
```

and in the body `Text(title)` becomes `titleText`. Keep every existing `NavRow(title: "…", …)` call site compiling (the labelled initialiser has the same parameters in the same order as the old memberwise one).

In `Paperweight/Views/SettingsView.swift` inside `#if DEBUG` (lines 76-129), change every literal to verbatim: `Text("Developer")` → `Text(verbatim: "Developer")`; `Text("Show armed-only screens")` → `Text(verbatim: "Show armed-only screens")`; the "Reveals Emergency unlock…" and "Shows the quiet screen…" and "Force quiet screen" and "Debug builds only — …" literals likewise; `NavRow(title: "Turn off without a token", …)` → `NavRow(verbatim: "Turn off without a token", …)`.

- [ ] **Step 5: Adopt Xcode's InfoPlist entries**

Replace `Paperweight/InfoPlist.xcstrings` with (no trailing newline):

```json
{
  "sourceLanguage" : "en",
  "strings" : {
    "CFBundleDisplayName" : {
      "extractionState" : "manual",
      "localizations" : {
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Paperweight"
          }
        }
      }
    },
    "CFBundleName" : {
      "comment" : "Bundle name",
      "extractionState" : "extracted_with_value",
      "localizations" : {
        "en" : {
          "stringUnit" : {
            "state" : "new",
            "value" : "Paperweight"
          }
        }
      }
    },
    "NFCReaderUsageDescription" : {
      "extractionState" : "manual",
      "localizations" : {
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Paperweight uses NFC to read your unlock token."
          }
        }
      }
    }
  },
  "version" : "1.0"
}
```

`PaperweightMonitor/InfoPlist.xcstrings`: the same shape with `CFBundleDisplayName` = `Paperweight Monitor`, `CFBundleName` = `PaperweightMonitor`, and no NFC key. `PaperweightWidget/InfoPlist.xcstrings`: `CFBundleDisplayName` = `Paperweight`, `CFBundleName` = `PaperweightWidget`, no NFC key. Run `swift Scripts/xcstrings-format.swift` on each of the three to guarantee the bytes.

- [ ] **Step 6: Sync, verify against Xcode's own output, test**

Run `Scripts/strings-sync.sh`. Expected: `248 keys, 0 stale, 0 promoted to translated` (the seven debug keys are gone). Run it again: byte-identical (`git diff --quiet Shared/Resources/Localizable.xcstrings` after the second run). Run `Scripts/strings-sync.sh --check`: green.

On this machine a git stash named "xcode catalog rewrite after device build" holds the catalog exactly as Xcode wrote it after a device build. Compare: `git show 'stash@{0}:Shared/Resources/Localizable.xcstrings' | cmp - Shared/Resources/Localizable.xcstrings`. Expected: identical. If the stash is missing, skip this and say so in the report.

Run the full suite (229 pass) and the three-target build.

- [ ] **Step 7: Commit**

```bash
git add Scripts/xcstrings-format.swift Scripts/tests/fixtures Scripts/strings-sync.sh Paperweight/InfoPlist.xcstrings PaperweightMonitor/InfoPlist.xcstrings PaperweightWidget/InfoPlist.xcstrings Paperweight/Views/SettingsView.swift Paperweight/Views/Components/QuietGlassControls.swift Shared/Resources/Localizable.xcstrings .github/workflows/ci.yml
git commit -m "chore(l10n): catalogs formatted exactly as Xcode writes them; debug strings stay out

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 2: `Scripts/catalog.py` and the status check in the lint

**Files:**
- Create: `Scripts/catalog.py`, `Scripts/tests/test_catalog.py`
- Modify: `Scripts/strings_check.py` (import `units` from catalog; `--status`), `Scripts/tests/test_strings_check.py`, `.github/workflows/ci.yml` (Ubuntu job)

**Interfaces:**
- Produces: `catalog.load(path) -> dict`; `catalog.save(path, data)` (Python dump, then `swift Scripts/xcstrings-format.swift` when `shutil.which("swift")`); `catalog.units(localization) -> Iterable[(form, value, state)]` (moved from `strings_check._units`); `catalog.source_units(key, entry, source) -> list[(form, value)]` (bare entry → `[("", key)]`); `catalog.PLURAL_FORMS: dict[str, list[str]]` with `DEFAULT_FORMS = ["one", "other"]`; `catalog.forms_for(lang) -> list[str]`; `catalog.status(data, languages) -> dict` shaped `{"languages": {lang: {"keys": int, "needsReview": int}}}`; `catalog.dumps_status(status) -> str` (JSON, indent 2, sorted keys, trailing newline).

- [ ] **Step 1: Write the failing tests**

Create `Scripts/tests/test_catalog.py`:

```python
import json, os, sys, tempfile, unittest
sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
import catalog  # noqa: E402


def unit(value, state="translated"):
    return {"stringUnit": {"state": state, "value": value}}


class Units(unittest.TestCase):
    def test_flat_and_plural_units(self):
        flat = {"stringUnit": {"state": "translated", "value": "Open"}}
        self.assertEqual(list(catalog.units(flat)), [("", "Open", "translated")])
        plural = {"variations": {"plural": {"one": unit("1 day"), "other": unit("%lld days", "needs_review")}}}
        self.assertEqual(list(catalog.units(plural)),
                         [("plural.one", "1 day", "translated"), ("plural.other", "%lld days", "needs_review")])

    def test_source_units_fall_back_to_the_key(self):
        self.assertEqual(catalog.source_units("Ready", {}, "en"), [("", "Ready")])
        entry = {"localizations": {"en": {"stringUnit": {"state": "translated", "value": "%1$@ %2$@"}}}}
        self.assertEqual(catalog.source_units("%@ %@", entry, "en"), [("", "%1$@ %2$@")])

    def test_plural_forms_per_language(self):
        self.assertEqual(catalog.forms_for("ja"), ["other"])
        self.assertEqual(catalog.forms_for("ko"), ["other"])
        self.assertEqual(catalog.forms_for("nl"), ["one", "other"])
        self.assertEqual(catalog.forms_for("es"), ["one", "other"])


class Status(unittest.TestCase):
    def test_counts_keys_and_needs_review(self):
        data = {"sourceLanguage": "en", "strings": {
            "Open": {"localizations": {"en": unit("Open"), "nl": unit("Open", "needs_review")}},
            "Ready": {"localizations": {"nl": unit("Klaar")}},
            "%lld days": {"localizations": {"en": {"variations": {"plural": {"one": unit("%lld day"), "other": unit("%lld days")}}},
                                            "nl": {"variations": {"plural": {"one": unit("%lld dag"), "other": unit("%lld dagen", "needs_review")}}}}},
            "Quiet": {}}}
        self.assertEqual(catalog.status(data, ["nl", "ja"]),
                         {"languages": {"nl": {"keys": 3, "needsReview": 2}, "ja": {"keys": 0, "needsReview": 0}}})

    def test_dumps_status_is_stable(self):
        s = catalog.dumps_status({"languages": {"nl": {"keys": 1, "needsReview": 1}}})
        self.assertTrue(s.endswith("\n"))
        self.assertEqual(json.loads(s), {"languages": {"nl": {"keys": 1, "needsReview": 1}}})


class SaveLoad(unittest.TestCase):
    def test_round_trip(self):
        with tempfile.TemporaryDirectory() as d:
            path = os.path.join(d, "c.xcstrings")
            data = {"sourceLanguage": "en", "strings": {"Quiet": {}}, "version": "1.0"}
            catalog.save(path, data)
            self.assertEqual(catalog.load(path), data)


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run to verify failure**

Run: `python3 -W error -m unittest Scripts/tests/test_catalog.py -v`
Expected: `ModuleNotFoundError: No module named 'catalog'`.

- [ ] **Step 3: Write the module**

Create `Scripts/catalog.py`:

```python
"""Read, write and summarise String Catalogs (.xcstrings).

Shared by the sync script, the lint and the translator. Standard library only.
"""
import json
import os
import shutil
import subprocess

# CLDR plural categories the catalog will carry per language. Languages with a
# single category write only "other"; everything else "one" and "other".
PLURAL_FORMS = {"ja": ["other"], "ko": ["other"], "zh": ["other"], "zh-Hans": ["other"], "zh-Hant": ["other"]}
DEFAULT_FORMS = ["one", "other"]

FORMATTER = os.path.join(os.path.dirname(os.path.abspath(__file__)), "xcstrings-format.swift")


def forms_for(lang):
    return list(PLURAL_FORMS.get(lang, DEFAULT_FORMS))


def load(path):
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def save(path, data):
    """Write the catalog, then reformat it exactly as Xcode would when `swift`
    is available (macOS). On other hosts the Python form is left in place; the
    next macOS write normalises it, and every check compares parsed JSON."""
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2, ensure_ascii=False, sort_keys=True)
    if shutil.which("swift"):
        subprocess.run(["swift", FORMATTER, path], check=True)


def units(localization):
    """Every (form, value, state) in one language: the plain unit, or each variation form."""
    if "stringUnit" in localization:
        u = localization["stringUnit"]
        yield "", u.get("value", ""), u.get("state", "")
    for kind, forms in localization.get("variations", {}).items():
        for form, entry in forms.items():
            u = entry.get("stringUnit", {})
            yield f"{kind}.{form}", u.get("value", ""), u.get("state", "")


def source_units(key, entry, source):
    """(form, value) pairs of the source language; a bare entry's value is its key."""
    loc = entry.get("localizations", {}).get(source)
    if not loc:
        return [("", key)]
    return [(form, value) for form, value, _ in units(loc)]


def status(data, languages):
    """Per language: how many keys carry a localization, and how many of those
    still have a unit in needs_review."""
    out = {}
    for lang in languages:
        keys = review = 0
        for entry in data.get("strings", {}).values():
            loc = entry.get("localizations", {}).get(lang)
            if not loc:
                continue
            keys += 1
            if any(state == "needs_review" for _, _, state in units(loc)):
                review += 1
        out[lang] = {"keys": keys, "needsReview": review}
    return {"languages": out}


def dumps_status(status_dict):
    return json.dumps(status_dict, indent=2, sort_keys=True) + "\n"
```

- [ ] **Step 4: Run to verify pass**

Run: `python3 -W error -m unittest Scripts/tests/test_catalog.py -v`
Expected: 6 tests OK. (The `SaveLoad` test runs the Swift formatter on macOS; on Ubuntu CI it exercises the Python branch.)

- [ ] **Step 5: The lint uses the module and checks the status file**

In `Scripts/strings_check.py`: add `import os` and, after `import sys`, `sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))` then `import catalog`. Delete `_units` and replace its two uses with `catalog.units`. Replace `source_units = list(_units(locs.get(source, {}))) or [("", key, "translated")]` with `source_units = [(form, value, "") for form, value in catalog.source_units(key, entry, source)]`.

Add a status check. In `main`, add an argument `p.add_argument("--status", default="", help="path of TranslationStatus.json; fails if it disagrees with the catalog")`, and after computing `found`:

```python
    if a.languages and a.status:
        expected = catalog.dumps_status(catalog.status(catalog_data, languages))
        try:
            with open(a.status, encoding="utf-8") as f:
                actual = f.read()
        except FileNotFoundError:
            actual = ""
        if actual != expected:
            found.append(f"status file out of date: {a.status} (run Scripts/translate.py, or write the recomputed status)")
```

(rename the loaded variable to `catalog_data` so it doesn't shadow the module). Print each problem as before; the return code follows `found`.

Add to `Scripts/tests/test_strings_check.py`:

```python
    def test_status_file_must_match_the_catalog(self):
        with tempfile.TemporaryDirectory() as d:
            cat = os.path.join(d, "c.xcstrings"); st = os.path.join(d, "s.json")
            with open(cat, "w") as f:
                json.dump(catalog({"Open": {"localizations": {"en": unit("Open"), "nl": unit("Open", "needs_review")}}}), f)
            with open(st, "w") as f:
                f.write('{"languages": {"nl": {"keys": 0, "needsReview": 0}}}\n')
            with contextlib.redirect_stdout(io.StringIO()):
                self.assertEqual(strings_check.main(["--catalog", cat, "--languages", "nl", "--status", st]), 1)
            with open(st, "w") as f:
                f.write('{\n  "languages": {\n    "nl": {\n      "keys": 1,\n      "needsReview": 1\n    }\n  }\n}\n')
            with contextlib.redirect_stdout(io.StringIO()):
                self.assertEqual(strings_check.main(["--catalog", cat, "--languages", "nl", "--status", st]), 0)
```

In `.github/workflows/ci.yml`'s `string-catalog` job, extend the run block:

```yaml
          python3 -W error -m unittest Scripts/tests/test_catalog.py Scripts/tests/test_strings_check.py
          python3 Scripts/strings-check.py --languages "$languages" --status Shared/Resources/TranslationStatus.json
```

- [ ] **Step 6: Run and commit**

Run: `python3 -W error -m unittest Scripts/tests/test_catalog.py Scripts/tests/test_strings_check.py -v` → 18 tests OK. `python3 Scripts/strings-check.py` → `248 keys checked, 0 problems, 0 warnings` (no `--languages`, so no status check yet).

```bash
git add Scripts/catalog.py Scripts/tests/test_catalog.py Scripts/strings_check.py Scripts/tests/test_strings_check.py .github/workflows/ci.yml
git commit -m "feat(l10n): catalog helpers shared by sync, lint and translator; status file check

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 3: The translator's pure core

**Files:**
- Create: `Scripts/translate.py` (core only; the transport and CLI come in Task 4), `Scripts/tests/test_translate.py`, `Scripts/translation-rules.md`, `Scripts/languages.txt`

**Interfaces:**
- Consumes: `catalog.load/save/units/source_units/forms_for/status/dumps_status`, `strings_check._placeholders`, `strings_check.BUDGET`.
- Produces: `Unit` (dict with `id`, `key`, `form`, `source`, `comment`, `budget`); `collect(data, lang, retranslate=()) -> list[Unit]`; `batched(units, size=40) -> list[list[Unit]]`; `build_messages(units, lang, rules) -> (system, user)`; `parse_reply(text) -> dict[str, str]`; `apply(data, lang, units, mapping) -> (applied: int, rejected: list[str])`; `LANGUAGE_NAMES` and `REGISTER` dicts; `load_rules(path) -> str`; `run(data, lang, send, rules, size=40, retranslate=(), dry_run=False, log=print) -> (applied, rejected)` where `send(system, user) -> str`.

- [ ] **Step 1: Rules, languages, failing tests**

Create `Scripts/languages.txt`:

```
es
nl
ja
ko
```

Create `Scripts/translation-rules.md`:

```markdown
You translate the user interface of Paperweight, an iOS app that makes a phone quiet on a schedule. Translate from English into the target language named in the request.

Voice
- The two state words are "quiet" (apps are shielded) and "open" (apps are usable). Never use words meaning blocked, banned, forbidden, free, or locked out. Choose the calmest natural equivalents and use them consistently.
- No exclamation marks. Calm, plain, second person. No praise, no shame, no streaks.
- Keep the length close to the English; a Lock Screen line marked with a budget must fit it.

Glossary (keep these consistent)
- Paperweight: the app's name. Never translate it.
- token: the physical NFC tag the user taps. Translate as the everyday word for such a tag or token, consistently.
- cool-off: a multi-day unlock that needs no token and ends by itself.
- day off: a planned day when apps stay open all day (loosens).
- quiet day: a planned day when apps stay quiet all day (tightens).
- open hours / quiet hours: the painted schedule.
- Screen Time: Apple's feature; use Apple's own localized name for it.
- Home Screen, Lock Screen, Control Center: use Apple's localized names.

Placeholders
- Keep every placeholder exactly as written: %@, %lld, %1$@, %2$lld and so on. You may reorder them; when you reorder two or more, use the numbered form.
- Keep the ½ character where it appears; it is part of the value.
- A unit whose form is "plural.one" is the singular; "plural.other" is the plural (or the only form).

Format
- Reply with one JSON object only, mapping each unit's "id" to its translation as a string. No commentary, no code fences.
```

Create `Scripts/tests/test_translate.py`:

```python
import json, os, sys, unittest
sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
import translate  # noqa: E402


def unit(value, state="translated"):
    return {"stringUnit": {"state": state, "value": value}}


def cat(strings):
    return {"sourceLanguage": "en", "version": "1.0", "strings": strings}


class Collect(unittest.TestCase):
    def test_bare_flat_and_plural_keys(self):
        data = cat({
            "Ready": {},
            "%@ tomorrow": {"localizations": {"en": unit("%@ tomorrow")}},
            "%lld days": {"comment": "Duration; has a plural rule", "localizations": {"en": {"variations": {"plural": {"one": unit("%lld day"), "other": unit("%lld days")}}}}},
        })
        got = translate.collect(data, "nl")
        self.assertEqual([(u["key"], u["form"], u["source"]) for u in got],
                         [("Ready", "", "Ready"), ("%@ tomorrow", "", "%@ tomorrow"),
                          ("%lld days", "plural.one", "%lld day"), ("%lld days", "plural.other", "%lld days")])
        self.assertEqual(got[2]["comment"], "Duration; has a plural rule")

    def test_single_category_language_gets_only_other(self):
        data = cat({"%lld days": {"localizations": {"en": {"variations": {"plural": {"one": unit("%lld day"), "other": unit("%lld days")}}}}}})
        self.assertEqual([u["form"] for u in translate.collect(data, "ja")], ["plural.other"])

    def test_translated_units_are_skipped_unless_retranslated_or_new(self):
        data = cat({
            "Open": {"localizations": {"en": unit("Open"), "nl": unit("Open", "needs_review")}},
            "Ready": {"localizations": {"en": unit("Ready"), "nl": unit("Klaar", "new")}},
            "Quiet": {"localizations": {"en": unit("Quiet"), "nl": unit("Stil")}},
        })
        self.assertEqual([u["key"] for u in translate.collect(data, "nl")], ["Ready"])
        self.assertEqual([u["key"] for u in translate.collect(data, "nl", retranslate={"Quiet"})], ["Ready", "Quiet"])

    def test_budget_comes_from_the_comment(self):
        data = cat({"until %@": {"comment": "Lock Screen; keep under 24 characters"}})
        self.assertEqual(translate.collect(data, "nl")[0]["budget"], 24)


class Batches(unittest.TestCase):
    def test_batched_by_size(self):
        units = [{"id": str(i)} for i in range(95)]
        sizes = [len(b) for b in translate.batched(units, 40)]
        self.assertEqual(sizes, [40, 40, 15])


class Messages(unittest.TestCase):
    def test_messages_carry_rules_register_and_units(self):
        system, user = translate.build_messages([{"id": "k1|", "source": "Open", "comment": "", "budget": None, "form": ""}], "nl", "RULES")
        self.assertIn("RULES", system)
        self.assertIn(translate.REGISTER["nl"], system)
        self.assertIn("Dutch", user)
        self.assertEqual(json.loads(user[user.index("["):])[0]["id"], "k1|")


class Parse(unittest.TestCase):
    def test_accepts_fenced_and_plain_json(self):
        self.assertEqual(translate.parse_reply('```json\n{"a": "b"}\n```'), {"a": "b"})
        self.assertEqual(translate.parse_reply('{"a": "b"}'), {"a": "b"})

    def test_rejects_non_object(self):
        with self.assertRaises(ValueError):
            translate.parse_reply('["a"]')


class Apply(unittest.TestCase):
    def test_writes_needs_review_units_and_rejects_bad_ones(self):
        data = cat({
            "%@ tomorrow": {"localizations": {"en": unit("%@ tomorrow")}},
            "Copied": {},
            "%lld days": {"localizations": {"en": {"variations": {"plural": {"one": unit("%lld day"), "other": unit("%lld days")}}}}},
            "Open": {},
        })
        units = translate.collect(data, "nl")
        mapping = {
            translate.unit_id("%@ tomorrow", ""): "%1$@ morgen",
            translate.unit_id("Copied", ""): "Gekopieerd!",
            translate.unit_id("%lld days", "plural.one"): "%lld dag",
            translate.unit_id("%lld days", "plural.other"): "dagen",
            translate.unit_id("Open", ""): "Open",
        }
        applied, rejected = translate.apply(data, "nl", units, mapping)
        self.assertEqual(applied, 3)
        self.assertEqual(sorted(rejected), ["%lld days [plural.other]: placeholders differ", "Copied: exclamation mark"])
        self.assertEqual(data["strings"]["%@ tomorrow"]["localizations"]["nl"], unit("%1$@ morgen", "needs_review"))
        self.assertEqual(data["strings"]["%lld days"]["localizations"]["nl"]["variations"]["plural"]["one"], unit("%lld dag", "needs_review"))
        self.assertNotIn("other", data["strings"]["%lld days"]["localizations"]["nl"]["variations"]["plural"])
        self.assertNotIn("nl", data["strings"]["Copied"].get("localizations", {}))

    def test_missing_ids_are_rejected(self):
        data = cat({"Open": {}})
        applied, rejected = translate.apply(data, "nl", translate.collect(data, "nl"), {})
        self.assertEqual((applied, rejected), (0, ["Open: no translation returned"]))


class Run(unittest.TestCase):
    def test_run_uses_send_and_is_idempotent(self):
        data = cat({"Open": {}, "Ready": {}})
        calls = []

        def send(system, user):
            calls.append(user)
            ids = [u["id"] for u in json.loads(user[user.index("["):])]
            return json.dumps({i: "x" for i in ids})

        self.assertEqual(translate.run(data, "nl", send, "RULES", log=lambda *_: None), (2, []))
        self.assertEqual(translate.run(data, "nl", send, "RULES", log=lambda *_: None), (0, []))
        self.assertEqual(len(calls), 1)

    def test_dry_run_sends_nothing(self):
        data = cat({"Open": {}})
        self.assertEqual(translate.run(data, "nl", lambda s, u: self.fail("sent"), "RULES", dry_run=True, log=lambda *_: None), (0, []))
        self.assertNotIn("localizations", data["strings"]["Open"])


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run to verify failure**

Run: `python3 -W error -m unittest Scripts/tests/test_translate.py -v`
Expected: `ModuleNotFoundError: No module named 'translate'`.

- [ ] **Step 3: Write the core**

Create `Scripts/translate.py`:

```python
#!/usr/bin/env python3
"""Machine-translate the String Catalog into the languages in Scripts/languages.txt.

Translations are written with state needs_review; only a person marks them
translated. Placeholder parity and the no-exclamation rule are enforced before
anything is written. Standard library only.
"""
import argparse
import json
import os
import sys
import time
import urllib.error
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import catalog  # noqa: E402
import strings_check  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
CATALOG = os.path.join(ROOT, "Shared", "Resources", "Localizable.xcstrings")
STATUS = os.path.join(ROOT, "Shared", "Resources", "TranslationStatus.json")
RULES = os.path.join(HERE, "translation-rules.md")
LANGUAGES = os.path.join(HERE, "languages.txt")

LANGUAGE_NAMES = {"es": "Spanish", "nl": "Dutch", "ja": "Japanese", "ko": "Korean",
                  "de": "German", "fr": "French", "it": "Italian", "pt-BR": "Brazilian Portuguese",
                  "zh-Hans": "Simplified Chinese", "zh-Hant": "Traditional Chinese"}
REGISTER = {
    "es": "Address the user informally with tú.",
    "nl": "Address the user informally with je.",
    "ja": "Use polite です／ます forms.",
    "ko": "Use the polite informal 해요체.",
}


def unit_id(key, form):
    return f"{key}|{form}"


def load_rules(path=RULES):
    with open(path, encoding="utf-8") as f:
        return f.read()


def read_languages(path=LANGUAGES):
    with open(path, encoding="utf-8") as f:
        return [line.strip() for line in f if line.strip() and not line.startswith("#")]


def _budget(comment):
    m = strings_check.BUDGET.search(comment or "")
    return int(m.group(1)) if m else None


def _needs_work(entry, lang, form):
    """True when this form has no translation yet, or one still in state new."""
    loc = entry.get("localizations", {}).get(lang)
    if not loc:
        return True
    if form == "":
        u = loc.get("stringUnit")
        return not u or u.get("state") == "new"
    kind, name = form.split(".", 1)
    u = loc.get("variations", {}).get(kind, {}).get(name, {}).get("stringUnit")
    return not u or u.get("state") == "new"


def collect(data, lang, retranslate=()):
    """Units the target language still needs, in catalog order."""
    source = data.get("sourceLanguage", "en")
    wanted_forms = catalog.forms_for(lang)
    out = []
    for key, entry in data.get("strings", {}).items():
        comment = entry.get("comment", "") or ""
        for form, value in catalog.source_units(key, entry, source):
            if form.startswith("plural.") and form.split(".", 1)[1] not in wanted_forms:
                continue
            if key not in retranslate and not _needs_work(entry, lang, form):
                continue
            out.append({"id": unit_id(key, form), "key": key, "form": form, "source": value,
                        "comment": comment, "budget": _budget(comment)})
    return out


def batched(units, size=40):
    return [units[i:i + size] for i in range(0, len(units), size)]


def build_messages(units, lang, rules):
    name = LANGUAGE_NAMES.get(lang, lang)
    system = rules.rstrip() + "\n\nRegister for this language\n- " + REGISTER.get(lang, "Use the register a careful native app would use.") + "\n"
    payload = [{"id": u["id"], "source": u["source"], "form": u["form"], "comment": u["comment"], "budget": u["budget"]}
               for u in units]
    user = (f"Translate these {len(units)} user-interface strings from English into {name} ({lang}). "
            "Return one JSON object mapping each id to its translation.\n\n" + json.dumps(payload, ensure_ascii=False, indent=1))
    return system, user


def parse_reply(text):
    body = text.strip()
    if body.startswith("```"):
        body = body.split("\n", 1)[1] if "\n" in body else ""
        body = body.rsplit("```", 1)[0]
    parsed = json.loads(body)
    if not isinstance(parsed, dict) or not all(isinstance(v, str) for v in parsed.values()):
        raise ValueError("reply is not a JSON object of strings")
    return parsed


def _write_unit(entry, lang, form, value):
    loc = entry.setdefault("localizations", {}).setdefault(lang, {})
    su = {"stringUnit": {"state": "needs_review", "value": value}}
    if form == "":
        loc["stringUnit"] = su["stringUnit"]
    else:
        kind, name = form.split(".", 1)
        loc.setdefault("variations", {}).setdefault(kind, {})[name] = su


def apply(data, lang, units, mapping):
    """Write validated translations; return (applied, rejected descriptions)."""
    applied, rejected = 0, []
    for u in units:
        label = u["key"] if u["form"] == "" else f"{u['key']} [{u['form']}]"
        value = mapping.get(u["id"])
        if value is None:
            rejected.append(f"{label}: no translation returned")
            continue
        if "!" in value:
            rejected.append(f"{label}: exclamation mark")
            continue
        if strings_check._placeholders(value) != strings_check._placeholders(u["source"]):
            rejected.append(f"{label}: placeholders differ")
            continue
        _write_unit(data["strings"][u["key"]], lang, u["form"], value)
        applied += 1
    return applied, rejected


def run(data, lang, send, rules, size=40, retranslate=(), dry_run=False, log=print):
    units = collect(data, lang, retranslate)
    log(f"{lang}: {len(units)} units to translate")
    if dry_run:
        for b in batched(units, size):
            system, user = build_messages(b, lang, rules)
            log(user)
        return 0, []
    applied, rejected = 0, []
    for i, b in enumerate(batched(units, size), 1):
        system, user = build_messages(b, lang, rules)
        mapping = parse_reply(send(system, user))
        a, r = apply(data, lang, b, mapping)
        applied += a
        rejected += r
        log(f"{lang}: batch {i}: {a} applied, {len(r)} rejected")
    return applied, rejected
```

- [ ] **Step 4: Run to verify pass**

Run: `python3 -W error -m unittest Scripts/tests/test_translate.py -v`
Expected: 12 tests OK.

- [ ] **Step 5: Commit**

```bash
git add Scripts/translate.py Scripts/tests/test_translate.py Scripts/translation-rules.md Scripts/languages.txt
git commit -m "feat(l10n): translator core — collect, batch, validate, apply, with rules and glossary

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 4: Transport, CLI, verify mode, and the first real run

**Files:**
- Modify: `Scripts/translate.py` (append), `Scripts/tests/test_translate.py` (append), `Shared/Resources/Localizable.xcstrings`, create `Shared/Resources/TranslationStatus.json`, modify `.github/workflows/ci.yml` (nothing new; the Ubuntu job already passes `--status`)

**Interfaces:**
- Produces: `anthropic_send(model, key) -> send` (a callable `(system, user) -> str` with retry); `main(argv=None, send_factory=anthropic_send) -> int`; CLI flags `--language CODE` (repeatable), `--retranslate KEY` (repeatable), `--dry-run`, `--model`, `--batch-size`, `--verify CODE`, `--summary PATH`.

- [ ] **Step 1: Failing tests for the CLI**

Append to `Scripts/tests/test_translate.py`:

```python
class Cli(unittest.TestCase):
    def _files(self, d):
        cat_path = os.path.join(d, "c.xcstrings"); st = os.path.join(d, "s.json"); langs = os.path.join(d, "l.txt")
        with open(cat_path, "w") as f:
            json.dump(cat({"Open": {}, "Ready": {}}), f)
        with open(langs, "w") as f:
            f.write("nl\nja\n")
        return cat_path, st, langs

    def test_main_translates_every_language_and_writes_status(self):
        import tempfile
        with tempfile.TemporaryDirectory() as d:
            cat_path, st, langs = self._files(d)

            def factory(model, key):
                def send(system, user):
                    ids = [u["id"] for u in json.loads(user[user.index("["):])]
                    return json.dumps({i: "x" for i in ids})
                return send

            rc = translate.main(["--catalog", cat_path, "--status", st, "--languages-file", langs, "--rules", os.path.join(os.path.dirname(__file__), "..", "translation-rules.md")],
                                send_factory=factory, env={"CLAUDE_PLATFORM_API_KEY": "k"}, log=lambda *_: None)
            self.assertEqual(rc, 0)
            with open(st) as f:
                self.assertEqual(json.load(f), {"languages": {"nl": {"keys": 2, "needsReview": 2}, "ja": {"keys": 2, "needsReview": 2}}})
            with open(cat_path) as f:
                self.assertEqual(json.load(f)["strings"]["Open"]["localizations"]["nl"]["stringUnit"]["state"], "needs_review")

    def test_main_without_key_exits_2_and_writes_nothing(self):
        import tempfile
        with tempfile.TemporaryDirectory() as d:
            cat_path, st, langs = self._files(d)
            rc = translate.main(["--catalog", cat_path, "--status", st, "--languages-file", langs], env={}, log=lambda *_: None)
            self.assertEqual(rc, 2)
            self.assertFalse(os.path.exists(st))

    def test_rejections_make_the_run_fail_but_keep_good_units(self):
        import tempfile
        with tempfile.TemporaryDirectory() as d:
            cat_path, st, langs = self._files(d)

            def factory(model, key):
                return lambda system, user: json.dumps({translate.unit_id("Open", ""): "Open!", translate.unit_id("Ready", ""): "Klaar"})

            rc = translate.main(["--catalog", cat_path, "--status", st, "--languages-file", langs, "--language", "nl"],
                                send_factory=factory, env={"CLAUDE_PLATFORM_API_KEY": "k"}, log=lambda *_: None)
            self.assertEqual(rc, 1)
            with open(cat_path) as f:
                strings = json.load(f)["strings"]
            self.assertNotIn("nl", strings["Open"].get("localizations", {}))
            self.assertEqual(strings["Ready"]["localizations"]["nl"]["stringUnit"]["value"], "Klaar")
```

- [ ] **Step 2: Run to verify failure**

Run: `python3 -W error -m unittest Scripts.tests.test_translate.Cli -v` (or the file with `-k Cli`)
Expected: `AttributeError: module 'translate' has no attribute 'main'`.

- [ ] **Step 3: Transport, verify and CLI**

Append to `Scripts/translate.py`:

```python
API = "https://api.anthropic.com/v1/messages"
DEFAULT_MODEL = "claude-sonnet-5"


def anthropic_send(model, key, max_tokens=8192, attempts=4):
    """A send(system, user) -> text callable over the Messages API, retrying
    on rate limits and server errors with a growing pause."""
    def send(system, user):
        # Claude 5 models reject `temperature`; determinism comes from the
        # rules and the JSON-only reply format.
        body = json.dumps({"model": model, "max_tokens": max_tokens,
                           "system": system, "messages": [{"role": "user", "content": user}]}).encode("utf-8")
        for attempt in range(1, attempts + 1):
            req = urllib.request.Request(API, data=body, headers={
                "x-api-key": key, "anthropic-version": "2023-06-01", "content-type": "application/json"})
            try:
                with urllib.request.urlopen(req, timeout=120) as resp:
                    reply = json.loads(resp.read().decode("utf-8"))
                return "".join(block.get("text", "") for block in reply.get("content", []) if block.get("type") == "text")
            except urllib.error.HTTPError as e:
                if e.code in (429, 500, 502, 503, 529) and attempt < attempts:
                    time.sleep(5 * attempt)
                    continue
                raise RuntimeError(f"Claude API HTTP {e.code}: {e.read().decode('utf-8', 'replace')[:300]}") from None
    return send


def verify(data, lang, send, log=print):
    """Back-translate every existing translation and print a judgement per unit. Read-only."""
    source = data.get("sourceLanguage", "en")
    rows = []
    for key, entry in data.get("strings", {}).items():
        loc = entry.get("localizations", {}).get(lang)
        if not loc:
            continue
        sources = dict(catalog.source_units(key, entry, source))
        for form, value, _ in catalog.units(loc):
            rows.append({"id": unit_id(key, form), "english": sources.get(form, sources.get("", key)), "translation": value})
    name = LANGUAGE_NAMES.get(lang, lang)
    for b in batched(rows, 40):
        system = ("You check app translations. For each unit, translate the given " + name +
                  " text back into English literally, then judge in one short line whether it keeps the English meaning, "
                  "tone (calm, no exclamation) and placeholders. Reply with one JSON object mapping id to "
                  "{\"back\": string, \"note\": string}. No code fences.")
        reply = parse_reply_objects(send(system, json.dumps(b, ensure_ascii=False, indent=1)))
        for r in b:
            j = reply.get(r["id"], {})
            log(f"{r['id']}\n  en:   {r['english']}\n  {lang}:   {r['translation']}\n  back: {j.get('back', '?')}\n  note: {j.get('note', '?')}")


def parse_reply_objects(text):
    body = text.strip()
    if body.startswith("```"):
        body = body.split("\n", 1)[1] if "\n" in body else ""
        body = body.rsplit("```", 1)[0]
    parsed = json.loads(body)
    if not isinstance(parsed, dict):
        raise ValueError("reply is not a JSON object")
    return parsed


def main(argv=None, send_factory=anthropic_send, env=None, log=print):
    env = os.environ if env is None else env
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--catalog", default=CATALOG)
    p.add_argument("--status", default=STATUS)
    p.add_argument("--languages-file", default=LANGUAGES)
    p.add_argument("--rules", default=RULES)
    p.add_argument("--language", action="append", default=[], help="only this language (repeatable)")
    p.add_argument("--retranslate", action="append", default=[], help="redo this key even if translated (repeatable)")
    p.add_argument("--dry-run", action="store_true", help="print the batches, send nothing, write nothing")
    p.add_argument("--model", default=DEFAULT_MODEL)
    p.add_argument("--batch-size", type=int, default=40)
    p.add_argument("--verify", metavar="CODE", help="back-translate this language and print judgements; writes nothing")
    p.add_argument("--summary", help="write a JSON summary {lang: {applied, rejected}} here")
    a = p.parse_args(argv)

    data = catalog.load(a.catalog)
    languages = a.language or read_languages(a.languages_file)
    rules = load_rules(a.rules)

    if a.verify:
        key = env.get("CLAUDE_PLATFORM_API_KEY")
        if not key:
            log("CLAUDE_PLATFORM_API_KEY is not set"); return 2
        verify(data, a.verify, send_factory(a.model, key), log=log)
        return 0

    if a.dry_run:
        for lang in languages:
            run(data, lang, None, rules, size=a.batch_size, retranslate=set(a.retranslate), dry_run=True, log=log)
        return 0

    key = env.get("CLAUDE_PLATFORM_API_KEY")
    if not key:
        log("CLAUDE_PLATFORM_API_KEY is not set; nothing translated")
        return 2
    send = send_factory(a.model, key)
    summary, failed = {}, False
    for lang in languages:
        applied, rejected = run(data, lang, send, rules, size=a.batch_size, retranslate=set(a.retranslate), log=log)
        summary[lang] = {"applied": applied, "rejected": rejected}
        for r in rejected:
            log(f"::warning::{lang}: rejected {r}")
        failed = failed or bool(rejected)
    catalog.save(a.catalog, data)
    all_languages = read_languages(a.languages_file)
    with open(a.status, "w", encoding="utf-8") as f:
        f.write(catalog.dumps_status(catalog.status(data, all_languages)))
    if a.summary:
        with open(a.summary, "w", encoding="utf-8") as f:
            json.dump(summary, f, indent=2)
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
```

- [ ] **Step 4: Run to verify pass**

Run: `python3 -W error -m unittest Scripts/tests/test_translate.py -v` → 15 tests OK.

- [ ] **Step 5: Dry run against the real catalog**

Run: `python3 Scripts/translate.py --dry-run --language nl | head -60`
Expected: `nl: 248 units to translate` followed by the first batch's user message (JSON of 40 units, comments and budgets present, plural forms listed per form). `git status` shows no change.

- [ ] **Step 6: The real run (needs the key)**

Run the translator with the key read from 1Password at call time (the value never lands in a shell variable you print or in the report):

Run: `CLAUDE_PLATFORM_API_KEY="$(op read 'op://Private/Paperweight iOS/l10n/claude-platform-api-key')" python3 Scripts/translate.py`

If `op read` fails (not signed in), stop and report NEEDS_CONTEXT.
Expected: four languages, about 7 batches each, `applied` counts summing to the unit count, few or no rejections. If any unit was rejected, run `CLAUDE_PLATFORM_API_KEY="$(op read 'op://Private/Paperweight iOS/l10n/claude-platform-api-key')" python3 Scripts/translate.py --language CODE --retranslate "KEY"` for each rejected key once; if it is rejected again, leave it and report it.

Then: `python3 Scripts/strings-check.py --languages "$(tr '\n' ' ' < Scripts/languages.txt)" --status Shared/Resources/TranslationStatus.json`
Expected: `248 keys checked, 0 problems, N warnings` where the warnings are Lock Screen budget overruns. List them in the report; fix each by rerunning `--retranslate` for that key with the budget comment in place (the model sees it), and if a language cannot fit, shorten by hand in the catalog and leave the state `needs_review`.

Sanity-read: `python3 - <<'EOF'` printing, for `ko` and `ja`, the translations of `QUIET`, `OPEN`, `Open until %@, then quiet`, `%lld days` (both forms if present), and `Days off & quiet days`; paste them in the report. Confirm no "!" anywhere: `grep -c '!' Shared/Resources/Localizable.xcstrings` should equal the count in `git show HEAD:Shared/Resources/Localizable.xcstrings | grep -c '!'` (only the English "exclamationmark.triangle" symbol name may contain one, and it is not a string value).

Run `Scripts/strings-sync.sh --check` (green; translations survive a sync) and the full suite (229 pass; tests pin English).

- [ ] **Step 7: Commit**

```bash
git add Scripts/translate.py Scripts/tests/test_translate.py Shared/Resources/Localizable.xcstrings Shared/Resources/TranslationStatus.json
git commit -m "feat(l10n): Claude transport and CLI; Spanish, Dutch, Japanese and Korean marked for review

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 5: The Translate workflow and the label

**Files:**
- Create: `.github/workflows/translate.yml`
- Modify: `docs/LOCALIZATION.md` (loop section)

**Interfaces:**
- Consumes: `Scripts/translate.py --summary PATH`, `Scripts/strings-check.py --languages --status`.

- [ ] **Step 1: Create the label**

Run: `gh label create translation --color 0E8A16 --description "Translations: machine output to review, fixes, and language requests" 2>&1 | tail -1` (a "already exists" message is fine).

- [ ] **Step 2: Write the workflow**

Create `.github/workflows/translate.yml`:

```yaml
name: Translate

# Fills in missing translations with Claude and opens a pull request for
# review. Runs when the catalog or the language list changes on main, or by
# hand. Never pushes to main. Needs the CLAUDE_PLATFORM_API_KEY repository secret;
# without it the run says so and exits green.
on:
  push:
    branches: [main]
    paths:
      - Shared/Resources/Localizable.xcstrings
      - Scripts/languages.txt
  workflow_dispatch:
    inputs:
      language:
        description: "Only this language code (blank = every language in Scripts/languages.txt)"
        required: false
        type: string

permissions:
  contents: write
  pull-requests: write

concurrency:
  group: translate
  cancel-in-progress: false

jobs:
  translate:
    name: Translate missing strings
    # macOS so the catalog is formatted the way Xcode writes it (swift is on the path).
    runs-on: macos-latest
    timeout-minutes: 30
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - name: Translate
        id: translate
        env:
          CLAUDE_PLATFORM_API_KEY: ${{ secrets.CLAUDE_PLATFORM_API_KEY }}
          LANGUAGE: ${{ inputs.language }}
        run: |
          set -euo pipefail
          if [ -z "${CLAUDE_PLATFORM_API_KEY:-}" ]; then
            echo "::notice::CLAUDE_PLATFORM_API_KEY is not set; nothing translated. Add it under Settings → Secrets to enable this workflow."
            echo "changed=false" >> "$GITHUB_OUTPUT"
            exit 0
          fi
          args=(--summary "$RUNNER_TEMP/summary.json")
          [ -n "${LANGUAGE:-}" ] && args+=(--language "$LANGUAGE")
          set +e
          python3 Scripts/translate.py "${args[@]}"
          rc=$?
          set -e
          # 1 = some units rejected (reported as warnings above); still worth a PR for the rest.
          [ "$rc" -eq 0 ] || [ "$rc" -eq 1 ] || exit "$rc"
          if git diff --quiet -- Shared/Resources/Localizable.xcstrings Shared/Resources/TranslationStatus.json; then
            echo "Nothing to translate."
            echo "changed=false" >> "$GITHUB_OUTPUT"
          else
            echo "changed=true" >> "$GITHUB_OUTPUT"
          fi

      - name: Lint the result
        if: steps.translate.outputs.changed == 'true'
        run: |
          set -euo pipefail
          python3 -W error -m unittest Scripts/tests/test_catalog.py Scripts/tests/test_strings_check.py Scripts/tests/test_translate.py
          python3 Scripts/strings-check.py --languages "$(tr '\n' ' ' < Scripts/languages.txt)" --status Shared/Resources/TranslationStatus.json

      # A PR opened with GITHUB_TOKEN gets no CI run of its own, so the lint
      # above is the check; full CI runs on main after the merge.
      - name: Open or update the pull request
        if: steps.translate.outputs.changed == 'true'
        env:
          GH_TOKEN: ${{ github.token }}
        run: |
          set -euo pipefail
          git config user.name "github-actions[bot]"
          git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
          git checkout -B translations/auto
          git add Shared/Resources/Localizable.xcstrings Shared/Resources/TranslationStatus.json
          git commit -m "chore(l10n): machine translations for review"
          git push --force origin translations/auto

          python3 - "$RUNNER_TEMP/summary.json" > "$RUNNER_TEMP/body.md" <<'EOF'
          import json, sys
          s = json.load(open(sys.argv[1]))
          print("Machine translations from the Translate workflow, marked *needs review* in the catalog.\n")
          print("| Language | Applied | Rejected |\n|---|---|---|")
          for lang, v in s.items():
              print(f"| {lang} | {v['applied']} | {len(v['rejected'])} |")
          rej = [f"- `{lang}`: {r}" for lang, v in s.items() for r in v["rejected"]]
          if rej:
              print("\nRejected units (left untranslated):\n" + "\n".join(rej))
          print("\nReview in Xcode's String Catalog editor (filter *Needs review*), or run "
                "`python3 Scripts/translate.py --verify CODE` for a back-translation pass. "
                "The catalog lint passed in the workflow; full CI runs on main after merge.")
          EOF

          if [ "$(gh pr list --head translations/auto --state open --json number --jq length)" = "0" ]; then
            gh pr create --base main --head translations/auto --label translation \
              --title "Machine translations for review" --body-file "$RUNNER_TEMP/body.md"
          else
            gh pr edit translations/auto --body-file "$RUNNER_TEMP/body.md"
          fi
```

Verify it parses: `python3 -c "import yaml; yaml.safe_load(open('.github/workflows/translate.yml')); print('yaml ok')"`.

- [ ] **Step 3: Document the loop**

In `docs/LOCALIZATION.md`, replace the "## The loop" section with:

```markdown
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
```

- [ ] **Step 4: Commit**

```bash
git add .github/workflows/translate.yml docs/LOCALIZATION.md
git commit -m "ci: Translate workflow opens a review PR when the catalog changes

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 6: `TranslationStatus` and `TranslationFeedback` in Shared

**Files:**
- Create: `Shared/TranslationStatus.swift`, `Shared/TranslationFeedback.swift`, `PaperweightTests/Models/TranslationStatusTests.swift`, `PaperweightTests/Models/TranslationFeedbackTests.swift`
- Modify: `Shared/Constants.swift`

**Interfaces:**
- Produces:
  - `Paperweight.repositoryURL: URL` (`https://github.com/erodewald/paperweight`).
  - `struct TranslationStatus: Decodable, Equatable { struct Language: Decodable, Equatable { var keys: Int; var needsReview: Int }; var languages: [String: Language]; static func load(from bundle: Bundle = L10n.bundle) -> TranslationStatus?; func needsReview(_ code: String) -> Bool }`.
  - `enum TranslationFeedback { struct Context: Equatable { var appLanguage: String; var deviceLanguages: [String]; var appVersion: String; var build: String; static func current(bundle: Bundle = .main, locale: Locale = .current) -> Context }; static func reportURL(_ c: Context) -> URL; static func requestURL(_ c: Context) -> URL; static func languageName(_ code: String, locale: Locale = .current) -> String }`.

- [ ] **Step 1: Failing tests**

Create `PaperweightTests/Models/TranslationStatusTests.swift`:

```swift
import XCTest

final class TranslationStatusTests: XCTestCase {
    private let fixture = """
    {"languages": {"ko": {"keys": 248, "needsReview": 248}, "nl": {"keys": 248, "needsReview": 0}}}
    """

    func test_decodes_and_reports_review_state() throws {
        let status = try JSONDecoder().decode(TranslationStatus.self, from: Data(fixture.utf8))
        XCTAssertTrue(status.needsReview("ko"))
        XCTAssertFalse(status.needsReview("nl"), "a fully reviewed language shows no notice")
        XCTAssertFalse(status.needsReview("en"), "the source language is never machine-translated")
        XCTAssertFalse(status.needsReview("fr"), "a language absent from the file shows no notice")
    }

    func test_loads_from_the_bundle() {
        TestLocale.useTestBundle()
        XCTAssertNotNil(TranslationStatus.load(), "TranslationStatus.json must ship in the bundle")
    }
}
```

Create `PaperweightTests/Models/TranslationFeedbackTests.swift`:

```swift
import XCTest

final class TranslationFeedbackTests: XCTestCase {
    private let context = TranslationFeedback.Context(appLanguage: "ko", deviceLanguages: ["ko-KR", "en-US"],
                                                      appVersion: "1.3.0", build: "1010")

    private func query(_ url: URL) -> [String: String] {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        return Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
    }

    func test_reportURL_targets_the_fix_form_with_prefilled_fields() {
        let url = TranslationFeedback.reportURL(context)
        XCTAssertEqual(url.host, "github.com")
        XCTAssertEqual(url.path, "/erodewald/paperweight/issues/new")
        let q = query(url)
        XCTAssertEqual(q["template"], "translation-fix.yml")
        XCTAssertEqual(q["language"], "ko")
        XCTAssertEqual(q["device-languages"], "ko-KR, en-US")
        XCTAssertEqual(q["app-version"], "1.3.0 (1010)")
        XCTAssertEqual(q["title"], "Wrong translation (ko)")
    }

    func test_requestURL_targets_the_request_form() {
        let q = query(TranslationFeedback.requestURL(context))
        XCTAssertEqual(q["template"], "translation-request.yml")
        XCTAssertEqual(q["device-languages"], "ko-KR, en-US")
        XCTAssertEqual(q["title"], "Language request")
        XCTAssertNil(q["language"])
    }

    func test_values_are_percent_escaped() {
        let odd = TranslationFeedback.Context(appLanguage: "pt-BR", deviceLanguages: ["pt-BR"], appVersion: "1.0 β", build: "1")
        let url = TranslationFeedback.reportURL(odd)
        XCTAssertFalse(url.absoluteString.contains(" "))
        XCTAssertEqual(query(url)["app-version"], "1.0 β (1)")
    }

    func test_languageName_is_localized() {
        XCTAssertEqual(TranslationFeedback.languageName("ko", locale: TestLocale.en), "Korean")
        XCTAssertEqual(TranslationFeedback.languageName("nl", locale: Locale(identifier: "nl_NL")), "Nederlands")
    }

    func test_current_context_reads_the_bundle_and_locale() {
        let c = TranslationFeedback.Context.current(bundle: Bundle(for: Self.self), locale: TestLocale.en)
        XCTAssertFalse(c.appLanguage.isEmpty)
        XCTAssertFalse(c.deviceLanguages.isEmpty)
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run the two classes with `-only-testing:`. Expected: compile errors (`cannot find 'TranslationStatus' in scope`, `'TranslationFeedback'`).

- [ ] **Step 3: Implement**

Append to `Shared/Constants.swift` inside `enum Paperweight`:

```swift
    /// Where translation feedback goes; the app never talks to it, it opens URLs.
    static let repositoryURL = URL(string: "https://github.com/erodewald/paperweight")!
```

Create `Shared/TranslationStatus.swift`:

```swift
import Foundation

/// Per-language review state, written by Scripts/translate.py into
/// Shared/Resources/TranslationStatus.json and read once at launch. A language
/// with unreviewed machine translations gets an honest notice in Settings.
struct TranslationStatus: Decodable, Equatable {
    struct Language: Decodable, Equatable {
        var keys: Int
        var needsReview: Int
    }

    var languages: [String: Language]

    static func load(from bundle: Bundle = L10n.bundle) -> TranslationStatus? {
        guard let url = bundle.url(forResource: "TranslationStatus", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(TranslationStatus.self, from: data)
    }

    /// True only for a language that ships machine translations nobody has
    /// reviewed yet. The source language and unknown languages are never flagged.
    func needsReview(_ code: String) -> Bool {
        (languages[code]?.needsReview ?? 0) > 0
    }
}
```

Create `Shared/TranslationFeedback.swift`:

```swift
import Foundation

/// Prefilled GitHub issue-form links for translation feedback. Pure: the app
/// hands the URL to the system and nothing else happens.
enum TranslationFeedback {
    struct Context: Equatable {
        var appLanguage: String
        var deviceLanguages: [String]
        var appVersion: String
        var build: String

        static func current(bundle: Bundle = .main, locale: Locale = .current) -> Context {
            let info = bundle.infoDictionary
            return Context(
                appLanguage: bundle.preferredLocalizations.first ?? "en",
                deviceLanguages: Locale.preferredLanguages,
                appVersion: info?["CFBundleShortVersionString"] as? String ?? "—",
                build: info?["CFBundleVersion"] as? String ?? "—")
        }

        var versionLine: String { "\(appVersion) (\(build))" }
        var deviceLanguageList: String { deviceLanguages.joined(separator: ", ") }
    }

    static func reportURL(_ c: Context) -> URL {
        issueURL(template: "translation-fix.yml", title: "Wrong translation (\(c.appLanguage))", fields: [
            ("language", c.appLanguage),
            ("device-languages", c.deviceLanguageList),
            ("app-version", c.versionLine),
        ])
    }

    static func requestURL(_ c: Context) -> URL {
        issueURL(template: "translation-request.yml", title: "Language request", fields: [
            ("device-languages", c.deviceLanguageList),
        ])
    }

    /// The language's own name for itself when the locale is that language,
    /// otherwise its name in the current locale ("Korean").
    static func languageName(_ code: String, locale: Locale = .current) -> String {
        locale.localizedString(forLanguageCode: code) ?? code
    }

    private static func issueURL(template: String, title: String, fields: [(String, String)]) -> URL {
        var components = URLComponents(url: Paperweight.repositoryURL.appendingPathComponent("issues/new"),
                                       resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "template", value: template),
                                 URLQueryItem(name: "title", value: title)]
            + fields.map { URLQueryItem(name: $0.0, value: $0.1) }
        return components.url!
    }
}
```

`Shared/Resources/TranslationStatus.json` is already in `Shared`, so the app, monitor and tests carry it; the widget's file list does not include it and does not need it.

- [ ] **Step 4: Run to verify pass**

Run the two classes. Expected: 7 tests pass. Note `test_languageName_is_localized` for `nl_NL` expects "Nederlands"; if Foundation on the simulator returns a different capitalisation, report the actual value rather than editing.

Run the full suite: 236 pass.

- [ ] **Step 5: Commit**

```bash
git add Shared/TranslationStatus.swift Shared/TranslationFeedback.swift Shared/Constants.swift PaperweightTests/Models/TranslationStatusTests.swift PaperweightTests/Models/TranslationFeedbackTests.swift
git commit -m "feat(l10n): translation status reader and prefilled feedback links

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 7: The Settings screen and the issue forms

**Files:**
- Create: `Paperweight/Views/TranslationsView.swift`, `.github/ISSUE_TEMPLATE/translation-fix.yml`, `.github/ISSUE_TEMPLATE/translation-request.yml`
- Modify: `Paperweight/Views/SettingsView.swift` (row in the Configure card), `Shared/Resources/Localizable.xcstrings` (via sync), `Shared/Resources/TranslationStatus.json` (via translator)

**Interfaces:**
- Consumes: `TranslationStatus.load()`, `TranslationFeedback.Context.current()`, `TranslationFeedback.reportURL/requestURL/languageName`, `NavRow`, `GroupedCard`, `CardDivider`, `pwScreenLabel()`, `pwScreen()`, `PW` colours, `.grotesk` fonts.

- [ ] **Step 1: Issue forms**

Create `.github/ISSUE_TEMPLATE/translation-fix.yml`:

```yaml
name: Wrong translation
description: Something in the app reads wrong in your language.
title: "Wrong translation"
labels: [translation]
body:
  - type: markdown
    attributes:
      value: Thanks. The app filled in the first three fields; the last three are yours.
  - type: input
    id: language
    attributes:
      label: App language
      description: The language the app was running in (code).
    validations:
      required: true
  - type: input
    id: device-languages
    attributes:
      label: Device languages
      description: Your phone's preferred languages, most preferred first.
  - type: input
    id: app-version
    attributes:
      label: App version
  - type: input
    id: screen
    attributes:
      label: Where you saw it
      placeholder: Home, Schedule, the widget, the Lock Screen…
  - type: textarea
    id: wrong-text
    attributes:
      label: What it says now
      description: Copy the text as it appears.
    validations:
      required: true
  - type: textarea
    id: better-text
    attributes:
      label: What it should say
      description: Optional. A better wording, or what felt wrong about it.
```

Create `.github/ISSUE_TEMPLATE/translation-request.yml`:

```yaml
name: Request a language
description: Ask for Paperweight in another language.
title: "Language request"
labels: [translation]
body:
  - type: input
    id: device-languages
    attributes:
      label: Device languages
      description: Filled in by the app; your phone's preferred languages.
  - type: input
    id: requested-language
    attributes:
      label: Language you would like
    validations:
      required: true
  - type: dropdown
    id: can-help
    attributes:
      label: Could you review a machine translation in that language?
      options:
        - "Yes, happy to read it over"
        - "No, just asking"
```

Check on GitHub after pushing: `https://github.com/erodewald/paperweight/issues/new?template=translation-fix.yml&language=ko&app-version=1.3.0+(1010)` shows the form with the two fields filled. Record the result in the report (a screenshot is not needed; say what you saw).

- [ ] **Step 2: The screen**

Create `Paperweight/Views/TranslationsView.swift`:

```swift
import SwiftUI

/// Settings → Language & translations. Shows the language the app is running
/// in, says plainly when that language's translations are machine-made and
/// unreviewed, and offers two ways to help: report a wrong translation, or ask
/// for a language. Both open a prefilled GitHub issue form in the browser; the
/// app itself talks to no server.
struct TranslationsView: View {
    @Environment(\.openURL) private var openURL

    private let context = TranslationFeedback.Context.current()
    private let status = TranslationStatus.load()

    private var languageName: String { TranslationFeedback.languageName(context.appLanguage) }
    private var unreviewed: Bool { status?.needsReview(context.appLanguage) ?? false }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("This app", comment: "Section heading over the current-language row").pwScreenLabel()
                    .padding(.top, 6).padding(.bottom, 10)
                GroupedCard {
                    HStack {
                        Text("Language", comment: "Row label: the language the app is running in")
                            .font(.grotesk(15)).foregroundStyle(PW.textPrimary)
                        Spacer(minLength: 12)
                        Text(languageName).font(.grotesk(13)).foregroundStyle(PW.textMuted)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 14)
                    if unreviewed {
                        CardDivider()
                        Text("This \(languageName) translation was made by a machine and hasn't been checked by a \(languageName) speaker yet. If something reads wrong, say so.",
                             comment: "Notice under the language row; both placeholders are the language name")
                            .font(.grotesk(13)).foregroundStyle(PW.textMuted)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 16).padding(.vertical, 12)
                    }
                    CardDivider()
                    Button { openURL(URL(string: UIApplication.openSettingsURLString)!) } label: {
                        NavRow(title: "Change language", systemImage: "globe", showsChevron: true)
                    }
                    .buttonStyle(.plain)
                }

                Text("Help", comment: "Section heading over the two feedback links").pwScreenLabel()
                    .padding(.top, 22).padding(.bottom, 10)
                GroupedCard {
                    Link(destination: TranslationFeedback.reportURL(context)) {
                        NavRow(title: "Report a wrong translation", systemImage: "text.badge.xmark", showsChevron: true)
                    }
                    CardDivider()
                    Link(destination: TranslationFeedback.requestURL(context)) {
                        NavRow(title: "Request a language", systemImage: "plus.bubble", showsChevron: true)
                    }
                }
                Text("Both open a form on GitHub with the language and version filled in. Nothing is sent until you post it.")
                    .font(.grotesk(13)).foregroundStyle(PW.textFaint)
                    .padding(.top, 10)
            }
            .padding(.horizontal, 18).padding(.bottom, 30)
        }
        .scrollContentBackground(.hidden)
        .pwScreen()
        .navigationTitle("Language & translations")
        .navigationBarTitleDisplayMode(.inline)
    }
}
```

In `Paperweight/Views/SettingsView.swift`, inside the Configure `GroupedCard`, after the Theme row's `CardDivider()` and before the Emergency unlock `NavigationLink`, add:

```swift
                    NavigationLink { TranslationsView() } label: {
                        NavRow(title: "Language & translations",
                               value: TranslationFeedback.languageName(TranslationFeedback.Context.current().appLanguage))
                    }
                    CardDivider()
```

- [ ] **Step 3: Sync, translate the new strings, verify on the simulator**

Run `Scripts/strings-sync.sh` (new keys: "This app", "Language", the notice, "Change language", "Help", "Report a wrong translation", "Request a language", the footer, "Language & translations"). Then `CLAUDE_PLATFORM_API_KEY="$(op read 'op://Private/Paperweight iOS/l10n/claude-platform-api-key')" python3 Scripts/translate.py` (the new units only) and the lint with `--languages … --status …`. If `op read` fails, stop and report NEEDS_CONTEXT.

Simulator: install, open Settings → Language & translations in English: the row shows "English", no notice, two links, Change language opens the iOS Settings app on Paperweight's page. Then launch with `-AppleLanguages "(ko)"`: the whole app should now read in Korean, the row shows the Korean name for Korean, and the notice appears. Screenshot both to `.superpowers/sdd/shots/` and describe what each shows. Tap "Report a wrong translation" in the simulator: Safari opens the GitHub form; confirm the language and version fields are filled (the simulator has no GitHub session; the form renders for anonymous viewers).

Run the full suite (236 pass) and the three-target build.

- [ ] **Step 4: Commit**

```bash
git add Paperweight/Views/TranslationsView.swift Paperweight/Views/SettingsView.swift .github/ISSUE_TEMPLATE Shared/Resources/Localizable.xcstrings Shared/Resources/TranslationStatus.json
git commit -m "feat(l10n): Language & translations screen with prefilled GitHub feedback forms

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 8: Docs, verification, pull request

**Files:**
- Modify: `docs/LOCALIZATION.md` (Settings section), `README.md` (one sentence), `docs/superpowers/specs/2026-09-12-localization-design.md` (§8 note that the app's notice text is the catalog key added in Task 7)

- [ ] **Step 1: Docs**

Append to `docs/LOCALIZATION.md`:

```markdown
## In the app

Settings → Language & translations shows the running language, a notice while
that language's translations are still unreviewed (driven by
`Shared/Resources/TranslationStatus.json`, which the translator writes and the
lint checks), a link to the iOS per-app language setting, and two GitHub issue
forms opened in Safari with the language and version prefilled:
`.github/ISSUE_TEMPLATE/translation-fix.yml` and `translation-request.yml`. Both
carry the `translation` label. A language request is answered by adding the code
to `Scripts/languages.txt`.
```

In `README.md`, extend the Localization bullet: `… see [docs/LOCALIZATION.md](docs/LOCALIZATION.md). Ships in English, Spanish, Dutch, Japanese and Korean; translations are machine-made and marked for review until a speaker checks them.`

- [ ] **Step 2: Full verification**

`xcodegen generate`; three-target build; full suite (236); `Scripts/strings-sync.sh --check`; `python3 -W error -m unittest Scripts/tests/test_catalog.py Scripts/tests/test_strings_check.py Scripts/tests/test_translate.py` (34 tests); `python3 Scripts/strings-check.py --languages "$(tr '\n' ' ' < Scripts/languages.txt)" --status Shared/Resources/TranslationStatus.json` (0 problems); `swift Scripts/xcstrings-format.swift Scripts/tests/fixtures/xcode-style.xcstrings /tmp/f && cmp Scripts/tests/fixtures/xcode-style.xcstrings /tmp/f`; both workflow files parse.

- [ ] **Step 3: Commit and open the PR**

```bash
git add docs/LOCALIZATION.md README.md docs/superpowers/specs/2026-09-12-localization-design.md
git commit -m "docs: the translation loop, the Settings screen, and how to add a language

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
git push -u origin feat/localization-phase-2
```

PR title: `Localization phase 2: four languages for review, Translate workflow, feedback from Settings`. Body: what landed; that `CLAUDE_PLATFORM_API_KEY` must be added as a repository secret for the workflow (link to Settings → Secrets); the on-device checks (Korean run, Settings row, both forms); the two screenshots. End with `🤖 Generated with [Claude Code](https://claude.com/claude-code)`.

---

## Self-review

**Spec coverage.** §1 "Xcode syncs too" (formatter, semantic check, verbatim debug strings, CFBundleName) → Task 1. §3 rules and register → `translation-rules.md` and `REGISTER` (Task 3). §5 lint additions (status file) → Task 2. §7 translator (collect, batches, validation, needs_review, idempotence, `--retranslate`/`--language`/`--dry-run`, status file, formatting, `--verify`) → Tasks 3–4; the Translate workflow (macOS, secret, PR on `translations/auto`, label, lint inside, no CI trigger caveat) → Task 5; adding a language → Task 5 docs. §8 screen (current language, notice, report, request, change language), status file semantics, issue forms with the listed ids, tests for URL builders and the status reader → Tasks 6–7. §9 files → file map.

**Placeholders.** None. Every step carries its code or its exact command. Task 4 Step 6 and Task 7 Step 3 depend on the API key and say what to do without it.

**Type consistency.** `catalog.units/source_units/forms_for/status/dumps_status/load/save`, `strings_check._placeholders/BUDGET`, `translate.unit_id/collect/batched/build_messages/parse_reply/apply/run/anthropic_send/verify/main`, `TranslationStatus.load/needsReview`, `TranslationFeedback.Context.current/reportURL/requestURL/languageName`, `NavRow(title:)`/`NavRow(verbatim:)`, `Paperweight.repositoryURL` are used with the same names and shapes throughout. The status JSON shape `{"languages": {code: {"keys", "needsReview"}}}` is identical in `catalog.status`, the lint's comparison, the Swift decoder and the fixtures.
