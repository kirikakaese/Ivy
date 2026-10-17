#!/usr/bin/env python3
#
# Copyright 2026 kiri
# SPDX-License-Identifier: AGPL-3.0-only
#

import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import ivy_strings  # noqa: E402


class PlaceholderTests(unittest.TestCase):
    def test_positional_and_plain(self):
        self.assertEqual(ivy_strings.placeholders("%@ has %d"), [(1, "@"), (2, "d")])
        self.assertEqual(ivy_strings.placeholders("%2$d von %1$@"), [(1, "@"), (2, "d")])

    def test_percent_sign_is_ignored(self):
        self.assertEqual(ivy_strings.placeholders("100%% of %@"), [(1, "@")])

    def test_integer_spellings_match(self):
        self.assertEqual(ivy_strings.placeholders("%i"), ivy_strings.placeholders("%d"))
        self.assertEqual(ivy_strings.placeholders("%lu"), ivy_strings.placeholders("%u"))


class ProblemTests(unittest.TestCase):
    def test_clean(self):
        tables = {"en": {"A": "Hello %@"}, "de": {"A": "Hallo %@"}}
        self.assertEqual(ivy_strings.problems(tables, {"A": "x.swift"}), [])

    def test_missing_english(self):
        found = ivy_strings.problems({"en": {}}, {"A": "x.swift"})
        self.assertEqual(found, ["x.swift: A has no English string"])

    def test_unused_english(self):
        found = ivy_strings.problems({"en": {"A": "a"}}, {})
        self.assertEqual(found, ["en: A is not used"])

    def test_translation_only_key(self):
        found = ivy_strings.problems({"en": {"A": "a"}, "de": {"B": "b"}}, {"A": "x.swift"})
        self.assertEqual(found, ["de: B does not exist in English"])

    def test_placeholder_mismatch(self):
        found = ivy_strings.problems({"en": {"A": "%@ and %d"}, "de": {"A": "%@"}}, {"A": "x.swift"})
        self.assertEqual(found, ["de: A uses different placeholders than English"])


class RepositoryTests(unittest.TestCase):
    def test_reads_files(self):
        with tempfile.TemporaryDirectory() as root:
            for locale, text in (("en", '"GREETING" = "Hello";\n'), ("de", '"GREETING" = "Hallo";\n')):
                directory = os.path.join(root, "Ivy", "Translations", f"{locale}.lproj")
                os.makedirs(directory)
                with open(os.path.join(directory, "Ivy.strings"), "w", encoding="utf-8") as f:
                    f.write(text)
            source = os.path.join(root, "Signal")
            os.makedirs(source)
            with open(os.path.join(source, "View.swift"), "w", encoding="utf-8") as f:
                f.write('let title = IvyLocalizedString("GREETING", comment: "Greeting")\n')
            self.assertEqual(ivy_strings.cmd_check(root), 0)


if __name__ == "__main__":
    unittest.main()
