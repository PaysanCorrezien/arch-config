#!/usr/bin/env bash
# Setup Chromium extension auto-install policy

set -euo pipefail

echo "=== Chromium Extensions Policy Setup ==="
echo

target_user="${SUDO_USER:-$USER}"
if [ -n "${target_user}" ] && [ "${target_user}" != "root" ]; then
  user_home="$(getent passwd "${target_user}" | cut -d: -f6)"
else
  user_home="$HOME"
fi

# Create policy directory
echo "→ Creating Chromium policy directory..."
sudo mkdir -p /etc/chromium/policies/managed

# Deploy extension policy with file URL access for Surfingkeys
echo "→ Installing extension auto-install policy..."
sudo tee /etc/chromium/policies/managed/extensions.json >/dev/null <<EOF
{
  "ExtensionInstallForcelist": [
    "gfbliohnnapiefjpjlpjnehglfpaknnc;https://clients2.google.com/service/update2/crx",
    "oboonakemofpalcgghocfoadofidjkkk;https://clients2.google.com/service/update2/crx",
    "hlepfoohegkhhmjieoechaddaejaokhf;https://clients2.google.com/service/update2/crx",
    "kgcjekpmcjjogibpjebkhaanilehneje;https://clients2.google.com/service/update2/crx"
  ],
  "ExtensionSettings": {
    "gfbliohnnapiefjpjlpjnehglfpaknnc": {
      "installation_mode": "force_installed",
      "update_url": "https://clients2.google.com/service/update2/crx",
      "runtime_allowed_hosts": ["file://${user_home}/.config/surfingkeys/*"]
    }
  },
  "DeveloperToolsAvailability": 1,
  "ExtensionDeveloperModeSettings": {
    "mode": 0
  }
}
EOF

echo "✓ Extension policy deployed to /etc/chromium/policies/managed/extensions.json"
echo
echo "=== Extensions Configured ==="
echo
echo "The following extensions will auto-install on next Chromium launch:"
echo "  • Surfingkeys (gfbliohnnapiefjpjlpjnehglfpaknnc)"
echo "  • KeePassXC Browser (oboonakemofpalcgghocfoadofidjkkk)"
echo "  • Refined GitHub (hlepfoohegkhhmjieoechaddaejaokhf)"
echo "  • KaraKeep (kgcjekpmcjjogibpjebkhaanilehneje)"
echo
echo "=== Surfingkeys Configuration ==="
echo
echo "✓ Config file synced to: ${user_home}/.config/surfingkeys/config.js"
echo "✓ Developer mode enabled via policy"
echo "✓ File URL access allowed via policy"
echo
echo "⚠ ONE-TIME MANUAL SETUP REQUIRED:"
echo
echo "Chrome policies cannot automatically enable 'Allow access to file URLs'"
echo "or set the config URL. You need to do this once manually:"
echo
echo "  1. Open Chromium → chrome://extensions"
echo "  2. Find Surfingkeys → Enable 'Allow access to file URLs'"
echo "  3. Click Surfingkeys options"
echo "  4. Set 'Load settings from' to: file://${user_home}/.config/surfingkeys/config.js"
echo "  5. Click 'Save'"
echo
echo "After this one-time setup, your config will auto-load on every browser restart."
echo "The setting persists across sessions and reboots."
echo
