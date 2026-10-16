#!/usr/bin/env python3
#
# Copyright 2026 kiri
# SPDX-License-Identifier: AGPL-3.0-only
#

import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import catalyst_dependencies  # noqa: E402


class VersionTests(unittest.TestCase):
    def test_reads_the_repository_podfile(self):
        with open(os.path.join(catalyst_dependencies.ROOT, "Podfile"), encoding="utf-8") as f:
            versions = catalyst_dependencies.podfile_versions(f.read())
        self.assertRegex(versions["libsignal"], r"^\d+\.\d+\.\d+$")
        self.assertRegex(versions["libsignal_checksum"], r"^[0-9a-f]{64}$")
        self.assertRegex(versions["ringrtc"], r"^\d+\.\d+\.\d+$")
        self.assertRegex(versions["mobilecoin"], r"^\d+\.\d+\.\d+$")


class PinTests(unittest.TestCase):
    VERSIONS = {"libsignal": "1.0.0", "ringrtc": "2.0.0", "mobilecoin": "3.0.0"}

    def test_only_matching_versions_are_used(self):
        pins = {
            "libsignal": {"version": "1.0.0"},
            "ringrtc": {"version": "1.9.0"},
        }
        usable = catalyst_dependencies.usable_pins(pins, self.VERSIONS)
        self.assertEqual(set(usable), {"libsignal"})

    def test_repository_pins_are_complete(self):
        for name, pin in catalyst_dependencies.load_pins().items():
            self.assertEqual(set(pin), {"version", "repository", "tag", "asset", "sha256"}, name)
            self.assertRegex(pin["sha256"], r"^[0-9a-f]{64}$")


if __name__ == "__main__":
    unittest.main()
