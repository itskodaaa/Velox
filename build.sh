#!/usr/bin/env bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$DIR/.build"
APP_DIR="$BUILD_DIR/Mumblr.app"
BIN_PATH="$BUILD_DIR/Mumblr_bin"
mkdir -p "$BUILD_DIR"

echo "==> Compiling native Swift 6.4 macOS 27 binary..."
swiftc -O -target arm64-apple-macosx27.0 -sdk "$(xcrun --show-sdk-path)" \
  "$DIR/Sources/main.swift" \
  -o "$BIN_PATH"

echo "==> Creating macOS App Bundle..."
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BIN_PATH" "$APP_DIR/Contents/MacOS/Mumblr"
cp "$DIR/Info.plist" "$APP_DIR/Contents/Info.plist"
if [ -f "$DIR/AppIcon.icns" ]; then
  cp "$DIR/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
fi
if [ -d "$DIR/Resources" ]; then
  cp -R "$DIR/Resources/"* "$APP_DIR/Contents/Resources/" 2>/dev/null || true
fi
chmod +x "$APP_DIR/Contents/MacOS/Mumblr"
if [ -f "$DIR/mumblr_daemon.py" ]; then
  chmod +x "$DIR/mumblr_daemon.py"
fi

SIGN_ID=$(security find-identity -v -p codesigning 2>/dev/null | grep "Joshua Umahi" | head -n 1 | awk -F '"' '{print $2}')
if [ -z "$SIGN_ID" ]; then
  SIGN_ID=$(security find-identity -v -p codesigning 2>/dev/null | grep "Apple Development" | head -n 1 | awk -F '"' '{print $2}')
fi
if [ -z "$SIGN_ID" ]; then
  SIGN_ID="-"
fi

echo "==> Code signing bundle with identity: $SIGN_ID..."
codesign --force --deep --sign "$SIGN_ID" --identifier "com.mumblr.app" "$APP_DIR"

echo "==> Installing to /Applications/Mumblr.app..."
pkill -f Mumblr 2>/dev/null || true
pkill -f Velox 2>/dev/null || true
pkill -f ParakeetFlow 2>/dev/null || true
rm -rf /Applications/Mumblr.app /Applications/Velox.app /Applications/ParakeetFlow.app 2>/dev/null || true
cp -R "$APP_DIR" /Applications/Mumblr.app
codesign --force --deep --sign "$SIGN_ID" --identifier "com.mumblr.app" /Applications/Mumblr.app
touch /Applications/Mumblr.app
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f /Applications/Mumblr.app 2>/dev/null || true

echo "==> Mumblr installed and code-signed successfully at /Applications/Mumblr.app!"
