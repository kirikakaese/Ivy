#!/usr/bin/env python3
#
# Copyright 2026 kiri
# SPDX-License-Identifier: AGPL-3.0-only
#

import os
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import ci_mtimes  # noqa: E402

OLD = 1_600_000_000_000_000_000


def write(root, path, text):
    full = os.path.join(root, path)
    os.makedirs(os.path.dirname(full), exist_ok=True)
    with open(full, "w") as file:
        file.write(text)


def mtime(root, path):
    return os.stat(os.path.join(root, path)).st_mtime_ns


class MtimeTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = self.temp.name
        git = ["git", "-C", self.root, "-c", "user.name=t", "-c", "user.email=t@t"]
        subprocess.run(git[:3] + ["init", "-q"], check=True)
        write(self.root, "Signal/A.swift", "a")
        write(self.root, "Signal/B.swift", "b")
        subprocess.run(git + ["add", "."], check=True)
        subprocess.run(git + ["commit", "-q", "-m", "x"], check=True)
        write(self.root, "Pods/Lib/C.m", "c")
        write(self.root, "Pods/Lib/D.m", "d")
        for path in ("Signal/A.swift", "Signal/B.swift", "Pods/Lib/C.m", "Pods/Lib/D.m"):
            os.utime(os.path.join(self.root, path), ns=(OLD, OLD))
        self.manifest = os.path.join(self.root, "dd", "manifest.json")
        ci_mtimes.save(self.root, self.manifest)

    def tearDown(self):
        self.temp.cleanup()

    def test_unchanged_files_get_their_times_back(self):
        # A new checkout and pod install touch every file.
        for path in ("Signal/A.swift", "Signal/B.swift", "Pods/Lib/C.m", "Pods/Lib/D.m"):
            os.utime(os.path.join(self.root, path))
        write(self.root, "Pods/Lib/D.m", "d2")
        ci_mtimes.restore(self.root, self.manifest)
        self.assertEqual(mtime(self.root, "Signal/A.swift"), OLD)
        self.assertEqual(mtime(self.root, "Pods/Lib/C.m"), OLD)
        self.assertGreater(mtime(self.root, "Pods/Lib/D.m"), OLD)

    def test_modified_tracked_file_keeps_new_time(self):
        write(self.root, "Signal/B.swift", "changed")
        ci_mtimes.restore(self.root, self.manifest)
        self.assertGreater(mtime(self.root, "Signal/B.swift"), OLD)

    def test_missing_manifest_changes_nothing(self):
        os.utime(os.path.join(self.root, "Signal/A.swift"))
        before = mtime(self.root, "Signal/A.swift")
        ci_mtimes.restore(self.root, os.path.join(self.root, "none.json"))
        self.assertEqual(mtime(self.root, "Signal/A.swift"), before)


if __name__ == "__main__":
    unittest.main()
