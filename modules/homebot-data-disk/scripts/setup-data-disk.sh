#!/usr/bin/env bash
# The current homebot stores /data in @data on the existing root filesystem.
# Never partition or format a disk during dcli sync.
set -euo pipefail
mount_point=/data
if mountpoint -q "$mount_point"; then
  echo "Existing /data mount preserved: $(findmnt -n -o SOURCE,FSTYPE --mountpoint "$mount_point")"
  exit 0
fi
if ! findmnt --fstab --mountpoint "$mount_point" >/dev/null; then
  uuid="$(findmnt -n -o UUID --mountpoint /)"
  if [[ -z "$uuid" || "$(findmnt -n -o FSTYPE --mountpoint /)" != btrfs ]] ||
    ! sudo btrfs subvolume list / | awk '$NF == "@data" {found=1} END {exit !found}'; then
    echo 'Restore the existing @data subvolume or its fstab entry before syncing.' >&2
    exit 1
  fi
  printf '\n# homebot existing @data subvolume\nUUID=%s /data btrfs noatime,compress=zstd:3,subvol=@data 0 0\n' "$uuid" | sudo tee -a /etc/fstab >/dev/null
fi
sudo install -d "$mount_point"
sudo systemctl daemon-reload
sudo mount "$mount_point"
echo 'Existing /data subvolume mounted; no formatting, snapshot or ownership changes.'
