# CC Usage Bar

Show Claude Code usage in the Noctalia bar using `ccusage` and `jq`.

## Requirements

- `ccusage` in `$PATH`
- `jq`

## IPC Commands

```bash
# Toggle visibility
qs -c noctalia-shell ipc call plugin:ccusage-bar toggle

# Show / hide explicitly
qs -c noctalia-shell ipc call plugin:ccusage-bar show
qs -c noctalia-shell ipc call plugin:ccusage-bar hide

# Force refresh
qs -c noctalia-shell ipc call plugin:ccusage-bar refresh

# Open panel
qs -c noctalia-shell ipc call plugin:ccusage-bar openPanel

# Open settings (toggles Noctalia settings if openSettings is unavailable)
qs -c noctalia-shell ipc call plugin:ccusage-bar openSettings
```

## Notes

- The bar widget shows the current reset-period usage and window progress percent.
- The panel includes day/week/month/total metrics, session summaries, and detailed block stats.
- Clicking the bar widget opens the usage panel with more metrics.
- The plan label is detected from ccusage configuration when available.
