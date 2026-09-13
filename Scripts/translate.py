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
