#!/bin/bash
# Hermes module post-install hook.
# - install Hermes Agent via upstream installer (idempotent, --skip-setup)
# - install user systemd units for gateway + remote dashboard API
# - explicitly allow the dashboard API through UFW on tailscale0
# - enable + start both services
#
# Existing ~/.hermes state (auth.json, .env, sessions, state.db, memories,
# config.yaml, skills) is preserved by the upstream installer.

set -euo pipefail

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
UNIT_SRC_DIR="${MODULE_DIR}/systemd"
UNIT_DST_DIR="${HOME}/.config/systemd/user"
HERMES_BIN="${HOME}/.local/bin/hermes"
HERMES_WRAPPER_SRC="${MODULE_DIR}/dotfiles/bin/hermes"
HERMES_WAIT_SRC="${MODULE_DIR}/dotfiles/bin/hermes-wait-network"
ROUTING_PATCH_SRC="${MODULE_DIR}/scripts/apply-discord-thread-routing-patch.py"
ROUTING_PATCH_DST="${HOME}/.local/lib/hermes-dcli/apply-discord-thread-routing-patch.py"
DEFAULT_ROUTING_SRC="${MODULE_DIR}/scripts/reconcile-default-routing.py"
DEFAULT_ROUTING_DST="${HOME}/.local/lib/hermes-dcli/reconcile-default-routing.py"
CRON_RELIABILITY_SRC="${MODULE_DIR}/scripts/reconcile-cron-reliability.py"
CRON_RELIABILITY_DST="${HOME}/.local/lib/hermes-dcli/reconcile-cron-reliability.py"
ROUTING_DROPIN_SRC="${UNIT_SRC_DIR}/hermes-gateway.service.d/10-discord-thread-routing.conf"
INSTALLER_URL="https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.sh"

echo "=== Hermes module install ==="

# 1. install or refresh hermes-agent
if [[ -x "${HERMES_BIN}" ]] && [[ -d "${HOME}/.hermes/hermes-agent/venv" ]]; then
    echo "[1/4] Hermes already installed at ${HERMES_BIN} — skipping installer"
else
    echo "[1/4] Running upstream installer (--skip-setup)..."
    curl -fsSL "${INSTALLER_URL}" | bash -s -- --skip-setup
fi

# The upstream installer exposes the CLI as a Python module. Install our stable
# user-facing wrapper so the systemd dashboard unit and interactive `hermes`
# command work on every host.
install -d -m 0755 "${HOME}/.local/bin"
install -m 0755 "${HERMES_WRAPPER_SRC}" "${HERMES_BIN}"
install -m 0755 "${HERMES_WAIT_SRC}" "${HOME}/.local/bin/hermes-wait-network"
install -d -m 0755 "${HOME}/.local/lib/hermes-dcli"
install -m 0755 "${ROUTING_PATCH_SRC}" "${ROUTING_PATCH_DST}"
install -m 0755 "${DEFAULT_ROUTING_SRC}" "${DEFAULT_ROUTING_DST}"
install -m 0755 "${CRON_RELIABILITY_SRC}" "${CRON_RELIABILITY_DST}"

# Hermes persists each profile's previous thread participation.  Keep the
# gateway guard that scopes automatic thread follow-ups to the shared intake
# forum, even when the upstream package is refreshed.
python3 "${ROUTING_PATCH_DST}"
python3 "${DEFAULT_ROUTING_DST}"
python3 "${CRON_RELIABILITY_DST}" --apply

# The STT monitor uses the Hermes-pinned Playwright CLI. Install its matching
# Chromium build up front so a scheduled benchmark change never triggers an
# unpinned npx download or fails halfway through evidence collection.
PLAYWRIGHT_BIN="${HOME}/.hermes/hermes-agent/node_modules/.bin/playwright"
if [[ ! -x "${PLAYWRIGHT_BIN}" ]]; then
    echo "Hermes Playwright CLI is missing: ${PLAYWRIGHT_BIN}" >&2
    exit 1
fi
"${PLAYWRIGHT_BIN}" install chromium

# 2. install user systemd units
echo "[2/4] Installing user systemd units..."
mkdir -p "${UNIT_DST_DIR}"
[[ ! -e "${UNIT_DST_DIR}/hermes-gateway.service" && ! -L "${UNIT_DST_DIR}/hermes-gateway.service" ]] || unlink "${UNIT_DST_DIR}/hermes-gateway.service"
[[ ! -e "${UNIT_DST_DIR}/hermes-serve.service" && ! -L "${UNIT_DST_DIR}/hermes-serve.service" ]] || unlink "${UNIT_DST_DIR}/hermes-serve.service"
install -m 0644 "${UNIT_SRC_DIR}/hermes-gateway.service" "${UNIT_DST_DIR}/hermes-gateway.service"
install -m 0644 "${UNIT_SRC_DIR}/hermes-serve.service" "${UNIT_DST_DIR}/hermes-serve.service"
profile_delay=3
for profile in correzianlabs-manager repository-orchestrator marketing life; do
    temporary_unit="$(mktemp)"
    sed -e "s/@PROFILE@/${profile}/g" -e "s/@START_DELAY@/${profile_delay}/g" \
        "${UNIT_SRC_DIR}/hermes-gateway-profile.service.in" > "${temporary_unit}"
    [[ ! -e "${UNIT_DST_DIR}/hermes-gateway-${profile}.service" && ! -L "${UNIT_DST_DIR}/hermes-gateway-${profile}.service" ]] || unlink "${UNIT_DST_DIR}/hermes-gateway-${profile}.service"
    install -m 0644 "${temporary_unit}" "${UNIT_DST_DIR}/hermes-gateway-${profile}.service"
    unlink "${temporary_unit}"
    profile_delay=$((profile_delay + 3))
done
# The old dashboard unit is intentionally not installed: the remote API must
# have one canonical, supervised owner on port 9119.
systemctl --user disable --now hermes-dashboard.service hermes-remote-dashboard.service 2>/dev/null || true
[[ ! -L "${UNIT_DST_DIR}/hermes-dashboard.service.d" ]] || unlink "${UNIT_DST_DIR}/hermes-dashboard.service.d"
install -d -m 0755 "${UNIT_DST_DIR}/hermes-dashboard.service.d"
[[ ! -e "${UNIT_DST_DIR}/hermes-dashboard.service.d/10-tailnet.conf" && ! -L "${UNIT_DST_DIR}/hermes-dashboard.service.d/10-tailnet.conf" ]] || unlink "${UNIT_DST_DIR}/hermes-dashboard.service.d/10-tailnet.conf"
install -m 0644 \
    "${UNIT_SRC_DIR}/hermes-dashboard.service.d/10-tailnet.conf" \
    "${UNIT_DST_DIR}/hermes-dashboard.service.d/10-tailnet.conf"
# Keep the Discord routing guard on every gateway service even if upstream
# recreates its main unit through `hermes gateway install`.
[[ ! -L "${UNIT_DST_DIR}/hermes-gateway.service.d" ]] || unlink "${UNIT_DST_DIR}/hermes-gateway.service.d"
install -d -m 0755 "${UNIT_DST_DIR}/hermes-gateway.service.d"
[[ ! -e "${UNIT_DST_DIR}/hermes-gateway.service.d/10-discord-thread-routing.conf" && ! -L "${UNIT_DST_DIR}/hermes-gateway.service.d/10-discord-thread-routing.conf" ]] || unlink "${UNIT_DST_DIR}/hermes-gateway.service.d/10-discord-thread-routing.conf"
temporary_dropin="$(mktemp)"
sed 's/@START_DELAY@/0/g' "${ROUTING_DROPIN_SRC}" > "${temporary_dropin}"
install -m 0644 "${temporary_dropin}" \
    "${UNIT_DST_DIR}/hermes-gateway.service.d/10-discord-thread-routing.conf"
unlink "${temporary_dropin}"
profile_delay=3
for profile in correzianlabs-manager repository-orchestrator marketing life; do
    dropin_dir="${UNIT_DST_DIR}/hermes-gateway-${profile}.service.d"
    [[ ! -L "${dropin_dir}" ]] || unlink "${dropin_dir}"
    install -d -m 0755 "${dropin_dir}"
    [[ ! -e "${dropin_dir}/10-discord-thread-routing.conf" && ! -L "${dropin_dir}/10-discord-thread-routing.conf" ]] || unlink "${dropin_dir}/10-discord-thread-routing.conf"
    temporary_dropin="$(mktemp)"
    sed "s/@START_DELAY@/${profile_delay}/g" "${ROUTING_DROPIN_SRC}" > "${temporary_dropin}"
    install -m 0644 "${temporary_dropin}" "${dropin_dir}/10-discord-thread-routing.conf"
    unlink "${temporary_dropin}"
    profile_delay=$((profile_delay + 3))
done
systemctl --user daemon-reload
echo "  ✓ ${UNIT_DST_DIR}/hermes-{gateway,dashboard}.service"

# Persist the network boundary in dcli's module hook as well as the live UFW
# state. This is idempotent and limits exposure to the Tailscale interface.
if command -v ufw >/dev/null 2>&1; then
    sudo ufw allow in on tailscale0 to any port 9119 proto tcp comment 'Hermes remote dashboard over Tailscale' || true
fi

# 3. enable lingering so services run without an active login session
echo "[3/4] Enabling user-session lingering..."
loginctl enable-linger "${USER}" >/dev/null 2>&1 || true

# 4. enable + (re)start services
echo "[4/4] Enabling hermes-gateway + hermes-serve..."
systemctl --user enable hermes-gateway.service hermes-serve.service >/dev/null
# restart picks up unit changes if already running; start otherwise
systemctl --user restart hermes-gateway.service hermes-serve.service
for profile in correzianlabs-manager repository-orchestrator marketing life; do
    if systemctl --user cat "hermes-gateway-${profile}.service" >/dev/null 2>&1; then
        systemctl --user restart "hermes-gateway-${profile}.service"
    fi
done
sleep 2
systemctl --user is-active \
    hermes-gateway.service \
    hermes-gateway-correzianlabs-manager.service \
    hermes-gateway-repository-orchestrator.service \
    hermes-gateway-marketing.service \
    hermes-gateway-life.service \
    hermes-serve.service

echo ""
echo "Done. Try:"
echo "  hermes status"
echo "  journalctl --user -u hermes-gateway -f"
echo "  http://$(tailscale ip -4 2>/dev/null | head -1 || echo '<tailscale-ip>'):9119"
