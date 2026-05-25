#!/bin/bash
# Hermes module post-install hook.
# - install Hermes Agent via upstream installer (idempotent, --skip-setup)
# - install user systemd units for gateway + dashboard
# - bind dashboard to this host's tailscale IP
# - enable + start both services
#
# Existing ~/.hermes state (auth.json, .env, sessions, state.db, memories,
# config.yaml, skills) is preserved by the upstream installer.

set -euo pipefail

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
UNIT_SRC_DIR="${MODULE_DIR}/systemd"
UNIT_DST_DIR="${HOME}/.config/systemd/user"
HERMES_BIN="${HOME}/.local/bin/hermes"
INSTALLER_URL="https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.sh"

echo "=== Hermes module install ==="

# 1. install or refresh hermes-agent
if [[ -x "${HERMES_BIN}" ]] && [[ -d "${HOME}/.hermes/hermes-agent/venv" ]]; then
    echo "[1/4] Hermes already installed at ${HERMES_BIN} — skipping installer"
else
    echo "[1/4] Running upstream installer (--skip-setup)..."
    curl -fsSL "${INSTALLER_URL}" | bash -s -- --skip-setup
fi

# 2. resolve this host's tailscale IPv4 for the dashboard bind
TAILSCALE_IP="$(tailscale ip -4 2>/dev/null | head -1 || true)"
if [[ -z "${TAILSCALE_IP}" ]]; then
    echo "  ⚠ tailscale ip -4 returned nothing — falling back to 127.0.0.1"
    TAILSCALE_IP="127.0.0.1"
fi
echo "  ✓ dashboard will bind to ${TAILSCALE_IP}:8443"

# 3. install user systemd units
echo "[2/4] Installing user systemd units..."
mkdir -p "${UNIT_DST_DIR}"
install -m 0644 "${UNIT_SRC_DIR}/hermes-gateway.service" "${UNIT_DST_DIR}/hermes-gateway.service"
sed "s|@TAILSCALE_IP@|${TAILSCALE_IP}|g" \
    "${UNIT_SRC_DIR}/hermes-dashboard.service.in" \
    > "${UNIT_DST_DIR}/hermes-dashboard.service"
chmod 0644 "${UNIT_DST_DIR}/hermes-dashboard.service"
systemctl --user daemon-reload
echo "  ✓ ${UNIT_DST_DIR}/hermes-{gateway,dashboard}.service"

# 4. enable lingering so services run without an active login session
echo "[3/4] Enabling user-session lingering..."
loginctl enable-linger "${USER}" >/dev/null 2>&1 || true

# 5. enable + (re)start services
echo "[4/4] Enabling hermes-gateway + hermes-dashboard..."
systemctl --user enable hermes-gateway.service hermes-dashboard.service >/dev/null
# restart picks up unit changes if already running; start otherwise
systemctl --user restart hermes-gateway.service hermes-dashboard.service
sleep 2
systemctl --user is-active hermes-gateway.service hermes-dashboard.service || true

echo ""
echo "Done. Try:"
echo "  hermes status"
echo "  journalctl --user -u hermes-gateway -f"
echo "  https://${TAILSCALE_IP}:8443"
