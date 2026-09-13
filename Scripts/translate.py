#!/usr/bin/env python3
"""Machine-translate the String Catalog into the languages in Scripts/languages.txt.

Translations are written with state needs_review; only a person marks them
translated. Placeholder parity and the no-exclamation rule are enforced before
anything is written. Standard library only.

main() exit codes: 0 clean run, 1 some units were rejected (validated but not
written; everything else still applied), 2 no CLAUDE_PLATFORM_API_KEY (nothing
translated; --verify also needs the key and returns 2 without it), 3 a
TransportError aborted the run partway through (whatever had already been
applied is still saved). --write-status is the exception: it never touches
the network, needs no key, and always returns 0.
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
        if entry.get("extractionState") == "stale":
            continue
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
    # Payload ids are the unit's position within this batch (short, so the
    # reply and its tokens stay small), not the long "key|form" unit id;
    # run() maps them back to real unit ids once the reply is parsed.
    name = LANGUAGE_NAMES.get(lang, lang)
    system = rules.rstrip() + "\n\nRegister for this language\n- " + REGISTER.get(lang, "Use the register a careful native app would use.") + "\n"
    payload = [{"id": str(i + 1), "source": u["source"], "form": u["form"], "comment": u["comment"], "budget": u["budget"]}
               for i, u in enumerate(units)]
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


def _label(u):
    return u["key"] if u["form"] == "" else f"{u['key']} [{u['form']}]"


def apply(data, lang, units, mapping):
    """Write validated translations; return (applied, rejected descriptions)."""
    applied, rejected = 0, []
    for u in units:
        label = _label(u)
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


def _send_batch(data, lang, units, send, rules, log):
    """Send one batch; on an unparseable or truncated reply, split it in half
    and retry each half (recursively), so one bad sub-batch doesn't cost the
    rest. A single unit that still fails is rejected, not raised. A
    TransportError (bad key, wrong model, exhausted retries) is not caught
    here: it is not the batch's fault, so it propagates and fails the run."""
    system, user = build_messages(units, lang, rules)
    try:
        reply = parse_reply(send(system, user))
    except (json.JSONDecodeError, ValueError, TruncatedReply) as e:
        if len(units) == 1:
            return 0, [f"{_label(units[0])}: reply unusable ({type(e).__name__})"]
        mid = len(units) // 2
        log(f"{lang}: batch of {len(units)} failed ({type(e).__name__}); splitting into {mid} and {len(units) - mid}")
        a1, r1 = _send_batch(data, lang, units[:mid], send, rules, log)
        a2, r2 = _send_batch(data, lang, units[mid:], send, rules, log)
        return a1 + a2, r1 + r2
    mapping = {}
    for short, value in reply.items():
        try:
            idx = int(short) - 1
        except ValueError:
            continue
        if 0 <= idx < len(units):
            mapping[units[idx]["id"]] = value
    return apply(data, lang, units, mapping)


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
        a, r = _send_batch(data, lang, b, send, rules, log)
        applied += a
        rejected += r
        log(f"{lang}: batch {i}: {a} applied, {len(r)} rejected")
    return applied, rejected


API = "https://api.anthropic.com/v1/messages"
DEFAULT_MODEL = "claude-sonnet-5"


class TransportError(RuntimeError):
    """A non-retryable failure: a bad key, an unknown model, a client error,
    or retries exhausted. Never worth splitting a batch and retrying half of
    it — the whole run should fail loudly and cheaply instead."""


class TruncatedReply(RuntimeError):
    """The model's reply was cut off at max_tokens. Worth splitting the batch
    (a smaller batch needs fewer output tokens) and retrying."""


def anthropic_send(model, key, max_tokens=16384, attempts=4):
    """A send(system, user) -> text callable over the Messages API, retrying
    on rate limits, server errors and network failures with a growing pause."""
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
                    resp_text = resp.read().decode("utf-8")
                try:
                    reply = json.loads(resp_text)
                except json.JSONDecodeError as e:
                    raise TransportError(f"Claude API: response was not JSON: {e}") from None
                if reply.get("stop_reason") == "max_tokens":
                    raise TruncatedReply("reply truncated at max_tokens")
                return "".join(block.get("text", "") for block in reply.get("content", []) if block.get("type") == "text")
            except urllib.error.HTTPError as e:
                if e.code in (429, 500, 502, 503, 529) and attempt < attempts:
                    time.sleep(5 * attempt)
                    continue
                raise TransportError(f"Claude API HTTP {e.code}: {e.read().decode('utf-8', 'replace')[:300]}") from None
            except (urllib.error.URLError, OSError) as e:
                if attempt < attempts:
                    time.sleep(5 * attempt)
                    continue
                raise TransportError(f"Claude API network error: {e}") from None
        raise TransportError("Claude API: retries exhausted")
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
        try:
            reply = parse_reply_objects(send(system, json.dumps(b, ensure_ascii=False, indent=1)))
        except (TruncatedReply, ValueError) as e:
            log(f"::warning::{lang}: verify batch of {len(b)} failed ({type(e).__name__}); skipping")
            continue
        for r in b:
            j = reply.get(r["id"], {})
            if not isinstance(j, dict):
                j = {}
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
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(line_buffering=True)
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
    p.add_argument("--write-status", action="store_true",
                   help="write --status from the catalog as it stands and exit; no key needed")
    a = p.parse_args(argv)

    data = catalog.load(a.catalog)
    languages = a.language or read_languages(a.languages_file)

    if a.write_status:
        all_languages = read_languages(a.languages_file)
        with open(a.status, "w", encoding="utf-8") as f:
            f.write(catalog.dumps_status(catalog.status(data, all_languages)))
        return 0

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
    all_languages = read_languages(a.languages_file)

    def save_progress():
        # Written after every language (not only at the end) so a crash
        # partway through a run keeps the languages already finished.
        catalog.save(a.catalog, data)
        with open(a.status, "w", encoding="utf-8") as f:
            f.write(catalog.dumps_status(catalog.status(data, all_languages)))

    summary, failed, rc = {}, False, None
    try:
        for lang in languages:
            applied, rejected = run(data, lang, send, rules, size=a.batch_size, retranslate=set(a.retranslate), log=log)
            summary[lang] = {"applied": applied, "rejected": rejected}
            for r in rejected:
                log(f"::warning::{lang}: rejected {r}")
            failed = failed or bool(rejected)
            save_progress()
    except TransportError as e:
        # Not the batch's fault (see _send_batch): a bad key, wrong model, or
        # exhausted retries. Abort the run loudly with exit code 3, but keep
        # whatever earlier languages already applied via the finally below.
        log(f"::error::{e}")
        rc = 3
    finally:
        # Runs on a normal finish too (harmless: save_progress() is
        # idempotent) and, after a TransportError, saves whatever the
        # in-flight language had already applied. By the time we're here a
        # TransportError has already been caught above (rc == 3) and is no
        # longer "in flight" as far as sys.exc_info() is concerned, so that
        # alone can't distinguish "we just handled a transport failure"
        # from "nothing went wrong" -- rc does. Only re-raise a save
        # failure when rc is still None (a plain run, or some exception
        # this function doesn't catch) *and* nothing is currently
        # propagating: that reproduces the old, unguarded behaviour for a
        # normal run, while never letting a save failure here downgrade an
        # already-handled TransportError (rc == 3, which must survive as
        # exit code 3) or mask an exception still on its way out.
        try:
            save_progress()
        except Exception as save_exc:
            log(f"::error::{save_exc}")
            if rc is None and sys.exc_info()[0] is None:
                raise
    if a.summary:
        # Written even on a transport failure, with whatever was applied
        # before the error.
        with open(a.summary, "w", encoding="utf-8") as f:
            json.dump(summary, f, indent=2)
    if rc is not None:
        return rc
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
