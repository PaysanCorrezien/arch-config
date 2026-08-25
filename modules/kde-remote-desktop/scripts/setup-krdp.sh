#!/usr/bin/env bash
# Configure KDE's built-in RDP server (krdp) so the host can be reached over
# Tailscale at <tailscale-ip>:3389. Idempotent — safe to re-run.
#
# KRDP reads port, certificate, quality, and authentication from
# krdpserverrc. It does *not* read a listen address from that file, so a
# systemd drop-in starts it through a wrapper that binds only to the live
# Tailscale IPv4 address. Until Tailscale is authenticated, KRDP stays down
# rather than falling back to a LAN-wide listener.

set -euo pipefail

module_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET_USER="${SUDO_USER:-$USER}"
if [[ "$(id -u)" -eq 0 && "${TARGET_USER}" == "root" ]]; then
  TARGET_USER="${LOGNAME:-dylan}"
fi
USER_HOME="$(getent passwd "${TARGET_USER}" | cut -d: -f6)"
USER_UID="$(id -u "${TARGET_USER}")"

run_user_cmd() {
  if [[ "$(id -u)" -eq 0 ]]; then
    sudo -u "${TARGET_USER}" XDG_RUNTIME_DIR="/run/user/${USER_UID}" "$@"
  else
    "$@"
  fi
}

CERT_DIR="${USER_HOME}/.local/share/krdpserver"
mkdir -p "$CERT_DIR"
chown "${TARGET_USER}:${TARGET_USER}" "$CERT_DIR"

# Generate a self-signed TLS cert if missing (clients will prompt to trust it once).
CERT_FILE="$CERT_DIR/krdp.crt"
KEY_FILE="$CERT_DIR/krdp.key"
if [[ ! -f "$CERT_FILE" || ! -f "$KEY_FILE" ]]; then
  echo "[krdp] Generating self-signed TLS certificate in $CERT_DIR"
  openssl req -x509 -newkey rsa:4096 -nodes -days 3650 \
    -keyout "$KEY_FILE" \
    -out   "$CERT_FILE" \
    -subj  "/CN=$(hostname)"
  chmod 600 "$KEY_FILE"
  chown "${TARGET_USER}:${TARGET_USER}" "$CERT_FILE" "$KEY_FILE"
fi

mkdir -p "${USER_HOME}/.config"
KRDP_CONF="${USER_HOME}/.config/krdpserverrc"
cat > "$KRDP_CONF" <<EOF
[General]
ListenPort=3389
AutogenerateCertificates=false
SystemUserEnabled=true
Autostart=true
Certificate=${CERT_FILE}
CertificateKey=${KEY_FILE}
EOF
chown "${TARGET_USER}:${TARGET_USER}" "$KRDP_CONF"

echo "[krdp] Wrote ${KRDP_CONF}"

echo "[krdp] Installing the tailnet-only service wrapper"
sudo install -Dm0755 "${module_dir}/scripts/krdp-tailnet-wrapper.sh" /usr/local/libexec/dcli-krdp-tailnet
sudo install -Dm0644 "${module_dir}/systemd/app-org.kde.krdpserver.service.d/10-tailnet.conf" \
  /etc/systemd/user/app-org.kde.krdpserver.service.d/10-tailnet.conf

# --- Always-on session so RDP works after a cold boot ----------------------
# krdp is a user service inside the Plasma session — if no session exists,
# port 3389 is closed. To make "power on → RDP in" work without a human at
# the console, we:
#   1. The installed Plasma display manager autologins into Plasma (Wayland)
#      at boot (Plasma Login Manager on current CachyOS; SDDM otherwise).
#   2. enable-linger so the user bus + krdp survive without an active seat.
#
# NOTE: this is a remote-only headless box — we explicitly do NOT auto-lock
# on login or on idle. RDP clients land directly on the desktop. Autolock
# stays off via setup-kde.sh (kscreenlockerrc Autolock=false, LockOnResume=false).
# Any stale ~/.config/autostart/krdp-autolock.desktop from earlier iterations
# is removed below.

if [[ "$(readlink -f /etc/systemd/system/display-manager.service 2>/dev/null || true)" == "/usr/lib/systemd/system/plasmalogin.service" ]]; then
  echo "[krdp] Configuring Plasma Login autologin for ${TARGET_USER} (Plasma Wayland)"
  sudo kwriteconfig6 --file /etc/plasmalogin.conf --group Autologin --key User "${TARGET_USER}"
  sudo kwriteconfig6 --file /etc/plasmalogin.conf --group Autologin --key Session plasma.desktop
  sudo kwriteconfig6 --file /etc/plasmalogin.conf --group Autologin --key Relogin true
else
  echo "[krdp] Configuring SDDM autologin for ${TARGET_USER} (Plasma Wayland)"
  sudo install -d /etc/sddm.conf.d
  sudo tee /etc/sddm.conf.d/30-autologin.conf >/dev/null <<EOF
[Autologin]
User=${TARGET_USER}
Session=plasma
Relogin=true
EOF
fi

echo "[krdp] Enabling user lingering so the session/krdp survives logout"
sudo loginctl enable-linger "${TARGET_USER}"

# Clean up auto-lock autostart from earlier iterations of this script
rm -f "${USER_HOME}/.config/autostart/krdp-autolock.desktop"

echo "[krdp] Disabling auto-lock and system sleep for always-on remote access"
sudo tee /etc/xdg/kscreenlockerrc >/dev/null <<'EOF'
[Daemon]
Autolock=false
LockOnResume=false
EOF
run_user_cmd kwriteconfig6 --file "${USER_HOME}/.config/kscreenlockerrc" --group Daemon --key Autolock false
run_user_cmd kwriteconfig6 --file "${USER_HOME}/.config/kscreenlockerrc" --group Daemon --key LockOnResume false
sudo systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target >/dev/null

echo "[krdp] Enabling KRDP user service (tailnet-only; survives reboot via linger)"
run_user_cmd systemctl --user daemon-reload
run_user_cmd systemctl --user enable app-org.kde.krdpserver.service 2>/dev/null || \
  echo "[krdp] NOTE: enable krdp from System Settings → Remote Desktop once, then re-run."
run_user_cmd systemctl --user restart app-org.kde.krdpserver.service 2>/dev/null || true

TS_IP=$(tailscale ip -4 2>/dev/null | head -n1 || true)
if [[ -n "${TS_IP}" ]]; then
  echo "[krdp] Done. Connect to ${TS_IP}:3389 from the tailnet."
else
  echo "[krdp] Tailscale is not authenticated. Complete 'tailscale up'; KRDP will retry automatically and bind once an IPv4 address exists."
fi
