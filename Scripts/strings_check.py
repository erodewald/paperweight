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
    """Every placeholder in value as a (position, type) tuple, so a
    positional form (`%1$@`) and an equivalent ordinal form (`%@` as the
    first unindexed placeholder) compare equal. `position` is the explicit
    `%N$` index for an indexed placeholder, or the 1-based ordinal among
    unindexed placeholders otherwise; `type` is the specifier without the
    position (`@`, `lld`, ...)."""
    result = []
    ordinal = 0
    for m in PLACEHOLDER.finditer(value):
        index, kind = m.groups()
        if index:
            position = int(index.rstrip("$"))
        else:
            ordinal += 1
            position = ordinal
        result.append((position, kind))
    return sorted(result)


def problems(catalog, languages):
    out = []
    source = catalog.get("sourceLanguage", "en")
    for key, entry in catalog.get("strings", {}).items():
        if entry.get("extractionState") == "stale":
            out.append(f"stale: {key!r}")
        locs = entry.get("localizations", {})
        source_units = list(_units(locs.get(source, {}))) or [("", key, "translated")]
        # Placeholders keyed by form ("" for a flat unit, "plural.one", etc.):
        # a plural's "one" form legitimately carries no %lld while "other"
        # does, so each translation unit is compared against its own form,
        # not the first source unit found.
        source_ph = {form: _placeholders(value) for form, value, _ in source_units}
        key_ph = _placeholders(key)
        for lang in languages:
            if lang not in locs:
                out.append(f"missing {lang}: {key!r}")
        for lang, loc in locs.items():
            if lang == source:
                continue
            for form, value, _ in _units(loc):
                if "!" in value:
                    out.append(f"exclamation mark in {lang}: {key!r}")
                # A form absent from the source (e.g. a language with its own
                # "few"/"many" plural category) falls back to the source's
                # "other" form, then the flat unit, then the key itself.
                expected = source_ph.get(
                    form, source_ph.get("plural.other", source_ph.get("", key_ph))
                )
                if _placeholders(value) != expected:
                    out.append(f"placeholders differ in {lang}: {key!r}")
    return sorted(set(out))


def warnings(catalog, languages):
    out = []
    source = catalog.get("sourceLanguage", "en")
    for key, entry in catalog.get("strings", {}).items():
        m = BUDGET.search(entry.get("comment", "") or "")
        if not m:
            continue
        budget = int(m.group(1))
        for lang, loc in entry.get("localizations", {}).items():
            if lang == source:
                continue
            for _, value, _ in _units(loc):
                if len(value) > budget:
                    out.append(f"over {budget} characters in {lang}: {key!r}")
    return sorted(set(out))


def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--catalog", default="Shared/Resources/Localizable.xcstrings")
    p.add_argument("--languages", default="", help="space-separated codes that must be fully translated")
    a = p.parse_args(argv)
    with open(a.catalog, encoding="utf-8") as f:
        catalog = json.load(f)
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
