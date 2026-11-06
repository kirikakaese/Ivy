#!/usr/bin/env python3
#
# Copyright 2026 kiri
# SPDX-License-Identifier: AGPL-3.0-only
#

"""Brings new Signal-iOS releases into Ivy (docs/UPSTREAM_SYNC.md).

Commands:
  status [--github-output]  Print the release Ivy is built on and the latest
                            stable upstream release. With --github-output,
                            also write current, latest and behind to the file
                            named by $GITHUB_OUTPUT.
  merge [TAG]               Create a branch from the current commit, fetch
                            the release (default: the latest) and merge it.
                            Resolves the cases that always go Ivy's way,
                            sets the client version and lists what is left.
  set-version TAG           Write the release into Config/Ivy.xcconfig and
                            the README.
  markers [BASE]            Compare the "// Ivy:" markers with BASE (default
                            origin/main) and list files that lost some. A
                            lost marker usually means a merge dropped one of
                            Ivy's changes.
"""

import os
import re
import subprocess
import sys

UPSTREAM_URL = "https://github.com/signalapp/Signal-iOS.git"
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
XCCONFIG = "Config/Ivy.xcconfig"
README = "README.md"
MARKER = "// Ivy:"

# Paths whose conflicts are always resolved with Ivy's side.
KEEP_OURS = (".github/", "Pods")

STABLE_TAG = re.compile(r"^(\d+)\.(\d+)\.(\d+)\.(\d+)$")


def parse_tag(tag):
    """Returns the version of a stable tag as a tuple, or None."""
    match = STABLE_TAG.match(tag)
    return tuple(int(part) for part in match.groups()) if match else None


def latest_stable(tags):
    """Returns the newest stable tag of a list of tag names, or None."""
    stable = [tag for tag in tags if parse_tag(tag)]
    return max(stable, key=parse_tag) if stable else None


def tags_from_ls_remote(output):
    """Extracts tag names from `git ls-remote --tags --refs` output."""
    tags = []
    for line in output.splitlines():
        parts = line.split("refs/tags/", 1)
        if len(parts) == 2:
            tags.append(parts[1].strip())
    return tags


def current_release(xcconfig_text):
    """Returns the release named in Ivy.xcconfig, e.g. 8.32.0.1910."""
    values = {}
    for line in xcconfig_text.splitlines():
        match = re.match(r"^\s*(IVY_UPSTREAM_\w+)\s*=\s*(\S+)", line)
        if match:
            values[match.group(1)] = match.group(2)
    marketing = values["IVY_UPSTREAM_MARKETING_VERSION"]
    build = values["IVY_UPSTREAM_BUILD_NUMBER"]
    if marketing.count(".") == 1:
        marketing += ".0"
    return f"{marketing}.{build}"


def with_release(xcconfig_text, tag):
    """Returns Ivy.xcconfig with the version values set to the tag."""
    major, minor, patch, build = parse_tag(tag)
    marketing = f"{major}.{minor}" if patch == 0 else f"{major}.{minor}.{patch}"
    text = re.sub(
        r"^(\s*IVY_UPSTREAM_MARKETING_VERSION\s*=\s*)\S+",
        lambda m: m.group(1) + marketing,
        xcconfig_text,
        flags=re.M,
    )
    text = re.sub(
        r"^(\s*IVY_UPSTREAM_BUILD_NUMBER\s*=\s*)\S+",
        lambda m: m.group(1) + str(build),
        text,
        flags=re.M,
    )
    return re.sub(r"\(\d+\.\d+\.\d+\.\d+\)", f"({tag})", text)


def readme_with_release(readme_text, tag):
    return re.sub(
        r"(currently release )\d+\.\d+\.\d+\.\d+",
        lambda m: m.group(1) + tag,
        readme_text,
    )


def branch_name(tag):
    major, minor, patch, _ = parse_tag(tag)
    suffix = f"-{patch}" if patch else ""
    return f"merge-upstream-{major}-{minor}{suffix}"


def marker_counts(grep_output):
    """Parses `git grep -c` output into {path: count}."""
    counts = {}
    for line in grep_output.splitlines():
        path, _, count = line.rpartition(":")
        if path and count.isdigit():
            counts[path] = int(count)
    return counts


def lost_markers(before, after):
    """Returns [(path, before, after)] for files with fewer markers."""
    return sorted(
        (path, count, after.get(path, 0))
        for path, count in before.items()
        if after.get(path, 0) < count
    )


def keeps_ours(path):
    return any(path == prefix or path.startswith(prefix) for prefix in KEEP_OURS)


# Commands.

def git(*args, check=True, capture=True):
    result = subprocess.run(
        ["git", *args], cwd=ROOT, text=True, check=False,
        stdout=subprocess.PIPE if capture else None,
        stderr=subprocess.PIPE if capture else None,
    )
    if check and result.returncode != 0:
        sys.exit(f"git {' '.join(args)} failed:\n{result.stderr or ''}")
    return result.stdout or ""


def read(path):
    with open(os.path.join(ROOT, path), encoding="utf-8") as file:
        return file.read()


def write(path, text):
    with open(os.path.join(ROOT, path), "w", encoding="utf-8") as file:
        file.write(text)


def fetch_latest():
    output = git("ls-remote", "--tags", "--refs", UPSTREAM_URL)
    tag = latest_stable(tags_from_ls_remote(output))
    if not tag:
        sys.exit("No stable upstream release found.")
    return tag


def command_status(args):
    current = current_release(read(XCCONFIG))
    latest = fetch_latest()
    behind = parse_tag(latest) > parse_tag(current)
    print(f"Ivy is built on {current}.")
    print(f"Latest stable Signal-iOS release: {latest}.")
    print("A newer release is out; see docs/UPSTREAM_SYNC.md." if behind else "Up to date.")
    if "--github-output" in args and os.environ.get("GITHUB_OUTPUT"):
        with open(os.environ["GITHUB_OUTPUT"], "a", encoding="utf-8") as out:
            out.write(f"current={current}\nlatest={latest}\nbehind={'true' if behind else 'false'}\n")
    return 0


def command_set_version(args):
    if len(args) != 1 or not parse_tag(args[0]):
        sys.exit("usage: upstream.py set-version TAG (for example 8.33.0.2000)")
    tag = args[0]
    write(XCCONFIG, with_release(read(XCCONFIG), tag))
    write(README, readme_with_release(read(README), tag))
    print(f"Set the client version to {tag}.")
    return 0


def command_merge(args):
    if git("status", "--porcelain").strip():
        sys.exit("The working tree has changes; commit or stash them first.")
    tag = args[0] if args else fetch_latest()
    if not parse_tag(tag):
        sys.exit(f"{tag} is not a stable release tag.")
    current = current_release(read(XCCONFIG))
    if parse_tag(tag) <= parse_tag(current):
        sys.exit(f"Ivy is already on {current}.")

    branch = branch_name(tag)
    git("checkout", "-b", branch)
    print(f"Fetching {tag}…")
    git("fetch", "--no-tags", UPSTREAM_URL, f"refs/tags/{tag}:refs/tags/upstream/{tag}")
    merge = subprocess.run(
        ["git", "merge", "--no-ff", "--no-commit", f"upstream/{tag}"],
        cwd=ROOT, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
    )
    print(merge.stdout.strip())

    conflicts = git("diff", "--name-only", "--diff-filter=U").split()
    left = []
    for path in conflicts:
        if keeps_ours(path):
            git("checkout", "--ours", "--", path, check=False)
            git("add", "--", path)
        else:
            left.append(path)
    # Upstream's Pods submodule pointer never comes back.
    git("rm", "-r", "--cached", "--quiet", "--ignore-unmatch", "Pods", check=False)

    command_set_version([tag])
    git("add", XCCONFIG, README)

    print()
    print(f"Branch {branch} has the merge of {tag}, not committed yet.")
    if left:
        print("Resolve these files (Ivy's changes are marked with \"// Ivy:\"):")
        for path in left:
            print(f"  {path}")
    print("Then run, in this order:")
    print(f"  git commit -m \"Merge Signal-iOS {tag}\"")
    print("  python3 Scripts/ivy/upstream.py markers")
    print("  make dependencies")
    print("  python3 Scripts/ivy/app_name.py check Scripts/ivy/app-name-rules.json Signal/translations")
    print("and continue with step 6 of docs/UPSTREAM_SYNC.md.")
    return 0


def command_markers(args):
    base = args[0] if args else "origin/main"
    before = marker_counts(git("grep", "-c", "-F", MARKER, base, check=False).replace(f"{base}:", ""))
    after = marker_counts(git("grep", "-c", "-F", MARKER, check=False))
    lost = lost_markers(before, after)
    print(f"{sum(after.values())} markers in {len(after)} files ({sum(before.values())} on {base}).")
    if not lost:
        print("No file lost a marker.")
        return 0
    print("Files with fewer markers than before; check that Ivy's changes survived:")
    for path, was, now in lost:
        print(f"  {path}: {was} -> {now}")
    return 1


COMMANDS = {
    "status": command_status,
    "merge": command_merge,
    "set-version": command_set_version,
    "markers": command_markers,
}


def main(argv):
    if len(argv) < 2 or argv[1] not in COMMANDS:
        print(__doc__)
        return 2
    return COMMANDS[argv[1]](argv[2:])


if __name__ == "__main__":
    sys.exit(main(sys.argv))
