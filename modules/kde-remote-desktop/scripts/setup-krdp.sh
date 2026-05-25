#!/usr/bin/env bash
# Configure KDE's built-in RDP server (krdp) so the host can be reached over
# Tailscale at <tailscale-ip>:3389. Idempotent — safe to re-run.
#
# After this script:
#   1. Open System Settings → Remote Desktop and flip "Enable RDP server" on
#      (system-user login is already preset, so no separate password needed —
#      authenticate with your normal system password).
#   2. Enable the user service:
#        systemctl --user enable --now app-org.kde.krdpserver.service
#   3. Connect from any RDP client to <tailscale-ip>:3389.

set -euo pipefail

CERT_DIR="$HOME/.local/share/krdpserver"
mkdir -p "$CERT_DIR"

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
fi

# Bind to the Tailscale IPv4 address so the RDP port is never exposed publicly.
TS_IP=$(tailscale ip -4 2>/dev/null | head -n1 || true)
if [[ -z "${TS_IP}" ]]; then
  echo "[krdp] WARNING: tailscale ip -4 returned nothing. Is tailscaled up?"
  echo "[krdp] Falling back to 127.0.0.1 — fix Tailscale and re-run to expose on tailnet."
  TS_IP="127.0.0.1"
fi

mkdir -p "$HOME/.config"
KRDP_CONF="$HOME/.config/krdpserverrc"
cat > "$KRDP_CONF" <<EOF
[General]
Address=${TS_IP}
Port=3389
Users=$(whoami)
SystemUserEnabled=true
Certificate=${CERT_FILE}
CertificateKey=${KEY_FILE}
EOF

echo "[krdp] Wrote ${KRDP_CONF} (bound to ${TS_IP}:3389)"

# --- Always-on session so RDP works after a cold boot ----------------------
# krdp is a user service inside the Plasma session — if no session exists,
# port 3389 is closed. To make "power on → RDP in" work without a human at
# the console, we:
#   1. SDDM autologin into Plasma (Wayland) at boot.
#   2. enable-linger so the user bus + krdp survive without an active seat.
#
# NOTE: this is a remote-only headless box — we explicitly do NOT auto-lock
# on login or on idle. RDP clients land directly on the desktop. Autolock
# stays off via setup-kde.sh (kscreenlockerrc Autolock=false, LockOnResume=false).
# Any stale ~/.config/autostart/krdp-autolock.desktop from earlier iterations
# is removed below.

USER_NAME="$(whoami)"

echo "[krdp] Configuring SDDM autologin for ${USER_NAME} (Plasma Wayland)"
sudo install -d /etc/sddm.conf.d
sudo tee /etc/sddm.conf.d/30-autologin.conf >/dev/null <<EOF
[Autologin]
User=${USER_NAME}
Session=plasma
Relogin=true
EOF

echo "[krdp] Enabling user lingering so the session/krdp survives logout"
sudo loginctl enable-linger "${USER_NAME}"

# Clean up auto-lock autostart from earlier iterations of this script
rm -f "$HOME/.config/autostart/krdp-autolock.desktop"

echo "[krdp] Enabling krdp user service (works now; survives reboot via linger)"
systemctl --user enable --now app-org.kde.krdpserver.service 2>/dev/null || \
  echo "[krdp] NOTE: enable krdp from System Settings → Remote Desktop once, then re-run."

echo "[krdp] Done. After reboot: ${TS_IP}:3389 will be reachable directly on the desktop."
echo "[krdp] First-time UI step: System Settings → Remote Desktop → toggle 'Enable RDP server' on."
