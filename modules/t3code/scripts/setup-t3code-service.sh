#!/usr/bin/env bash
set -euo pipefail

desktop_user="${TARGET_USER:-${SUDO_USER:-$USER}}"
if [[ -z "$desktop_user" || "$desktop_user" == root ]]; then
  desktop_user="$(loginctl list-users --no-legend 2>/dev/null | awk '$1 >= 1000 { print $2; exit }')"
fi
desktop_user="${desktop_user:-$USER}"
desktop_home="$(getent passwd "$desktop_user" | cut -d: -f6)"
desktop_uid="$(id -u "$desktop_user")"
module_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

run_as_desktop_user() {
  if [[ "$(id -u)" -eq 0 ]]; then
    sudo -H -u "$desktop_user" env \
      HOME="$desktop_home" \
      XDG_RUNTIME_DIR="/run/user/$desktop_uid" \
      DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$desktop_uid/bus" \
      "$@"
  else
    "$@"
  fi
}

run_as_desktop_user npx --yes t3@latest service install
service_unit="${desktop_home}/.config/systemd/user/t3code.service"
run_as_desktop_user install -d "$(dirname "$service_unit")"
run_as_desktop_user ln -sfn \
  "${module_root}/dotfiles/systemd/user/t3code.service" "$service_unit"
run_as_desktop_user systemctl --user daemon-reload
run_as_desktop_user systemctl --user enable --now t3code.service
run_as_desktop_user systemctl --user restart t3code.service

echo "[t3code] Enabled the always-on T3 Code user service"
