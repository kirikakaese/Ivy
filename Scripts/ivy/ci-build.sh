#!/usr/bin/env bash
#
# Copyright 2026 kiri
# SPDX-License-Identifier: AGPL-3.0-only
#
# Builds the app for CI and runs tests.
#
#   Scripts/ivy/ci-build.sh fast   Build the app and all test bundles.
#   Scripts/ivy/ci-build.sh full   Build, then run the full test suite.
#
# Build products and Xcode's compilation cache live in $DERIVED_DATA
# (default ~/IvyDerivedData) so CI can cache them between runs.

set -euo pipefail

MODE="${1:-fast}"
DERIVED_DATA="${DERIVED_DATA:-$HOME/IvyDerivedData}"
LOG_DIR="$HOME/Library/Logs/Ivy-CI"
rm -rf "$LOG_DIR"
mkdir -p "$LOG_DIR"

RUNTIME=$(xcrun simctl list runtimes -j \
  | jq -r '.runtimes | map(select(.name | startswith("iOS")) | select(.isAvailable)) | sort_by(.version) | last | .identifier')
SIMULATOR=$(xcrun simctl list devices -j \
  | jq -r --arg runtime "$RUNTIME" '.devices[$runtime] | map(select(.name | startswith("iPhone"))) | first | .udid')
echo "Runtime: $RUNTIME"
echo "Simulator: $SIMULATOR"

COMMON=(
  -workspace Signal.xcworkspace
  -scheme Signal
  -destination "platform=iOS Simulator,id=$SIMULATOR"
  -derivedDataPath "$DERIVED_DATA"
  -disableAutomaticPackageResolution
  COMPILATION_CACHE_ENABLE_CACHING=YES
)

run() {
  local log="$1"; shift
  NSUnbufferedIO=YES xcodebuild "${COMMON[@]}" "$@" 2>&1 \
    | tee "$LOG_DIR/$log" \
    | xcbeautify --renderer github-actions --disable-logging
}

run build.log build-for-testing

if [ "$MODE" = "full" ]; then
  run test.log test-without-building \
    -resultBundlePath "$LOG_DIR/TestResult.xcresult" \
    -test-timeouts-enabled YES \
    -maximum-test-execution-time-allowance 300 \
    -default-test-execution-time-allowance 60
fi
