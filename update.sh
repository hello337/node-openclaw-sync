#!/usr/bin/env bash
#
# Pull latest changes and restart the timer. Run from the repo directory.
# After git pull: sudo ./update.sh
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

if [ -d .git ]; then
    git pull
fi

if [ "$(id -u)" -ne 0 ]; then
    echo "Run with sudo to restart timer: sudo ./update.sh" >&2
    exit 1
fi

systemctl restart openclaw-sync.timer
echo "Timer restarted."
