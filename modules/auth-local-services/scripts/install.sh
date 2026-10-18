#!/usr/bin/env bash
# Restore service definitions without interrupting running jobs or launching
# cleanup. Application checkouts, runner registration and .env files stay local.
set -euo pipefail
module_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
target_user="${SUDO_USER:-${USER}}"
if [[ "$target_user" == root ]]; then target_user=dylan; fi
if [[ "$target_user" != dylan ]]; then
  echo 'auth-local-services targets the existing dylan account on vps1.' >&2
  exit 1
fi
user_home="$(getent passwd "$target_user" | cut -d: -f6)"
uid="$(id -u "$target_user")"
as_user() {
  sudo -u "$target_user" env HOME="$user_home" XDG_RUNTIME_DIR="/run/user/$uid" "$@"
}
for file in "$module_dir"/bin/*; do
  sudo install -Dm0755 "$file" "/usr/local/bin/$(basename "$file")"
done
while IFS= read -r -d '' file; do
  relative="${file#"$module_dir/systemd/system/"}"
  sudo install -Dm0644 "$file" "/etc/systemd/system/$relative"
done < <(find "$module_dir/systemd/system" -type f -print0)
while IFS= read -r -d '' file; do
  relative="${file#"$module_dir/systemd/user/"}"
  destination="$user_home/.config/systemd/user/$relative"
  # Definitions may have been symlinked by a previous dotfiles setup.
  if [[ -L "$destination" ]]; then sudo unlink "$destination"; fi
  sudo install -D -o "$target_user" -g "$(id -gn "$target_user")" -m0644 "$file" "$destination"
done < <(find "$module_dir/systemd/user" -type f -print0)
sudo systemctl daemon-reload
as_user systemctl --user daemon-reload
sudo loginctl enable-linger "$target_user"

# Enable the same maintenance cadence; do not run cleanup during a config sync.
sudo systemctl enable runner-watchdog.timer btrfs-alloc-guard.timer deploy-backup-rotate.timer
# The third runner in each repo is installed but disabled on the live host.
for name in \
  actions.runner.PaysanCorrezien-brassens-monorepo.vps1-{1,2}.service \
  actions.runner.PaysanCorrezien-chirac.chirac-vps1-{1,2}.service; do
  unit="$module_dir/systemd/system/$name"
  executable="$(sed -n 's/^ExecStart=//p' "$unit")"
  if [[ -x "$executable" ]]; then
    sudo systemctl enable "$(basename "$unit")"
  else
    echo "Runner registration missing: $executable (unit installed, not enabled)"
  fi
done
# Application-specific private service files are not published in this repo.
unit="$module_dir/systemd/user/hermes-gateway.service"
directory="$(sed -n 's/^WorkingDirectory=//p' "$unit")"
executable="$(sed -n 's/^ExecStart=//p' "$unit" | cut -d' ' -f1)"
if [[ -d "$directory" && -x "$executable" ]]; then
  as_user systemctl --user enable hermes-gateway.service
else
  echo 'Local Hermes files missing (unit installed, not enabled)'
fi
echo 'Definitions installed. Existing processes were left running; enabled services take effect at next boot.'
