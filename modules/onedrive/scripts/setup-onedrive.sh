#!/usr/bin/env bash
# Post-install setup script for OneDrive

set -euo pipefail

target_user="${SUDO_USER:-$USER}"
if [ -n "${target_user}" ] && [ "${target_user}" != "root" ]; then
  user_home="$(getent passwd "${target_user}" | cut -d: -f6)"
else
  user_home="$HOME"
fi

echo "→ Enabling OneDrive user service for ${target_user}..."

oneD_path="${user_home}/.config/scripts/oneD"
if [ -f "${oneD_path}" ]; then
  chmod +x "${oneD_path}"
else
  echo "⚠️  ${oneD_path} not found; dotfiles may not be synced yet"
fi

run_user_cmd() {
  if [ "$(id -u)" -eq 0 ] && [ -n "${SUDO_USER:-}" ]; then
    sudo -u "${target_user}" XDG_RUNTIME_DIR="/run/user/$(id -u "${target_user}")" "$@"
  else
    "$@"
  fi
}

if command -v systemctl >/dev/null 2>&1; then
  run_user_cmd systemctl --user daemon-reload
  run_user_cmd systemctl --user enable --now onedrive.service
  echo "✓ OneDrive service enabled"
else
  echo "⚠️  systemctl not found; skip enabling onedrive.service"
fi
