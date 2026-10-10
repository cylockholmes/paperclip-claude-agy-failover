# paperclip-claude-agy-failover

An [ACP](https://agentclientprotocol.com) wrapper for [Paperclip](https://github.com/paperclipai/paperclip) that keeps **Claude as the primary agent** and automatically **falls over to the Antigravity CLI (`agy`)** when Claude can't serve a turn (usage/quota exhausted, or an auth failure). Once a short cooldown passes, Claude is tried again.

## How it works

Paperclip's `claude_local` adapter launches `claude-agent-acp`. This wrapper sits in its place:

1. Starts the real `claude-agent-acp` and proxies ACP JSON-RPC between Paperclip and Claude.
2. Watches Claude's output for failure signals: monthly/session/weekly limits, rate limits, low credit balance, `401`/OAuth expired or revoked, authentication errors, and `_meta.jetbrains.air.sessionFailure` with `severity: "error"`. Only error responses and short notices count, so long normal replies that mention "rate limit" don't trigger it.
3. On failure it records a cooldown in a state file, then replays the in-flight prompt through `agy --print` and streams the output back to Paperclip as ACP message chunks.
4. While the cooldown is active, new runs go straight to `agy`. When it expires, the state file is removed and the next run starts on Claude again.

| Failure kind | Default cooldown | Override (ms) |
| --- | --- | --- |
| Quota / limit | 15 minutes | `PAPERCLIP_CLAUDE_QUOTA_COOLDOWN_MS` |
| Auth (401, expired/revoked token) | 2 minutes | `PAPERCLIP_CLAUDE_AUTH_COOLDOWN_MS` |

Each failover writes `[claude-to-agy] failing over to agy: <reason>` to stderr, so it shows up in the Paperclip run logs.

### Use your real Claude login

Paperclip launches agents with an isolated `HOME`, a private `CLAUDE_CONFIG_DIR`, and sometimes a managed `CLAUDE_CODE_OAUTH_TOKEN`. Those can go stale or get revoked even though your normal `claude` login is fine. The wrapper therefore starts Claude with your **real** `HOME` and strips `CLAUDE_CONFIG_DIR`, `CLAUDE_CODE_OAUTH_TOKEN`, `ANTHROPIC_AUTH_TOKEN`, `ANTHROPIC_API_KEY`, `XDG_CONFIG_HOME` and `XDG_DATA_HOME`, so Claude uses the same credentials as `claude` in your terminal. `agy` is likewise run with your real `HOME` so it finds its own saved login. Interactive auth prompts from `agy` are suppressed so they never leak into agent chat.

> If you authenticate Claude with an API key rather than a subscription login, remove the env-stripping loop in `startClaude()` first.

## Requirements

- macOS or Linux, Node.js 18+
- Paperclip with `claude_local` agents (`claude-agent-acp` installed)
- `claude` logged in from your terminal
- Antigravity CLI (`agy`) installed and logged in (run `agy` once in a terminal)

## Install

```bash
git clone https://github.com/cylockholmes/paperclip-claude-agy-failover.git
cd paperclip-claude-agy-failover
./install.sh        # copies the wrapper to ~/.paperclip/bin/
```

Then point your agents at it, either:

**A. Per agent** — set `adapterConfig.agentCommand` on each `claude_local` agent to `~/.paperclip/bin/claude-to-agy-acp-wrapper` (use the absolute path), via the Paperclip UI or API.

**B. Globally** — replace the `claude-agent-acp` binary Paperclip launches so every agent, including future hires, goes through the wrapper:

```bash
BIN=/path/to/node_modules/.bin          # directory containing claude-agent-acp
mv "$BIN/claude-agent-acp" "$BIN/claude-agent-acp.real"
ln -s ~/.paperclip/bin/claude-to-agy-acp-wrapper "$BIN/claude-agent-acp"
```

The wrapper finds `claude-agent-acp.real` on `PATH` (or via `PAPERCLIP_CLAUDE_BIN`) and never launches itself. Note that reinstalling the package can undo option B.

## Configuration

All optional environment variables:

| Variable | Default |
| --- | --- |
| `PAPERCLIP_CLAUDE_BIN` | first `claude-agent-acp.real` / `claude-agent-acp` on `PATH` that isn't this wrapper |
| `PAPERCLIP_AGY_BIN` | `~/.local/bin/agy` |
| `PAPERCLIP_CLAUDE_STATE_FILE` | `~/.paperclip/data/claude_quota_state.json` |
| `PAPERCLIP_CLAUDE_QUOTA_COOLDOWN_MS` | `900000` |
| `PAPERCLIP_CLAUDE_AUTH_COOLDOWN_MS` | `120000` |
| `PAPERCLIP_REAL_HOME` / `PAPERCLIP_REAL_USER` | current user's home / name |

## Troubleshooting

- **Force Claude again right now:** `rm ~/.paperclip/data/claude_quota_state.json`
- **Always on agy:** check the run's stderr log for the `failing over` line; it contains the exact error Claude returned.
- **Revoked/expired token:** run `claude` in a terminal and log in again.

## Limitations

- Failover is per turn: an in-flight prompt is replayed on `agy`, but Claude's session context isn't transferred.
- `agy` runs with `--dangerously-skip-permissions`; only use this on projects you trust agents to modify.
- Not affiliated with Paperclip, Anthropic, or Google.

## License

MIT
