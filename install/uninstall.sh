#!/bin/bash
# Wolf uninstaller. Intentionally routed through the removal gate: it refuses
# while sites are still blocked, so uninstalling can't be an impulse bypass.
# (A determined root user can edit this script — that's a documented residual
# limit; see DESIGN.md. The point is friction against a moment of weakness.)
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
    echo "error: run with sudo." >&2
    exit 1
fi

BLOCKED=$(/usr/local/bin/wolf status 2>/dev/null | grep -c '✗' || true)
if [[ "${BLOCKED:-0}" -gt 0 ]]; then
    echo "refusing to uninstall: $BLOCKED site(s) still blocked." >&2
    echo "Remove them first (this respects the cooldown / partner passphrase):" >&2
    echo "  sudo wolf remove <site>        # queues, unblocks after cooldown" >&2
    echo "  sudo wolf remove <site> --now  # instant, needs partner passphrase" >&2
    exit 1
fi

echo "==> Stopping daemon"
launchctl bootout system /Library/LaunchDaemons/com.wolf.daemon.plist 2>/dev/null || true

echo "==> Clearing immutable flags and removing files"
for f in "/Library/Application Support/Wolf/state.json" \
         "/Library/Application Support/Wolf/clock_floor" \
         /etc/pf.anchors/wolf /Library/LaunchDaemons/com.wolf.daemon.plist; do
    chflags noschg "$f" 2>/dev/null || true
done
rm -f /usr/local/bin/wolf /usr/local/sbin/wolfd
rm -f /Library/LaunchDaemons/com.wolf.daemon.plist
rm -rf "/Library/Application Support/Wolf"
rm -f /etc/pf.anchors/wolf

echo "Wolf removed. (Your /etc/hosts and /etc/pf.conf edits: review manually if desired.)"
