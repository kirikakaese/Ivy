#!/usr/bin/env python3
#
# Copyright 2026 kiri
# SPDX-License-Identifier: AGPL-3.0-only
#

"""Mac Catalyst variants of the prebuilt libraries in the Podfile.

Commands:
  versions    Print the pinned libsignal, RingRTC and MobileCoin versions
              (and the upstream libsignal archive checksum) read from the
              Podfile, as key=value lines.
"""

import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def podfile_versions(text):
    def find(pattern):
        m = re.search(pattern, text, re.M)
        if not m:
            raise SystemExit(f"Podfile: no match for {pattern}")
        return m.group(1)

    return {
        "libsignal": find(r"^pod 'LibSignalClient'.*tag: 'v([^']+)'"),
        "libsignal_checksum": find(r"^ENV\['LIBSIGNAL_FFI_PREBUILD_CHECKSUM'\] = '([0-9a-f]{64})'"),
        "ringrtc": find(r"^pod 'SignalRingRTC'.*tag: 'v([^']+)'"),
        "mobilecoin": find(r"pod 'LibMobileCoin/CoreHTTP'.*tag: 'signal/([^']+)'"),
    }


def cmd_versions():
    with open(os.path.join(ROOT, "Podfile"), encoding="utf-8") as f:
        for key, value in podfile_versions(f.read()).items():
            print(f"{key}={value}")
    return 0


def main(argv):
    if len(argv) == 2 and argv[1] == "versions":
        return cmd_versions()
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
