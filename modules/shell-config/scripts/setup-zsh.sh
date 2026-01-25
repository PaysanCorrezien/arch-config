#!/usr/bin/env bash
# Post-install setup script for ZSH

set -euo pipefail

echo "=== ZSH Post-Install Setup ==="
echo

target_user="${SUDO_USER:-$USER}"
if [ -n "${target_user}" ] && [ "${target_user}" != "root" ]; then
  user_home="$(getent passwd "${target_user}" | cut -d: -f6)"
else
  user_home="$HOME"
fi

# Add user to docker group
echo "→ Adding user to docker group..."
if getent group docker >/dev/null 2>&1; then
  sudo usermod -aG docker "$target_user"
  echo "✓ User added to docker group"
else
  echo "⚠ docker group not found, skipping"
fi
echo

# Create config directories
echo "→ Creating ZSH config directories..."
mkdir -p "${user_home}/.config/zsh"
mkdir -p "${user_home}/.config/scripts"
echo "✓ Directories created"

# Setup npm global directory
echo
echo "→ Setting up npm global directory..."
mkdir -p "${user_home}/.npm-global"
if command -v npm &>/dev/null; then
  sudo -u "${target_user}" npm config set prefix "${user_home}/.npm-global"
  echo "✓ npm global directory configured"
else
  echo "⚠ npm not found, skipping npm configuration"
fi

# Create clipboard copy script
echo
echo "→ Creating clipboard helper script..."
cat > "${user_home}/.config/scripts/clipboard-copy.sh" <<'EOF'
#!/usr/bin/env bash
# Clipboard copy helper - works with xclip or wl-clipboard

if command -v wl-copy &>/dev/null; then
  # Wayland
  wl-copy
elif command -v xclip &>/dev/null; then
  # X11
  xclip -selection clipboard
else
  echo "Error: Neither wl-copy nor xclip found" >&2
  exit 1
fi
EOF

chmod +x "${user_home}/.config/scripts/clipboard-copy.sh"
echo "✓ Clipboard helper created"

# Create empty secrets file if it doesn't exist
echo
echo "→ Creating secrets file template..."
if [ ! -f "${user_home}/.config/zsh/secrets.zsh" ]; then
  cat > "${user_home}/.config/zsh/secrets.zsh" <<'EOF'
# Secret environment variables and API keys
# This file is sourced by .zshrc

# Example:
# export OPENAI_API_KEY="your-key-here"
# export GITHUB_TOKEN="your-token-here"
EOF
  echo "✓ Secrets template created at ${user_home}/.config/zsh/secrets.zsh"
else
  echo "✓ Secrets file already exists"
fi

# Set ZSH as default shell
echo
echo "→ Setting ZSH as default shell..."
zsh_path="$(command -v zsh)"
if command -v getent &>/dev/null; then
  current_shell="$(getent passwd "${target_user}" | cut -d: -f7)"
else
  current_shell="$SHELL"
fi
if [ -z "$current_shell" ]; then
  current_shell="$SHELL"
fi
if [ "$current_shell" != "$zsh_path" ]; then
  echo "Current shell: $current_shell"
  echo "Changing to: $zsh_path"
  chsh -s "$zsh_path" "${target_user}"
  echo "✓ Default shell changed to ZSH"
  echo "  (You'll need to log out and back in for this to take effect)"
else
  echo "✓ ZSH is already the default shell"
fi

echo
echo "=== ZSH Setup Complete! ==="
echo
echo "Next steps:"
echo "  1. Log out and log back in (or run: exec zsh)"
echo "  2. Edit ~/.config/zsh/secrets.zsh to add your API keys"
echo "  3. Customize ~/.config/zsh/aliases.zsh as needed"
echo
