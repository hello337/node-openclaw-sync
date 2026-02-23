# node-openclaw-sync

Syncs config and OAuth between [xNode](https://xnode.pro) and a local [OpenClaw](https://docs.openclaw.ai) instance. Run on the server where OpenClaw is installed: it fetches settings from the xNode API and applies them (agents_defaults, tools_web_search, OAuth tokens, auth-link requests for device flow).

**Requirements on the server:** `curl`, `jq`, and `openclaw` in PATH.

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

- **GET /openclaw/config** — fetches config using the token.
- Applies **agents_defaults** and **tools_web_search** to the local OpenClaw via `openclaw gateway call config.patch`.
- Handles **oauth_url_requests**: when a user requests an auth link (e.g. Qwen Portal), runs `openclaw models auth login --provider ...`, extracts the URL from output, and sends it to xNode (**POST /openclaw/oauth-auth-url**).
- Applies **oauth_pending** (tokens / callback URLs) via the OpenClaw CLI and marks them as applied (**POST /openclaw/oauth-consumed**).

Token and API base are read from the `env` file in the repo root (see `env.example`).
