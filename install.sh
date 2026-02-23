#!/usr/bin/env bash
#
# Install openclaw-sync "in place": use the current (repo) directory as install dir.
# Creates env from env.example if needed, installs systemd units pointing here, enables timer.
# Run with sudo from the repo directory.
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$SCRIPT_DIR"

if [ "$(id -u)" -ne 0 ]; then
    echo "Run with sudo: sudo ./install.sh" >&2
    exit 1
fi

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

echo "Installing systemd units (install dir: $INSTALL_DIR) ..."
cat > /etc/systemd/system/openclaw-sync.service << EOF
[Unit]
Description=OpenClaw xNode sync (config + OAuth)
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
EnvironmentFile=-$INSTALL_DIR/env
ExecStart=$INSTALL_DIR/openclaw-sync
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
cp "$INSTALL_DIR/openclaw-sync.timer" /etc/systemd/system/
systemctl daemon-reload
systemctl enable openclaw-sync.timer
systemctl start openclaw-sync.timer

echo "Done. Timer runs every 10s. Check: systemctl status openclaw-sync.timer"
