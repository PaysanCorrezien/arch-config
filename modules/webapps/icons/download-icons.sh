#!/usr/bin/env bash
# Download all webapp icons to the repo
# Run this once to populate the icons directory

set -euo pipefail

cd "$(dirname "$0")"

echo "Downloading webapp icons..."
echo

download() {
    local name="$1"
    local url="$2"

    if [[ -f "${name}.png" ]]; then
        echo "  ✓ ${name}.png already exists"
        return
    fi

    echo "  → Downloading ${name}.png..."
    if command -v curl &>/dev/null; then
        curl -sL "$url" -o "${name}.png" || echo "    ✗ Failed"
    elif command -v wget &>/dev/null; then
        wget -q "$url" -O "${name}.png" || echo "    ✗ Failed"
    else
        echo "    ✗ curl or wget required"
        exit 1
    fi
}

# Download all icons from dashboard-icons CDN (homarr-labs/dashboard-icons)
# CDN: https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/<icon-name>.png
download "youtube" "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/youtube.png"
download "youtube-music" "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/youtube-music.png"
download "claude-ai" "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/claude-ai.png"
download "chatgpt" "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/chatgpt.png"
download "github" "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/github.png"
download "teams" "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/microsoft-teams.png"
download "nixos" "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/nixos.png"
download "gmail" "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/gmail.png"
download "calendar" "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/google-calendar.png"

echo
echo "✓ Icon download complete!"
echo "All icons sourced from: https://github.com/homarr-labs/dashboard-icons"
