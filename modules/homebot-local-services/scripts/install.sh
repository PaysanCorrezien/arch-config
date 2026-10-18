#!/usr/bin/env bash
set -euo pipefail
module_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
for file in "$module_dir"/bin/*; do
  sudo install -Dm0755 "$file" "/usr/local/bin/$(basename "$file")"
done
for file in "$module_dir"/systemd/*; do
  sudo install -Dm0644 "$file" "/etc/systemd/system/$(basename "$file")"
done
sudo systemctl daemon-reload
# Preserve the existing backup script on upgraded hosts, including its local
# credentials. A fresh install uses the versioned replacement with a local env.
if [[ -x /data/docker/compose/backup-restic.sh ]] || [[ -r /etc/homebot-backup.env ]]; then
  sudo systemctl enable restic-backup.timer
else
  echo 'Backup timer not enabled: restore /etc/homebot-backup.env and its password file first.'
fi
sudo systemctl enable calibre-autoadd.timer
echo 'Homebot service definitions installed; no backup, prune or app restart was run.'
