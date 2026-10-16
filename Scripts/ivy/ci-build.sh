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
            block = lines[i:i + 60]
            end = next((n for n, l in enumerate(block[1:], 1) if l == ""), len(block))
            print("\n".join(block[:end]))
            print()
PY
}

run() {
  local log="$1"; shift
  local status
  NSUnbufferedIO=YES xcodebuild "${COMMON[@]}" "$@" 2>&1 \
    | tee "$LOG_DIR/$log" \
    | xcbeautify --renderer github-actions --disable-logging \
    && status=(0 0 0) || status=("${PIPESTATUS[@]}")
  if [ "${status[0]}" != 0 ] || [ "${status[1]}" != 0 ] || [ "${status[2]}" != 0 ]; then
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
