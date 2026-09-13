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
