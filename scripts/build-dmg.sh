#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$ROOT_DIR/SonoText"
DIST_DIR="$ROOT_DIR/output"
STAGING_DIR="$DIST_DIR/dmg-root"
APP_BUNDLE="$STAGING_DIR/SonoText.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_BINARY="$APP_MACOS/SonoText"
SOURCE_PLIST="$APP_DIR/Resources/Info.plist"
TARGET_PLIST="$APP_CONTENTS/Info.plist"
SCRATCH_DIR="$ROOT_DIR/.swift-build"
BUILT_BINARY="$SCRATCH_DIR/arm64-apple-macosx/release/SonoText"

if [[ ! -d "$APP_DIR" ]]; then
  echo "Expected app directory not found: $APP_DIR" >&2
  exit 1
fi

if [[ ! -f "$SOURCE_PLIST" ]]; then
  echo "Info.plist source file not found: $SOURCE_PLIST" >&2
  exit 1
fi

if ! command -v swift >/dev/null 2>&1; then
  echo "swift not found in PATH. Install Xcode Command Line Tools or Swift toolchain." >&2
  exit 1
fi

if ! command -v hdiutil >/dev/null 2>&1; then
  echo "hdiutil not found. This script must run on macOS." >&2
  exit 1
fi

PRERELEASE_LABEL="${1:-}"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$SOURCE_PLIST")"
BUILD_NUMBER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$SOURCE_PLIST")"

DMG_BASENAME="SonoText-$VERSION"
if [[ -n "$PRERELEASE_LABEL" ]]; then
  DMG_BASENAME="$DMG_BASENAME-$PRERELEASE_LABEL"
fi
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

echo "Preparing DMG staging directory..."
rm -rf "$STAGING_DIR"
mkdir -p "$APP_MACOS"
cp "$BUILT_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"
cp "$SOURCE_PLIST" "$TARGET_PLIST"

if command -v codesign >/dev/null 2>&1; then
  echo "Signing app bundle (ad-hoc)..."
  codesign --force --deep --sign - "$APP_BUNDLE"
fi

ln -sfn /Applications "$STAGING_DIR/Applications"

echo "Creating DMG: $DMG_PATH"
rm -f "$DMG_PATH"
hdiutil create \
  -volname "SonoText $VERSION" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

echo
echo "DMG ready:"
echo "  $DMG_PATH"
echo "Version: $VERSION (build $BUILD_NUMBER)"
