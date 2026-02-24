# node-openclaw-sync

Syncs config and OAuth between [xNode](https://xnode.pro) and a local [OpenClaw](https://docs.openclaw.ai) instance. Run on the server where OpenClaw is installed: it fetches settings from the xNode API and applies them (agents_defaults, tools_web_search, OAuth tokens, auth-link requests for device flow).

**Requirements on the server:** `curl`, `jq`, `script` (from util-linux), and `openclaw` in PATH.

**Provider plugins:** For "Get auth link" (OAuth/device flow), the script enables the right plugin per provider (see [OpenClaw docs](https://docs.openclaw.ai/concepts/model-providers)) and captures the URL to send to xNode. After the first enable of a plugin, **the script restarts the OpenClaw gateway** once so it loads. Then the script applies pasted tokens/URLs from the config and marks them consumed; `agents_defaults` from the API enables all models for the configured providers.

| xNode config key     | OpenClaw provider    | Plugin to enable (script does it) |
|----------------------|----------------------|-----------------------------------|
| openai_codex         | openai-codex         | (built-in)                        |
| google_antigravity   | google-antigravity   | google-antigravity-auth           |
| qwen_portal          | qwen-portal          | qwen-portal-auth                  |
| github_copilot       | github-copilot       | (built-in)                        |
| google_gemini_cli    | google-gemini-cli    | google-gemini-cli-auth            |
| minimax_portal       | minimax-portal       | minimax-portal-auth               |
| anthropic_setup_token| anthropic            | (paste-token, no plugin)          |

---

## First-time setup on the server

You don't need to use `/opt`. Clone the repo **wherever you like** (home dir, `/opt`, `/srv`); installation is in-place: systemd will run the script from that directory.

### 1. Clone the repository

```bash
git clone https://github.com/YOUR_USER/node-openclaw-sync.git
cd node-openclaw-sync
```

(Replace `YOUR_USER` with your GitHub username. The path can be anything, e.g. `~/node-openclaw-sync` or `/opt/node-openclaw-sync`.)

### 2. Set the token

Get the token from the xNode admin: **Pending Nodes** (or All Users Nodes) → your **OpenClaw** record → **Token** button → copy.

```bash
cp env.example env
nano env
```

In `env` set:

```
OPENCLAW_CONFIG_TOKEN=your-token-from-admin
```

Optionally, if the API is not at api.xnode.pro:

```
OPENCLAW_API_BASE=https://your-api-host
```

Save and exit.

### 3. Install and enable the timer

```bash
chmod +x install.sh
sudo ./install.sh
```

The script does not copy files elsewhere: it tells systemd to use **this directory** (the repo) and enables a timer that runs every **10 seconds**. On first run, `env` is created from `env.example` if it doesn't exist.

### 4. Verify

```bash
systemctl status openclaw-sync.timer
journalctl -u openclaw-sync.service -f
```

The timer should be `active`; logs should show no token or network errors.

---

## Deploying to a new server (checklist)

When you roll this out to each new server, do the following once per server:

1. **Install OpenClaw** on the server (gateway + CLI), start the gateway, ensure it listens on the chosen port (e.g. 18789).
2. **Clone this repo**, create `env` from `env.example`, set `OPENCLAW_CONFIG_TOKEN` (and optionally `OPENCLAW_API_BASE`). Run `sudo ./install.sh`.
3. **Pairing:** The script automatically sets `gateway.controlUi.allowInsecureAuth true` in the OpenClaw config, so CLI connections from localhost don't require manual pairing. This is safe when the gateway is bound to loopback (`127.0.0.1`). After first deploy, restart the gateway once so the setting takes effect: `openclaw gateway restart`.
4. Optionally run the sync once by hand to confirm: `./openclaw-sync`.

No need to repeat pairing unless you revoke the device or reinstall OpenClaw state.

**Security:** `allowInsecureAuth` disables device identity and pairing. Use only when the gateway is not exposed (loopback or trusted host). Do not use on a publicly reachable port.

---

## Updating: pull from GitHub and restart

Go to the repo directory, pull, then restart the timer:

```bash
cd /path/to/node-openclaw-sync   # wherever you cloned
sudo git pull
sudo systemctl restart openclaw-sync.timer
```

Or in one line (use your path):

```bash
cd ~/node-openclaw-sync && sudo git pull && sudo systemctl restart openclaw-sync.timer
```

The `env` file is not modified by `git pull` (it's in `.gitignore`).

**If the systemd unit changed** (e.g. new `Environment=` lines), re-run `sudo ./install.sh` after pull to regenerate the unit file and reload systemd.

**Using update.sh:**

```bash
cd /path/to/node-openclaw-sync
git pull
sudo ./update.sh
```

`update.sh` runs `git pull` and restarts the timer.

---

## What the script does

1. **GET /openclaw/config** — fetches config (env, oauth_pending, oauth_url_requests, agents_defaults, tools_web_search).
2. **agents_defaults + tools_web_search** — applies them via `openclaw gateway call config.patch` so all models for configured providers are enabled and Brave Search is set if present.
3. **oauth_url_requests** (user clicked "Get auth link" on the site): for each requested provider, the script enables the plugin if needed, runs `openclaw models auth login --provider <id>`, captures the auth URL from output, and sends it to xNode (**POST /openclaw/oauth-auth-url**). The frontend then shows the link; the user opens it, signs in, and pastes the callback URL back.
4. **oauth_pending** (user pasted token or callback URL): the script applies each value — `anthropic_setup_token` via `openclaw models auth paste-token --provider anthropic`, all other keys via `openclaw models auth login --provider <id>` with the value fed to stdin. Then it marks those keys as consumed (**POST /openclaw/oauth-consumed**). After that, agents_defaults from step 2 keeps all models for those providers enabled.

API keys (env) are only sent in the config; OpenClaw receives them through the same config.patch when agents_defaults is applied. No extra step needed for API-key-only providers.

Token and API base are read from the `env` file in the repo root (see `env.example`).

---

## Technical notes

### Pseudo-TTY for auth login

OpenClaw's CLI suppresses interactive output (device-code URLs, spinners) when stdout is not a TTY ([GitHub #13192](https://github.com/openclaw/openclaw/discussions/13192)). The sync script uses Linux `script -qec` to wrap `openclaw models auth login` in a pseudo-TTY, ensuring the URL is printed. ANSI escape codes are stripped from the captured output.

If `script` is not available or doesn't support the `-q -e -c` flags, the script falls back to plain `timeout` (which may not capture the URL — install `util-linux` to fix).

### Gateway restart behavior

When the script enables a new plugin and restarts the gateway, it exits immediately after `openclaw gateway start` (`exit 0`) and does NOT fetch the auth URL in the same run. The next timer tick (~10s) proceeds to Phase B. `openclaw gateway start` may return non-zero just because its internal health check times out with plugins loaded ([OpenClaw #22972](https://github.com/openclaw/openclaw/issues/22972)); the daemon is still starting.

A flag file (`/tmp/openclaw-sync-gateway-restarted`) with a 120-second cooldown prevents repeated restarts. After Phase B successfully captures and posts a URL, the flag file is cleaned up.

The systemd unit sets `Environment=XDG_RUNTIME_DIR=/run/user/0` so that `openclaw gateway start/stop` (which manage a user-level systemd service) work from within a system service context.

### Gateway health check

Before Phase B, the script runs `openclaw gateway health --timeout 10000`. If the gateway isn't healthy, the run exits gracefully. The next timer tick retries.

---

## Troubleshooting

### Viewing logs

```bash
journalctl -u openclaw-sync.service -n 200 --no-pager
journalctl -u openclaw-sync.service -f
```

The script logs the full raw output of `openclaw models auth login` to the journal. Look for `auth login raw output:` lines to see what the command produced.

### "auth login produced no output"

This means the pseudo-TTY wrapper (`script -qec`) either isn't available or didn't work. Check:

1. `script` is installed: `which script` (should be `/usr/bin/script` from `util-linux`).
2. Test it manually: `script -q -e -c "echo test" /dev/null` — should print "test".
3. If `script` doesn't support `-e -c` (very old distro), update `util-linux`.

### "no URL in output"

The auth login produced output, but no URL was found. Run manually on the server:

```bash
openclaw models auth login --provider qwen-portal
```

Check whether a URL is printed. If yes but the script can't capture it, the output format may have changed.

### "plugin not loaded"

The plugin is enabled in config but the running gateway hasn't loaded it yet. Restart the gateway:

```bash
openclaw gateway restart
```

### "Gateway is not healthy"

The gateway isn't responding. Check:

```bash
openclaw gateway status
openclaw gateway health
```

If not running, start it: `openclaw gateway start`. If it fails to start, check port conflicts: `lsof -nP -iTCP:18789 -sTCP:LISTEN`.

### Which user runs the gateway?

```bash
ps -o user= -p $(lsof -t -iTCP:18789 -sTCP:LISTEN 2>/dev/null) 2>/dev/null || echo "No listener on 18789"
```
