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
