#!/usr/bin/env bash
# Run the same steps as the Release DMG GitHub Action locally.
# Use this to verify the build and DMG creation work before relying on CI.
# Does not upload to any release; outputs a .dmg in the repo root.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$ROOT_DIR/SonoText"
BUILD_DIR="$ROOT_DIR/.build-release"
BUNDLE_DIR="${RUNNER_TEMP:-/tmp}/SonoText-release.app"
DMG_NAME="${1:-SonoText-local.dmg}"
OUTPUT_DMG="$ROOT_DIR/$DMG_NAME"

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
hdiutil create -volname "SonoText" -srcfolder "$BUNDLE_DIR" -ov -format UDZO "$OUTPUT_DMG"

echo "Done. DMG: $OUTPUT_DMG"
