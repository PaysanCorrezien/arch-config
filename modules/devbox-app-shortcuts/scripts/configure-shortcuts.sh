#!/usr/bin/env bash
# Make dedicated app bindings win over Plasma's positional task-manager keys.

set -euo pipefail

desktop_user="${TARGET_USER:-${SUDO_USER:-$USER}}"
if [[ -z "$desktop_user" || "$desktop_user" == "root" ]]; then
  desktop_user="$(loginctl list-users --no-legend 2>/dev/null | awk '$1 >= 1000 { print $2; exit }')"
fi
desktop_user="${desktop_user:-$USER}"
desktop_home="$(getent passwd "$desktop_user" | cut -d: -f6)"
desktop_uid="$(id -u "$desktop_user")"

run_as_desktop_user() {
  if [[ "$(id -u)" -eq 0 ]]; then
    sudo -H -u "$desktop_user" env \
      XDG_RUNTIME_DIR="/run/user/$desktop_uid" \
      DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$desktop_uid/bus" \
      "$@"
  else
    "$@"
  fi
}

shortcut_file="$desktop_home/.config/kglobalshortcutsrc"

# These are default positional bindings.  Clear only the ones claimed below.
for number in 1 2 3 6 7 9; do
  run_as_desktop_user kwriteconfig6 --file "$shortcut_file" --group plasmashell \
    --key "activate task manager entry $number" "none,none,Activate task manager entry $number"
done

# Meta+0 is KWin's default actual-size zoom action.
run_as_desktop_user kwriteconfig6 --file "$shortcut_file" --group kwin \
  --key view_actual_size "none,none,View Actual Size"

# Plasma 6 command shortcuts are desktop entries marked with
# X-KDE-GlobalAccel-CommandShortcut.  Their `_launch` actions live below the
# `services` group, keyed by the desktop-entry basename.
declare -A shortcuts=(
  [devbox-discord.desktop]=Meta+6
  [devbox-terminal.desktop]=Meta+1
  [devbox-keepassxc.desktop]=Meta+7
  [devbox-helium.desktop]=Meta+0
  [devbox-remmina.desktop]=Meta+2
  [devbox-claude.desktop]=Meta+3
  [devbox-chatgpt.desktop]=Meta+X
  [devbox-email.desktop]=Meta+9
  [devbox-x.desktop]=Meta+P
)
declare -A key_codes=(
  [devbox-discord.desktop]=268435510  # Meta+6
  [devbox-terminal.desktop]=268435505 # Meta+1
  [devbox-keepassxc.desktop]=268435511 # Meta+7
  [devbox-helium.desktop]=268435504    # Meta+0
  [devbox-remmina.desktop]=268435506  # Meta+2
  [devbox-claude.desktop]=268435507   # Meta+3
  [devbox-chatgpt.desktop]=268435544  # Meta+X
  [devbox-email.desktop]=268435513    # Meta+9
  [devbox-x.desktop]=268435536        # Meta+P
)
declare -A labels=(
  [devbox-discord.desktop]=Discord
  [devbox-terminal.desktop]=Terminal
  [devbox-keepassxc.desktop]=KeePassXC
  [devbox-helium.desktop]='Helium Browser'
  [devbox-remmina.desktop]=Remmina
  [devbox-claude.desktop]='Claude Desktop'
  [devbox-chatgpt.desktop]=ChatGPT
  [devbox-email.desktop]=Email
  [devbox-x.desktop]=X
)
for desktop_file in "${!shortcuts[@]}"; do
  run_as_desktop_user kwriteconfig6 --file "$shortcut_file" \
    --group services --group "$desktop_file" --key _launch "${shortcuts[$desktop_file]}"
done

# Meta+0 now focuses Helium rather than the Gmail web app.  Remove Gmail's
# previous claim before registering the new owner of that shortcut.
run_as_desktop_user kwriteconfig6 --file "$shortcut_file" \
  --group services --group devbox-gmail.desktop --key _launch none

# Rebuild the desktop-entry cache, then make KGlobalAccel register the
# managed command-shortcut launchers immediately.  This intentionally does not
# restart KWin because that risks destabilising the active display session.
run_as_desktop_user install -d "$desktop_home/.local/share/kglobalaccel"
run_as_desktop_user kbuildsycoca6 --noincremental
run_as_desktop_user systemctl --user restart plasma-kglobalaccel.service

# Register command shortcuts over the active session bus as well.  Merely
# writing kglobalshortcutsrc defers discovery until a compositor restart;
# registration here makes the new bindings live without touching KWin.
for desktop_file in "${!shortcuts[@]}"; do
  label="${labels[$desktop_file]}"
  run_as_desktop_user busctl --user call org.kde.kglobalaccel /kglobalaccel \
    org.kde.KGlobalAccel doRegister as 4 "$desktop_file" _launch "$label" "Focus or launch $label"
  run_as_desktop_user busctl --user call org.kde.kglobalaccel /kglobalaccel \
    org.kde.KGlobalAccel setShortcut asaiu 4 "$desktop_file" _launch "$label" \
    "Focus or launch $label" 1 "${key_codes[$desktop_file]}" 0 >/dev/null
done

echo "[devbox-app-shortcuts] Installed Meta+0/1/2/3/6/7/9/X/P application bindings"
