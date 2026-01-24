#!/usr/bin/env bash
# Post-install setup script for Tmux

set -euo pipefail

echo "=== Tmux Post-Install Setup ==="
echo

target_user="${SUDO_USER:-$USER}"
if [ -n "${target_user}" ] && [ "${target_user}" != "root" ]; then
  user_home="$(getent passwd "${target_user}" | cut -d: -f6)"
else
  user_home="$HOME"
fi

run_user_cmd() {
  if [ "$(id -u)" -eq 0 ] && [ -n "${SUDO_USER:-}" ]; then
    sudo -u "${target_user}" XDG_RUNTIME_DIR="/run/user/$(id -u "${target_user}")" "$@"
  else
    "$@"
  fi
}

# Fix ownership from prior root runs so user writes work reliably.
if [ "$(id -u)" -eq 0 ] && [ "${target_user}" != "root" ]; then
  for path in "${user_home}/.tmux" "${user_home}/.config/scripts" "${user_home}/.config/tmux"; do
    if [ -e "${path}" ] && [ "$(stat -c %u "${path}")" -ne "$(id -u "${target_user}")" ]; then
      chown -R "${target_user}:${target_user}" "${path}"
    fi
  done
fi

# Create necessary directories
echo "→ Creating tmux directories..."
run_user_cmd mkdir -p "${user_home}/.config/tmux"
run_user_cmd mkdir -p "${user_home}/.config/scripts"
run_user_cmd mkdir -p "${user_home}/.config/tmux/plugins"
run_user_cmd mkdir -p "${user_home}/.tmux/resurrect"
run_user_cmd mkdir -p "${user_home}/.tmux/scripts"
run_user_cmd mkdir -p "${user_home}/Notes"
echo "✓ Directories created"

# Migrate plugins from legacy path if present
legacy_plugins_dir="${user_home}/.tmux/plugins"
xdg_plugins_dir="${user_home}/.config/tmux/plugins"
if [ -d "${legacy_plugins_dir}" ] && [ ! -d "${xdg_plugins_dir}/tpm" ]; then
  echo "→ Migrating tmux plugins to XDG path..."
  run_user_cmd mkdir -p "${xdg_plugins_dir}"
  run_user_cmd cp -a "${legacy_plugins_dir}/." "${xdg_plugins_dir}/" 2>/dev/null || true
  echo "✓ Plugin migration complete"
fi

# Copy and make executable all helper scripts
echo
echo "→ Installing tmux helper scripts..."

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# List of scripts to install
scripts=(
  "tmux-copymode-process-clipboard.sh"
  "tmux-copy-to-clipboard.sh"
  "tmux-copy-to-clipboard-pipe.sh"
  "tmux-rename-window.sh"
  "tmux-rename-pane.sh"
  "tmux-pane-history.sh"
  "tmux-pane-back.sh"
  "tmux-pane-forward.sh"
  "tmux-config-toggle.sh"
  "tmux-notes-toggle.sh"
  "pwsh-interactive.sh"
  "save_tmux_context.sh"
)

for script in "${scripts[@]}"; do
  if [ -f "$SCRIPT_DIR/$script" ]; then
    run_user_cmd cp "$SCRIPT_DIR/$script" "${user_home}/.config/scripts/"
    run_user_cmd chmod +x "${user_home}/.config/scripts/$script"
    echo "  ✓ Installed $script"
  else
    echo "  ⚠ Warning: $script not found"
  fi
done

echo "✓ Helper scripts installed"

# Install ensure-session helper script
if [ -f "$SCRIPT_DIR/ensure-session" ]; then
  run_user_cmd cp "$SCRIPT_DIR/ensure-session" "${user_home}/.tmux/scripts/ensure-session"
  run_user_cmd chmod +x "${user_home}/.tmux/scripts/ensure-session"
  echo "✓ Installed ensure-session"
else
  echo "⚠ Warning: ensure-session not found"
fi

# Install TPM (Tmux Plugin Manager) if not already installed
echo
echo "→ Installing TPM (Tmux Plugin Manager) for ${target_user}..."
if [ ! -d "${user_home}/.config/tmux/plugins/tpm" ]; then
  run_user_cmd git clone https://github.com/tmux-plugins/tpm "${user_home}/.config/tmux/plugins/tpm"
  echo "✓ TPM installed"
else
  echo "✓ TPM already installed"
fi

# Install critical tmux plugins manually (TPM sometimes fails to clone)
echo
echo "→ Installing critical tmux plugins..."
plugins_dir="${user_home}/.config/tmux/plugins"

critical_plugins=(
  "tmux-plugins/tmux-sensible"
  "christoomey/vim-tmux-navigator"
  "tmux-plugins/tmux-resurrect"
  "tmux-plugins/tmux-continuum"
  "laktak/extrakto"
  "catppuccin/tmux"
  "sainnhe/tmux-fzf"
  "wfxr/tmux-fzf-url"
  "omerxx/tmux-floax"
)

for plugin in "${critical_plugins[@]}"; do
  plugin_name=$(basename "$plugin")
  plugin_path="${plugins_dir}/${plugin_name}"

  if [ ! -d "$plugin_path" ]; then
    echo "  → Installing $plugin_name..."
    run_user_cmd git clone "https://github.com/${plugin}" "$plugin_path" 2>/dev/null || true
  else
    echo "  ✓ $plugin_name already installed"
  fi
done

echo "✓ Critical plugins installed"

# Run TPM install as well (for any remaining plugins)
echo
echo "→ Running TPM plugin installation..."
tmux_conf="${user_home}/.config/tmux/tmux.conf"
if [ -d "${user_home}/.config/tmux/plugins/tpm" ] && [ -f "${tmux_conf}" ]; then
  TMUX_PLUGIN_MANAGER_PATH="${user_home}/.config/tmux/plugins" \
    run_user_cmd "${user_home}/.config/tmux/plugins/tpm/bin/install_plugins" 2>/dev/null || true
  echo "✓ TPM plugin installation complete"
elif [ ! -f "${tmux_conf}" ]; then
  echo "⚠ tmux.conf not found; skipping TPM plugin installation"
else
  echo "⚠ TPM not found, skipping TPM plugin installation"
fi

# Verify clipboard helper exists
echo
echo "→ Verifying clipboard helper..."
if [ -f "${user_home}/.config/scripts/clipboard-copy.sh" ]; then
  echo "✓ Clipboard helper found"
else
  echo "⚠ Warning: Clipboard helper not found"
  echo "  The shell-config module should have created it"
  echo "  You may need to enable the shell-config module"
fi

# Check if tmux is running and offer to reload config
echo
if [ -n "${TMUX:-}" ]; then
  echo "→ Tmux is currently running"
  read -p "Would you like to reload the tmux config now? [y/N] " -n 1 -r
  echo
  if [[ $REPLY =~ ^[Yy]$ ]]; then
    run_user_cmd tmux source-file "${tmux_conf}"
    echo "✓ Tmux config reloaded"
  else
    echo "  You can reload later with: tmux source-file ${tmux_conf}"
  fi
else
  echo "→ Tmux is not currently running"
  echo "  Start tmux to load the new configuration"
fi

echo
echo "=== Tmux Setup Complete! ==="
echo
echo "Key Features Enabled:"
echo "  • TPM (Tmux Plugin Manager) with auto-install"
echo "  • Vim-tmux navigator for seamless navigation"
echo "  • Resurrect + Continuum for session persistence"
echo "  • Catppuccin Mocha theme"
echo "  • Sesh session manager (Prefix + f)"
echo "  • Pane history navigation (Prefix + b/B)"
echo "  • Notes session toggle (Prefix + N)"
echo "  • LazyGit popup (Prefix + g)"
echo "  • Floax floating windows (Prefix + w)"
echo
echo "Key Bindings:"
echo "  Prefix: Ctrl+A (or Ctrl+Space)"
echo "  Split horizontal: Prefix + s"
echo "  Split vertical: Prefix + v"
echo "  New window: Prefix + t"
echo "  Pane navigation: Prefix + h/j/k/l"
echo "  Session manager: Prefix + f"
echo "  LazyGit: Prefix + g"
echo "  Reload config: Prefix + R"
echo
echo "Next steps:"
echo "  1. Start tmux: tmux"
echo "  2. Press Prefix + I to install/update plugins (if needed)"
echo "  3. Press Prefix + f to try the session manager"
echo
