# Claude Renew Daemon

Minimal auto-renew daemon for Claude usage blocks using `ccusage`.

## What it does
- Polls `ccusage blocks --json --active` for the current block end time.
- When the reset is within `RENEW_WINDOW_SECONDS` (default 120s), it waits until reset and runs a tiny `claude` session.
- If `ccusage`/`jq` is unavailable, it falls back to `~/.claude-last-activity` and a 5-hour (18000s) window.

## Service
- Unit: `~/.config/systemd/user/claude-renew-daemon.service`
- Binary: `~/.local/bin/claude-renew-daemon`

## Logs
- Logs go to the systemd journal for the user service.
  - `journalctl --user -u claude-renew-daemon.service -f`

## Settings (env vars)
- `RENEW_WINDOW_SECONDS` (default 120)
- `CHECK_INTERVAL_SECONDS` (default 60)
- `RESET_SECONDS` (default 18000)
- `LAST_ACTIVITY_FILE` (default `~/.claude-last-activity`)
