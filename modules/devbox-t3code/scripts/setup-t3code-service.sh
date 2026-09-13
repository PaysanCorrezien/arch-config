#!/usr/bin/env bash
set -euo pipefail

desktop_user="${TARGET_USER:-${SUDO_USER:-$USER}}"
if [[ -z "$desktop_user" || "$desktop_user" == root ]]; then
  desktop_user="$(loginctl list-users --no-legend 2>/dev/null | awk '$1 >= 1000 { print $2; exit }')"
fi
desktop_user="${desktop_user:-$USER}"
desktop_home="$(getent passwd "$desktop_user" | cut -d: -f6)"
desktop_uid="$(id -u "$desktop_user")"

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
pty_prestart="ExecStartPre=${desktop_home}/.config/dcli/modules/devbox-t3code/scripts/prepare-node-pty.sh"
if ! grep -Fxq "$pty_prestart" "$service_unit"; then
  sed -i "/^\[Service\]$/a ${pty_prestart}" "$service_unit"
fi
run_as_desktop_user systemctl --user daemon-reload
run_as_desktop_user systemctl --user enable --now t3code.service
run_as_desktop_user systemctl --user restart t3code.service

echo "[devbox-t3code] Enabled the always-on T3 Code user service"
