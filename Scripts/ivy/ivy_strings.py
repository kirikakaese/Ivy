#!/usr/bin/env python3
#
# Copyright 2026 kiri
# SPDX-License-Identifier: AGPL-3.0-only
#
"""Checks Ivy's own string table (Ivy/Translations/<locale>.lproj/Ivy.strings).

    ivy_strings.py check [repository root]

Fails when
  - code uses a key with IvyLocalizedString that has no English string,
  - an English string is not used anywhere,
  - a translation has a key that English does not have,
  - a translation does not use the same format placeholders as English.
"""
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import app_name  # noqa: E402

TRANSLATIONS = os.path.join("Ivy", "Translations")
TABLE = "Ivy.strings"
SOURCE_DIRS = ("Signal", "SignalUI", "SignalServiceKit", "SignalNSE", "SignalShareExtension", "IvyWidgets")
SKIPPED_DIRS = {"tests", "test", "translations"}

_USE = re.compile(r'IvyLocalizedString\(\s*"((?:[^"\\]|\\.)*)"')
_PLACEHOLDER = re.compile(r"%(?:(\d+)\$)?[-+ #0]*\d*(?:\.\d+)?(?:hh|h|ll|l|q|z|t|j)?([@dDiuUxXoOfeEgGcCsSpaA%])")


def placeholders(value):
    """The format placeholders of a string, by position, ignoring %%."""
    result = []
    position = 0
    for index, conversion in _PLACEHOLDER.findall(value):
        if conversion == "%":
            continue
        position += 1
        number = int(index) if index else position
        conversion = {"i": "d", "D": "d", "U": "u"}.get(conversion, conversion)
        result.append((number, conversion))
    return sorted(result)


def load_tables(root):
    directory = os.path.join(root, TRANSLATIONS)
    tables = {}
    for entry in sorted(os.listdir(directory)):
        if not entry.endswith(".lproj"):
            continue
        path = os.path.join(directory, entry, TABLE)
        if os.path.exists(path):
            tables[entry[: -len(".lproj")]] = app_name.load_table(path)
    return tables


def used_keys(root):
    keys = {}
    for source_dir in SOURCE_DIRS:
        for dirpath, dirnames, filenames in os.walk(os.path.join(root, source_dir)):
            dirnames[:] = [d for d in dirnames if d not in SKIPPED_DIRS]
            for filename in filenames:
                if not filename.endswith(".swift"):
                    continue
                path = os.path.join(dirpath, filename)
                with open(path, encoding="utf-8") as f:
                    for key in _USE.findall(f.read()):
                        keys.setdefault(key, os.path.relpath(path, root))
    return keys


def problems(tables, keys):
    result = []
    english = tables.get("en")
    if english is None:
        return ["en.lproj/Ivy.strings is missing"]
    for key, path in sorted(keys.items()):
        if key not in english:
            result.append(f"{path}: {key} has no English string")
    for key in sorted(set(english) - set(keys)):
        result.append(f"en: {key} is not used")
    for locale, table in sorted(tables.items()):
        if locale == "en":
            continue
        for key, value in sorted(table.items()):
            if key not in english:
                result.append(f"{locale}: {key} does not exist in English")
            elif placeholders(value) != placeholders(english[key]):
                result.append(f"{locale}: {key} uses different placeholders than English")
    return result


def cmd_check(root):
    found = problems(load_tables(root), used_keys(root))
    for problem in found:
        print(problem)
    if found:
        return 1
    print("Ivy strings OK")
    return 0


def main(argv):
    if len(argv) not in (2, 3) or argv[1] != "check":
        print(__doc__)
        return 2
    return cmd_check(argv[2] if len(argv) == 3 else ".")


if __name__ == "__main__":
    sys.exit(main(sys.argv))
