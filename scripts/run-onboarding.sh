#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$ROOT_DIR/SonoText"
MODEL_DIR="$HOME/Library/Application Support/SonoText/Models"
BUNDLE_DIR="/Applications/SonoText.app"
BUNDLE_CONTENTS_DIR="$BUNDLE_DIR/Contents"
BUNDLE_MACOS_DIR="$BUNDLE_CONTENTS_DIR/MacOS"
BUNDLE_PLIST_PATH="$BUNDLE_CONTENTS_DIR/Info.plist"
SOURCE_PLIST_PATH="$APP_DIR/Resources/Info.plist"
BUILD_DIR="$ROOT_DIR/.build-onboarding"
BINARY_PATH="$APP_DIR/.build/release/SonoText"

FULL_RESET=0
REBIRTH_RESET=0

usage() {
  echo "Usage: $(basename "$0") [--full] [--rebirth]"
  echo
  echo "  --full   Also remove local Whisper models to replay download onboarding."
  echo "  --rebirth  Full reset + reset TCC permissions (Microphone/Accessibility/Input Monitoring/Automation)."
}

for arg in "$@"; do
  case "$arg" in
    --full)
      FULL_RESET=1
      ;;
    --rebirth)
      FULL_RESET=1
      REBIRTH_RESET=1
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

if ! command -v swift >/dev/null 2>&1; then
  echo "swift not found in PATH. Install Xcode Command Line Tools or Swift toolchain." >&2
  exit 1
fi

if [[ ! -f "$SOURCE_PLIST_PATH" ]]; then
  echo "Info.plist source file not found: $SOURCE_PLIST_PATH" >&2
  exit 1
fi

if [[ ! -w "/Applications" ]]; then
  echo "No write permission to /Applications. Re-run with sudo:" >&2
  echo "  sudo ./scripts/run-onboarding.sh [--full|--rebirth]" >&2
  exit 1
fi

echo "Stopping any running SonoText process..."
pkill -x SonoText >/dev/null 2>&1 || true

echo "Resetting onboarding flag..."
defaults delete com.sonotext.mac onboarding_complete >/dev/null 2>&1 || true
defaults delete SonoText onboarding_complete >/dev/null 2>&1 || true
if [[ -n "${SUDO_USER:-}" ]]; then
  sudo -u "$SUDO_USER" defaults delete com.sonotext.mac onboarding_complete >/dev/null 2>&1 || true
  sudo -u "$SUDO_USER" defaults delete SonoText onboarding_complete >/dev/null 2>&1 || true
fi

if [[ "$FULL_RESET" -eq 1 ]]; then
  echo "Removing local Whisper models for full first-run onboarding..."
  rm -rf "$MODEL_DIR"
fi

if [[ "$REBIRTH_RESET" -eq 1 ]]; then
  if ! command -v tccutil >/dev/null 2>&1; then
    echo "tccutil not found; skipping TCC permission reset." >&2
  else
    echo "Resetting TCC permissions for com.sonotext.mac..."
    tccutil reset Microphone com.sonotext.mac >/dev/null 2>&1 || true
    tccutil reset Accessibility com.sonotext.mac >/dev/null 2>&1 || true
    tccutil reset ListenEvent com.sonotext.mac >/dev/null 2>&1 || true
    tccutil reset AppleEvents com.sonotext.mac >/dev/null 2>&1 || true
  fi
fi

echo "Preparing clean release build..."
(
  cd "$APP_DIR"
  swift package clean 2>/dev/null || true
)
rm -rf "$BUILD_DIR"
echo "Building release executable..."
(
  cd "$APP_DIR"
  swift build -c release --build-path "$BUILD_DIR"
)
BINARY_PATH=$(find "$BUILD_DIR" -maxdepth 5 -type f -name SonoText 2>/dev/null | head -1)
if [[ -z "$BINARY_PATH" ]]; then
  BINARY_PATH="$BUILD_DIR/arm64-apple-macosx/release/SonoText"
fi

if [[ ! -x "$BINARY_PATH" ]]; then
  echo "Built executable not found: $BINARY_PATH" >&2
  exit 1
fi

echo "Assembling app bundle at $BUNDLE_DIR"
rm -rf "$BUNDLE_DIR"
mkdir -p "$BUNDLE_MACOS_DIR"
cp "$BINARY_PATH" "$BUNDLE_MACOS_DIR/SonoText"
chmod +x "$BUNDLE_MACOS_DIR/SonoText"
cp "$SOURCE_PLIST_PATH" "$BUNDLE_PLIST_PATH"

if command -v codesign >/dev/null 2>&1; then
  echo "Signing app bundle (ad-hoc)..."
  codesign --force --deep --sign - "$BUNDLE_DIR"
fi

echo "Launching app bundle..."
open "$BUNDLE_DIR"
