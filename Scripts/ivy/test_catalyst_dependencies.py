#!/usr/bin/env python3
#
# Copyright 2026 kiri
# SPDX-License-Identifier: AGPL-3.0-only
#

import hashlib
import io
import os
import sys
import tempfile
import unittest
import urllib.error
from unittest import mock

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


class DownloadTests(unittest.TestCase):
    CONTENT = b"archive"
    PIN = {
        "version": "1.0.0",
        "repository": "example/app",
        "tag": "v1",
        "asset": "archive.tar.gz",
        "sha256": hashlib.sha256(CONTENT).hexdigest(),
    }

    def download(self, direct_status, api_status=None):
        """Downloads with a download link and an API that answer as given."""
        asked = []

        def urlopen(request, timeout=None):
            url = request.full_url
            asked.append(url)
            if url.startswith("https://github.com/"):
                status = direct_status
            elif url.endswith("/releases/tags/v1"):
                return io.BytesIO(b'{"assets": [{"name": "archive.tar.gz", "url": "https://api.github.com/asset"}]}')
            else:
                status = api_status
                self.assertEqual(request.unredirected_hdrs.get("Authorization"), "Bearer token")
                self.assertNotIn("Authorization", request.headers)
            if status:
                raise urllib.error.HTTPError(url, status, "refused", None, None)
            return io.BytesIO(self.CONTENT)

        with tempfile.TemporaryDirectory() as directory, \
                mock.patch("urllib.request.urlopen", urlopen), \
                mock.patch.dict(os.environ, {"GH_TOKEN": "token"}), \
                mock.patch("time.sleep"):
            dest = catalyst_dependencies.download(self.PIN, os.path.join(directory, "archive.tar.gz"))
            with open(dest, "rb") as f:
                self.assertEqual(f.read(), self.CONTENT)
        return asked

    def test_public_download_uses_the_link(self):
        self.assertEqual(len(self.download(direct_status=None)), 1)

    def test_private_repository_falls_back_to_the_api(self):
        # A private repository answers its download link with "not found".
        asked = self.download(direct_status=404)
        self.assertEqual(asked[-1], "https://api.github.com/asset")

    def test_refusal_by_the_api_is_final(self):
        with self.assertRaises(urllib.error.HTTPError):
            self.download(direct_status=404, api_status=404)


if __name__ == "__main__":
    unittest.main()
