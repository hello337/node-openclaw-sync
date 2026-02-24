# node-openclaw-sync

Syncs config and OAuth between [xNode](https://xnode.pro) and a local [OpenClaw](https://docs.openclaw.ai) instance. Run on the server where OpenClaw is installed.

**Requirements:** `curl`, `jq`, `openssl`, `openclaw` in PATH. Optional: `gemini` CLI (for Gemini CLI OAuth), `script` (for CLI fallback).

## Provider support matrix

| xNode key            | OpenClaw provider    | Auth flow                    | Status              |
|----------------------|----------------------|------------------------------|---------------------|
| `qwen_portal`        | qwen-portal          | device-code (direct API)     | **Full support**    |
| `github_copilot`     | github-copilot       | device-code (direct API)     | **Full support**    |
| `minimax_portal`     | minimax-portal       | device-code (direct API)     | **Full support**    |
| `openai_codex`       | openai-codex         | redirect OAuth (direct API)  | **Full support**    |
| `google_gemini_cli`  | google-gemini-cli    | redirect OAuth (direct API)  | **Full support** *  |
| `anthropic_setup_token`| anthropic          | paste-token                  | **Full support**    |

> \* Requires `gemini` CLI installed or `GEMINI_CLI_OAUTH_CLIENT_ID` env var set.

---

## First-time setup

### 1. Clone & configure

```bash
git clone https://github.com/YOUR_USER/node-openclaw-sync.git
cd node-openclaw-sync
cp env.example env
nano env  # set OPENCLAW_CONFIG_TOKEN
```

### 2. Install systemd timer

```bash
chmod +x install.sh
sudo ./install.sh
```

### 3. Verify

```bash
systemctl status openclaw-sync.timer
journalctl -u openclaw-sync.service -f
```

---

## How each auth flow works

### Device-code providers (Qwen, GitHub Copilot, MiniMax)

Two-phase flow handled entirely without the OpenClaw CLI:

1. **Phase B** (user clicks "Get auth link"): Script calls the provider's device-code API directly, gets `verification_uri` + `user_code`, saves `device_code` and PKCE verifier to state file, POSTs URL to xNode.
2. **Phase 0** (every 10s): Polls the provider's token endpoint using saved `device_code`. When user approves → saves token to `~/.openclaw/agents/main/agent/auth-profiles.json` → applies `config.patch` (provider config + `agents.defaults`) → notifies xNode.

### Redirect OAuth providers (OpenAI Codex, Google Gemini CLI)

Two-phase flow with PKCE verifier persisted between script runs:

1. **Phase B** (user clicks "Get auth link"): Script generates PKCE verifier + challenge, builds the full authorization URL, saves the verifier to a state file, POSTs URL to xNode.
2. **Phase 3** (user pastes redirect URL): Script reads the saved verifier, extracts the `code` parameter from the pasted URL, exchanges it for tokens using the **same** PKCE verifier, saves to `auth-profiles.json`.

This solves the fundamental problem with CLI-based approaches where each CLI run generates its own PKCE verifier.

### Paste-token (Anthropic)

Simple pipe: `echo "$token" | openclaw models auth paste-token --provider anthropic`.

---

## Technical details per provider

| Provider | Client ID | Endpoint | Auth profile key |
|---|---|---|---|
| Qwen Portal | `f0304373b74a44d2b584a3fb70ca9e56` | `chat.qwen.ai/api/v1/oauth2` | `qwen-portal:default` |
| GitHub Copilot | `Iv1.b507a08c87ecfe98` | `github.com/login/device/code` | `github-copilot:github` |
| MiniMax Portal | `78257093-7e40-4613-99e0-527b14b39113` | `api.minimax.io/oauth` | `minimax-portal:default` |
| OpenAI Codex | `app_EMoamEEZ73f0CkXaXp7hrann` | `auth.openai.com/oauth` | `openai-codex:default` |
| Google Gemini CLI | Extracted from Gemini CLI | `accounts.google.com/o/oauth2/v2` | `google-gemini-cli:default` |

---

## Deploying to a new server

1. Install OpenClaw + start gateway.
2. Clone this repo, set `OPENCLAW_CONFIG_TOKEN`, run `sudo ./install.sh`.
3. Script auto-sets `gateway.controlUi.allowInsecureAuth true` for localhost.
4. Test: `./openclaw-sync`.

## Updating

```bash
cd /path/to/node-openclaw-sync
sudo git pull
sudo systemctl restart openclaw-sync.timer
```

---

## Troubleshooting

### Viewing logs

```bash
journalctl -u openclaw-sync.service -n 200 --no-pager
journalctl -u openclaw-sync.service -f
```

### "device_poll.X: pending"

Normal — user hasn't completed authorization yet. Script keeps polling until done or expired.

### "no client_id" for google_gemini_cli

Install Gemini CLI (`npm install -g @google/gemini-cli`) or set `OPENCLAW_GEMINI_OAUTH_CLIENT_ID` / `GEMINI_CLI_OAUTH_CLIENT_ID` env var.

### "no 'code' in pasted URL" for redirect providers

The user pasted something that isn't a valid redirect URL. It should look like:
- OpenAI: `http://localhost:1455/auth/callback?code=...&state=...`
- Gemini: `http://localhost:8085/oauth2callback?code=...&state=...`

### "state mismatch" for redirect providers

The pasted URL doesn't match the saved auth request. The user may have started a new auth flow. Click "Get auth link" again.

### "Gateway is not healthy"

```bash
openclaw gateway status
openclaw gateway start
```
