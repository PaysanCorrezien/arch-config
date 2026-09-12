#!/usr/bin/env bash
set -euo pipefail

desktop_file="devbox-keyboard-shortcuts.desktop"
shortcut="Meta+Shift+K"
shortcut_code=301989963 # Qt Meta + Shift + K
label="Keyboard shortcuts"
description="Show active Plasma keyboard shortcuts"
shortcut_file="${HOME}/.config/kglobalshortcutsrc"

kwriteconfig6 --file "$shortcut_file" --group services \
  --group "$desktop_file" --key _launch "$shortcut"
kbuildsycoca6 --noincremental
systemctl --user restart plasma-kglobalaccel.service
busctl --user call org.kde.kglobalaccel /kglobalaccel \
  org.kde.KGlobalAccel doRegister as 4 "$desktop_file" _launch "$label" "$description"
busctl --user call org.kde.kglobalaccel /kglobalaccel \
  org.kde.KGlobalAccel setShortcut asaiu 4 "$desktop_file" _launch \
  "$label" "$description" 1 "$shortcut_code" 4 >/dev/null

echo "[devbox-keyboard-helper] Registered Meta+Shift+K"
