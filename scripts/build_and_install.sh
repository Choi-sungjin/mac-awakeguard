#!/bin/bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$PROJECT_ROOT/build"
APP_NAME="HeraAwakeGuard"
INSTALL_HOME="${INSTALL_HOME:-$HOME}"
APP_BUNDLE="$INSTALL_HOME/Applications/${APP_NAME}.app"
BIN_DIR="$APP_BUNDLE/Contents/MacOS"
RESOURCES_DIR="$APP_BUNDLE/Contents/Resources"

mkdir -p "$BUILD_DIR" "$BIN_DIR" "$RESOURCES_DIR"

swiftc \
  -O \
  -framework AppKit \
  -framework IOKit \
  "$PROJECT_ROOT"/Sources/main.swift \
  -o "$BUILD_DIR/$APP_NAME"

cp "$BUILD_DIR/$APP_NAME" "$BIN_DIR/$APP_NAME"
cp "$PROJECT_ROOT/resources/Info.plist" "$APP_BUNDLE/Contents/Info.plist"
cp "$PROJECT_ROOT/usage.html" "$RESOURCES_DIR/usage.html"
if [ -f "$PROJECT_ROOT/resources/${APP_NAME}.icns" ]; then
  cp "$PROJECT_ROOT/resources/${APP_NAME}.icns" "$RESOURCES_DIR/${APP_NAME}.icns"
elif [ -d "$PROJECT_ROOT/${APP_NAME}.iconset" ]; then
  iconutil -c icns "$PROJECT_ROOT/${APP_NAME}.iconset" -o "$RESOURCES_DIR/${APP_NAME}.icns"
fi

chmod +x "$BIN_DIR/$APP_NAME"

if command -v codesign >/dev/null 2>&1; then
  codesign --force --deep --sign - "$APP_BUNDLE" >/dev/null 2>&1 || true
fi

echo "Installed $APP_BUNDLE"
