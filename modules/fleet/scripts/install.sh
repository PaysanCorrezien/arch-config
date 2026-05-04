#!/bin/bash
# Fleet module post-install hook.
# - install /usr/local/bin/fleet
# - install user systemd units (~/.config/systemd/user/)
# - clone fleet repo on first run (skipped if SSH not ready)
# - enable & start the 4x/day timer

set -euo pipefail

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN_SRC="${MODULE_DIR}/bin/fleet"
BIN_DST="/usr/local/bin/fleet"
UNIT_SRC_DIR="${MODULE_DIR}/systemd"
UNIT_DST_DIR="${HOME}/.config/systemd/user"
FLEET_REPO_URL="${FLEET_REPO_URL:-git@github.com:paysancorrezien/fleet.git}"
FLEET_REPO_PATH="${FLEET_REPO_PATH:-${HOME}/.local/share/fleet-state}"

echo "=== Fleet module install ==="

# 1. install CLI binary
echo "[1/4] Installing fleet CLI to ${BIN_DST}..."
sudo install -m 0755 "${BIN_SRC}" "${BIN_DST}"
echo "  ✓ ${BIN_DST}"

# 2. install user systemd units
echo "[2/4] Installing user systemd units..."
mkdir -p "${UNIT_DST_DIR}"
install -m 0644 "${UNIT_SRC_DIR}/fleet-sync.service" "${UNIT_DST_DIR}/"
install -m 0644 "${UNIT_SRC_DIR}/fleet-sync.timer"   "${UNIT_DST_DIR}/"
systemctl --user daemon-reload
echo "  ✓ ${UNIT_DST_DIR}/fleet-sync.{service,timer}"

# 3. clone fleet state repo (first time only)
echo "[3/4] Ensuring fleet state repo at ${FLEET_REPO_PATH}..."
if [[ -d "${FLEET_REPO_PATH}/.git" ]]; then
    echo "  ✓ already cloned"
else
    mkdir -p "$(dirname "${FLEET_REPO_PATH}")"
    if git clone "${FLEET_REPO_URL}" "${FLEET_REPO_PATH}" 2>&1; then
        echo "  ✓ cloned ${FLEET_REPO_URL}"
    else
        echo "  ⚠ clone failed (likely SSH not configured for github.com)."
        echo "    Add an SSH key with push access to ${FLEET_REPO_URL},"
        echo "    then re-run: fleet sync"
    fi
fi

# 4. enable + start timer
echo "[4/4] Enabling fleet-sync.timer..."
# allow timers to run without an active login session
loginctl enable-linger "${USER}" >/dev/null 2>&1 || true
systemctl --user enable --now fleet-sync.timer
echo "  ✓ timer enabled (next: $(systemctl --user list-timers fleet-sync.timer --no-legend --no-pager | awk '{print $1, $2}'))"

echo ""
echo "Done. Try:"
echo "  fleet status        # this host"
echo "  fleet sync          # push state now"
echo "  fleet show          # whole-fleet dashboard"
