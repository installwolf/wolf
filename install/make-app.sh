#!/bin/bash
# Bundles the WolfBar executable into a proper Wolf.app menu-bar app.
# Usage: ./install/make-app.sh [dest-dir]   (default /Applications)
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
DEST="${1:-/Applications}"
APP="$DEST/Wolf.app"

echo "==> Building release"
# Always build as the invoking (non-root) user so .build never gets root-owned
# artifacts that break the next build. -H points SwiftPM caches at their home.
BUILD_USER="${SUDO_USER:-$(id -un)}"
if [ "$(id -u)" -eq 0 ] && [ -n "${SUDO_USER:-}" ]; then
    chown -R "$BUILD_USER" "$REPO/.build" 2>/dev/null || true
    sudo -u "$BUILD_USER" -H bash -lc "cd '$REPO' && swift build -c release"
else
    (cd "$REPO" && swift build -c release)
fi

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$REPO/.build/release/WolfBar" "$APP/Contents/MacOS/Wolf"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>               <string>Wolf</string>
    <key>CFBundleDisplayName</key>        <string>Wolf</string>
    <key>CFBundleIdentifier</key>         <string>com.wolf.menubar</string>
    <key>CFBundleExecutable</key>         <string>Wolf</string>
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
