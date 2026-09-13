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
