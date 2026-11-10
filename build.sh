#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

APP_BUNDLE="Pennyworth.app"
BINARY_PATH=".build/release/Pennyworth"
RESOURCE_BUNDLE=".build/release/Pennyworth_Pennyworth.bundle"

echo "▶ swift build (release)"
swift build -c release

echo "▶ Packaging $APP_BUNDLE"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"
cp "$BINARY_PATH" "$APP_BUNDLE/Contents/MacOS/Pennyworth"
cp Info.plist "$APP_BUNDLE/Contents/Info.plist"
cp -R "$RESOURCE_BUNDLE" "$APP_BUNDLE/Contents/Resources/"

echo "✅ Done → $(pwd)/$APP_BUNDLE"
echo "   Run: open $APP_BUNDLE  (then press ⌥Space to summon)"
