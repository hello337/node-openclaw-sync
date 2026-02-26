#!/usr/bin/env bash
#
# Update openclaw-sync and restart the user timer (for install-user.sh).
# Run from the repo directory. No root/sudo.
# After git pull: ./update-user.sh
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

if [ "$(id -u)" -eq 0 ]; then
    echo "This script is for a normal user (no root). For system-wide install use: sudo ./update.sh" >&2
    exit 1
fi

if [ -d .git ]; then
    git pull
fi

systemctl --user daemon-reload
systemctl --user restart openclaw-sync.timer
echo "User timer restarted."
echo "  Status: systemctl --user status openclaw-sync.timer"
echo "  Logs:   journalctl --user -u openclaw-sync.service -f"
