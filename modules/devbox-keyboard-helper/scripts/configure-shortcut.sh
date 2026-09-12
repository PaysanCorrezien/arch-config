#!/usr/bin/env bash
set -euo pipefail

desktop_file="devbox-keyboard-shortcuts.desktop"
shortcut="Meta+Shift+K"
shortcut_code=301989963 # Qt Meta + Shift + K
label="Keyboard shortcuts"
description="Show active Plasma keyboard shortcuts"
desktop_user="${TARGET_USER:-${SUDO_USER:-$USER}}"
if [[ -z "$desktop_user" || "$desktop_user" == "root" ]]; then
  desktop_user="$(loginctl list-users --no-legend 2>/dev/null | awk '$1 >= 1000 { print $2; exit }')"
fi
desktop_user="${desktop_user:-$USER}"
desktop_home="$(getent passwd "$desktop_user" | cut -d: -f6)"
desktop_uid="$(id -u "$desktop_user")"
shortcut_file="$desktop_home/.config/kglobalshortcutsrc"

run_as_desktop_user() {
  if [[ "$(id -u)" -eq 0 && "$desktop_user" != "root" ]]; then
    sudo -H -u "$desktop_user" env \
      HOME="$desktop_home" \
      XDG_RUNTIME_DIR="/run/user/$desktop_uid" \
      DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$desktop_uid/bus" \
      "$@"
  else
    env \
      HOME="$desktop_home" \
      XDG_RUNTIME_DIR="/run/user/$desktop_uid" \
      DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$desktop_uid/bus" \
      "$@"
  fi
}

run_as_desktop_user kwriteconfig6 --file "$shortcut_file" --group services \
  --group "$desktop_file" --key _launch "$shortcut"
run_as_desktop_user kbuildsycoca6 --noincremental
run_as_desktop_user systemctl --user restart plasma-kglobalaccel.service
run_as_desktop_user busctl --user call org.kde.kglobalaccel /kglobalaccel \
  org.kde.KGlobalAccel doRegister as 4 "$desktop_file" _launch "$label" "$description"
run_as_desktop_user busctl --user call org.kde.kglobalaccel /kglobalaccel \
  org.kde.KGlobalAccel setShortcut asaiu 4 "$desktop_file" _launch \
  "$label" "$description" 1 "$shortcut_code" 4 >/dev/null

echo "[devbox-keyboard-helper] Registered Meta+Shift+K"
