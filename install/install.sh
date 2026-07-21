#!/bin/bash
# Bulwark installer. Builds release binaries, installs the CLI + root watchdog,
# wires up the pf anchor, and starts the LaunchDaemon. Run with sudo.
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
    echo "error: run with sudo — this installs a root LaunchDaemon." >&2
    exit 1
fi

REPO="$(cd "$(dirname "$0")/.." && pwd)"
PLIST="/Library/LaunchDaemons/com.bulwark.daemon.plist"
PF_CONF="/etc/pf.conf"
PF_ANCHOR="/etc/pf.anchors/bulwark"

echo "==> Building release binaries"
# Build as the invoking user so SwiftPM caches land in their home, not root's.
sudo -u "${SUDO_USER:-root}" bash -lc "cd '$REPO' && swift build -c release"
BIN="$REPO/.build/release"

echo "==> Installing binaries"
install -d /usr/local/bin /usr/local/sbin
install -m 755 "$BIN/bulwark"  /usr/local/bin/bulwark
install -m 755 "$BIN/bulwarkd" /usr/local/sbin/bulwarkd

echo "==> Creating state directory"
install -d -m 755 "/Library/Application Support/Bulwark"

echo "==> Wiring pf anchor (so blocks survive reboot)"
install -d /etc/pf.anchors
[[ -f "$PF_ANCHOR" ]] || echo "# managed by bulwark" > "$PF_ANCHOR"
if ! grep -q 'anchor "bulwark"' "$PF_CONF" 2>/dev/null; then
    cp "$PF_CONF" "${PF_CONF}.bulwark-backup" 2>/dev/null || true
    {
        echo ''
        echo 'anchor "bulwark"'
        echo "load anchor \"bulwark\" from \"$PF_ANCHOR\""
    } >> "$PF_CONF"
fi

echo "==> Installing the menu-bar app"
"$REPO/install/make-app.sh" /Applications >/dev/null

echo "==> Installing and starting the watchdog daemon"
install -m 644 "$REPO/install/com.bulwark.daemon.plist" "$PLIST"
launchctl bootout system "$PLIST" 2>/dev/null || true
launchctl bootstrap system "$PLIST"
launchctl enable system/com.bulwark.daemon

echo ""
echo "Bulwark is installed and the watchdog is running."
echo ""
echo "Next steps:"
echo "  1. Have your accountability partner set the passphrase (you should NOT watch):"
echo "       sudo bulwark set-passphrase"
echo "  2. Block sites:"
echo "       sudo bulwark add pornhub.com xvideos.com"
echo "  3. Check status any time (or use the menu-bar app):"
echo "       bulwark status"
echo "       open /Applications/Bulwark.app"
