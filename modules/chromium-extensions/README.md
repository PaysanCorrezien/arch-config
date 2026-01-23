# Chromium Extensions Module

Manages automatic installation and configuration of Chromium extensions via policy.

## Extensions Installed

- **Surfingkeys** - Vim-like keyboard navigation for the web
- **KeePassXC Browser** - Password manager integration
- **Refined GitHub** - GitHub UI enhancements
- **KaraKeep** - Google Keep integration

## How It Works

### Extension Installation

Extensions are deployed via `/etc/chromium/policies/managed/extensions.json` using:
- `ExtensionInstallForcelist` - Auto-installs extensions on browser launch
- `ExtensionSettings` - Configures extension-specific settings

### Surfingkeys Configuration

Your Surfingkeys config is managed as a dotfile:

1. **Config location**: `dotfiles/surfingkeys/config.js` (syncs to `~/.config/surfingkeys/config.js`)
2. **Policy enables**: File URL access for the extension
3. **One-time setup**: Set "Load settings from" URL in Surfingkeys options (persists)

## Customizing Surfingkeys

Edit `dotfiles/surfingkeys/config.js` to customize:

```javascript
// Change theme
settings.theme = `...`;

// Add custom key mappings
map('J', 'E');  // Next tab
map('K', 'R');  // Previous tab

// Add search engines
addSearchAlias('g', 'google', 'https://www.google.com/search?q=', 's');
addSearchAlias('gh', 'github', 'https://github.com/search?q=', 's');
```

See [Surfingkeys documentation](https://github.com/brookhong/Surfingkeys) for more examples.

## First-Time Setup

After running `dcli sync`:

**Automated via policy:**
- ✓ Developer mode enabled on chrome://extensions
- ✓ Extensions auto-installed
- ✓ Config file synced to ~/.config/surfingkeys/config.js

**Manual one-time setup (unavoidable):**
1. Open Chromium → `chrome://extensions`
2. Find Surfingkeys → Enable "Allow access to file URLs"
3. Click Surfingkeys options
4. Set "Load settings from" to: `file:///home/dylan/.config/surfingkeys/config.js`
5. Click "Save"

**Why manual?** Chrome doesn't expose policies to automatically enable "Allow access to file URLs" or set the config URL. This is a security restriction. You only need to do this once - it persists across browser sessions and system reboots.

After setup, your config auto-loads from the file on every browser restart.

## Adding More Extensions

Edit `scripts/setup-extensions.sh` and add to the `ExtensionInstallForcelist` array:

```bash
"extension_id;https://clients2.google.com/service/update2/crx"
```

Find the extension ID from the Chrome Web Store URL.

## Policy Files

- `/etc/chromium/policies/managed/extensions.json` - Main extension policy
- Extensions auto-update from Chrome Web Store
