#!/usr/bin/env bash
set -euo pipefail

config_dir="/etc/sddm.conf.d"
config_file="${config_dir}/20-autologin.conf"

user_name="${SUDO_USER:-${USER}}"

session="niri.desktop"
if [ -f /usr/share/wayland-sessions/niri.desktop ]; then
  session="niri.desktop"
else
  # Fallback: pick first niri-related Wayland session if present
  first_match=$(ls /usr/share/wayland-sessions 2>/dev/null | rg -i '^niri.*\.desktop$' | head -n 1 || true)
  if [ -n "${first_match}" ]; then
    session="${first_match}"
  fi
fi

sudo install -d "${config_dir}"
sudo tee "${config_file}" >/dev/null <<EOF_CONF
[Autologin]
User=${user_name}
Session=${session}
Relogin=true
EOF_CONF

echo "Configured SDDM autologin for user ${user_name} (session: ${session})."
