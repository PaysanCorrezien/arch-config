# AI Usage Plugin

Track and display AI provider usage (Claude Code, Codex/OpenAI) in the Noctalia bar.

## Features

- **Multi-Provider Support**: Track usage from Claude Code and Codex (OpenAI) simultaneously
- **Bar Widget**: Displays current usage percentage and time remaining for each provider
- **Detailed Panel**: View 5-hour and 7-day usage windows with progress bars
- **Auto Reset**: Automatically send a message to CLI tools when the 5-hour window resets to start a fresh window
- **Plan Detection**: Automatically detects and displays your subscription tier (Pro, Max, Team, etc.)
- **Per-Provider Settings**: Enable/disable each provider independently, choose which to show in bar

## Requirements

- `curl` - For API requests
- `jq` - For JSON parsing
- **For Claude**: Active Claude Code session with OAuth credentials at `~/.claude/.credentials.json`
- **For Codex**: Codex CLI authenticated with credentials at `~/.codex/auth.json`

## Usage

### Bar Widget

The bar widget shows usage for enabled providers:
- **Left section**: Claude usage (percentage + time remaining)
- **Right section**: Codex usage (percentage + time remaining)
- **Click**: Opens the detailed usage panel

### Panel

The panel provides detailed information:
- 5-hour rolling window usage with reset countdown
- 7-day weekly limit usage
- Connection status and plan type badges
- Error messages when authentication fails

## Keybindings

### Niri

```kdl
Super+I  hotkey-overlay-title="Noctalia AI-Usage Panel" { spawn "qs" "-c" "noctalia-shell" "ipc" "call" "plugin:ai-usage" "openPanel"; }
```

### Hyprland

```conf
bind = SUPER, I, exec, qs -c noctalia-shell ipc call plugin:ai-usage openPanel
```

### Sway

```conf
bindsym $mod+i exec qs -c noctalia-shell ipc call plugin:ai-usage openPanel
```

## IPC Commands

Control the plugin via CLI for keybindings or scripts:

```bash
# General usage
qs -c noctalia-shell ipc call plugin:ai-usage <command>
```

| Command | Description |
|---------|-------------|
| `openPanel` | Open the usage panel on the current screen |
| `refresh` | Force refresh usage data from all providers |
| `openSettings` | Open the plugin settings |

### Examples

```bash
# Open the usage panel
qs -c noctalia-shell ipc call plugin:ai-usage openPanel

# Force refresh usage data
qs -c noctalia-shell ipc call plugin:ai-usage refresh

# Open settings
qs -c noctalia-shell ipc call plugin:ai-usage openSettings
```

## Settings

Configure the plugin through the Noctalia settings panel.

### General

| Setting | Default | Description |
|---------|---------|-------------|
| `refreshIntervalSeconds` | 60 | How often to fetch usage data (in seconds) |
| `showBar` | true | Display the usage widget in the bar |
| `autoResetEnabled` | true | Allow CLI reset messages on window refresh |

### Claude Code

| Setting | Default | Description |
|---------|---------|-------------|
| `claudeEnabled` | true | Track Claude Code API usage |
| `showClaudeInBar` | true | Display Claude usage in the bar widget |
| `claudeResetEnabled` | true | Send a message to Claude CLI when window resets |
| `claudeResetMessage` | "hi" | Message sent to trigger a new window |

### Codex (OpenAI)

| Setting | Default | Description |
|---------|---------|-------------|
| `codexEnabled` | true | Track Codex/OpenAI API usage |
| `showCodexInBar` | true | Display Codex usage in the bar widget |
| `codexCredentialsPath` | `$HOME/.codex/auth.json` | Path to Codex credentials file |
| `codexResetEnabled` | false | Send a message to Codex CLI when window resets |
| `codexResetMessage` | "hi" | Message sent to trigger a new window |

## How It Works

### Claude Code

Reads the OAuth token from `~/.claude/.credentials.json` and queries the Anthropic usage API to fetch:
- 5-hour rolling window utilization
- 7-day weekly utilization
- Rate limit tier and subscription type

### Codex (OpenAI)

Reads the access token from the configured credentials path and queries the ChatGPT usage API to fetch:
- Primary window (5-hour) utilization
- Secondary window (7-day) utilization
- Plan type and connection status

### Auto Reset

When enabled, the plugin monitors the reset countdown. When a window resets (reaches 0), it automatically pipes a message to the respective CLI tool (`claude` or `codex`) to start a fresh conversation and trigger a new usage window.

## Structure

```
ai-usage/
├── Main.qml              # Plugin entry point and state management
├── BarWidget.qml         # Bar widget component
├── Panel.qml             # Detailed usage panel
├── Settings.qml          # Plugin settings UI
├── ProviderCard.qml      # Reusable provider card component
├── providers/
│   ├── ClaudeProvider.qml    # Claude API integration
│   ├── CodexProvider.qml     # Codex/OpenAI API integration
│   └── ProviderUtils.js      # Shared utility functions
├── watcher/
│   └── ResetWatcher.qml      # Auto-reset logic
└── public/
    ├── claude-ai.svg         # Claude icon
    └── openai-light.svg      # OpenAI icon
```

## Troubleshooting

### "No access token found" (Claude)

Ensure you're logged into Claude Code:
```bash
claude login
```

### "Credentials file not found" (Codex)

Ensure Codex is authenticated:
```bash
codex
# Follow the login prompts
```

### "Token expired" (Codex)

Re-authenticate with Codex:
```bash
codex
# The CLI will refresh your token
```

### Usage not updating

- Check if the refresh interval is set correctly
- Verify the credentials files exist and contain valid tokens
- Check Noctalia logs for detailed error messages

## License

MIT License
