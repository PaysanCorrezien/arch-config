#!/usr/bin/env bash
# Prepare the Google Drive mount service. OAuth is intentionally interactive
# and is performed by the owner with `rclone config` after this hook finishes.

set -euo pipefail

target_user="${SUDO_USER:-$USER}"
if [ "${target_user}" = "root" ]; then
  echo "Run Google Drive OAuth as the desktop user, not root."
  exit 1
fi
target_home="$(getent passwd "${target_user}" | cut -d: -f6)"
mount_dir="/srv/winshare/GoogleDrive"

# /srv/winshare is mounted in the Windows guest as Z:.  Keep the rclone
# credentials and cache private to the desktop user, while exposing only the
# Drive filesystem itself through the existing shared drive.
install -d -m 0755 "${mount_dir}"
install -d -m 0700 "${target_home}/.cache/rclone/gdrive" "${target_home}/.config/rclone"

# The Windows guest reaches this FUSE mount through the root-owned virtiofsd
# process. `allow_other` is therefore required; FUSE rejects it unless this
# host-level opt-in is enabled first.
if ! grep -qxF 'user_allow_other' /etc/fuse.conf 2>/dev/null; then
  if [ "$(id -u)" -eq 0 ]; then
    sed -i 's/^#user_allow_other$/user_allow_other/' /etc/fuse.conf
  else
    sudo sed -i 's/^#user_allow_other$/user_allow_other/' /etc/fuse.conf
  fi
fi

if [ ! -e "${target_home}/GoogleDrive" ] && [ ! -L "${target_home}/GoogleDrive" ]; then
  ln -s "${mount_dir}" "${target_home}/GoogleDrive"
elif [ -L "${target_home}/GoogleDrive" ] && [ "$(readlink -f "${target_home}/GoogleDrive")" != "${mount_dir}" ]; then
  echo "${target_home}/GoogleDrive points somewhere unexpected; refusing to replace it."
  exit 1
fi

run_user() {
  if [ "$(id -u)" -eq 0 ]; then
    sudo -u "${target_user}" XDG_RUNTIME_DIR="/run/user/$(id -u "${target_user}")" "$@"
  else
    "$@"
  fi
}

run_user systemctl --user daemon-reload
run_user systemctl --user enable gdrive.service

if [ -f "${target_home}/.config/rclone/rclone.conf" ]; then
  run_user systemctl --user restart gdrive.service
  echo "Google Drive mount service enabled and started."
else
  echo "Google Drive service enabled but waiting for OAuth."
  echo "Run as ${target_user}: rclone config"
  echo "Create a remote named 'gdrive' with storage type 'drive', then start: systemctl --user start gdrive.service"
fi
