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
  COMPILATION_CACHE_ENABLE_CACHING=YES
  ${PLATFORM_SETTINGS[@]+"${PLATFORM_SETTINGS[@]}"}
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
