#!/usr/bin/env python3
#
# Copyright 2026 kiri
# SPDX-License-Identifier: AGPL-3.0-only
#

import os
import plistlib
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import app_name  # noqa: E402

RULES = {
    "aliases": {"ar": ["سيجنال"]},
    "Localizable.strings": {
        "APP": {"replace": [True]},
        "MIXED": {"replace": [True, False]},
        "KEEP": {"replace": [False]},
    },
    "InfoPlist.strings": {
        "NSCameraUsageDescription": {"replace": [True]},
    },
    "PluralAware.stringsdict": {
        "RING": {"replace_all": True},
    },
}


class ReplaceTests(unittest.TestCase):
    def transform(self, table, locale="en", name="Localizable.strings"):
        return app_name.transform_table(name, table, locale, RULES)

    def test_replaces_app_occurrences_only(self):
        table, applied, unmatched = self.transform(
            {
                "APP": "Signal needs access.",
                "MIXED": "Signal is using space. Signal Backups help.",
                "KEEP": "Signal will never message you.",
                "OTHER": "Signal",
            }
        )
        self.assertEqual(table["APP"], "Ivy needs access.")
        self.assertEqual(table["MIXED"], "Ivy is using space. Signal Backups help.")
        self.assertEqual(table["KEEP"], "Signal will never message you.")
        self.assertEqual(table["OTHER"], "Signal")
        self.assertEqual(applied, 2)
        self.assertEqual(unmatched, [])

    def test_inflected_forms_follow_the_decision(self):
        table, _, _ = self.transform({"APP": "Signals Zugriff wird benötigt."}, "de")
        self.assertEqual(table["APP"], "Ivys Zugriff wird benötigt.")

    def test_aliases_are_matched(self):
        table, _, _ = self.transform({"APP": "يحتاج سيجنال إلى الوصول."}, "ar")
        self.assertEqual(table["APP"], "يحتاج Ivy إلى الوصول.")

    def test_mismatched_mixed_string_is_left_unchanged(self):
        table, applied, unmatched = self.transform({"MIXED": "Signal only once."})
        self.assertEqual(table["MIXED"], "Signal only once.")
        self.assertEqual(applied, 0)
        self.assertEqual(unmatched, ["MIXED"])

    def test_all_app_string_with_extra_occurrence_is_replaced(self):
        table, _, _ = self.transform({"APP": "Signal, Signal needs access."})
        self.assertEqual(table["APP"], "Ivy, Ivy needs access.")

    def test_transform_is_idempotent(self):
        once, _, _ = self.transform({"MIXED": "Signal is using space. Signal Backups help."})
        twice, _, _ = self.transform(once)
        self.assertEqual(once, twice)

    def test_stringsdict_replace_all(self):
        value = {"NSStringLocalizedFormatKey": "%#@n@", "n": {"one": "Signal will ring %d", "other": "Signal will ring %d"}}
        table, _, _ = self.transform({"RING": value}, name="PluralAware.stringsdict")
        self.assertEqual(table["RING"]["n"]["other"], "Ivy will ring %d")


class ParsingTests(unittest.TestCase):
    def test_parses_quoted_and_unquoted_keys(self):
        text = '/* comment */\n"A" = "x \\"q\\" \\n";\nNSKey = "y";\n'
        self.assertEqual(app_name.parse_strings_text(text), {"A": 'x "q" \n', "NSKey": "y"})


class ApplyTests(unittest.TestCase):
    def test_apply_rewrites_compiled_bundle(self):
        with tempfile.TemporaryDirectory() as tmp:
            lproj = os.path.join(tmp, "de.lproj")
            os.mkdir(lproj)
            with open(os.path.join(lproj, "Localizable.strings"), "w", encoding="utf-16") as f:
                f.write('"APP" = "Signal braucht Zugriff.";\n"KEEP" = "Signal schreibt dir nie.";\n')
            with open(os.path.join(lproj, "InfoPlist.strings"), "wb") as f:
                plistlib.dump({"NSCameraUsageDescription": "Signal verwendet die Kamera."}, f, fmt=plistlib.FMT_BINARY)
            rules_path = os.path.join(tmp, "rules.json")
            with open(rules_path, "w", encoding="utf-8") as f:
                import json

                json.dump(RULES, f)
            app_name.cmd_apply(rules_path, tmp)
            with open(os.path.join(lproj, "Localizable.strings"), "rb") as f:
                strings = plistlib.load(f)
            with open(os.path.join(lproj, "InfoPlist.strings"), "rb") as f:
                info = plistlib.load(f)
        self.assertEqual(strings, {"APP": "Ivy braucht Zugriff.", "KEEP": "Signal schreibt dir nie."})
        self.assertEqual(info, {"NSCameraUsageDescription": "Ivy verwendet die Kamera."})

    def test_apply_reads_utf16_stringsdict_from_mac_builds(self):
        # macOS builds write XML property lists as UTF-16 but keep the UTF-8
        # declaration.
        value = {"NSStringLocalizedFormatKey": "%#@n@", "n": {"one": "Signal will ring", "other": "Signal will ring"}}
        xml = plistlib.dumps({"RING": value}, fmt=plistlib.FMT_XML).decode("utf-8")
        with tempfile.TemporaryDirectory() as tmp:
            lproj = os.path.join(tmp, "en.lproj")
            os.mkdir(lproj)
            path = os.path.join(lproj, "PluralAware.stringsdict")
            with open(path, "w", encoding="utf-16") as f:
                f.write(xml)
            rules_path = os.path.join(tmp, "rules.json")
            with open(rules_path, "w", encoding="utf-8") as f:
                import json

                json.dump(RULES, f)
            app_name.cmd_apply(rules_path, tmp)
            with open(path, "rb") as f:
                table = plistlib.load(f)
        self.assertEqual(table["RING"]["n"]["other"], "Ivy will ring")


if __name__ == "__main__":
    unittest.main()
