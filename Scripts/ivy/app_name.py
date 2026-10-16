#!/usr/bin/env python3
#
# Copyright 2026 kiri
# SPDX-License-Identifier: AGPL-3.0-only
#

"""Shows Ivy's name wherever upstream strings use "Signal" to mean the app.

Upstream translation files stay untouched. A reviewed rule list
(app-name-rules.json) records, for every English string that mentions
"Signal", which occurrences name the app (replaced with "Ivy") and which
name the Signal network, service or organization (kept). Each rule stores a
fingerprint of the English text it was reviewed against.

Commands:
  apply <rules> <resources-dir>   Rewrite the compiled .lproj files of a
                                  built app bundle (Xcode build phase).
  check <rules> <translations-dir>
                                  Fail if upstream English strings changed or
                                  new strings mention "Signal" without a rule.
  report <rules> <translations-dir>
                                  Print, per locale, how many rules apply.
  explain <rules> <translations-dir>
                                  Print every rule with its English text,
                                  marking replaced occurrences as [Ivy].
"""

import hashlib
import json
import os
import plistlib
import re
import sys

APP_NAME = "Ivy"
TABLES = ("Localizable.strings", "InfoPlist.strings", "PluralAware.stringsdict")


# MARK: - .strings parsing


def _unescape(s):
    out = []
    i = 0
    while i < len(s):
        c = s[i]
        if c == "\\" and i + 1 < len(s):
            n = s[i + 1]
            if n == "n":
                out.append("\n")
            elif n == "t":
                out.append("\t")
            elif n == "r":
                out.append("\r")
            elif n == "U" and re.match(r"[0-9a-fA-F]{4}", s[i + 2 : i + 6]):
                out.append(chr(int(s[i + 2 : i + 6], 16)))
                i += 6
                continue
            else:
                out.append(n)
            i += 2
            continue
        out.append(c)
        i += 1
    return "".join(out)


_STRINGS_ENTRY = re.compile(
    r'(?:"((?:[^"\\]|\\.)*)"|([A-Za-z0-9_.\-]+))\s*=\s*"((?:[^"\\]|\\.)*)"\s*;'
)


def parse_strings_text(text):
    """Parses an old-style .strings file (comments are skipped)."""
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    text = re.sub(r"(?m)^\s*//.*$", "", text)
    result = {}
    for m in _STRINGS_ENTRY.finditer(text):
        key = _unescape(m.group(1)) if m.group(1) is not None else m.group(2)
        result[key] = _unescape(m.group(3))
    return result


def _decode(data):
    if data.startswith(b"\xff\xfe") or data.startswith(b"\xfe\xff"):
        return data.decode("utf-16")
    if data.startswith(b"\xef\xbb\xbf"):
        return data[3:].decode("utf-8")
    return data.decode("utf-8")


def load_table(path):
    with open(path, "rb") as f:
        data = f.read()
    try:
        return plistlib.loads(data)
    except Exception:
        if path.endswith(".stringsdict"):
            raise
        return parse_strings_text(_decode(data))


# MARK: - Replacement


def _pattern(locale, aliases):
    names = ["Signal"] + list(aliases.get(locale, []))
    return re.compile("|".join(re.escape(n) for n in names))


def replace_occurrences(value, decisions, pattern):
    """Replaces the app-name occurrences of one string.

    Returns the new value, or None if the translation cannot be matched
    to the English decisions."""
    matches = list(pattern.finditer(value))
    if not matches:
        return value
    if len(matches) == len(decisions):
        flags = decisions
    elif all(decisions):
        flags = [True] * len(matches)
    else:
        return None
    out = []
    last = 0
    for m, flag in zip(matches, flags):
        out.append(value[last : m.start()])
        out.append(APP_NAME if flag else m.group(0))
        last = m.end()
    out.append(value[last:])
    return "".join(out)


def _replace_all_in(obj, pattern):
    if isinstance(obj, str):
        return pattern.sub(APP_NAME, obj)
    if isinstance(obj, dict):
        return {k: _replace_all_in(v, pattern) for k, v in obj.items()}
    if isinstance(obj, list):
        return [_replace_all_in(v, pattern) for v in obj]
    return obj


def transform_table(table_name, table, locale, rules):
    """Returns (new_table, applied, unmatched)."""
    pattern = _pattern(locale, rules.get("aliases", {}))
    table_rules = rules.get(table_name, {})
    result = dict(table)
    applied = 0
    unmatched = []
    for key, rule in table_rules.items():
        if key not in result:
            continue
        if table_name.endswith(".stringsdict"):
            if rule.get("replace_all"):
                result[key] = _replace_all_in(result[key], pattern)
                applied += 1
            continue
        decisions = rule["replace"]
        if not any(decisions):
            continue
        new_value = replace_occurrences(result[key], decisions, pattern)
        if new_value is None:
            unmatched.append(key)
            continue
        if new_value != result[key]:
            applied += 1
        result[key] = new_value
    return result, applied, unmatched


# MARK: - Commands


def load_rules(path):
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def cmd_apply(rules_path, resources_dir):
    rules = load_rules(rules_path)
    for entry in sorted(os.listdir(resources_dir)):
        if not entry.endswith(".lproj"):
            continue
        locale = entry[: -len(".lproj")]
        for table_name in TABLES:
            path = os.path.join(resources_dir, entry, table_name)
            if not os.path.exists(path):
                continue
            try:
                table = load_table(path)
                new_table, _, _ = transform_table(table_name, table, locale, rules)
                if new_table != table:
                    with open(path, "wb") as f:
                        plistlib.dump(new_table, f, fmt=plistlib.FMT_BINARY)
            except Exception as e:
                # Xcode shows lines in this form as build errors.
                print(f"{path}: error: cannot apply the app name rules: {type(e).__name__}: {e}", file=sys.stderr)
                raise
    return 0


def _english_tables(translations_dir):
    en = os.path.join(translations_dir, "en.lproj")
    return {name: load_table(os.path.join(en, name)) for name in TABLES}


def _english_text(table_name, value):
    if table_name.endswith(".stringsdict"):
        return json.dumps(value, ensure_ascii=False)
    return value


def fingerprint(text):
    return hashlib.sha256(text.encode("utf-8")).hexdigest()[:16]


def cmd_check(rules_path, translations_dir):
    rules = load_rules(rules_path)
    problems = []
    for table_name, table in _english_tables(translations_dir).items():
        table_rules = rules.get(table_name, {})
        for key, value in table.items():
            text = _english_text(table_name, value)
            if "Signal" not in text:
                continue
            rule = table_rules.get(key)
            if rule is None:
                problems.append(f"{table_name}: new string needs a rule: {key}: {text}")
            elif rule["fingerprint"] != fingerprint(text):
                problems.append(f"{table_name}: English text changed, review the rule: {key}: {text}")
            elif "replace" in rule and len(rule["replace"]) != text.count("Signal"):
                problems.append(f"{table_name}: rule has the wrong number of decisions: {key}")
        for key in table_rules:
            if key not in table:
                problems.append(f"{table_name}: rule for a removed string: {key}")
    for p in problems:
        print(p)
    print(f"{len(problems)} problem(s)")
    return 1 if problems else 0


def cmd_report(rules_path, translations_dir):
    rules = load_rules(rules_path)
    for entry in sorted(os.listdir(translations_dir)):
        if not entry.endswith(".lproj"):
            continue
        locale = entry[: -len(".lproj")]
        applied_total = 0
        unmatched_total = []
        for table_name in TABLES:
            path = os.path.join(translations_dir, entry, table_name)
            if not os.path.exists(path):
                continue
            _, applied, unmatched = transform_table(table_name, load_table(path), locale, rules)
            applied_total += applied
            unmatched_total += unmatched
        print(f"{locale}: {applied_total} strings renamed, {len(unmatched_total)} left unchanged")
        for key in unmatched_total:
            print(f"  unchanged: {key}")
    return 0


def cmd_explain(rules_path, translations_dir):
    rules = load_rules(rules_path)
    english = _english_tables(translations_dir)
    pattern = _pattern("en", {})
    for table_name in TABLES:
        for key, rule in sorted(rules.get(table_name, {}).items()):
            text = _english_text(table_name, english[table_name].get(key, ""))
            decisions = rule.get("replace") or [rule.get("replace_all", False)] * text.count("Signal")
            marked = iter(decisions)
            shown = pattern.sub(lambda m: "[Ivy]" if next(marked, False) else m.group(0), text)
            print(f"{table_name} {key}: {shown}")
    return 0


COMMANDS = {"apply": cmd_apply, "check": cmd_check, "report": cmd_report, "explain": cmd_explain}


def main(argv):
    if len(argv) != 4 or argv[1] not in COMMANDS:
        print(__doc__)
        return 2
    return COMMANDS[argv[1]](argv[2], argv[3])


if __name__ == "__main__":
    sys.exit(main(sys.argv))
