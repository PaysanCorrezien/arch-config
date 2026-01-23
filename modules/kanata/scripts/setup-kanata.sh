#!/bin/bash
# Setup Linux permissions and enable the kanata user service

set -e

echo "=== Kanata setup ==="

if ! command -v kanata >/dev/null 2>&1; then
  echo "Error: kanata is not installed. Install it first, then re-run this script."
  exit 1
fi

TARGET_USER="${SUDO_USER:-$USER}"

# Ensure uinput group exists
if ! getent group uinput >/dev/null 2>&1; then
  sudo groupadd uinput
fi

# Grant input/uinput access to the current user
sudo usermod -aG input,uinput "$TARGET_USER"

# Allow the uinput device for the uinput group
RULE_PATH="/etc/udev/rules.d/99-kanata.rules"
sudo tee "$RULE_PATH" >/dev/null <<'RULE'
KERNEL=="uinput", SUBSYSTEM=="misc", MODE="0660", GROUP="uinput", OPTIONS+="static_node=uinput"
RULE

sudo udevadm control --reload-rules
sudo udevadm trigger --name-match=uinput
sudo modprobe uinput

# Ensure permissions stay correct on boot even if udev is late.
TMPFILES_PATH="/etc/tmpfiles.d/kanata-uinput.conf"
sudo tee "$TMPFILES_PATH" >/dev/null <<'RULE'
z /dev/uinput 0660 root uinput -
RULE
sudo systemd-tmpfiles --create "$TMPFILES_PATH"

# Enable the user service if possible
if systemctl --user daemon-reload >/dev/null 2>&1; then
  systemctl --user enable --now kanata.service
  echo "Kanata user service enabled."
else
  echo "Run: systemctl --user enable --now kanata.service"
fi

echo "Note: log out and back in for group changes to take effect."
