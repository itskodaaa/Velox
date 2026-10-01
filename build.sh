#!/usr/bin/env bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$DIR/Velox.app"

echo "==> Compiling native Swift 6.4 macOS 27 binary..."
swiftc -O -target arm64-apple-macosx27.0 -sdk "$(xcrun --show-sdk-path)" \
  "$DIR/Sources/main.swift" \
  -o "$DIR/Velox_bin"

echo "==> Creating macOS App Bundle..."
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$DIR/Velox_bin" "$APP_DIR/Contents/MacOS/Velox"
cp "$DIR/Info.plist" "$APP_DIR/Contents/Info.plist"
if [ -f "$DIR/AppIcon.icns" ]; then
  cp "$DIR/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
fi
chmod +x "$APP_DIR/Contents/MacOS/Velox"
chmod +x "$DIR/parakeet_daemon.py"

SIGN_ID=$(security find-identity -v -p codesigning 2>/dev/null | grep "Joshua Umahi" | head -n 1 | awk -F '"' '{print $2}')
if [ -z "$SIGN_ID" ]; then
  SIGN_ID=$(security find-identity -v -p codesigning 2>/dev/null | grep "Apple Development" | head -n 1 | awk -F '"' '{print $2}')
fi
if [ -z "$SIGN_ID" ]; then
  SIGN_ID="-"
fi

echo "==> Code signing bundle with identity: $SIGN_ID..."
codesign --force --deep --sign "$SIGN_ID" --identifier "com.velox.app" "$APP_DIR"

echo "==> Installing to /Applications/Velox.app..."
pkill -f ParakeetFlow 2>/dev/null || true
pkill -f Velox 2>/dev/null || true
rm -rf /Applications/ParakeetFlow.app /Applications/Velox.app 2>/dev/null || true
cp -R "$APP_DIR" /Applications/Velox.app
ln -sf /Applications/Velox.app /Applications/ParakeetFlow.app
codesign --force --deep --sign "$SIGN_ID" --identifier "com.velox.app" /Applications/Velox.app
touch /Applications/Velox.app
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f /Applications/Velox.app 2>/dev/null || true

echo "==> Velox installed and code-signed successfully at /Applications/Velox.app!"
