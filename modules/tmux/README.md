# Tmux Module - Complete Terminal Multiplexer Setup

This module provides a comprehensive tmux configuration matching your NixOS setup, with TPM (Tmux Plugin Manager) for plugin management and all custom scripts for advanced features.

## Features

### Core Configuration
- **Prefix Keys:** `Ctrl+A` (primary) or `Ctrl+Space` (secondary)
- **Vi Mode:** Enabled for copy mode
- **Mouse Support:** Full mouse integration
- **History:** 1,000,000 lines
- **256 Color Support:** True color terminal
- **Auto-renaming:** Windows and panes automatically renamed based on process/path

### Plugins (via TPM)
1. **vim-tmux-navigator** - Seamless navigation between vim and tmux panes
2. **tmux-resurrect** - Save and restore tmux sessions
3. **tmux-continuum** - Auto-save sessions every minute
4. **extrakto** - Extract text from panes
5. **catppuccin** - Mocha theme for beautiful status line
6. **tmux-fzf** - FZF integration for tmux commands
7. **tmux-fzf-url** - Open URLs from panes with FZF
8. **tmux-floax** - Floating windows support

### Custom Scripts
All scripts are automatically installed to `~/.config/scripts/`:

1. **tmux-rename-window.sh** - Auto-rename windows based on active pane
2. **tmux-rename-pane.sh** - Auto-rename pane titles
3. **tmux-pane-history.sh** - Track pane switching history
4. **tmux-pane-back.sh** - Navigate backward through pane history
5. **tmux-pane-forward.sh** - Navigate forward through pane history
6. **tmux-notes-toggle.sh** - Quick toggle to Notes session
7. **save_tmux_context.sh** - Save current session/window

### Sesh Integration
Powerful session manager with FZF interface:
- Pre-configured sessions (Downloads, repositories, home)
- Zoxide integration for recent directories
- Tmux session listing
- Config directory quick access
- Custom startup commands per session

## Key Bindings

### Window & Pane Management
```
Prefix + s          Split horizontally (current path)
Prefix + v          Split vertically (current path)
Prefix + t          New window (current path)
Prefix + x          Kill pane (no confirmation)
Prefix + h/j/k/l    Navigate panes (vim-style)
Shift + Left/Right  Switch windows
```

### Session Management
```
Prefix + f          Sesh launcher (main session manager)
Prefix + K          Kill sessions (with FZF selection)
Prefix + M-R        Root sessions
Prefix + j/k        Switch between sessions
```

### Copy Mode
```
Prefix + S          Enter copy mode (search/visual)
Prefix + V          Enter copy mode + select line
v                   Begin selection (in copy mode)
Ctrl+v              Rectangle toggle (in copy mode)
y                   Yank to clipboard (in copy mode)
```

### Special Features
```
Prefix + N          Toggle Notes session
Prefix + c          Toggle arch-config session
Prefix + g          LazyGit popup (80% screen)
Prefix + w          Floating window (tmux-floax)
Prefix + b          Navigate back in pane history
Prefix + B          Navigate forward in pane history
Prefix + Ctrl+s     Save current context
Prefix + R          Reload tmux config
Prefix + r          Rename session
```

### TPM Plugin Management
```
Prefix + I          Install new plugins
Prefix + U          Update plugins
Prefix + M-u        Uninstall plugins not in config
```

## Sesh Session Manager

Press `Prefix + f` to launch the session manager with these features:

### Navigation Keys (in FZF)
- `Ctrl+a` - Show all sessions
- `Ctrl+t` - Show only tmux sessions
- `Ctrl+g` - Show config directories
- `Ctrl+x` - Show zoxide (recent directories)
- `Ctrl+f` - Find directories (fd search)
- `Ctrl+d` - Kill selected session
- `Tab/Shift+Tab` - Navigate up/down

### Pre-configured Sessions
From `~/.config/sesh/sesh.toml`:
- **Downloads** - Opens in ~/Downloads with yazi
- **repositories (c)** - Opens in ~/repo with ls
- **home (~)** - Opens in home directory

## Auto-Renaming Logic

### Windows
Windows are automatically renamed based on the active pane's:
- **Shell processes** (zsh, bash, etc.): Shows formatted path (last 2-3 directories)
- **Other processes**: Shows process name

### Panes
Pane titles follow the same logic as windows, visible in the pane border.

### Examples
```
Shell in ~/repo/nix/modules     →  "repo/nix/modules"
Running nvim                    →  "nvim"
Shell in ~/Downloads            →  "Downloads"
Running lazygit                 →  "lazygit"
```

## Pane History Navigation

Navigate through your pane switching history like a web browser:

1. **Automatic Tracking**: Every pane switch is recorded
2. **Go Back**: `Prefix + b` - Return to previously focused pane
3. **Go Forward**: `Prefix + B` - Move forward in history
4. **Wrap Around**: Navigates in a circular fashion
5. **Cross-Session**: Works across different tmux sessions
6. **Cleanup**: Automatically removes invalid panes

History is stored globally and persists up to 100 entries.

## Notes Session

Quick access to a dedicated Notes session:

```bash
Prefix + N          Toggle Notes session
```

- Creates session in `~/Notes` directory
- Opens with nvim by default
- Toggles back to previous session when in Notes
- Automatically created on first use

## Resurrection & Continuum

Your tmux environment is automatically saved:

- **Auto-save**: Every 1 minute
- **Restore on start**: Sessions automatically restored
- **Save location**: `~/.tmux/resurrect/`
- **Vim/Neovim**: Session strategies enabled
- **Pane contents**: Captured for full restoration

### Manual Control
```bash
Prefix + Ctrl+s     Save session manually (via resurrect)
Prefix + Ctrl+r     Restore session manually
```

## Clipboard Integration

Copy mode integrates with system clipboard:
- Uses `~/.config/scripts/clipboard-copy.sh`
- Automatically detects Wayland (`wl-copy`) or X11 (`xclip`)
- Yanked text goes directly to system clipboard

## Theme (Catppuccin Mocha)

Beautiful status line with modules:
- Application name
- CPU usage
- Session name
- System uptime
- Battery status (if available)
- Window list with custom formatting

## Configuration Files

### Main Config
- **tmux.conf**: `~/.config/tmux/tmux.conf`
- **Sesh config**: `~/.config/sesh/sesh.toml`

### Scripts Directory
All scripts in `~/.config/scripts/`:
- `tmux-rename-window.sh`
- `tmux-rename-pane.sh`
- `tmux-pane-history.sh`
- `tmux-pane-back.sh`
- `tmux-pane-forward.sh`
- `tmux-notes-toggle.sh`
- `save_tmux_context.sh`

### Plugin Directory
- **TPM**: `~/.config/tmux/plugins/tpm/`
- **Plugins**: `~/.config/tmux/plugins/*/`

### Data Directories
- **Resurrect**: `~/.tmux/resurrect/`
- **History log**: `~/.tmuxhistory.log`
- **Context save**: `~/.tmux_saved_context`

## Post-Install Setup

After running `dcli sync`, the setup script will:

1. ✅ Create all necessary directories
2. ✅ Install helper scripts to `~/.config/scripts/`
3. ✅ Install TPM (Tmux Plugin Manager)
4. ✅ Install all tmux plugins
5. ✅ Create history log file
6. ✅ Verify clipboard helper exists

### First Run

```bash
# Start tmux
tmux

# If plugins didn't install automatically:
Prefix + I          # Install plugins

# Try the session manager:
Prefix + f          # Launch sesh

# Open LazyGit:
Prefix + g          # Popup window
```

## Customization

### Add More Sessions to Sesh

Edit `~/.config/sesh/sesh.toml`:

```toml
[[session]]
name = "My Project"
path = "~/projects/myproject"
startup_command = "nvim"
```

### Modify Key Bindings

Edit `~/.config/tmux/tmux.conf`, then:
```bash
Prefix + R          # Reload config
```

### Change Theme

Edit the catppuccin flavor in `tmux.conf`:
```tmux
set -g @catppuccin_flavor "mocha"    # or "latte", "frappe", "macchiato"
```

## Troubleshooting

### Plugins Not Loading
```bash
# Ensure TPM is installed
ls ~/.config/tmux/plugins/tpm

# Reinstall plugins
Prefix + I
```

### Scripts Not Working
```bash
# Check scripts exist and are executable
ls -l ~/.config/scripts/tmux-*.sh

# Make executable if needed
chmod +x ~/.config/scripts/tmux-*.sh
```

### Clipboard Not Working
```bash
# Verify clipboard helper exists
ls -l ~/.config/scripts/clipboard-copy.sh

# Test it
echo "test" | ~/.config/scripts/clipboard-copy.sh
```

### Auto-renaming Not Working
```bash
# Check if scripts are executable
ls -l ~/.config/scripts/tmux-rename-*.sh

# Enable debug logging
tail -f ~/.tmuxhistory.log
```

## Advanced Features

### Vim-Tmux Navigation

Seamlessly navigate between vim/neovim and tmux panes using the same keys:
- `Ctrl+h/j/k/l` - Navigate in any direction
- Works in normal mode in vim/neovim
- Works outside vim in tmux

### Extrakto

Extract text from panes:
- URLs, file paths, git SHAs, etc.
- Press `Prefix + Tab` to launch
- FZF interface for selection

### FZF URL Opener

Open URLs from pane history:
- Scans last 2000 lines
- FZF interface for selection
- Automatic browser opening

## Comparison to NixOS Setup

### What's Included ✅
- ✅ All key bindings and shortcuts
- ✅ All custom scripts (rename, history navigation, notes toggle)
- ✅ Sesh session manager with configuration
- ✅ TPM plugin system (equivalent to Nix plugins)
- ✅ Catppuccin theme
- ✅ Vim-tmux navigator
- ✅ Resurrect + Continuum
- ✅ Auto-renaming logic
- ✅ Clipboard integration

### What's Different 🔄
- 🔄 Plugin management via TPM instead of Nix
- 🔄 WSL-specific features removed (PowerShell integration)
- 🔄 Scripts use `/usr/bin/zsh` instead of Nix paths

### What Works the Same ✨
- ✨ Prefix keys (Ctrl+A and Ctrl+Space)
- ✨ All custom keybindings
- ✨ Pane history navigation
- ✨ Window/pane auto-renaming
- ✨ Notes session toggle
- ✨ LazyGit popup
- ✨ Session persistence

## Summary

This tmux module provides a complete, production-ready terminal multiplexer setup with:
- **9 plugins** for extended functionality
- **7 custom scripts** for advanced features
- **Sesh integration** for powerful session management
- **Auto-renaming** for better context awareness
- **Pane history** for browser-like navigation
- **Full clipboard** integration
- **Beautiful theme** with Catppuccin Mocha

All configured to match your NixOS workflow on Arch Linux! 🚀
