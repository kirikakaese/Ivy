#!/bin/bash
#
# Copyright 2026 kiri
# SPDX-License-Identifier: AGPL-3.0-only
#
# Archives the iOS app and uploads it to TestFlight. Xcode signs with the
# team's certificates and creates the App IDs and profiles itself, using the
# App Store Connect API key. Needs APPLE_TEAM_ID, ASC_KEY_ID, ASC_ISSUER_ID,
# ASC_KEY (the .p8 file's text) and IVY_BUILD.

set -euo pipefail

WORK="${RUNNER_TEMP:-$(mktemp -d)}/testflight"
LOG_DIR="$HOME/Library/Logs/Ivy-CI"
mkdir -p "$WORK" "$LOG_DIR"

# Pasted secrets can carry a trailing line break, which breaks the sign-in.
ASC_KEY_ID="$(printf '%s' "$ASC_KEY_ID" | tr -d '[:space:]')"
ASC_ISSUER_ID="$(printf '%s' "$ASC_ISSUER_ID" | tr -d '[:space:]')"
APPLE_TEAM_ID="$(printf '%s' "$APPLE_TEAM_ID" | tr -d '[:space:]')"
export ASC_KEY_ID ASC_ISSUER_ID APPLE_TEAM_ID

KEY_PATH="$WORK/AuthKey_${ASC_KEY_ID}.p8"
trap 'rm -f "$KEY_PATH"' EXIT
# Checks the key and the app record first and writes the key file.
IVY_BUNDLE_ID=io.github.kirikakaese.ivy ruby "$(dirname "$0")/asc-check.rb" "$KEY_PATH"

AUTH=(
  -allowProvisioningUpdates
  -authenticationKeyPath "$KEY_PATH"
  -authenticationKeyID "$ASC_KEY_ID"
  -authenticationKeyIssuerID "$ASC_ISSUER_ID"
)

run() {
  local name="$1"
  shift
  set +e
  NSUnbufferedIO=YES xcodebuild "$@" 2>&1 | tee "$LOG_DIR/$name.log" | xcbeautify --renderer github-actions
  local status=("${PIPESTATUS[@]}")
  set -e
  if [ "${status[0]}" -ne 0 ]; then
    echo "::group::All errors"
    grep -E '(^|: |fatal )error: |\*\* .*FAILED \*\*' "$LOG_DIR/$name.log" | sort -u | head -200 || true
    echo "::endgroup::"
    exit 1
  fi
}

ARCHIVE="$WORK/Ivy.xcarchive"
run archive \
  -workspace Signal.xcworkspace \
  -scheme Signal \
  -configuration "App Store Release" \
  -destination "generic/platform=iOS" \
  -archivePath "$ARCHIVE" \
  "${AUTH[@]}" \
  DEVELOPMENT_TEAM="$APPLE_TEAM_ID" \
  CODE_SIGN_STYLE=Automatic \
  CODE_SIGN_IDENTITY="Apple Development" \
  PROVISIONING_PROFILE_SPECIFIER= \
  IVY_BUILD="$IVY_BUILD" \
  archive

cat > "$WORK/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key>
	<string>app-store-connect</string>
	<key>destination</key>
	<string>upload</string>
	<key>teamID</key>
	<string>${APPLE_TEAM_ID}</string>
	<key>signingStyle</key>
	<string>automatic</string>
	<key>manageAppVersionAndBuildNumber</key>
	<false/>
	<key>uploadSymbols</key>
	<true/>
</dict>
</plist>
PLIST

run export \
  -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportOptionsPlist "$WORK/ExportOptions.plist" \
  -exportPath "$WORK/export" \
  "${AUTH[@]}"

echo "Uploaded build $IVY_BUILD to App Store Connect. It shows up in TestFlight after Apple has processed it."
