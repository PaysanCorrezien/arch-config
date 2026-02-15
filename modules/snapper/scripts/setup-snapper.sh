#!/usr/bin/env bash
set -euo pipefail

echo "=== Snapper + GRUB snapshots setup ==="
echo ""

require_cmd() {
  local cmd="$1"
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    echo "Error: '${cmd}' is not installed."
    exit 1
  fi
}

require_cmd snapper
require_cmd btrfs

root_fstype="$(findmnt -no FSTYPE /)"
if [ "${root_fstype}" != "btrfs" ]; then
  echo "Error: Root filesystem is not Btrfs (found: ${root_fstype})."
  exit 1
fi

home_fstype="$(findmnt -no FSTYPE /home || true)"
if [ "${home_fstype}" != "btrfs" ]; then
  echo "Warning: /home is not Btrfs (found: ${home_fstype:-none})."
  echo "Home snapshots will be skipped."
fi

set_snapper_value() {
  local config_file="$1"
  local key="$2"
  local value="$3"

  if sudo grep -q "^${key}=" "${config_file}"; then
    sudo sed -i "s|^${key}=.*|${key}=\"${value}\"|" "${config_file}"
  else
    echo "${key}=\"${value}\"" | sudo tee -a "${config_file}" >/dev/null
  fi
}

echo "[1/6] Creating snapper configs if missing..."
if [ ! -f /etc/snapper/configs/root ]; then
  sudo snapper -c root create-config /
  echo "  ✓ Created root snapper config"
else
  echo "  ✓ Root snapper config already exists"
fi

if [ "${home_fstype}" = "btrfs" ]; then
  if [ ! -f /etc/snapper/configs/home ]; then
    sudo snapper -c home create-config /home
    echo "  ✓ Created home snapper config"
  else
    echo "  ✓ Home snapper config already exists"
  fi
fi

echo ""
echo "[2/6] Configuring snapper policies..."

# Root config - More aggressive retention for server use
set_snapper_value /etc/snapper/configs/root TIMELINE_CREATE yes
set_snapper_value /etc/snapper/configs/root TIMELINE_CLEANUP yes
set_snapper_value /etc/snapper/configs/root NUMBER_CLEANUP yes
set_snapper_value /etc/snapper/configs/root TIMELINE_LIMIT_HOURLY 24
set_snapper_value /etc/snapper/configs/root TIMELINE_LIMIT_DAILY 14
set_snapper_value /etc/snapper/configs/root TIMELINE_LIMIT_WEEKLY 8
set_snapper_value /etc/snapper/configs/root TIMELINE_LIMIT_MONTHLY 12
set_snapper_value /etc/snapper/configs/root TIMELINE_LIMIT_YEARLY 3

# Home config - Less aggressive retention (files change less frequently)
if [ "${home_fstype}" = "btrfs" ] && [ -f /etc/snapper/configs/home ]; then
  set_snapper_value /etc/snapper/configs/home TIMELINE_CREATE yes
  set_snapper_value /etc/snapper/configs/home TIMELINE_CLEANUP yes
  set_snapper_value /etc/snapper/configs/home NUMBER_CLEANUP yes
  set_snapper_value /etc/snapper/configs/home TIMELINE_LIMIT_HOURLY 12
  set_snapper_value /etc/snapper/configs/home TIMELINE_LIMIT_DAILY 7
  set_snapper_value /etc/snapper/configs/home TIMELINE_LIMIT_WEEKLY 4
  set_snapper_value /etc/snapper/configs/home TIMELINE_LIMIT_MONTHLY 6
  set_snapper_value /etc/snapper/configs/home TIMELINE_LIMIT_YEARLY 2
fi

echo "  ✓ Snapper policies updated with retention limits"

echo ""
echo "[3/6] Enabling snapper timers..."
sudo systemctl enable --now snapper-timeline.timer snapper-cleanup.timer
echo "  ✓ snapper-timeline.timer and snapper-cleanup.timer enabled"

echo ""
echo "[4/6] Enabling GRUB snapshot integration..."
grub_unit=""
if systemctl list-unit-files --type=path | rg -q '^grub-btrfs\.path'; then
  grub_unit="grub-btrfs.path"
elif systemctl list-unit-files --type=service | rg -q '^grub-btrfsd\.service'; then
  grub_unit="grub-btrfsd.service"
fi

if [ -n "${grub_unit}" ]; then
  sudo systemctl enable --now "${grub_unit}"
  echo "  ✓ ${grub_unit} enabled"
else
  echo "  ⚠ grub-btrfs unit not found; install grub-btrfs to enable GRUB snapshot entries"
fi

if command -v grub-mkconfig >/dev/null 2>&1 && [ -d /boot/grub ]; then
  sudo grub-mkconfig -o /boot/grub/grub.cfg >/dev/null
  echo "  ✓ GRUB configuration regenerated"
else
  echo "  ⚠ grub-mkconfig or /boot/grub not found; skipped GRUB config regeneration"
fi

echo ""
echo "[5/6] Snapshot hooks..."
if ls /etc/pacman.d/hooks/*snapper* >/dev/null 2>&1; then
  echo "  ✓ snap-pac hooks found in /etc/pacman.d/hooks"
else
  echo "  ⚠ snap-pac hooks not found; verify snap-pac is installed"
fi

echo ""
echo "[6/6] Verification summary..."
if sudo snapper list-configs | awk 'NR>2 {print $1}' | rg -q '^root$'; then
  echo "  ✓ snapper config: root"
else
  echo "  ✗ snapper config: root (missing)"
fi

if [ "${home_fstype}" = "btrfs" ]; then
  if sudo snapper list-configs | awk 'NR>2 {print $1}' | rg -q '^home$'; then
    echo "  ✓ snapper config: home"
  else
    echo "  ✗ snapper config: home (missing)"
  fi
fi

if systemctl is-enabled --quiet snapper-timeline.timer; then
  echo "  ✓ snapper-timeline.timer enabled"
else
  echo "  ✗ snapper-timeline.timer not enabled"
fi

if systemctl is-enabled --quiet snapper-cleanup.timer; then
  echo "  ✓ snapper-cleanup.timer enabled"
else
  echo "  ✗ snapper-cleanup.timer not enabled"
fi

if [ -n "${grub_unit}" ]; then
  if systemctl is-enabled --quiet "${grub_unit}"; then
    echo "  ✓ ${grub_unit} enabled"
  else
    echo "  ✗ ${grub_unit} not enabled"
  fi
fi

echo ""
echo "Setup complete. You can list snapshots with:"
echo "  sudo snapper -c root list"
if [ "${home_fstype}" = "btrfs" ]; then
  echo "  sudo snapper -c home list"
fi
