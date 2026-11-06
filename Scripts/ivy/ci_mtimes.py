#!/usr/bin/env python3
#
# Copyright 2026 kiri
# SPDX-License-Identifier: AGPL-3.0-only
#

"""Keeps file modification times stable between CI runs.

Xcode decides what to rebuild by comparing modification times with the ones
it recorded. A fresh checkout and a fresh `pod install` give every file the
current time, so a restored build cache would be ignored and the whole app
rebuilt. This script records each file's content hash and modification time
next to the build products, and on the next run gives every file whose
content is unchanged its old time back. Changed files keep the current time
and are rebuilt.

  ci_mtimes.py save <manifest>      Record the files of the working tree.
  ci_mtimes.py restore <manifest>   Restore the times of unchanged files.

Covers the files git tracks, everything under Pods/ and the test data
submodule.
"""

import hashlib
import json
import os
import subprocess
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
EXTRA_DIRS = ("Pods", "SignalServiceKit/tests/MessageBackup/Signal-Message-Backup-Tests")


def tracked_files(root):
    """Returns {path: blob hash} for unmodified tracked files."""
    output = subprocess.run(
        ["git", "ls-files", "-s", "-z"], cwd=root, check=True,
        stdout=subprocess.PIPE,
    ).stdout.decode("utf-8", "surrogateescape")
    modified = set(subprocess.run(
        ["git", "diff", "--name-only", "-z"], cwd=root, check=True,
        stdout=subprocess.PIPE,
    ).stdout.decode("utf-8", "surrogateescape").split("\0"))
    files = {}
    for entry in output.split("\0"):
        if not entry:
            continue
        meta, path = entry.split("\t", 1)
        mode, blob, _stage = meta.split()
        # Submodules (160000) are directories; their files are listed below
        # when they matter.
        if mode != "160000" and path not in modified:
            files[path] = blob
    return files


def content_hash(path):
    digest = hashlib.sha1()
    with open(path, "rb") as file:
        for chunk in iter(lambda: file.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def extra_files(root, tracked):
    """Returns {path: content hash} for untracked files under EXTRA_DIRS."""
    files = {}
    for directory in EXTRA_DIRS:
        for dirpath, _dirnames, filenames in os.walk(os.path.join(root, directory)):
            for name in filenames:
                full = os.path.join(dirpath, name)
                path = os.path.relpath(full, root)
                if path in tracked or os.path.islink(full):
                    continue
                files[path] = content_hash(full)
    return files


def snapshot(root):
    tracked = tracked_files(root)
    files = dict(tracked)
    files.update(extra_files(root, tracked))
    return files


def save(root, manifest):
    entries = {}
    for path, digest in snapshot(root).items():
        full = os.path.join(root, path)
        if os.path.isfile(full) and not os.path.islink(full):
            entries[path] = [digest, os.stat(full).st_mtime_ns]
    os.makedirs(os.path.dirname(os.path.abspath(manifest)), exist_ok=True)
    with open(manifest, "w", encoding="utf-8") as file:
        json.dump(entries, file, separators=(",", ":"))
    print(f"Recorded {len(entries)} files.")


def restore(root, manifest):
    if not os.path.exists(manifest):
        print("No recorded times; this build starts from scratch.")
        return
    with open(manifest, encoding="utf-8") as file:
        recorded = json.load(file)
    restored = changed = 0
    for path, digest in snapshot(root).items():
        entry = recorded.get(path)
        full = os.path.join(root, path)
        if not entry or not os.path.isfile(full) or os.path.islink(full):
            continue
        if entry[0] == digest:
            os.utime(full, ns=(entry[1], entry[1]))
            restored += 1
        else:
            changed += 1
    print(f"Restored the times of {restored} unchanged files; {changed} changed.")


def main(argv):
    if len(argv) != 3 or argv[1] not in ("save", "restore"):
        print(__doc__)
        return 2
    (save if argv[1] == "save" else restore)(ROOT, argv[2])
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
