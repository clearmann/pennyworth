#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

APP_BUNDLE="${APP_BUNDLE-Pennyworth.app}"
BINARY_PATH=".build/release/Pennyworth"
RESOURCE_BUNDLE=".build/release/Pennyworth_Pennyworth.bundle"

case "$APP_BUNDLE" in
    *.app) ;;
    *) echo "APP_BUNDLE must name an .app directory" >&2; exit 1 ;;
esac
[[ "$APP_BUNDLE" = /* ]] || APP_BUNDLE="$PWD/$APP_BUNDLE"
if [[ -L "$APP_BUNDLE" || ( -e "$APP_BUNDLE" && "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP_BUNDLE/Contents/Info.plist" 2>/dev/null)" != "com.clearmann.pennyworth" ) ]]; then
    echo "Refusing to replace a symlink or non-Pennyworth bundle: $APP_BUNDLE" >&2
    exit 1
fi

echo "▶ swift build (release)"
swift build -c release

echo "▶ Packaging $APP_BUNDLE"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"
cp "$BINARY_PATH" "$APP_BUNDLE/Contents/MacOS/Pennyworth"
cp Info.plist "$APP_BUNDLE/Contents/Info.plist"
cp -R "$RESOURCE_BUNDLE" "$APP_BUNDLE/Contents/Resources/"

# Default ad-hoc signing cannot guarantee TCC permissions survive rebuilds.
# CODE_SIGN_IDENTITY may select an existing stable certificate; failures never fall back.
/usr/bin/codesign --force --sign "${CODE_SIGN_IDENTITY--}" "$APP_BUNDLE"
/usr/bin/codesign --verify --strict "$APP_BUNDLE"

echo "✅ Done → $APP_BUNDLE"
echo "   Run: open \"$APP_BUNDLE\"  (then press ⌥Space to summon)"
