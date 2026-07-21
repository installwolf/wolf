#!/bin/bash
# Wolf installer. Builds release binaries, installs the CLI + root watchdog,
# wires up the pf anchor, and starts the LaunchDaemon. Run with sudo.
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
    echo "error: run with sudo — this installs a root LaunchDaemon." >&2
    exit 1
fi

REPO="$(cd "$(dirname "$0")/.." && pwd)"
PLIST="/Library/LaunchDaemons/com.wolf.daemon.plist"
PF_CONF="/etc/pf.conf"
PF_ANCHOR="/etc/pf.anchors/wolf"

echo "==> Building release binaries"
BUILD_USER="${SUDO_USER:-root}"
# Heal any root-owned artifacts from an earlier run so the user build can write
# (EPERM otherwise). Then build as the invoking user, HOME set for SwiftPM caches.
[ -d "$REPO/.build" ] && chown -R "$BUILD_USER" "$REPO/.build" 2>/dev/null || true
sudo -u "$BUILD_USER" -H bash -lc "cd '$REPO' && swift build -c release"
BIN="$REPO/.build/release"

echo "==> Installing binaries"
install -d /usr/local/bin /usr/local/sbin
install -m 755 "$BIN/wolf"  /usr/local/bin/wolf
install -m 755 "$BIN/wolfd" /usr/local/sbin/wolfd

echo "==> Creating state directory"
install -d -m 755 "/Library/Application Support/Wolf"

echo "==> Wiring pf anchor (so blocks survive reboot)"
install -d /etc/pf.anchors
[[ -f "$PF_ANCHOR" ]] || echo "# managed by wolf" > "$PF_ANCHOR"
if ! grep -q 'anchor "wolf"' "$PF_CONF" 2>/dev/null; then
    cp "$PF_CONF" "${PF_CONF}.wolf-backup" 2>/dev/null || true
    {
        echo ''
        echo 'anchor "wolf"'
        echo "load anchor \"wolf\" from \"$PF_ANCHOR\""
    } >> "$PF_CONF"
fi

echo "==> Installing the menu-bar app"
"$REPO/install/make-app.sh" /Applications >/dev/null

echo "==> Installing and starting the watchdog daemon"
install -m 644 "$REPO/install/com.wolf.daemon.plist" "$PLIST"
launchctl bootout system "$PLIST" 2>/dev/null || true
launchctl bootstrap system "$PLIST"
launchctl enable system/com.wolf.daemon

echo ""
echo "Wolf is installed and the watchdog is running."
echo ""
echo "Next steps:"
echo "  1. Have your accountability partner set the passphrase (you should NOT watch):"
echo "       sudo wolf set-passphrase"
echo "  2. Block sites (no sudo needed — the daemon handles it):"
echo "       wolf add pornhub.com xvideos.com"
echo "  3. Check status any time (or use the menu-bar app):"
echo "       wolf status"
echo "       open /Applications/Wolf.app"
