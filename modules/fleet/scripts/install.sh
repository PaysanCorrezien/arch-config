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
FLEET_REPO_HTTPS="https://github.com/PaysanCorrezien/fleet.git"
FLEET_REPO_SSH="git@github.com:paysancorrezien/fleet.git"
FLEET_REPO_PATH="${FLEET_REPO_PATH:-${HOME}/.local/share/fleet-state}"

# Pick clone URL: HTTPS if `gh` is authenticated (no SSH key required),
# else SSH (user must add a deploy key). Override with FLEET_REPO_URL.
if [[ -z "${FLEET_REPO_URL:-}" ]]; then
    if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
        FLEET_REPO_URL="${FLEET_REPO_HTTPS}"
        USE_GH=1
    else
        FLEET_REPO_URL="${FLEET_REPO_SSH}"
        USE_GH=0
    fi
fi

echo "=== Fleet module install ==="

# 0. ensure python deps (declared in packages.yaml but install.sh may run
#    standalone — don't rely on a full dcli sync having happened first)
NEEDED_PKGS=(python python-yaml python-rich git)
MISSING=()
for p in "${NEEDED_PKGS[@]}"; do
    pacman -Qi "$p" >/dev/null 2>&1 || MISSING+=("$p")
done
if (( ${#MISSING[@]} > 0 )); then
    echo "[0/4] Installing python deps: ${MISSING[*]}"
    sudo pacman -S --needed --noconfirm "${MISSING[@]}"
fi

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

# 3. write per-host fleet config + clone state repo (first time only)
echo "[3/4] Ensuring fleet state repo at ${FLEET_REPO_PATH}..."
mkdir -p "${HOME}/.config/fleet"
if [[ ! -f "${HOME}/.config/fleet/config.yaml" ]]; then
    cat > "${HOME}/.config/fleet/config.yaml" <<EOF
fleet_repo: ${FLEET_REPO_URL}
fleet_repo_path: ${FLEET_REPO_PATH/#$HOME/~}
arch_config_path: ~/.config/arch-config
EOF
fi
# if gh is available, ensure git uses its credential helper for github.com
if (( USE_GH )); then
    gh auth setup-git >/dev/null 2>&1 || true
fi
if [[ -d "${FLEET_REPO_PATH}/.git" ]]; then
    echo "  ✓ already cloned"
else
    mkdir -p "$(dirname "${FLEET_REPO_PATH}")"
    if git clone "${FLEET_REPO_URL}" "${FLEET_REPO_PATH}" 2>&1; then
        echo "  ✓ cloned ${FLEET_REPO_URL}"
    else
        if (( USE_GH )); then
            echo "  ⚠ clone failed via HTTPS even though gh is authenticated."
            echo "    Try: gh auth refresh -h github.com -s repo"
        else
            echo "  ⚠ clone failed (no gh auth and no SSH key for github.com)."
            echo "    Either: gh auth login -w   (recommended)"
            echo "    Or: add an SSH deploy key on ${FLEET_REPO_SSH}"
            echo "    Then re-run: fleet sync"
        fi
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
