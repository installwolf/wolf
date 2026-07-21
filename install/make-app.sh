#!/bin/bash
# Bundles the BulwarkBar executable into a proper Bulwark.app menu-bar app.
# Usage: ./install/make-app.sh [dest-dir]   (default /Applications)
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
DEST="${1:-/Applications}"
APP="$DEST/Bulwark.app"

echo "==> Building release"
(cd "$REPO" && swift build -c release)

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$REPO/.build/release/BulwarkBar" "$APP/Contents/MacOS/Bulwark"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>               <string>Bulwark</string>
    <key>CFBundleDisplayName</key>        <string>Bulwark</string>
    <key>CFBundleIdentifier</key>         <string>com.bulwark.menubar</string>
    <key>CFBundleExecutable</key>         <string>Bulwark</string>
    <key>CFBundleVersion</key>            <string>1.0</string>
    <key>CFBundleShortVersionString</key> <string>1.0</string>
    <key>CFBundlePackageType</key>        <string>APPL</string>
    <key>LSMinimumSystemVersion</key>     <string>13.0</string>
    <key>LSUIElement</key>                <true/>
</dict>
</plist>
PLIST

# Ad-hoc sign so Gatekeeper/TCC treat it as a stable identity on this machine.
codesign --force --deep --sign - "$APP" 2>/dev/null || true

echo "Done. Launch it with:  open \"$APP\""
echo "(To start at login: System Settings ▸ General ▸ Login Items ▸ +)"
