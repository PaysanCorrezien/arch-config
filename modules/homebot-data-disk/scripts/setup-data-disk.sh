#!/usr/bin/env bash
set -euo pipefail

DISK="/dev/sda"
MOUNT_POINT="/data"
SUBVOL_NAME="@data"
user_name="${SUDO_USER:-${USER}}"

echo "=== Homebot 4TB Data Disk Setup ==="
echo ""
echo "⚠️  WARNING: This will ERASE ALL DATA on ${DISK}!"
echo "    Disk: ${DISK} (4TB Seagate)"
echo "    Mount: ${MOUNT_POINT}"
echo "    Filesystem: btrfs with zstd:3 compression"
echo ""
read -p "Type 'YES' to continue: " confirm
if [ "${confirm}" != "YES" ]; then
  echo "Aborted."
  exit 1
fi

echo ""
echo "[1/7] Checking prerequisites..."
if ! command -v btrfs >/dev/null 2>&1; then
  echo "Error: btrfs-progs not installed"
  exit 1
fi

if ! command -v snapper >/dev/null 2>&1; then
  echo "Error: snapper not installed"
  exit 1
fi

if [ ! -b "${DISK}" ]; then
  echo "Error: ${DISK} is not a block device"
  exit 1
fi

echo "  ✓ Prerequisites OK"

echo ""
echo "[2/7] Partitioning ${DISK}..."
sudo parted -s "${DISK}" mklabel gpt
sudo parted -s "${DISK}" mkpart primary btrfs 0% 100%
sudo partprobe "${DISK}"
sleep 2

PARTITION="${DISK}1"
if [ ! -b "${PARTITION}" ]; then
  echo "Error: Partition ${PARTITION} not found after partitioning"
  exit 1
fi

echo "  ✓ Created partition ${PARTITION}"

echo ""
echo "[3/7] Formatting ${PARTITION} as btrfs..."
sudo mkfs.btrfs -f -L "homebot-data" "${PARTITION}"
echo "  ✓ Formatted as btrfs with label 'homebot-data'"

echo ""
echo "[4/7] Creating btrfs subvolume..."
# Mount temporarily to create subvolume
sudo mkdir -p /mnt/temp-data
sudo mount "${PARTITION}" /mnt/temp-data

# Create @data subvolume
sudo btrfs subvolume create "/mnt/temp-data/${SUBVOL_NAME}"
echo "  ✓ Created subvolume ${SUBVOL_NAME}"

# Get subvolume ID for fstab
SUBVOL_ID=$(sudo btrfs subvolume list /mnt/temp-data | grep "${SUBVOL_NAME}" | awk '{print $2}')
echo "  ✓ Subvolume ID: ${SUBVOL_ID}"

sudo umount /mnt/temp-data
sudo rmdir /mnt/temp-data

echo ""
echo "[5/7] Mounting at ${MOUNT_POINT}..."
sudo mkdir -p "${MOUNT_POINT}"

# Mount with compression
sudo mount -o compress=zstd:3,subvol="${SUBVOL_NAME}" "${PARTITION}" "${MOUNT_POINT}"
echo "  ✓ Mounted with zstd:3 compression"

# Add to fstab
FSTAB_ENTRY="UUID=$(sudo blkid -s UUID -o value ${PARTITION}) ${MOUNT_POINT} btrfs compress=zstd:3,subvol=${SUBVOL_NAME} 0 0"

if ! grep -q "${MOUNT_POINT}" /etc/fstab; then
  echo "# Homebot 4TB data disk" | sudo tee -a /etc/fstab >/dev/null
  echo "${FSTAB_ENTRY}" | sudo tee -a /etc/fstab >/dev/null
  echo "  ✓ Added to /etc/fstab"
else
  echo "  ⚠ ${MOUNT_POINT} already in /etc/fstab, skipping"
fi

echo ""
echo "[6/7] Configuring snapper for ${MOUNT_POINT}..."
if [ ! -f /etc/snapper/configs/data ]; then
  sudo snapper -c data create-config "${MOUNT_POINT}"
  echo "  ✓ Created snapper config 'data'"

  # Configure retention policy for data disk
  sudo sed -i 's|^TIMELINE_LIMIT_HOURLY=.*|TIMELINE_LIMIT_HOURLY="12"|' /etc/snapper/configs/data
  sudo sed -i 's|^TIMELINE_LIMIT_DAILY=.*|TIMELINE_LIMIT_DAILY="7"|' /etc/snapper/configs/data
  sudo sed -i 's|^TIMELINE_LIMIT_WEEKLY=.*|TIMELINE_LIMIT_WEEKLY="4"|' /etc/snapper/configs/data
  sudo sed -i 's|^TIMELINE_LIMIT_MONTHLY=.*|TIMELINE_LIMIT_MONTHLY="6"|' /etc/snapper/configs/data
  sudo sed -i 's|^TIMELINE_LIMIT_YEARLY=.*|TIMELINE_LIMIT_YEARLY="2"|' /etc/snapper/configs/data
  echo "  ✓ Configured retention policy (12h, 7d, 4w, 6m, 2y)"
else
  echo "  ✓ Snapper config 'data' already exists"
fi

echo ""
echo "[7/7] Setting ownership..."
sudo chown -R "${user_name}:${user_name}" "${MOUNT_POINT}"
echo "  ✓ Ownership set to ${user_name}"

echo ""
echo "=== Setup Complete ==="
echo ""
echo "Your 4TB data disk is ready:"
echo "  Location: ${MOUNT_POINT}"
echo "  Filesystem: btrfs with zstd:3 compression"
echo "  Subvolume: ${SUBVOL_NAME}"
echo "  Snapshots: Managed by snapper (config: data)"
echo "  Owner: ${user_name}"
echo ""
echo "Usage:"
echo "  - Store data directly in ${MOUNT_POINT}/"
echo "  - Docker volumes: ${MOUNT_POINT}/docker-volumes/"
echo "  - View snapshots: sudo snapper -c data list"
echo "  - Check space: df -h ${MOUNT_POINT}"
echo ""
