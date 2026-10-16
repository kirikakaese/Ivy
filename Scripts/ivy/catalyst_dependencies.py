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
  install     Download the Mac Catalyst builds listed in
              catalyst-dependencies.json, verify their checksums and add
              them to the CocoaPods installation. Run after `pod install`
              (part of `make dependencies`). Builds that are not published
              yet, or that belong to another version than the Podfile pins,
              are skipped with a warning; the iOS app builds without them.
"""

import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tarfile
import tempfile
import urllib.request

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


PINS = os.path.join(os.path.dirname(os.path.abspath(__file__)), "catalyst-dependencies.json")
CACHES = os.path.expanduser("~/Library/Caches")


def load_pins():
    with open(PINS, encoding="utf-8") as f:
        return json.load(f)


def usable_pins(pins, versions):
    """Returns the pinned builds that match the Podfile versions."""
    usable = {}
    for name in ("libsignal", "ringrtc", "mobilecoin"):
        pin = pins.get(name)
        if pin is None:
            print(f"warning: no Mac Catalyst build of {name} is published yet")
        elif pin["version"] != versions[name]:
            print(f"warning: the Mac Catalyst build of {name} is for {pin['version']}, the Podfile pins {versions[name]}")
        else:
            usable[name] = pin
    return usable


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def extract(archive, dest):
    with tarfile.open(archive) as tar:
        if hasattr(tarfile, "data_filter"):
            tar.extractall(dest, filter="data")
        else:
            tar.extractall(dest)


def download(pin, dest):
    """Downloads a pinned release asset to dest unless it is already there."""
    if os.path.exists(dest) and sha256(dest) == pin["sha256"]:
        return dest
    url = f"https://github.com/{pin['repository']}/releases/download/{pin['tag']}/{pin['asset']}"
    print(f"downloading {url}")
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    tmp = dest + ".part"
    with urllib.request.urlopen(url) as response, open(tmp, "wb") as out:
        shutil.copyfileobj(response, out)
    actual = sha256(tmp)
    if actual != pin["sha256"]:
        os.remove(tmp)
        raise SystemExit(f"checksum mismatch for {pin['asset']}: {actual}")
    os.replace(tmp, dest)
    return dest


def install_libsignal(pin):
    print(f"installing libsignal {pin['version']} with Mac Catalyst")
    # The libsignal pod extracts this archive at build time; its checksum is
    # set in the Podfile environment (Scripts/ivy/podfile.rb).
    download(pin, os.path.join(CACHES, "org.signal.libsignal", pin["asset"]))


def install_ringrtc(pin, version):
    print(f"installing RingRTC {version} with Mac Catalyst")
    archive = download(pin, os.path.join(CACHES, "org.signal.ringrtc", "ivy-" + pin["asset"]))
    release = os.path.join(CACHES, "org.signal.ringrtc", f"prebuild-{version}", "release")
    pod_release = os.path.join(ROOT, "Pods", "SignalRingRTC", "out", "release")
    with tempfile.TemporaryDirectory() as tmp:
        extract(archive, tmp)

        target = "aarch64-apple-ios-macabi"
        lib_dir = os.path.join(release, "libringrtc", target)
        shutil.rmtree(lib_dir, ignore_errors=True)
        shutil.copytree(os.path.join(tmp, "libringrtc", target), lib_dir)
        link = os.path.join(pod_release, "libringrtc", target)
        if os.path.lexists(link):
            os.remove(link)
        os.symlink(lib_dir, link)

        xcframework = os.path.join(release, "WebRTC.xcframework")
        print(f"WebRTC.xcframework at {xcframework}: {sorted(os.listdir(xcframework))}")
        with open(os.path.join(xcframework, "Info.plist"), "rb") as f:
            if b"maccatalyst" in f.read():
                print("WebRTC.xcframework already has a Mac Catalyst slice")
                return
        frameworks = []
        for entry in sorted(os.listdir(xcframework)):
            framework = os.path.join(xcframework, entry, "WebRTC.framework")
            if os.path.isdir(framework):
                frameworks += ["-framework", framework]
        frameworks += ["-framework", os.path.join(tmp, "WebRTC.framework")]
        combined = os.path.join(tmp, "WebRTC.xcframework")
        subprocess.run(["xcodebuild", "-create-xcframework", *frameworks, "-output", combined], check=True)
        for extra in os.listdir(xcframework):
            if extra.endswith(".md") or extra.endswith(".txt"):
                shutil.copy(os.path.join(xcframework, extra), combined)
        shutil.rmtree(xcframework)
        shutil.copytree(combined, xcframework, symlinks=True)
        print(f"WebRTC.xcframework now has: {sorted(os.listdir(xcframework))}")


def install_mobilecoin(pin):
    print(f"installing MobileCoin {pin['version']} with Mac Catalyst")
    archive = download(pin, os.path.join(CACHES, "org.signal.ivy", pin["asset"]))
    artifacts = os.path.join(ROOT, "Pods", "LibMobileCoin", "Artifacts")
    extract(archive, artifacts)


def cmd_install():
    with open(os.path.join(ROOT, "Podfile"), encoding="utf-8") as f:
        versions = podfile_versions(f.read())
    pins = usable_pins(load_pins(), versions)
    if "libsignal" in pins:
        install_libsignal(pins["libsignal"])
    if "ringrtc" in pins:
        install_ringrtc(pins["ringrtc"], versions["ringrtc"])
    if "mobilecoin" in pins:
        install_mobilecoin(pins["mobilecoin"])
    return 0


def main(argv):
    if len(argv) == 2 and argv[1] == "versions":
        return cmd_versions()
    if len(argv) == 2 and argv[1] == "install":
        return cmd_install()
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
