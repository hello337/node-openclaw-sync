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
