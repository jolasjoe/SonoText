#!/usr/bin/env bash
# Run the same steps as the Release DMG GitHub Action locally.
# Use this to verify the build and DMG creation work before relying on CI.
# Does not upload to any release; outputs a .dmg in the output/ folder.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$ROOT_DIR/SonoText"
BUILD_DIR="$ROOT_DIR/.build-release"
BUNDLE_DIR="${RUNNER_TEMP:-/tmp}/SonoText-release.app"
DMG_NAME="${1:-SonoText-local.dmg}"
OUTPUT_DIR="$ROOT_DIR/output"
OUTPUT_DMG="$OUTPUT_DIR/$DMG_NAME"
mkdir -p "$OUTPUT_DIR"

# Use a dedicated build dir the current user owns (avoids permission errors when SonoText/.build was created by root).
echo "Build release binary..."
(cd "$APP_DIR" && swift build -c release --build-path "$BUILD_DIR")

BINARY_PATH=$(find "$BUILD_DIR" -maxdepth 5 -type f -name SonoText 2>/dev/null | head -1)
if [[ -z "$BINARY_PATH" || ! -x "$BINARY_PATH" ]]; then
  echo "Built binary not found under $BUILD_DIR" >&2
  exit 1
fi

echo "Create app bundle at $BUNDLE_DIR..."
rm -rf "$BUNDLE_DIR"
mkdir -p "$BUNDLE_DIR/Contents/MacOS"
cp "$BINARY_PATH" "$BUNDLE_DIR/Contents/MacOS/SonoText"
chmod +x "$BUNDLE_DIR/Contents/MacOS/SonoText"
cp "$APP_DIR/Resources/Info.plist" "$BUNDLE_DIR/Contents/Info.plist"

echo "Ad-hoc sign app bundle..."
codesign --force --deep --sign - "$BUNDLE_DIR"

echo "Create DMG: $OUTPUT_DMG..."
rm -f "$OUTPUT_DMG"
DMG_STAGING="${RUNNER_TEMP:-/tmp}/dmg-staging-$$"
mkdir -p "$DMG_STAGING"
cp -R "$BUNDLE_DIR" "$DMG_STAGING/SonoText.app"
ln -s /Applications "$DMG_STAGING/Applications"
hdiutil create -volname "SonoText" -srcfolder "$DMG_STAGING" -ov -format UDZO "$OUTPUT_DMG"
rm -rf "$DMG_STAGING"

echo "Done. DMG: $OUTPUT_DMG"
