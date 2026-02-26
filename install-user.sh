#!/usr/bin/env bash
#
# Install openclaw-sync for the current user (no root/sudo).
# Creates env from env.example if needed, installs systemd user units,
# enables the timer. Same idea as install.sh, but for non-root.
#
# Run from the repo directory: ./install-user.sh
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$SCRIPT_DIR"
USER_UNITS="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
mkdir -p "$USER_UNITS"

if [ "$(id -u)" -eq 0 ]; then
    echo "This script is for a normal user (no root). For system-wide install use: sudo ./install.sh" >&2
    exit 1
fi

for dep in jq openssl curl; do
    if ! command -v "$dep" &>/dev/null; then
        echo "Missing required dependency: $dep" >&2
        exit 1
    fi
done

if [ ! -x "$INSTALL_DIR/openclaw-sync" ]; then
    chmod +x "$INSTALL_DIR/openclaw-sync"
fi

if [ ! -f "$INSTALL_DIR/env" ]; then
    if [ -f "$INSTALL_DIR/env.example" ]; then
        cp "$INSTALL_DIR/env.example" "$INSTALL_DIR/env"
        echo "Created $INSTALL_DIR/env - edit it and set OPENCLAW_CONFIG_TOKEN."
    else
        touch "$INSTALL_DIR/env"
        echo "Created empty env — add OPENCLAW_CONFIG_TOKEN=your-token"
    fi
    chmod 600 "$INSTALL_DIR/env"
else
    echo "Using existing env"
fi

echo "Installing systemd user units (install dir: $INSTALL_DIR) ..."
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
systemctl --user enable openclaw-sync.timer
systemctl --user start openclaw-sync.timer

echo "Done. Timer runs every 10s (user systemd)."
echo "  Status: systemctl --user status openclaw-sync.timer"
echo "  Logs:   journalctl --user -u openclaw-sync.service -f"
echo "  Update: ./update-user.sh  (after git pull, no sudo)"
if ! loginctl show-user "$(whoami)" 2>/dev/null | grep -q 'Linger=yes'; then
    echo ""
    echo "To keep the timer running after you log out (e.g. over SSH), run once (needs root):"
    echo "  sudo loginctl enable-linger $(whoami)"
fi
