#!/usr/bin/env bash
# Create PWA-style web app launchers
# Based on NixOS work.nix web app system

set -euo pipefail

echo "=== Web Apps Setup ==="
echo

# Determine which browser to use
BROWSER=""
if command -v microsoft-edge &>/dev/null; then
    BROWSER="microsoft-edge"
    BROWSER_BIN="microsoft-edge-stable"
elif command -v chromium &>/dev/null; then
    BROWSER="chromium"
    BROWSER_BIN="chromium"
elif command -v google-chrome &>/dev/null; then
    BROWSER="google-chrome"
    BROWSER_BIN="google-chrome-stable"
else
    echo "❌ Error: No supported browser found (microsoft-edge, chromium, or google-chrome)"
    echo "   Please install one of these browsers first."
    exit 1
fi

echo "→ Using browser: $BROWSER"
echo

# Get script directory to locate icons
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ICONS_DIR="$(dirname "$SCRIPT_DIR")/icons"

# Create applications directory
mkdir -p ~/.local/share/applications
mkdir -p ~/.local/share/icons/webapps

# Helper function to copy webapp icon from repo
copy_icon() {
    local name="$1"
    local source="$ICONS_DIR/${name}.png"
    local dest="$HOME/.local/share/icons/webapps/${name}.png"

    if [[ -f "$source" ]]; then
        echo "  → Installing ${name} icon..."
        cp "$source" "$dest"
    else
        echo "  ⚠ Warning: Icon not found: ${name}.png"
        echo "    Please add to: $ICONS_DIR/"
    fi
}

# Helper function to create a web app desktop entry
# On Wayland, Chromium-based browsers set app_id based on the app URL, not --class
# We use --app-id flag for Edge, and ensure proper Wayland/Ozone settings
create_webapp() {
    local name="$1"
    local desktop_id="$2"
    local url="$3"
    local icon="$4"
    local description="$5"
    local categories="$6"
    local app_id="$7"  # Explicit app_id for window rules

    local desktop_file="$HOME/.local/share/applications/${desktop_id}.desktop"

    echo "  → Creating ${name}..."

    # Build the exec command based on browser
    local exec_cmd
    if [[ "$BROWSER" == "microsoft-edge" ]]; then
        # Edge on Wayland: use --app-id for consistent window class
        exec_cmd="${BROWSER_BIN} --ozone-platform-hint=auto --enable-features=WebAppEnableKeyboardShortcuts --app=${url} --class=${app_id}"
    else
        # Chromium/Chrome: use profile directory to isolate and --class
        exec_cmd="${BROWSER_BIN} --ozone-platform-hint=auto --enable-features=WebAppEnableKeyboardShortcuts --app=${url} --class=${app_id}"
    fi

    cat > "$desktop_file" <<EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=${name}
Comment=${description}
Exec=${exec_cmd}
Icon=${icon}
Categories=Network;${categories}
StartupWMClass=${app_id}
Terminal=false
StartupNotify=true
X-WebApp-URL=${url}
EOF

    chmod +x "$desktop_file"
}

# Create web apps matching NixOS configuration

echo "→ Installing webapp icons..."
echo

# Copy icons from repo to system
copy_icon "youtube"
copy_icon "youtube-music"
copy_icon "claude-ai"
copy_icon "chatgpt"
copy_icon "github"
copy_icon "teams"
copy_icon "nixos"
copy_icon "gmail"
copy_icon "calendar"
copy_icon "x"

echo
echo "→ Creating web app launchers..."
echo

# YouTube
create_webapp \
    "YouTube" \
    "youtube-webapp" \
    "https://youtube.com" \
    "$HOME/.local/share/icons/webapps/youtube.png" \
    "YouTube Video Platform" \
    "AudioVideo;Video;Player;" \
    "youtube"

# YouTube Music
create_webapp \
    "YouTube Music" \
    "youtube-music-webapp" \
    "https://music.youtube.com" \
    "$HOME/.local/share/icons/webapps/youtube-music.png" \
    "YouTube Music Streaming" \
    "AudioVideo;Audio;Player;" \
    "youtube-music"

# Claude AI
create_webapp \
    "Claude AI" \
    "claude-ai" \
    "https://claude.ai/new" \
    "$HOME/.local/share/icons/webapps/claude-ai.png" \
    "Claude AI Assistant" \
    "Development;Utility;" \
    "claude"

# ChatGPT
create_webapp \
    "ChatGPT" \
    "chatgpt" \
    "https://chat.openai.com" \
    "$HOME/.local/share/icons/webapps/chatgpt.png" \
    "ChatGPT AI Assistant" \
    "Development;Utility;" \
    "chatgpt"

# GitHub
create_webapp \
    "GitHub" \
    "github-webapp" \
    "https://github.com" \
    "$HOME/.local/share/icons/webapps/github.png" \
    "GitHub Web Interface" \
    "Development;" \
    "github"

# Microsoft Teams
create_webapp \
    "Microsoft Teams" \
    "ms-teams-webapp" \
    "https://teams.microsoft.com" \
    "$HOME/.local/share/icons/webapps/teams.png" \
    "Microsoft Teams" \
    "Network;InstantMessaging;Office;" \
    "teams"

# NixOS Discourse
create_webapp \
    "NixOS Discourse" \
    "nixos-discourse" \
    "https://discourse.nixos.org" \
    "$HOME/.local/share/icons/webapps/nixos.png" \
    "NixOS Community Forums" \
    "Development;Network;" \
    "nixos-discourse"

# Gmail
create_webapp \
    "Gmail" \
    "gmail-webapp" \
    "https://mail.google.com" \
    "$HOME/.local/share/icons/webapps/gmail.png" \
    "Gmail Web Client" \
    "Office;Email;" \
    "gmail"

# Google Calendar
create_webapp \
    "Google Calendar" \
    "gcalendar-webapp" \
    "https://calendar.google.com" \
    "$HOME/.local/share/icons/webapps/calendar.png" \
    "Google Calendar" \
    "Office;Calendar;" \
    "gcalendar"

# X
create_webapp \
    "X" \
    "x-webapp" \
    "https://x.com" \
    "$HOME/.local/share/icons/webapps/x.png" \
    "X Social Network" \
    "Network;News;" \
    "x"

echo
echo "✓ Created 10 web app launchers"

# Update desktop database
echo
echo "→ Updating desktop database..."
if command -v update-desktop-database &>/dev/null; then
    update-desktop-database ~/.local/share/applications
    echo "✓ Desktop database updated"
fi

echo
echo "=== Web Apps Setup Complete! ==="
echo
echo "Web apps created:"
echo "  • YouTube"
echo "  • YouTube Music"
echo "  • Claude AI"
echo "  • ChatGPT"
echo "  • GitHub"
echo "  • Microsoft Teams"
echo "  • NixOS Discourse"
echo "  • Gmail"
echo "  • Google Calendar"
echo "  • X"
echo
echo "Launch from your application menu or run:"
echo "  youtube-webapp"
echo "  youtube-music-webapp"
echo "  claude-ai"
echo "  chatgpt"
echo "  etc."
echo
echo "Icons installed to: ~/.local/share/icons/webapps/"
echo "Icon source files: $ICONS_DIR"
echo
