# node-openclaw-sync

Syncs config and OAuth between [xNode](https://xnode.pro) and a local [OpenClaw](https://docs.openclaw.ai) instance. Run on the server where OpenClaw is installed: it fetches settings from the xNode API and applies them (agents_defaults, tools_web_search, OAuth tokens, auth-link requests for device flow).

**Requirements on the server:** `curl`, `jq`, and `openclaw` in PATH.

**Provider plugins:** For "Get auth link" (OAuth/device flow), the script enables the right plugin per provider (see [OpenClaw docs](https://docs.openclaw.ai/concepts/model-providers)) and captures the URL to send to xNode. After the first enable of a plugin, **restart the OpenClaw gateway** once so it loads. Then the script applies pasted tokens/URLs from the config and marks them consumed; `agents_defaults` from the API enables all models for the configured providers.

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
3. **One-time pairing** so the sync script (and CLI) can talk to the gateway:
   - The first time the script or `openclaw` CLI connects to the gateway, the gateway may respond with **pairing required**. Open the gateway in a browser **on that server**: `http://127.0.0.1:18789/` (if you’re remote, use an SSH tunnel: `ssh -L 18789:127.0.0.1:18789 root@server` then open `http://localhost:18789/`).
   - In the dashboard, approve the pending device (the one used by the sync/CLI). After that, the script and CLI will connect without asking again.
4. Optionally run the sync once by hand to confirm: `./openclaw-sync`.

No need to repeat pairing unless you revoke the device or reinstall OpenClaw state.

**Pairing / allowInsecureAuth**  
The sync script sets `gateway.controlUi.allowInsecureAuth true` in the OpenClaw config at each run so that the CLI (and script) can connect without manual device pairing. This only makes sense when the gateway is bound to loopback (`127.0.0.1`) and not exposed to the network. **After first deploy**, restart the OpenClaw gateway once so the setting takes effect: `openclaw gateway restart`.  

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

## Troubleshooting

**How to see which user runs the OpenClaw gateway**

- By process (default port 18789):
  ```bash
  lsof -nP -iTCP:18789 -sTCP:LISTEN
  ```
  or:
  ```bash
  ss -tlnp | grep 18789
  ```
  Then check the process owner: `ps -o user= -p <PID>`.

- By systemd: if the gateway is a **user** service, the unit is under `~/.config/systemd/user/` and you'd use `systemctl --user status openclaw-gateway` (as that user). If it's a **system** service, `systemctl status openclaw-gateway` (often as root) and the unit is under `/etc/systemd/system/`.

- One-liner to print the gateway process user:
  ```bash
  ps -o user= -p $(lsof -t -iTCP:18789 -sTCP:LISTEN 2>/dev/null) 2>/dev/null || echo "No listener on 18789"
  ```

When the script enables a plugin and restarts the gateway, it exits right after `openclaw gateway start` and does **not** fetch the auth URL in the same run. The next run (e.g. in ~10s via the timer) will fetch the URL once the gateway is ready. This avoids a known OpenClaw issue where the gateway needs more than a few seconds to become healthy after restart ([openclaw/openclaw#22972](https://github.com/openclaw/openclaw/issues/22972)).

**"Waiting for link" never shows the link**

1. **OPENCLAW_API_BASE** must be the **exact same API** your frontend and browser use. If the frontend talks to `https://api.xnode.pro`, the script's `env` must have `OPENCLAW_API_BASE=https://api.xnode.pro` (no trailing slash). If you use a custom backend or ngrok for local dev, set that URL in the script's `env` on the machine where the script runs; otherwise the script posts the URL to a different backend and the frontend never sees it.
2. Run the script **by hand** on the server: `./openclaw-sync`. Look for either `oauth_url_requests.qwen_portal: auth URL sent to xNode` (success) or `no URL in output` / `failed to POST`. If you see "no URL in output", run `openclaw models auth login --provider qwen-portal` manually on the server and check whether a URL is printed; if it only works in an interactive terminal, the gateway may need more time after restart (wait 20–30s and run the script again).
3. Ensure the **config token** in the script's `env` is the one from the same OpenClaw node that the user is configuring in the UI (Pending Nodes → Token).
