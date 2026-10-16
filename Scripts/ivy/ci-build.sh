#!/usr/bin/env bash
#
# Copyright 2026 kiri
# SPDX-License-Identifier: AGPL-3.0-only
#
# Builds the app for CI and runs tests.
#
#   Scripts/ivy/ci-build.sh ios fast     iPhone/iPad simulator, build only
#   Scripts/ivy/ci-build.sh ios full     ... and run the full test suite
#   Scripts/ivy/ci-build.sh macos fast   Mac Catalyst, build only
#   Scripts/ivy/ci-build.sh macos full   ... and run the full test suite
#
# "Build only" builds the app and all test bundles. Build products and
# Xcode's compilation cache live in $DERIVED_DATA (default ~/IvyDerivedData)
# so CI can cache them between runs.

set -euo pipefail

PLATFORM="${1:?platform: ios or macos}"
MODE="${2:-fast}"
DERIVED_DATA="${DERIVED_DATA:-$HOME/IvyDerivedData}"
LOG_DIR="$HOME/Library/Logs/Ivy-CI"
rm -rf "$LOG_DIR"
mkdir -p "$LOG_DIR"

case "$PLATFORM" in
  ios)
    RUNTIME=$(xcrun simctl list runtimes -j \
      | jq -r '.runtimes | map(select(.name | startswith("iOS")) | select(.isAvailable)) | sort_by(.version) | last | .identifier')
    SIMULATOR=$(xcrun simctl list devices -j \
      | jq -r --arg runtime "$RUNTIME" '.devices[$runtime] | map(select(.name | startswith("iPhone"))) | first | .udid')
    echo "Simulator: $SIMULATOR ($RUNTIME)"
    DESTINATION="platform=iOS Simulator,id=$SIMULATOR"
    PLATFORM_SETTINGS=()
    ;;
  macos)
    DESTINATION="platform=macOS,variant=Mac Catalyst,arch=arm64"
    # CI has no signing identity. Sign ad hoc so the app and tests can run.
    PLATFORM_SETTINGS=(CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= PROVISIONING_PROFILE_SPECIFIER= CODE_SIGN_ENTITLEMENTS=)
    ;;
  *)
    echo "unknown platform: $PLATFORM" >&2
    exit 2
    ;;
esac

COMMON=(
  -workspace Signal.xcworkspace
  -scheme Signal
  -destination "$DESTINATION"
  -derivedDataPath "$DERIVED_DATA"
  -disableAutomaticPackageResolution
  -IDEBuildingContinueBuildingAfterErrors=YES
  COMPILATION_CACHE_ENABLE_CACHING=YES
  ${PLATFORM_SETTINGS[@]+"${PLATFORM_SETTINGS[@]}"}
)

# Prints the output of each command xcodebuild lists as failed.
failed_command_output() {
  python3 - "$1" <<'PY'
import sys
lines = open(sys.argv[1], errors="replace").read().split("\n")
try:
    start = lines.index("The following build commands failed:")
except ValueError:
    sys.exit(0)
for entry in lines[start + 1:]:
    if not entry.startswith("\t"):
        break
    command = entry.strip()
    for i, line in enumerate(lines[:start]):
        if line == command:
            # Skip the environment Xcode exports for script phases.
            block = [l for l in lines[i:i + 2000] if not l.startswith("    export ")][:80]
            end = next((n for n, l in enumerate(block[1:], 1) if l == ""), len(block))
            print("\n".join(block[:end]))
            print()
PY
}

# Stops xcodebuild when its formatted output (what the job log shows) has
# been silent for STALL_MINUTES, after printing where the test processes are
# stuck. The raw log is not a reliable signal because a stuck test can keep
# logging. Per-test time limits do not catch every hang.
watchdog() {
  local pretty="$1" raw="$2" limit=$(( ${STALL_MINUTES:-10} * 60 ))
  while sleep 30; do
    [ -f "$pretty" ] || continue
    if [ $(( $(date +%s) - $(stat -f %m "$pretty") )) -ge "$limit" ]; then
      echo "::group::No progress for ${STALL_MINUTES:-10} minutes; stopping"
      echo "Last test lines of the raw log:"
      grep -i "^test case '" "$raw" | tail -5 | cut -c1-300
      echo "End of the raw log:"
      tail -80 "$raw" | cut -c1-300
      echo "Swift Testing tests that started but did not finish:"
      unfinished_swift_tests "$raw" || true
      for pid in $(pgrep -x Ivy) $(pgrep -f '/xctest( |$)'); do
        echo "== $(ps -o command= -p "$pid" | cut -c1-200)"
        # Keep the thread headers and the app's own frames.
        sample "$pid" 3 2>&1 \
          | grep -E 'Thread_|Signal|Ivy|XCTWaiter|swift_task|Testing' \
          | grep -vE 'dyld|\?\?\?' | cut -c1-220 | head -600
      done
      echo "::endgroup::"
      pkill -x xcodebuild || true
      return
    fi
  done
}

# Lists Swift Testing tests (and parameterized cases) that started but did
# not finish, from the raw xcodebuild output.
unfinished_swift_tests() {
  python3 - "$1" <<'PY'
import re, sys
started, ended = {}, set()
for line in open(sys.argv[1], errors="replace"):
    m = re.search(r"Test (case passing .* to )?(\S+\(.*?\)) started", line)
    if m and "◇" in line:
        started[line.split("◇", 1)[1].replace(" started.", "").strip()] = True
    m = re.search(r"[✔✘] Test (case passing .* to )?(\S+\(.*?\)) (passed|failed|recorded|skipped)", line)
    if m:
        ended.add(line.split(" ", 2)[-1].rsplit(" passed", 1)[0].rsplit(" failed", 1)[0].strip())
for name in started:
    key = name.replace("Test ", "", 1)
    if not any(key in e for e in ended):
        print("  " + name[:300])
PY
}

# Prints the details of test failures recorded in the result bundle.
test_failures() {
  local bundle="$1"
  [ -d "$bundle" ] || return 0
  xcrun xcresulttool get test-results summary --path "$bundle" > "$LOG_DIR/TestResultSummary.json" 2>/dev/null || return 0
  python3 Scripts/parse-xcresult.py "$LOG_DIR/TestResultSummary.json" | head -400
}

run() {
  local log="$1"; shift
  local status watchdog_pid
  watchdog "$LOG_DIR/$log.formatted" "$LOG_DIR/$log" &
  watchdog_pid=$!
  NSUnbufferedIO=YES xcodebuild "${COMMON[@]}" "$@" 2>&1 \
    | tee "$LOG_DIR/$log" \
    | xcbeautify --renderer github-actions --disable-logging \
    | tee "$LOG_DIR/$log.formatted" \
    && status=(0 0 0 0) || status=("${PIPESTATUS[@]}")
  kill "$watchdog_pid" 2>/dev/null || true
  if [ "${status[*]}" != "0 0 0 0" ]; then
    echo "xcodebuild exited with ${status[0]}, tee with ${status[1]}, xcbeautify with ${status[2]}"
    # GitHub shows only the first few errors as annotations; list them all.
    echo "::group::All errors"
    grep -E '(^|: |fatal )error: |\*\* .*FAILED \*\*|failed with a nonzero exit code' "$LOG_DIR/$log" \
      | sed -E 's#^/Users/[^/]+/work/[^/]+/[^/]+/##' | sort -u | head -300 || true
    echo "::endgroup::"
    # Failures that are not compiler errors (for example a failing script
    # phase) are summarized at the end of the raw log.
    echo "::group::End of the build log"
    tail -80 "$LOG_DIR/$log"
    echo "::endgroup::"
    echo "::group::Output of failed commands"
    failed_command_output "$LOG_DIR/$log" || true
    echo "::endgroup::"
    echo "::group::Test failures"
    test_failures "$LOG_DIR/TestResult.xcresult" || true
    echo "::endgroup::"
    return 1
  fi
}

run build.log build-for-testing

if [ "$MODE" = "full" ]; then
  run test.log test-without-building \
    -resultBundlePath "$LOG_DIR/TestResult.xcresult" \
    -test-timeouts-enabled YES \
    -maximum-test-execution-time-allowance 300 \
    -default-test-execution-time-allowance 60
fi
