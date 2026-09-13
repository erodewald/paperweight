import json, os, sys, tempfile, unittest
sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
import strings_check  # noqa: E402


def unit(value, state="translated"):
    return {"stringUnit": {"state": state, "value": value}}


def catalog(strings):
    return {"sourceLanguage": "en", "version": "1.0", "strings": strings}


class Findings(unittest.TestCase):
    def check(self, strings, languages=()):
        return strings_check.problems(catalog(strings), list(languages))

    def test_clean_catalog_has_no_problems(self):
        self.assertEqual(self.check({"Open all day": {"localizations": {"en": unit("Open all day")}}}), [])

    def test_stale_key_is_a_problem(self):
        p = self.check({"Old": {"extractionState": "stale", "localizations": {"en": unit("Old")}}})
        self.assertIn("stale: 'Old'", p)

    def test_placeholder_mismatch_is_a_problem(self):
        p = self.check({"%lld apps": {"localizations": {
            "en": unit("%lld apps"), "nl": unit("apps")}}}, ["nl"])
        self.assertIn("placeholders differ in nl: '%lld apps'", p)

    def test_exclamation_mark_is_a_problem(self):
        p = self.check({"Copied": {"localizations": {"en": unit("Copied"), "es": unit("¡Copiado!")}}}, ["es"])
        self.assertIn("exclamation mark in es: 'Copied'", p)

    def test_missing_language_is_a_problem(self):
        p = self.check({"Open": {"localizations": {"en": unit("Open")}}}, ["ja"])
        self.assertIn("missing ja: 'Open'", p)

    def test_needs_review_counts_as_present(self):
        p = self.check({"Open": {"localizations": {"en": unit("Open"), "ja": unit("開放", "needs_review")}}}, ["ja"])
        self.assertEqual(p, [])

    def test_plural_variations_are_checked_per_form(self):
        p = self.check({"%lld days": {"localizations": {
            "en": {"variations": {"plural": {"one": unit("%lld day"), "other": unit("%lld days")}}},
            "nl": {"variations": {"plural": {"one": unit("dag"), "other": unit("%lld dagen")}}}}}}, ["nl"])
        self.assertIn("placeholders differ in nl: '%lld days'", p)

    def test_plural_forms_are_compared_form_for_form(self):
        # "one" legitimately has no placeholder while "other" does; matching
        # forms (nl mirrors en's one/other) must not be flagged.
        matching = {"%lld items": {"localizations": {
            "en": {"variations": {"plural": {"one": unit("1 item"), "other": unit("%lld items")}}},
            "nl": {"variations": {"plural": {"one": unit("1 item"), "other": unit("%lld items")}}}}}}
        self.assertEqual(self.check(matching, ["nl"]), [])

        # nl's "many" form has no counterpart in the English source, so it
        # falls back to comparing against source "other" rather than failing.
        extra_form = {"%lld items": {"localizations": {
            "en": {"variations": {"plural": {"one": unit("1 item"), "other": unit("%lld items")}}},
            "nl": {"variations": {"plural": {
                "one": unit("1 item"), "other": unit("%lld items"), "many": unit("%lld items")}}}}}}
        self.assertEqual(self.check(extra_form, ["nl"]), [])

    def test_budget_comment_warns_but_does_not_fail(self):
        strings = {"until %@": {"comment": "Lock Screen; keep under 24 characters",
                                "localizations": {"en": unit("until %@"),
                                                  "nl": unit("tot en met het moment dat %@")}}}
        self.assertEqual(self.check(strings, ["nl"]), [])
        self.assertIn("over 24 characters in nl: 'until %@'", strings_check.warnings(catalog(strings), ["nl"]))


class Cli(unittest.TestCase):
    def test_exit_code_reflects_problems(self):
        with tempfile.TemporaryDirectory() as d:
            path = os.path.join(d, "c.xcstrings")
            with open(path, "w") as f:
                json.dump(catalog({"Old": {"extractionState": "stale", "localizations": {"en": unit("Old")}}}), f)
            self.assertEqual(strings_check.main(["--catalog", path]), 1)
            with open(path, "w") as f:
                json.dump(catalog({"Ok": {"localizations": {"en": unit("Ok")}}}), f)
            self.assertEqual(strings_check.main(["--catalog", path]), 0)


if __name__ == "__main__":
    unittest.main()
