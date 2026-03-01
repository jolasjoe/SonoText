#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/build-dmg-release.sh [--prerelease <label>] [--skip-notarize]

Builds a release-grade DMG:
1) Builds release binary
2) Assembles SonoText.app
3) Signs app with Developer ID
4) Notarizes + staples app (unless --skip-notarize)
5) Creates DMG
6) Signs DMG
7) Notarizes + staples DMG (unless --skip-notarize)
8) Verifies DMG checksum and stapling

Required environment variables:
  DEVELOPER_ID_APPLICATION   Example: "Developer ID Application: Your Name (TEAMID)"

Required unless --skip-notarize:
  NOTARYTOOL_PROFILE         Keychain profile created via:
                             xcrun notarytool store-credentials "<profile>" \
                               --apple-id "<apple_id>" --team-id "<team_id>" --password "<app_specific_password>"
EOF
}

PRERELEASE_LABEL=""
SKIP_NOTARIZE=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --prerelease)
      if [[ $# -lt 2 ]]; then
        echo "--prerelease requires a value" >&2
        usage
        exit 1
      fi
      PRERELEASE_LABEL="$2"
      shift 2
      ;;
    --skip-notarize)
      SKIP_NOTARIZE=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      exit 1
      ;;
  esac
done

: "${DEVELOPER_ID_APPLICATION:?Set DEVELOPER_ID_APPLICATION to your Developer ID cert name}"
if [[ "$SKIP_NOTARIZE" -eq 0 ]]; then
  : "${NOTARYTOOL_PROFILE:?Set NOTARYTOOL_PROFILE (or pass --skip-notarize)}"
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$ROOT_DIR/SonoText"
DIST_DIR="$ROOT_DIR/output"
STAGING_DIR="$DIST_DIR/release-dmg-root"
APP_BUNDLE="$STAGING_DIR/SonoText.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_BINARY="$APP_MACOS/SonoText"
SOURCE_PLIST="$APP_DIR/Resources/Info.plist"
TARGET_PLIST="$APP_CONTENTS/Info.plist"
SCRATCH_DIR="$ROOT_DIR/.swift-build-release-dist"
BUILT_BINARY="$SCRATCH_DIR/arm64-apple-macosx/release/SonoText"

for cmd in swift hdiutil codesign xcrun ditto /usr/libexec/PlistBuddy; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Missing required command: $cmd" >&2
    exit 1
  fi
done

if [[ ! -d "$APP_DIR" ]]; then
  echo "Expected app directory not found: $APP_DIR" >&2
  exit 1
fi

if [[ ! -f "$SOURCE_PLIST" ]]; then
  echo "Info.plist source file not found: $SOURCE_PLIST" >&2
  exit 1
fi

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$SOURCE_PLIST")"
BUILD_NUMBER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$SOURCE_PLIST")"

DMG_BASENAME="SonoText-$VERSION"
if [[ -n "$PRERELEASE_LABEL" ]]; then
  DMG_BASENAME="$DMG_BASENAME-$PRERELEASE_LABEL"
fi

APP_ZIP_PATH="$DIST_DIR/$DMG_BASENAME-app-notary.zip"
DMG_PATH="$DIST_DIR/$DMG_BASENAME.dmg"

echo "Building release executable..."
(
  cd "$APP_DIR"
  swift build -c release --scratch-path "$SCRATCH_DIR"
)

if [[ ! -x "$BUILT_BINARY" ]]; then
  echo "Built executable not found: $BUILT_BINARY" >&2
  exit 1
fi

echo "Preparing app bundle..."
mkdir -p "$DIST_DIR"
rm -rf "$STAGING_DIR"
mkdir -p "$APP_MACOS"
cp "$BUILT_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"
cp "$SOURCE_PLIST" "$TARGET_PLIST"

echo "Signing app bundle with Developer ID..."
codesign --force --deep --timestamp --options runtime --sign "$DEVELOPER_ID_APPLICATION" "$APP_BUNDLE"
codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"

if [[ "$SKIP_NOTARIZE" -eq 0 ]]; then
  echo "Submitting app for notarization..."
  rm -f "$APP_ZIP_PATH"
  ditto -c -k --keepParent "$APP_BUNDLE" "$APP_ZIP_PATH"
  xcrun notarytool submit "$APP_ZIP_PATH" --keychain-profile "$NOTARYTOOL_PROFILE" --wait

  echo "Stapling app..."
  xcrun stapler staple "$APP_BUNDLE"
  xcrun stapler validate "$APP_BUNDLE"
else
  echo "Skipping notarization for app (--skip-notarize)."
fi

ln -sfn /Applications "$STAGING_DIR/Applications"

echo "Creating DMG..."
rm -f "$DMG_PATH"
hdiutil create \
  -volname "SonoText $VERSION" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

echo "Signing DMG..."
codesign --force --timestamp --sign "$DEVELOPER_ID_APPLICATION" "$DMG_PATH"
codesign --verify --verbose=2 "$DMG_PATH"

if [[ "$SKIP_NOTARIZE" -eq 0 ]]; then
  echo "Submitting DMG for notarization..."
  xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARYTOOL_PROFILE" --wait

  echo "Stapling DMG..."
  xcrun stapler staple "$DMG_PATH"
  xcrun stapler validate "$DMG_PATH"
else
  echo "Skipping notarization for DMG (--skip-notarize)."
fi

echo "Verifying DMG checksum..."
hdiutil verify "$DMG_PATH"

echo
echo "Release DMG ready:"
echo "  $DMG_PATH"
echo "Version: $VERSION (build $BUILD_NUMBER)"
if [[ "$SKIP_NOTARIZE" -eq 1 ]]; then
  echo "Notarization: skipped"
else
  echo "Notarization: app + DMG stapled"
fi
