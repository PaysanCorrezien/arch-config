#!/usr/bin/env bash
# Migrate a docker bind-mount data directory to btrfs +C (no-COW).
#
# Why: postgres/sqlite on btrfs with COW + zstd compression turns every
# fsync into an extent allocation + metadata DUP write + checksum +
# compression cycle. On the auth host this surfaced as 28-51 ms write
# latency and constant `btrfs-endio-write` kworker activity.
#
# `chattr +C` only takes effect on *new* files, so we can't toggle it
# in place — we must recreate the directory and copy data into it.
#
# Usage:
#   sudo btrfs-nocow-migrate.sh <data-dir> [<service>...]
#
# Compose project: pass via the COMPOSE_FILE env var (native docker-compose
# convention — colon-separated list of compose files). When set together
# with services, the script stops/starts those services around the
# migration. Otherwise it expects you to have stopped whatever holds the
# dir open already.
#
# Example:
#   COMPOSE_FILE=auth-compose.yml:gitea-compose.yml \
#     sudo -E btrfs-nocow-migrate.sh /home/dylan/docker/gitea/db gitea-db gitea
#
# On failure the original data dir is restored from the .cow backup, so a
# half-finished run never leaves the service unable to start.

set -euo pipefail

DATA_DIR=${1:?usage: $0 <data-dir> [<service>...]}
shift
SERVICES=("$@")
: "${COMPOSE_FILE:=}"

if [[ ! -d "$DATA_DIR" ]]; then
  echo "error: $DATA_DIR is not a directory" >&2
  exit 1
fi

DATA_DIR=$(realpath "$DATA_DIR")
BACKUP_DIR="${DATA_DIR}.cow-$(date +%Y%m%d-%H%M%S)"

# Verify we're on btrfs — chattr +C is a no-op elsewhere.
fstype=$(stat -f -c %T "$DATA_DIR")
if [[ "$fstype" != "btrfs" ]]; then
  echo "error: $DATA_DIR is on $fstype, not btrfs — nothing to do" >&2
  exit 1
fi

# Skip if every file already has +C set (cheap idempotency check on the dir flag).
if lsattr -d "$DATA_DIR" 2>/dev/null | awk '{print $1}' | grep -q 'C'; then
  echo "skip: $DATA_DIR already has +C set on the directory"
  exit 0
fi

stop_services() {
  if [[ -n "$COMPOSE_FILE" && ${#SERVICES[@]} -gt 0 ]]; then
    echo ">> stopping services: ${SERVICES[*]}"
    docker compose stop "${SERVICES[@]}"
  fi
}

start_services() {
  if [[ -n "$COMPOSE_FILE" && ${#SERVICES[@]} -gt 0 ]]; then
    echo ">> starting services: ${SERVICES[*]}"
    # `up -d` so any compose changes (e.g. new postgres command:) take effect.
    docker compose up -d "${SERVICES[@]}"
  fi
}

rollback() {
  echo "!! rollback: restoring $DATA_DIR from $BACKUP_DIR" >&2
  rm -rf "$DATA_DIR"
  mv "$BACKUP_DIR" "$DATA_DIR"
  start_services || true
}

trap 'echo "!! migration failed at line $LINENO" >&2; rollback' ERR

echo ">> migrating $DATA_DIR"
echo "   backup will live at $BACKUP_DIR"

stop_services

# Move aside, recreate empty with +C, copy contents back.
mv "$DATA_DIR" "$BACKUP_DIR"
mkdir -p "$DATA_DIR"
chown --reference="$BACKUP_DIR" "$DATA_DIR"
chmod --reference="$BACKUP_DIR" "$DATA_DIR"
chattr +C "$DATA_DIR"

# --reflink=never forces a real copy (otherwise btrfs would share extents
# with the COW source and inherit its COW status).
cp -a --reflink=never "$BACKUP_DIR/." "$DATA_DIR/"

# Sanity: count files with +C vs total. Some btrfs file types (sockets,
# certain special files) refuse lsattr; that's fine. We just need to
# confirm the flag actually propagated to *most* of the regular files.
total=$(find "$DATA_DIR" -type f | wc -l)
nocow=$(find "$DATA_DIR" -type f -exec lsattr {} + 2>/dev/null | awk '$1 ~ /C/' | wc -l)
if [[ "$total" -gt 0 ]] && (( nocow * 2 < total )); then
  echo "!! +C only propagated to $nocow/$total files — aborting" >&2
  false
fi

start_services

# Quiet success — caller can decide when to remove the backup.
disabled_count=$(find "$DATA_DIR" -type f -exec lsattr {} + 2>/dev/null | grep -c 'C')
echo ">> migrated. $disabled_count files now nocow."
echo ">> backup retained at $BACKUP_DIR — remove once services are verified healthy."
trap - ERR
