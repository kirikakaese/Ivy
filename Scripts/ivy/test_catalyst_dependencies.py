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


if __name__ == "__main__":
    unittest.main()
