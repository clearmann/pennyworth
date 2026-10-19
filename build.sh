#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

APP_BUNDLE="Pennyworth.app"
BINARY_PATH=".build/release/Pennyworth"

echo "▶ swift build (release)"
swift build -c release

echo "▶ Packaging $APP_BUNDLE"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
cp "$BINARY_PATH" "$APP_BUNDLE/Contents/MacOS/Pennyworth"
cp Info.plist "$APP_BUNDLE/Contents/Info.plist"

echo "✅ Done → $(pwd)/$APP_BUNDLE"
echo "   Run: open $APP_BUNDLE  (then press ⌥Space to summon)"
