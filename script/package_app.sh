#!/usr/bin/env bash
set -euo pipefail

CONFIGURATION="release"
if [[ "${1:-}" == "--debug" ]]; then
  CONFIGURATION="debug"
elif [[ -n "${1:-}" ]]; then
  echo "usage: $0 [--debug]" >&2
  exit 2
fi

PROCESS_NAME="TimbreCanvas"
DISPLAY_NAME="TimbreCanvas"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACKAGE_DIR="$ROOT_DIR/App"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$DISPLAY_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"

swift build --package-path "$PACKAGE_DIR" -c "$CONFIGURATION"
BIN_DIR="$(swift build --package-path "$PACKAGE_DIR" -c "$CONFIGURATION" --show-bin-path)"
BUILD_BINARY="$BIN_DIR/$PROCESS_NAME"
RESOURCE_BUNDLE="$BIN_DIR/TimbreCanvas_TimbreCanvas.bundle"

if [[ ! -x "$BUILD_BINARY" ]]; then
  echo "missing app executable: $BUILD_BINARY" >&2
  exit 1
fi
if [[ ! -d "$RESOURCE_BUNDLE" ]]; then
  echo "missing SwiftPM resource bundle: $RESOURCE_BUNDLE" >&2
  exit 1
fi

if [[ -d "$APP_BUNDLE" ]]; then
  rm -rf "$APP_BUNDLE"
fi
mkdir -p "$APP_MACOS" "$APP_RESOURCES"
cp "$BUILD_BINARY" "$APP_MACOS/$PROCESS_NAME"
cp -R "$RESOURCE_BUNDLE" "$APP_RESOURCES/TimbreCanvas_TimbreCanvas.bundle"
mkdir -p "$APP_RESOURCES/RuntimeHost"
rsync -a \
  --exclude '__pycache__' \
  --exclude '*.pyc' \
  "$ROOT_DIR/RuntimeHost/timbrecanvas_runtime/" \
  "$APP_RESOURCES/RuntimeHost/timbrecanvas_runtime/"
cp "$PACKAGE_DIR/Resources/Info.plist" "$APP_CONTENTS/Info.plist"
cp "$PACKAGE_DIR/Resources/AppIcon.icns" "$APP_RESOURCES/AppIcon.icns"
chmod +x "$APP_MACOS/$PROCESS_NAME"

plutil -lint "$APP_CONTENTS/Info.plist" >/dev/null
codesign --force --deep --sign - "$APP_BUNDLE"
codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"

echo "$APP_BUNDLE"
