#!/usr/bin/env bash
# Post-install setup for Espanso (Wayland)

set -euo pipefail

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

espanso_bin="$(command -v espanso || true)"
if [ -z "${espanso_bin}" ]; then
  echo "⚠️  espanso not found in PATH; skipping setup"
  exit 0
fi

if command -v setcap >/dev/null 2>&1; then
  if [ "$(id -u)" -eq 0 ]; then
    setcap "cap_dac_override+p" "${espanso_bin}"
  else
    sudo setcap "cap_dac_override+p" "${espanso_bin}"
  fi
  echo "✓ Granted CAP_DAC_OVERRIDE to ${espanso_bin}"
else
  echo "⚠️  setcap not found; install 'libcap' and re-run this hook"
fi

if command -v systemctl >/dev/null 2>&1; then
  run_user_cmd espanso service register

  # Patch systemd service for Wayland/niri compatibility
  service_file="${user_home}/.config/systemd/user/espanso.service"
  if [ -f "${service_file}" ]; then
    # Add environment variables if not already present
    if ! grep -q "WAYLAND_DISPLAY" "${service_file}"; then
      sed -i '/^\[Service\]/a Environment="WAYLAND_DISPLAY=wayland-1"\nEnvironment="XDG_CURRENT_DESKTOP=niri"\nEnvironment="GTK_THEME="' "${service_file}"
      echo "✓ Patched espanso.service for Wayland/niri"
    fi
  fi

  run_user_cmd systemctl --user daemon-reload
  run_user_cmd systemctl --user enable --now espanso.service
  echo "✓ Espanso user service enabled"
else
  echo "⚠️  systemctl not found; skipping espanso service enablement"
fi

if [ -d "${user_home}/.config/espanso" ]; then
  echo "ℹ️  Espanso config dir: ${user_home}/.config/espanso"
  echo "    If using non-US layout, set keyboard_layout in default.yml"
fi
