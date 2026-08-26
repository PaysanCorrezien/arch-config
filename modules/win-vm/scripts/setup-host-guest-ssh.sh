#!/usr/bin/env bash
# Establish the KVM-only SSH path from the Windows guest back to this host.
#
# The guest public key arrives via stdin.  It is intentionally never stored in
# the repository: public keys are guest-specific runtime state, while this
# script is the durable provisioning logic.

set -euo pipefail

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET_USER="${SUDO_USER:-$USER}"
if [[ "$(id -u)" -eq 0 && "${TARGET_USER}" == "root" ]]; then
  TARGET_USER="${LOGNAME:-dylan}"
fi
USER_HOME="$(getent passwd "${TARGET_USER}" | cut -d: -f6)"
ENV_FILE="${USER_HOME}/.config/win-vm/win-vm.env"

say() { printf '[win-vm ssh] %s\n' "$*"; }
die() { printf '[win-vm ssh] ERROR: %s\n' "$*" >&2; exit 1; }

[[ -f "${ENV_FILE}" ]] || die "Missing ${ENV_FILE}"
# shellcheck source=/dev/null
source "${ENV_FILE}"
: "${VM_IP:=192.168.122.50}"
: "${WIN_VM_USER:=dylan}"

IFS= read -r GUEST_PUBLIC_KEY || die 'Expected the Windows public key on stdin'
[[ "${GUEST_PUBLIC_KEY}" == ssh-ed25519\ * ]] || die 'Expected an ssh-ed25519 public key'
printf '%s\n' "${GUEST_PUBLIC_KEY}" | ssh-keygen -lf - >/dev/null || die 'Invalid Windows public key'

SSH_DIR="${USER_HOME}/.ssh"
AUTHORIZED_KEYS="${SSH_DIR}/authorized_keys"
sudo install -d -o "${TARGET_USER}" -g "${TARGET_USER}" -m 0700 "${SSH_DIR}"
sudo touch "${AUTHORIZED_KEYS}"
sudo chown "${TARGET_USER}:${TARGET_USER}" "${AUTHORIZED_KEYS}"
sudo chmod 0600 "${AUTHORIZED_KEYS}"
if ! sudo -u "${TARGET_USER}" grep -Fqx "${GUEST_PUBLIC_KEY}" "${AUTHORIZED_KEYS}"; then
  printf '%s\n' "${GUEST_PUBLIC_KEY}" | sudo -u "${TARGET_USER}" tee -a "${AUTHORIZED_KEYS}" >/dev/null
  say 'Authorized the active Windows guest public key.'
else
  say 'The active Windows guest public key is already authorized.'
fi

CLIENT_CONFIG="${SSH_DIR}/config"
if ! grep -q '^# >>> dcli windows-vm >>>$' "${CLIENT_CONFIG}" 2>/dev/null; then
  sudo tee -a "${CLIENT_CONFIG}" >/dev/null <<EOF
# >>> dcli windows-vm >>>
Host windows-vm
  HostName ${VM_IP}
  User ${WIN_VM_USER}
  IdentityFile ~/.ssh/win-vm-control
  IdentitiesOnly yes
# <<< dcli windows-vm <<<
EOF
  sudo chown "${TARGET_USER}:${TARGET_USER}" "${CLIENT_CONFIG}"
  sudo chmod 0600 "${CLIENT_CONFIG}"
fi

# The native OpenSSH server is reachable only through libvirt's private bridge.
# UFW remains responsible for denying all LAN/WAN SSH traffic.
BRIDGE_IP="$(ip -o -4 addr show dev virbr0 | awk '{print $4}' | cut -d/ -f1 | head -n1)"
[[ -n "${BRIDGE_IP}" ]] || die 'virbr0 has no IPv4 address'
sudo ssh-keygen -A
sudo sshd -t
sudo systemctl enable --now sshd.service

if command -v ufw >/dev/null 2>&1 && sudo ufw status | grep -q 'Status: active'; then
  if ! sudo ufw status | grep -Fq 'Windows VM SSH'; then
    sudo ufw allow in on virbr0 from "${VM_IP}" to "${BRIDGE_IP}" port 22 proto tcp comment 'Windows VM SSH'
  fi
fi

say "Ready: Windows can use ssh ${TARGET_USER}@${BRIDGE_IP}; Linux can use ssh windows-vm."
