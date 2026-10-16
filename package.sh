#!/usr/bin/env bash
#
# package.sh — build a signed, notarized, stapled Beacon.dmg into dist/.
#
#   ./package.sh
#
# Output:
#   dist/Beacon-<ver>.dmg    Developer ID signed, notarized, stapled.
#                            Beacon.app plus an Applications shortcut.
#   build/Build/Products/Release/Beacon.app
#                            The same app, also notarized and stapled.
#
# Requires: xcodegen, create-dmg, Xcode, the Developer ID Application cert,
# and a notarytool keychain profile (see NOTARY_PROFILE).
set -euo pipefail
cd "$(dirname "$0")"
ROOT="$PWD"

# Notarization credentials are per team. Beacon uses the same profile as Focus Pill.
NOTARY_PROFILE="${NOTARY_PROFILE:-focuspill-notary}"

VERSION="$(grep -Eo 'MARKETING_VERSION:[[:space:]]*"[^"]+"' project.yml 2>/dev/null \
  | head -1 | sed -E 's/.*"([^"]+)".*/\1/')"
VERSION="${VERSION:-1.0.0}"

DIST="dist"
MAC_DMG="$DIST/Beacon-${VERSION}.dmg"
mkdir -p "$DIST"

# Submit an artifact (.app is zipped first; a .dmg goes as-is), poll notarytool
# info, then staple the ticket onto $1. Polling beats `submit --wait`, which
# holds one connection open and can time out on a slow job.
notarize_submit_and_staple() {
  local target="$1" submit_artifact tmp_zip=""
  if [[ "$target" == *.app ]]; then
    tmp_zip="$(mktemp -d)/Beacon-notarize-submission.zip"
    ditto -c -k --keepParent "$target" "$tmp_zip"
    submit_artifact="$tmp_zip"
  else
    submit_artifact="$target"
  fi

  echo "==> [macOS] submitting $(basename "$target") to Apple notary service…"
  local submit_json sub_id
  submit_json="$(xcrun notarytool submit "$submit_artifact" \
    --keychain-profile "$NOTARY_PROFILE" --output-format json)"
  [ -n "$tmp_zip" ] && rm -f "$tmp_zip"
  sub_id="$(echo "$submit_json" | sed -nE 's/.*"id"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p' | head -1)"
  [ -n "$sub_id" ] || { echo "!! Could not read a submission id from notarytool:"; echo "$submit_json"; exit 1; }
  echo "    submission id: $sub_id — waiting for a verdict…"

  local notary_status="" elapsed=0
  until [ "$notary_status" = "Accepted" ] || [ "$notary_status" = "Invalid" ] || [ "$notary_status" = "Rejected" ]; do
    sleep 20
    elapsed=$((elapsed + 20))
    notary_status="$(xcrun notarytool info "$sub_id" --keychain-profile "$NOTARY_PROFILE" 2>&1 \
      | sed -nE 's/^[[:space:]]*status:[[:space:]]*(.+)$/\1/p')"
    if [ $((elapsed % 60)) -eq 0 ]; then
      echo "    …still ${notary_status:-checking} after ${elapsed}s"
    fi
  done

  if [ "$notary_status" != "Accepted" ]; then
    echo "!! Notarization did not succeed (status: $notary_status). Fetching the log…"
    xcrun notarytool log "$sub_id" --keychain-profile "$NOTARY_PROFILE"
    exit 1
  fi

  echo "==> [macOS] stapling notarization ticket onto $(basename "$target")"
  xcrun stapler staple "$target"
}

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "    xcodegen missing; installing via Homebrew…"
  brew install xcodegen
fi
if ! command -v create-dmg >/dev/null 2>&1; then
  echo "    create-dmg missing; installing via Homebrew…"
  brew install create-dmg
fi

# Looked up by description rather than a hardcoded hash, so a renewed cert still matches.
developer_id="$(security find-identity -v -p codesigning \
  | grep 'Developer ID Application' | head -1 | sed -E 's/^[[:space:]]*[0-9]+\) [0-9A-F]+ "(.+)"$/\1/')"
[ -n "$developer_id" ] || { echo "!! No 'Developer ID Application' identity in the login Keychain."; exit 1; }

echo "==> [macOS] $VERSION — generating Xcode project"
xcodegen generate >/dev/null

# A plain `xcodebuild build` signs with a dev-style signature (get-task-allow
# entitlement, no secure timestamp) and does NOT re-sign nested vendored binaries
# (Sparkle) with our identity. archive + export with the developer-id method does.
echo "==> [macOS] archiving universal (arm64 + x86_64) Release build"
rm -rf "$DIST/Beacon.xcarchive"
xcodebuild -project Beacon.xcodeproj -scheme Beacon \
  -configuration Release -derivedDataPath build \
  -archivePath "$DIST/Beacon.xcarchive" \
  ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO archive | tail -5

echo "==> [macOS] exporting Developer ID-signed .app"
rm -rf "$DIST/export"
xcodebuild -exportArchive -archivePath "$DIST/Beacon.xcarchive" \
  -exportPath "$DIST/export" -exportOptionsPlist ExportOptions.plist | tail -5

app="build/Build/Products/Release/Beacon.app"
rm -rf "$app"
ditto "$DIST/export/Beacon.app" "$app"

# Staple the app first. Once someone drags it out of the DMG, only a ticket on
# the app itself travels with the copy.
notarize_submit_and_staple "$app"
echo "==> [macOS] verifying Gatekeeper acceptance (.app)"
spctl -a -vvv --type execute "$app"

echo "==> [macOS] building disk image"
bg="$(mktemp -d)/background.png"
swift Tools/generate-dmg-background.swift "$bg" 660 400
dmg_src="$(mktemp -d)/dmg-src"
mkdir -p "$dmg_src"
ditto "$app" "$dmg_src/Beacon.app"
rm -f "$MAC_DMG"
create-dmg \
  --volname "Beacon" \
  --background "$bg" \
  --window-pos 200 120 \
  --window-size 660 400 \
  --icon-size 128 \
  --icon "Beacon.app" 180 190 \
  --hide-extension "Beacon.app" \
  --app-drop-link 480 190 \
  --codesign "$developer_id" \
  --hdiutil-retries 20 \
  --overwrite \
  "$MAC_DMG" \
  "$dmg_src"
rm -rf "$dmg_src" "$(dirname "$bg")"

notarize_submit_and_staple "$MAC_DMG"
echo "==> [macOS] verifying Gatekeeper acceptance (.dmg)"
spctl -a -vvv -t install "$MAC_DMG"

echo "    -> $MAC_DMG"
ls -lh "$MAC_DMG" "$app"
