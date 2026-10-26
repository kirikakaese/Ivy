#!/bin/bash
#
# Copyright 2026 kiri
# SPDX-License-Identifier: AGPL-3.0-only
#
# Archives the iOS app and uploads it to TestFlight. Signing goes through
# the App Store Connect API (Scripts/ivy/asc-signing.rb): a certificate and
# profiles only for this run, removed again at the end. Needs
# APPLE_TEAM_ID, ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY (the .p8 file's text)
# and IVY_BUILD.

set -euo pipefail

SCRIPTS="$(cd "$(dirname "$0")" && pwd)"
WORK="${RUNNER_TEMP:-$(mktemp -d)}/testflight"
LOG_DIR="$HOME/Library/Logs/Ivy-CI"
SIGNING="$WORK/signing"
KEYCHAIN="$WORK/ivy-signing.keychain-db"
APP_GROUP="group.io.github.kirikakaese.ivy.group"
export IVY_BUNDLE_ID="io.github.kirikakaese.ivy"
mkdir -p "$WORK" "$LOG_DIR"

# Pasted secrets can carry a trailing line break.
ASC_KEY_ID="$(printf '%s' "$ASC_KEY_ID" | tr -d '[:space:]')"
ASC_ISSUER_ID="$(printf '%s' "$ASC_ISSUER_ID" | tr -d '[:space:]')"
APPLE_TEAM_ID="$(printf '%s' "$APPLE_TEAM_ID" | tr -d '[:space:]')"
export ASC_KEY_ID ASC_ISSUER_ID APPLE_TEAM_ID

cleanup() {
  ruby "$SCRIPTS/asc-signing.rb" cleanup "$SIGNING" || true
  security delete-keychain "$KEYCHAIN" 2>/dev/null || true
  rm -rf "$SIGNING" "$HOME/.appstoreconnect/private_keys"
}
trap cleanup EXIT

ruby "$SCRIPTS/asc-check.rb"
ruby "$SCRIPTS/asc-signing.rb" prepare "$SIGNING"

# A keychain only for this run, with the run's certificate.
KEYCHAIN_PASSWORD="$(openssl rand -hex 16)"
security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
security set-keychain-settings -lut 21600 "$KEYCHAIN"
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
curl -fsSL https://www.apple.com/certificateauthority/AppleWWDRCAG3.cer -o "$SIGNING/wwdr.cer"
security import "$SIGNING/wwdr.cer" -k "$KEYCHAIN" >/dev/null || true
security import "$SIGNING/signing-key.pem" -k "$KEYCHAIN" -t priv -f openssl -T /usr/bin/codesign -T /usr/bin/security >/dev/null
security import "$SIGNING/signing.cer" -k "$KEYCHAIN" -T /usr/bin/codesign >/dev/null
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN" >/dev/null
# shellcheck disable=SC2046
security list-keychains -d user -s "$KEYCHAIN" $(security list-keychains -d user | tr -d '"')
security find-identity -v -p codesigning "$KEYCHAIN"

# The profiles, and whether each carries the App Group. Apple's API can't
# assign an App Group to an App ID; that is a one-time step on the website.
PROFILE_DIRS=("$HOME/Library/MobileDevice/Provisioning Profiles" "$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles")
mkdir -p "${PROFILE_DIRS[@]}"
missing=""
for profile in "$SIGNING"/profiles/*.mobileprovision; do
  bundle_id="$(basename "$profile" .mobileprovision)"
  plist="$SIGNING/$bundle_id.plist"
  security cms -D -i "$profile" > "$plist"
  uuid="$(/usr/libexec/PlistBuddy -c 'Print :UUID' "$plist")"
  for dir in "${PROFILE_DIRS[@]}"; do
    cp "$profile" "$dir/$uuid.mobileprovision"
  done
  groups="$(/usr/libexec/PlistBuddy -c 'Print :Entitlements:com.apple.security.application-groups' "$plist" 2>/dev/null || true)"
  case "$groups" in
    *"$APP_GROUP"*) ;;
    *) missing="$missing $bundle_id" ;;
  esac
done
if [ -n "$missing" ]; then
  echo "::error::These App IDs don't have the App Group $APP_GROUP yet:$missing. On developer.apple.com > Identifiers, create the App Group (filter: App Groups) if needed, then open each of these App IDs, click Configure next to App Groups, tick the group, and save. Then run the workflow again. (docs/TESTFLIGHT.md, step 6)"
  exit 1
fi

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

# Every app and extension gets the profile named after its bundle ID;
# frameworks get none.
ARCHIVE="$WORK/Ivy.xcarchive"
run archive \
  -workspace Signal.xcworkspace \
  -scheme Signal \
  -configuration "App Store Release" \
  -destination "generic/platform=iOS" \
  -archivePath "$ARCHIVE" \
  DEVELOPMENT_TEAM="$APPLE_TEAM_ID" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="Apple Distribution" \
  'PROVISIONING_PROFILE_SPECIFIER=$(IVY_PROFILE_$(WRAPPER_EXTENSION))' \
  'IVY_PROFILE_app=Ivy CI $(PRODUCT_BUNDLE_IDENTIFIER)' \
  'IVY_PROFILE_appex=Ivy CI $(PRODUCT_BUNDLE_IDENTIFIER)' \
  OTHER_CODE_SIGN_FLAGS="--keychain $KEYCHAIN" \
  IVY_BUILD="$IVY_BUILD" \
  archive

profiles=""
for profile in "$SIGNING"/profiles/*.mobileprovision; do
  bundle_id="$(basename "$profile" .mobileprovision)"
  profiles="$profiles<key>$bundle_id</key><string>Ivy CI $bundle_id</string>"
done
cat > "$WORK/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key>
	<string>app-store-connect</string>
	<key>destination</key>
	<string>export</string>
	<key>teamID</key>
	<string>${APPLE_TEAM_ID}</string>
	<key>signingStyle</key>
	<string>manual</string>
	<key>signingCertificate</key>
	<string>Apple Distribution</string>
	<key>provisioningProfiles</key>
	<dict>${profiles}</dict>
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
  -exportPath "$WORK/export"

IPA="$(ls "$WORK"/export/*.ipa | head -1)"
mkdir -p "$HOME/.appstoreconnect/private_keys"
ruby -r "$SCRIPTS/asc" -e 'File.write(ARGV[0], ASC.key_pem, perm: 0o600)' \
  "$HOME/.appstoreconnect/private_keys/AuthKey_${ASC_KEY_ID}.p8"
set +e
xcrun altool --upload-app --type ios --file "$IPA" \
  --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID" 2>&1 | tee "$LOG_DIR/upload.log"
upload_status="${PIPESTATUS[0]}"
set -e
if [ "$upload_status" -ne 0 ]; then
  echo "::error::The upload to App Store Connect failed:"
  grep -iE 'error|fail' "$LOG_DIR/upload.log" | head -20 || true
  exit 1
fi

echo "Uploaded build $IVY_BUILD to App Store Connect. It shows up in TestFlight after Apple has processed it."
