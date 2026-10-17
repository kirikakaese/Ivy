#!/usr/bin/env bash
#
# Copyright 2026 kiri
# SPDX-License-Identifier: AGPL-3.0-only
#
# Builds the Mac beta: a Release build for Mac Catalyst on Apple Silicon
# (the Mac WebRTC library has no Intel slice), signed ad hoc,
# without extensions, zipped for a GitHub release.
#
#   Scripts/ivy/mac-beta.sh [output directory]
#
# The build defines IVY_MAC_BETA (see SignalServiceKit/Ivy/IvyMacBeta.swift).

set -euo pipefail

OUTPUT="${1:-build/mac-beta}"
DERIVED_DATA="${DERIVED_DATA:-$HOME/IvyBetaDerivedData}"
LOG_DIR="$HOME/Library/Logs/Ivy-CI"
mkdir -p "$OUTPUT" "$LOG_DIR"

set +e
NSUnbufferedIO=YES xcodebuild \
  -workspace Signal.xcworkspace \
  -scheme Signal \
  -configuration Release \
  -destination "platform=macOS,variant=Mac Catalyst,arch=arm64" \
  -derivedDataPath "$DERIVED_DATA" \
  -disableAutomaticPackageResolution \
  COMPILATION_CACHE_ENABLE_CACHING=YES \
  ARCHS=arm64 \
  ONLY_ACTIVE_ARCH=YES \
  CODE_SIGN_IDENTITY=- \
  CODE_SIGN_STYLE=Manual \
  DEVELOPMENT_TEAM= \
  PROVISIONING_PROFILE_SPECIFIER= \
  CODE_SIGN_ENTITLEMENTS= \
  'SWIFT_ACTIVE_COMPILATION_CONDITIONS=$(inherited) IVY_MAC_BETA' \
  build 2>&1 | tee "$LOG_DIR/mac-beta.log" | xcbeautify --renderer github-actions
status=("${PIPESTATUS[@]}")
set -e
if [ "${status[0]}" -ne 0 ]; then
  echo "::group::All errors"
  grep -E '(^|: |fatal )error: |\*\* .*FAILED \*\*' "$LOG_DIR/mac-beta.log" | sort -u | head -200 || true
  echo "::endgroup::"
  exit 1
fi

APP="$DERIVED_DATA/Build/Products/Release-maccatalyst/Ivy.app"
if [ ! -d "$APP" ]; then
  echo "Ivy.app not found in $DERIVED_DATA/Build/Products" >&2
  ls "$DERIVED_DATA/Build/Products" >&2 || true
  exit 1
fi

STAGE=$(mktemp -d)
cp -R "$APP" "$STAGE/Ivy Beta.app"
APP="$STAGE/Ivy Beta.app"

# The extensions need the app group, which an ad hoc signature can't have.
rm -rf "$APP/Contents/PlugIns" "$APP/Contents/Extensions"

# Sign everything again ad hoc, without entitlements.
codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"
codesign --display --entitlements - "$APP" || true

ZIP="$OUTPUT/Ivy-Mac-Beta.zip"
rm -f "$ZIP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
shasum -a 256 "$ZIP" | tee "$ZIP.sha256"
echo "Built $ZIP"
