#!/usr/bin/env bash
#
# release.sh — cut a signed Beacon release.
#
#   ./release.sh              # build, sign, publish the feed and the GitHub release
#   ./release.sh --dry-run    # build and sign into dist/; publish nothing
#
# The feed is web/appcast.xml on https://beacon-for-github.vercel.app.
# That address is compiled into every build. Do not change it.
# The zip and the disk images are GitHub Release assets. Sparkle downloads
# the zip. The website's "latest" link uses Beacon.dmg.
#
# A real run must be on main, with a clean tree apart from project.yml.
# --dry-run restores the build number on the way out, including on failure.
set -euo pipefail
cd "$(dirname "$0")"
ROOT="$PWD"

SPARKLE_VER="2.10.0"
REPO="Avivhdr/beacon"
DIST="dist"
SITE="https://beacon-for-github.vercel.app"
TAP_DIR="${BEACON_TAP:-$ROOT/dist/homebrew-tap}"

DRY_RUN=false
[ "${1:-}" = "--dry-run" ] && DRY_RUN=true

# --- 0. preflight -------------------------------------------------------------
if ! $DRY_RUN; then
  BRANCH="$(git rev-parse --abbrev-ref HEAD)"
  [ "$BRANCH" = "main" ] || { echo "!! On '$BRANCH'. Release from main."; exit 1; }
  UNRELATED="$(git status --porcelain | grep -vE '^( M|M |MM) project\.yml$' || true)"
  [ -z "$UNRELATED" ] || {
    echo "!! Working tree has changes beyond project.yml. Commit or stash them first."
    echo "$UNRELATED"
    exit 1
  }
fi

# --- 1. Sparkle tools ---------------------------------------------------------
TOOLS="$ROOT/.sparkle-tools/${SPARKLE_VER}"
GEN_APPCAST="$TOOLS/bin/generate_appcast"
if [ ! -x "$GEN_APPCAST" ]; then
  echo "==> Fetching Sparkle ${SPARKLE_VER} tools…"
  mkdir -p "$TOOLS"
  curl -fsSL "https://github.com/sparkle-project/Sparkle/releases/download/${SPARKLE_VER}/Sparkle-${SPARKLE_VER}.tar.xz" \
    | tar -xJ -C "$TOOLS"
fi

# --- 2. version + build number ------------------------------------------------
VERSION="$(grep -Eo 'MARKETING_VERSION:[[:space:]]*"[^"]+"' project.yml \
  | head -1 | sed -E 's/.*"([^"]+)".*/\1/')"
[ -n "$VERSION" ] || { echo "!! Could not read MARKETING_VERSION from project.yml"; exit 1; }
TAG="v${VERSION}"

if ! $DRY_RUN; then
  if gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1; then
    echo "!! Release $TAG already exists. Bump MARKETING_VERSION in project.yml and retry."
    exit 1
  fi
fi

OLD_BUILD="$(grep -Eo 'CURRENT_PROJECT_VERSION:[[:space:]]*"[0-9]+"' project.yml \
  | head -1 | sed -E 's/.*"([0-9]+)".*/\1/')"
OLD_BUILD="${OLD_BUILD:-0}"
NEW_BUILD=$((OLD_BUILD + 1))
echo "==> Releasing Beacon ${VERSION} (build ${OLD_BUILD} -> ${NEW_BUILD})"

set_build_number() {
  sed -i '' -E "s/(CURRENT_PROJECT_VERSION:[[:space:]]*\")[0-9]+(\")/\1${1}\2/" project.yml
}
# The build number is compiled into the app. A dry run still needs the bump,
# and the trap puts the committed number back even when packaging fails.
if $DRY_RUN; then
  trap 'set_build_number "$OLD_BUILD"' EXIT
fi
set_build_number "$NEW_BUILD"

# --- 3. signed app + disk image ----------------------------------------------
echo "==> Building universal Release app and disk image…"
./package.sh

APP="build/Build/Products/Release/Beacon.app"
HUMAN_DMG="$DIST/Beacon-${VERSION}.dmg"
[ -d "$APP" ] || { echo "!! Build did not produce $APP"; exit 1; }
[ -f "$HUMAN_DMG" ] || { echo "!! Build did not produce $HUMAN_DMG"; exit 1; }

# --- 4. Sparkle zip + appcast -------------------------------------------------
# Keep the bundle at the archive root. Sparkle rejects a zip that wraps it
# in an extra folder. --sequesterRsrc keeps Finder resource forks out of the
# archive; those bytes change the signature.
STAGE="$(mktemp -d)"
UPDATE_ZIP_NAME="Beacon-${VERSION}.zip"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$STAGE/$UPDATE_ZIP_NAME"

NOTES="$STAGE/Beacon-${VERSION}.html"
awk -v ver="$VERSION" '
  $0 ~ "^## " ver "( |$)" { found=1; next }
  found && /^## / { exit }
  found { print }
' CHANGELOG.md > "$STAGE/notes.md"
[ -s "$STAGE/notes.md" ] || { echo "!! CHANGELOG.md has no section for ${VERSION}"; exit 1; }
./scripts/notes-to-html.sh < "$STAGE/notes.md" > "$NOTES"

DOWNLOAD_PREFIX="https://github.com/${REPO}/releases/download/${TAG}/"
echo "==> Signing the update and writing the appcast…"
"$GEN_APPCAST" \
  --account beacon \
  --download-url-prefix "$DOWNLOAD_PREFIX" \
  --embed-release-notes \
  --link "$SITE" \
  "$STAGE"
[ -f "$STAGE/appcast.xml" ] || { echo "!! generate_appcast did not write appcast.xml"; exit 1; }

mkdir -p "$DIST"
cp "$STAGE/$UPDATE_ZIP_NAME" "$DIST/$UPDATE_ZIP_NAME"
cp "$STAGE/appcast.xml" "$DIST/appcast.xml"
if ! $DRY_RUN; then
  cp "$STAGE/appcast.xml" web/appcast.xml
fi

echo
echo "==> Appcast:"
sed -e 's/^/    /' "$DIST/appcast.xml"
echo

# --- 5. publish ---------------------------------------------------------------
if $DRY_RUN; then
  echo "==> DRY RUN complete. Nothing committed or published."
  ls -lh "$DIST/appcast.xml" "$DIST/$UPDATE_ZIP_NAME" "$HUMAN_DMG"
  exit 0
fi

echo "==> Creating GitHub release ${TAG}…"
# The site links to releases/latest/download/Beacon.dmg, so the same disk
# image is uploaded under that stable name as well as the versioned name.
STABLE_DMG="$DIST/Beacon.dmg"
cp "$HUMAN_DMG" "$STABLE_DMG"
gh release create "$TAG" \
  "$DIST/$UPDATE_ZIP_NAME" \
  "$HUMAN_DMG" \
  "$STABLE_DMG" \
  --repo "$REPO" \
  --title "Beacon ${VERSION}" \
  --notes-file "$STAGE/notes.md"

echo "==> Committing the feed and pushing main…"
git add project.yml web/appcast.xml
git commit -m "release: ${TAG} (build ${NEW_BUILD})"
git push origin HEAD:main

echo "==> Waiting for ${SITE}/appcast.xml to serve build ${NEW_BUILD}…"
LIVE=false
for _ in $(seq 1 60); do
  if curl -fsS --max-time 10 "${SITE}/appcast.xml" 2>/dev/null \
      | grep -q "<sparkle:version>${NEW_BUILD}</sparkle:version>"; then
    LIVE=true
    break
  fi
  sleep 5
done
if ! $LIVE; then
  echo "!! The feed did not show build ${NEW_BUILD} within 5 minutes."
  exit 1
fi
echo "    Feed is live."

ENCLOSURE="$(sed -nE 's/.*url="([^"]+)".*/\1/p' web/appcast.xml | head -1)"
FEED_LENGTH="$(sed -nE 's/.*length="([0-9]+)".*/\1/p' web/appcast.xml | head -1)"
[ -n "$ENCLOSURE" ] && [ -n "$FEED_LENGTH" ] || { echo "!! Appcast has no enclosure."; exit 1; }

ACTUAL="$(curl -fsSL --max-time 120 -o /dev/null -w '%{http_code} %{size_download}' "$ENCLOSURE" || true)"
HTTP_CODE="${ACTUAL%% *}"
BYTE_COUNT="${ACTUAL##* }"
echo "    Enclosure: HTTP ${HTTP_CODE:-unreachable}, ${BYTE_COUNT:-0} bytes, feed length ${FEED_LENGTH}"
[ "$HTTP_CODE" = "200" ] && [ "$BYTE_COUNT" = "$FEED_LENGTH" ] || {
  echo "!! Enclosure check failed."
  exit 1
}

LATEST_CODE="$(curl -fsSL -o /dev/null -w '%{http_code}' --max-time 60 \
  "https://github.com/${REPO}/releases/latest/download/Beacon.dmg" || true)"
echo "    Beacon.dmg: HTTP ${LATEST_CODE:-unreachable}"
[ "$LATEST_CODE" = "200" ] || { echo "!! releases/latest/download/Beacon.dmg did not return 200."; exit 1; }

# --- 6. Homebrew cask ---------------------------------------------------------
CASK="$TAP_DIR/Casks/beacon.rb"
if [ ! -f "$CASK" ]; then
  echo "!! No cask at $CASK. Prepare it (Phase 7) or set BEACON_TAP."
  exit 1
fi
SHA="$(shasum -a 256 "$HUMAN_DMG" | awk '{print $1}')"
sed -i '' -E "s/^(  version \").*(\")/\1${VERSION}\2/" "$CASK"
sed -i '' -E "s/^(  sha256 \").*(\")/\1${SHA}\2/" "$CASK"
echo "==> Cask is ${VERSION} (${SHA})"
if [ -d "$TAP_DIR/.git" ]; then
  git -C "$TAP_DIR" add Casks/beacon.rb
  git -C "$TAP_DIR" commit -m "beacon ${VERSION}"
  git -C "$TAP_DIR" push
  echo "    Tap pushed."
else
  echo "!! Cask file updated, but $TAP_DIR is not a git checkout to push."
  exit 1
fi

echo
echo "==> Published Beacon ${VERSION} (build ${NEW_BUILD})."
echo "    Feed:     ${SITE}/appcast.xml"
echo "    Update:   ${ENCLOSURE}"
echo "    Download: https://github.com/${REPO}/releases/latest/download/Beacon.dmg"
