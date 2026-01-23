#!/usr/bin/env bash
# Post-install setup script for Niri window manager with Noctalia

set -euo pipefail

echo "=== Niri + Noctalia Post-Install Setup ==="
echo

# Create screenshots directory
echo "→ Creating screenshots directory..."
mkdir -p ~/Pictures/Screenshots
echo "✓ Screenshots directory created"

# Make niri helper scripts executable (synced via dotfiles to ~/.config/niri/scripts/)
echo
echo "→ Setting up niri helper scripts..."
if [[ -d ~/.config/niri/scripts ]]; then
    chmod +x ~/.config/niri/scripts/* 2>/dev/null || true
    echo "✓ Helper scripts at ~/.config/niri/scripts/ made executable"
else
    echo "  (scripts will be available after dotfiles sync)"
fi

# NOTE: Using Noctalia for dashboard and notifications
# No need to enable waybar or mako services
echo
echo "→ Noctalia Configuration..."
echo "  • Using Noctalia for dashboard and notifications"
echo "  • No need to enable waybar/mako services"
echo "  • Noctalia is integrated via cachyos-niri-noctalia"
echo "✓ Noctalia integration ready"

# Set up Flatpak Wayland env
echo
echo "→ Setting up Flatpak Wayland environment..."
mkdir -p ~/.var/app
echo "✓ Flatpak environment configured"

echo
echo "→ Setting Nautilus defaults and bookmarks..."
if [[ -x ~/.config/niri/scripts/setup-nautilus.sh ]]; then
    ~/.config/niri/scripts/setup-nautilus.sh
    echo "✓ Nautilus settings applied"
else
    echo "  (setup-nautilus.sh will be available after dotfiles sync)"
fi

echo
echo "=== Niri + Noctalia Setup Complete! ==="
echo
echo "Next steps:"
echo "  1. Log out and select 'Niri' from your display manager"
echo "  2. Or start Niri from TTY with: niri-session"
echo "  3. Press Mod+Shift+/ to see keybindings"
echo "  4. Noctalia dashboard will be available automatically"
echo "  5. Customize ~/.config/niri/config.kdl as needed"
echo
