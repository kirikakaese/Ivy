#!/usr/bin/env python3
#
# Copyright 2026 kiri
# SPDX-License-Identifier: AGPL-3.0-only
#

import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import upstream  # noqa: E402

XCCONFIG = """// (8.32.0.1910). Update both values with every upstream merge.
IVY_UPSTREAM_MARKETING_VERSION = 8.32
IVY_UPSTREAM_BUILD_NUMBER = 1910
IVY_BUILD = 0
"""


class TagTests(unittest.TestCase):
    def test_stable_tags_parse(self):
        self.assertEqual(upstream.parse_tag("8.32.0.1910"), (8, 32, 0, 1910))
        self.assertIsNone(upstream.parse_tag("8.33.0.2000-beta"))
        self.assertIsNone(upstream.parse_tag("v8.33"))

    def test_latest_ignores_betas_and_sorts_numerically(self):
        tags = ["8.9.0.100", "8.32.0.1910", "8.33.0.1990-beta", "8.33.0.2000", "8.33.0.999"]
        self.assertEqual(upstream.latest_stable(tags), "8.33.0.2000")
        self.assertIsNone(upstream.latest_stable(["8.40.0.1-beta"]))

    def test_ls_remote_output(self):
        output = "abc\trefs/tags/8.32.0.1910\ndef\trefs/tags/8.33.0.2000-beta\n"
        self.assertEqual(upstream.tags_from_ls_remote(output), ["8.32.0.1910", "8.33.0.2000-beta"])

    def test_branch_name(self):
        self.assertEqual(upstream.branch_name("8.33.0.2000"), "merge-upstream-8-33")
        self.assertEqual(upstream.branch_name("8.33.1.2010"), "merge-upstream-8-33-1")


class VersionTests(unittest.TestCase):
    def test_current_release(self):
        self.assertEqual(upstream.current_release(XCCONFIG), "8.32.0.1910")

    def test_with_release(self):
        text = upstream.with_release(XCCONFIG, "8.33.0.2000")
        self.assertIn("IVY_UPSTREAM_MARKETING_VERSION = 8.33\n", text)
        self.assertIn("IVY_UPSTREAM_BUILD_NUMBER = 2000\n", text)
        self.assertIn("(8.33.0.2000)", text)
        self.assertIn("IVY_BUILD = 0\n", text)
        self.assertEqual(upstream.current_release(text), "8.33.0.2000")

    def test_with_patch_release(self):
        text = upstream.with_release(XCCONFIG, "8.33.1.2010")
        self.assertIn("IVY_UPSTREAM_MARKETING_VERSION = 8.33.1\n", text)
        self.assertEqual(upstream.current_release(text), "8.33.1.2010")

    def test_readme(self):
        text = "based on Signal-iOS (currently release 8.32.0.1910) and"
        self.assertEqual(
            upstream.readme_with_release(text, "8.33.0.2000"),
            "based on Signal-iOS (currently release 8.33.0.2000) and",
        )


class MarkerTests(unittest.TestCase):
    def test_counts_and_losses(self):
        before = upstream.marker_counts("Signal/A.swift:3\nSignal/B.swift:1\nSignal/C.swift:2\n")
        after = upstream.marker_counts("Signal/A.swift:3\nSignal/C.swift:1\n")
        self.assertEqual(
            upstream.lost_markers(before, after),
            [("Signal/B.swift", 1, 0), ("Signal/C.swift", 2, 1)],
        )

    def test_keeps_ours(self):
        self.assertTrue(upstream.keeps_ours(".github/workflows/ci.yml"))
        self.assertTrue(upstream.keeps_ours("Pods"))
        self.assertFalse(upstream.keeps_ours("Signal/AppDelegate.swift"))


PODFILE = """pod 'LibSignalClient', git: 'x', tag: 'v0.105.0'
ENV['LIBSIGNAL_FFI_PREBUILD_CHECKSUM'] = '%s'
pod 'SignalRingRTC', git: 'y', tag: 'v2.73.0'
  pod 'LibMobileCoin/CoreHTTP', git: 'z', tag: 'signal/6.0.2'
""" % ("a" * 64)


class AutomationTests(unittest.TestCase):
    def test_lock_gets_the_podfile_checksum(self):
        import hashlib
        lock = "PODS:\n  - A (1)\n\nPODFILE CHECKSUM: 0000\n\nCOCOAPODS: 1.15.2\n"
        updated = upstream.lock_with_podfile_checksum(lock, PODFILE)
        self.assertIn("PODFILE CHECKSUM: " + hashlib.sha1(PODFILE.encode()).hexdigest() + "\n", updated)
        self.assertIn("COCOAPODS: 1.15.2", updated)

    def test_dependency_changes(self):
        newer = PODFILE.replace("v0.105.0", "v0.106.0").replace("v2.73.0", "v2.74.1")
        self.assertEqual(
            upstream.dependency_changes(PODFILE, newer),
            {"libsignal": ("0.105.0", "0.106.0"), "ringrtc": ("2.73.0", "2.74.1")},
        )
        self.assertEqual(upstream.dependency_changes(PODFILE, PODFILE), {})


if __name__ == "__main__":
    unittest.main()
