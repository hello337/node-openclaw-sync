#!/usr/bin/env bash
#
# Update openclaw-sync: pull, reinstall user units (so env path is correct),
# stop any running run, restart timer. Run from the repo directory. No root/sudo.
# After changing env (token/API): ./update-user.sh
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$SCRIPT_DIR"
USER_UNITS="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
cd "$SCRIPT_DIR"

if [ "$(id -u)" -eq 0 ]; then
    echo "This script is for a normal user (no root). For system-wide install use: sudo ./update.sh" >&2
    exit 1
fi

if [ -d .git ]; then
    echo "Pulling latest changes..."
    git pull
fi

# Reinstall unit files so EnvironmentFile points to current INSTALL_DIR/env
mkdir -p "$USER_UNITS"
echo "Reinstalling user units (env: $INSTALL_DIR/env) ..."
cat > "$USER_UNITS/openclaw-sync.service" << EOF
[Unit]
Description=OpenClaw xNode sync (config + OAuth)
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
Environment=HOME=$HOME
EnvironmentFile=-$INSTALL_DIR/env
ExecStart=$INSTALL_DIR/openclaw-sync
StandardOutput=journal
StandardError=journal
EOF

cat > "$USER_UNITS/openclaw-sync.timer" << EOF
[Unit]
Description=Run OpenClaw xNode sync every 10 seconds

[Timer]
OnBootSec=30
OnUnitActiveSec=10
Persistent=true
AccuracySec=1s

[Install]
WantedBy=timers.target
EOF

systemctl --user daemon-reload
# Stop current run so next run loads fresh env (token/API)
systemctl --user stop openclaw-sync.service 2>/dev/null || true
systemctl --user restart openclaw-sync.timer

echo "Done. Timer restarted; next run will use env from $INSTALL_DIR/env"
if [ -f "$INSTALL_DIR/env" ]; then
    _api="$(grep -E '^OPENCLAW_API_BASE=' "$INSTALL_DIR/env" 2>/dev/null | cut -d= -f2- | tr -d '"')"
    [ -n "$_api" ] && echo "  OPENCLAW_API_BASE=$_api"
fi
echo "  Status: systemctl --user status openclaw-sync.timer"
echo "  Logs:   journalctl --user -u openclaw-sync.service -f"
