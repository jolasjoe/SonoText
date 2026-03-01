#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$ROOT_DIR/SonoText"
MODEL_DIR="$HOME/Library/Application Support/SonoText/Models"
BUNDLE_DIR="/Applications/SonoText.app"
BUNDLE_CONTENTS_DIR="$BUNDLE_DIR/Contents"
BUNDLE_MACOS_DIR="$BUNDLE_CONTENTS_DIR/MacOS"
BUNDLE_PLIST_PATH="$BUNDLE_CONTENTS_DIR/Info.plist"
BINARY_PATH="$APP_DIR/.build/release/SonoText"

FULL_RESET=0

usage() {
  echo "Usage: $(basename "$0") [--full]"
  echo
  echo "  --full   Also remove local Whisper models to replay download onboarding."
}

for arg in "$@"; do
  case "$arg" in
    --full)
      FULL_RESET=1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $arg" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ ! -d "$APP_DIR" ]]; then
  echo "Expected app directory not found: $APP_DIR" >&2
  exit 1
fi

echo "Stopping any running SonoText process..."
pkill -x SonoText >/dev/null 2>&1 || true

echo "Resetting onboarding flag..."
defaults delete com.sonotext.mac onboarding_complete >/dev/null 2>&1 || true
defaults delete SonoText onboarding_complete >/dev/null 2>&1 || true

if [[ "$FULL_RESET" -eq 1 ]]; then
  echo "Removing local Whisper models for full first-run onboarding..."
  rm -rf "$MODEL_DIR"
fi

echo "Preparing clean release build..."
(
  cd "$APP_DIR"
  swift package clean
) || true
rm -rf "$APP_DIR/.build"

echo "Building release executable..."
(
  cd "$APP_DIR"
  swift build -c release
)

if [[ ! -x "$BINARY_PATH" ]]; then
  echo "Built executable not found: $BINARY_PATH" >&2
  exit 1
fi

echo "Assembling app bundle at $BUNDLE_DIR"
rm -rf "$BUNDLE_DIR"
mkdir -p "$BUNDLE_MACOS_DIR"
cp "$BINARY_PATH" "$BUNDLE_MACOS_DIR/SonoText"
chmod +x "$BUNDLE_MACOS_DIR/SonoText"

cat > "$BUNDLE_PLIST_PATH" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>SonoText</string>
    <key>CFBundleIdentifier</key>
    <string>com.sonotext.mac</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>SonoText</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSMicrophoneUsageDescription</key>
    <string>SonoText needs microphone access to record your dictation.</string>
    <key>NSAppleEventsUsageDescription</key>
    <string>SonoText needs automation access to paste dictation into your active app.</string>
</dict>
</plist>
EOF

if command -v codesign >/dev/null 2>&1; then
  echo "Signing app bundle (ad-hoc)..."
  codesign --force --deep --sign - "$BUNDLE_DIR"
fi

echo "Launching app bundle..."
open "$BUNDLE_DIR"
