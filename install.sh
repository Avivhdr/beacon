#!/usr/bin/env bash
# Build a Release Beacon.app, copy it to /Applications, and launch it.
set -euo pipefail
cd "$(dirname "$0")"

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "==> Installing XcodeGen (via Homebrew)..."
  brew install xcodegen
fi

echo "==> Generating app icon..."
swift Tools/generate-icon.swift Sources/Beacon/Assets.xcassets/AppIcon.appiconset

echo "==> Generating Xcode project..."
xcodegen generate

echo "==> Building (Release)..."
xcodebuild \
  -project Beacon.xcodeproj \
  -scheme Beacon \
  -configuration Release \
  -derivedDataPath build \
  build | tail -20

APP="build/Build/Products/Release/Beacon.app"
echo "==> Installing to /Applications..."
# The process was named GitHubNotifications before the rename.
pkill -x Beacon || true
pkill -x GitHubNotifications || true
rm -rf "/Applications/Beacon.app" "/Applications/GitHub Notifications.app"
cp -R "$APP" "/Applications/Beacon.app"

echo "==> Launching..."
open "/Applications/Beacon.app"
echo "Done. Beacon is in /Applications."
