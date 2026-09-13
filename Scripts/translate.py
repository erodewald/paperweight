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


API = "https://api.anthropic.com/v1/messages"
DEFAULT_MODEL = "claude-sonnet-5"


def anthropic_send(model, key, max_tokens=8192, attempts=4):
    """A send(system, user) -> text callable over the Messages API, retrying
    on rate limits and server errors with a growing pause."""
    def send(system, user):
        # Claude 5 models reject `temperature`; determinism comes from the rules
        # and the JSON-only reply format.
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
