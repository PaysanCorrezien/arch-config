#!/usr/bin/env bash
# Configure ZFS on gpu host:
#   - load zfs kernel module
#   - import existing "mediapool" mirror (sda + sdb) if present
#   - otherwise offer to create a fresh mirror on those two disks
#   - enable zfs services so the pool comes back on reboot
set -euo pipefail

POOL_NAME="mediapool"
DISK_A="/dev/sda"
DISK_B="/dev/sdb"

echo "=== gpu-zfs setup ==="

if ! command -v zpool >/dev/null 2>&1; then
  echo "Error: zpool not in PATH — zfs-utils not installed yet."
  echo "Re-run after dcli finishes installing packages."
  exit 1
fi

echo ""
echo "[1/5] Loading zfs kernel module..."
if ! lsmod | grep -q '^zfs '; then
  if ! sudo modprobe zfs; then
    echo "  ✗ modprobe zfs failed."
    echo "    The DKMS module probably hasn't built yet for kernel $(uname -r)."
    echo "    Try: sudo dkms autoinstall && sudo modprobe zfs"
    exit 1
  fi
fi
echo "  ✓ zfs module loaded"

echo ""
echo "[2/5] Looking for existing pools..."
if zpool list -H -o name 2>/dev/null | grep -qx "${POOL_NAME}"; then
  echo "  ✓ Pool '${POOL_NAME}' already imported"
elif sudo zpool import 2>/dev/null | grep -q "pool: ${POOL_NAME}"; then
  echo "  Found exportable pool '${POOL_NAME}', importing..."
  sudo zpool import -f "${POOL_NAME}"
  echo "  ✓ Imported '${POOL_NAME}'"
else
  echo "  No existing '${POOL_NAME}' detected on this system."
  # Check if the target disks already carry zfs labels for some other pool
  if sudo blkid "${DISK_A}1" 2>/dev/null | grep -q zfs_member \
     || sudo blkid "${DISK_B}1" 2>/dev/null | grep -q zfs_member; then
    echo "  ⚠ ${DISK_A} and/or ${DISK_B} contain zfs_member partitions"
    echo "    but no importable pool was found. Aborting to avoid data loss."
    echo "    Investigate with: sudo zpool import -d /dev"
    exit 1
  fi

  echo ""
  echo "  Both disks appear blank — offering to create a new mirror pool."
  echo "    Pool name: ${POOL_NAME}"
  echo "    Layout:    mirror ${DISK_A} ${DISK_B}"
  echo "    ⚠ This WIPES ${DISK_A} and ${DISK_B}."
  read -r -p "  Type 'CREATE' to proceed, anything else to skip: " confirm
  if [ "${confirm}" != "CREATE" ]; then
    echo "  Skipped pool creation. Module will still enable services."
  else
    # Use by-id paths for stability across reboots
    A_ID=$(readlink -f "${DISK_A}" | xargs -I{} sh -c 'for p in /dev/disk/by-id/*; do [ "$(readlink -f $p)" = {} ] && echo $p && break; done')
    B_ID=$(readlink -f "${DISK_B}" | xargs -I{} sh -c 'for p in /dev/disk/by-id/*; do [ "$(readlink -f $p)" = {} ] && echo $p && break; done')
    A_ID="${A_ID:-${DISK_A}}"
    B_ID="${B_ID:-${DISK_B}}"
    sudo zpool create -o ashift=12 -O compression=zstd -O atime=off \
      -O xattr=sa -O acltype=posixacl \
      "${POOL_NAME}" mirror "${A_ID}" "${B_ID}"
    echo "  ✓ Created mirror pool '${POOL_NAME}'"
  fi
fi

echo ""
echo "[3/5] Refreshing import cache..."
sudo mkdir -p /etc/zfs
if zpool list -H -o name 2>/dev/null | grep -qx "${POOL_NAME}"; then
  sudo zpool set cachefile=/etc/zfs/zpool.cache "${POOL_NAME}"
  echo "  ✓ Cache file updated"
else
  echo "  ⚠ Pool not present, skipping cache update"
fi

echo ""
echo "[4/5] Enabling ZFS services..."
sudo systemctl enable --now zfs-import-cache.service zfs-mount.service zfs-zed.service zfs.target
echo "  ✓ Services enabled (import-cache, mount, zed, zfs.target)"

echo ""
echo "[5/5] Status:"
sudo zpool status "${POOL_NAME}" 2>/dev/null || true
echo ""
zfs list -r "${POOL_NAME}" 2>/dev/null || true

echo ""
echo "=== Done ==="
echo "Pool '${POOL_NAME}' will auto-import on boot via zfs-import-cache.service."
