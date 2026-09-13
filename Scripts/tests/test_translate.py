import io
import json
import os
import sys
import unittest
import urllib.error
from unittest import mock

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

    def test_partial_plural_requests_only_the_missing_form(self):
        data = cat({"%lld days": {"localizations": {
            "en": {"variations": {"plural": {"one": unit("%lld day"), "other": unit("%lld days")}}},
            "nl": {"variations": {"plural": {"other": unit("%lld dagen")}}}}}})
        got = translate.collect(data, "nl")
        self.assertEqual([(u["key"], u["form"]) for u in got], [("%lld days", "plural.one")])


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
        self.assertEqual(json.loads(user[user.index("["):])[0]["id"], "1")


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

    def test_batch_failure_splits_and_recovers(self):
        data = cat({str(i): {} for i in range(5)})
        calls = []

        def send(system, user):
            payload = json.loads(user[user.index("["):])
            calls.append(len(payload))
            if len(payload) > 2:
                raise ValueError("too big")
            return json.dumps({p["id"]: f"t{p['id']}" for p in payload})

        applied, rejected = translate.run(data, "nl", send, "RULES", log=lambda *_: None)
        self.assertEqual((applied, rejected), (5, []))
        self.assertEqual(calls, [5, 2, 3, 1, 2])


class Transport(unittest.TestCase):
    def test_transport_error_is_not_split(self):
        data = cat({"Open": {}, "Ready": {}})
        calls = []

        def send(system, user):
            calls.append(user)
            raise translate.TransportError("bad key")

        with self.assertRaises(translate.TransportError):
            translate.run(data, "nl", send, "RULES", log=lambda *_: None)
        self.assertEqual(len(calls), 1)

    def test_truncated_reply_is_split(self):
        data = cat({str(i): {} for i in range(3)})

        def send(system, user):
            payload = json.loads(user[user.index("["):])
            if len(payload) > 1:
                raise translate.TruncatedReply("cut off")
            return json.dumps({p["id"]: f"t{p['id']}" for p in payload})

        applied, rejected = translate.run(data, "nl", send, "RULES", log=lambda *_: None)
        self.assertEqual((applied, rejected), (3, []))

    def test_network_errors_are_retried(self):
        class FakeResponse:
            def __enter__(self):
                return self

            def __exit__(self, *exc):
                return False

            def read(self):
                return json.dumps({"content": [{"type": "text", "text": "{}"}], "stop_reason": "end_turn"}).encode("utf-8")

        with mock.patch("translate.urllib.request.urlopen", side_effect=[urllib.error.URLError("dns"), FakeResponse()]) as m, \
                mock.patch("translate.time.sleep"):
            result = translate.anthropic_send("m", "k")("system", "user")
        self.assertEqual(result, "{}")
        self.assertEqual(m.call_count, 2)

    def test_non_retryable_http_error_raises_transport_error(self):
        err = urllib.error.HTTPError(translate.API, 401, "unauthorized", {}, io.BytesIO(b"{}"))
        with mock.patch("translate.urllib.request.urlopen", side_effect=err) as m:
            with self.assertRaises(translate.TransportError):
                translate.anthropic_send("m", "k")("system", "user")
        self.assertEqual(m.call_count, 1)


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
                def send(system, user):
                    payload = json.loads(user[user.index("["):])
                    want = {"Open": "Open!", "Ready": "Klaar"}
                    return json.dumps({p["id"]: want[p["source"]] for p in payload})
                return send

            rc = translate.main(["--catalog", cat_path, "--status", st, "--languages-file", langs, "--language", "nl"],
                                send_factory=factory, env={"CLAUDE_PLATFORM_API_KEY": "k"}, log=lambda *_: None)
            self.assertEqual(rc, 1)
            with open(cat_path) as f:
                strings = json.load(f)["strings"]
            self.assertNotIn("nl", strings["Open"].get("localizations", {}))
            self.assertEqual(strings["Ready"]["localizations"]["nl"]["stringUnit"]["value"], "Klaar")

    def test_transport_failure_exits_3_and_still_writes_status_and_summary(self):
        import tempfile
        with tempfile.TemporaryDirectory() as d:
            cat_path, st, langs = self._files(d)
            summary_path = os.path.join(d, "summary.json")

            def factory(model, key):
                def send(system, user):
                    raise translate.TransportError("bad key")
                return send

            rc = translate.main(["--catalog", cat_path, "--status", st, "--languages-file", langs,
                                 "--summary", summary_path],
                                send_factory=factory, env={"CLAUDE_PLATFORM_API_KEY": "k"}, log=lambda *_: None)
            self.assertEqual(rc, 3)
            self.assertTrue(os.path.exists(st))
            self.assertTrue(os.path.exists(summary_path))

    def test_transport_failure_survives_a_save_error_in_finally(self):
        # A TransportError has already been handled (rc == 3) by the time
        # finally's own save runs; a failure there must not re-raise and
        # turn the exit code back into an uncaught-exception 1.
        import tempfile
        with tempfile.TemporaryDirectory() as d:
            cat_path, st, langs = self._files(d)
            summary_path = os.path.join(d, "summary.json")

            def factory(model, key):
                def send(system, user):
                    raise translate.TransportError("bad key")
                return send

            with mock.patch("translate.catalog.save", side_effect=RuntimeError("disk full")):
                rc = translate.main(["--catalog", cat_path, "--status", st, "--languages-file", langs,
                                     "--summary", summary_path],
                                    send_factory=factory, env={"CLAUDE_PLATFORM_API_KEY": "k"}, log=lambda *_: None)
            self.assertEqual(rc, 3)
            self.assertTrue(os.path.exists(summary_path))

    def test_write_status_needs_no_key(self):
        import tempfile
        with tempfile.TemporaryDirectory() as d:
            cat_path, st, langs = self._files(d)
            with open(cat_path, "rb") as f:
                before = f.read()
            rc = translate.main(["--catalog", cat_path, "--status", st, "--languages-file", langs, "--write-status"],
                                env={}, log=lambda *_: None)
            self.assertEqual(rc, 0)
            with open(st) as f:
                self.assertEqual(json.load(f), {"languages": {
                    "nl": {"keys": 0, "needsReview": 0}, "ja": {"keys": 0, "needsReview": 0}}})
            with open(cat_path, "rb") as f:
                self.assertEqual(f.read(), before)


if __name__ == "__main__":
    unittest.main()
