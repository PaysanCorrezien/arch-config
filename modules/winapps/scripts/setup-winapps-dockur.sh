#!/usr/bin/env bash
set -euo pipefail

target_user="${SUDO_USER:-${USER}}"
target_home="${HOME}"
if [[ -n "${SUDO_USER:-}" ]] && command -v getent >/dev/null 2>&1; then
  target_home="$(getent passwd "${SUDO_USER}" | cut -d: -f6)"
fi

config_dir="${target_home}/.config/winapps"
compose_file="${config_dir}/docker-compose.yml"
env_file="${config_dir}/.env"
winapps_conf="${config_dir}/winapps.conf"
repo_url="https://github.com/winapps-org/winapps.git"
repo_dir="${target_home}/.local/share/winapps"
launcher_repo_url="https://github.com/winapps-org/winapps-launcher.git"
launcher_repo_dir="${target_home}/.local/share/winapps-launcher"
bin_dir="${target_home}/.local/bin"

mkdir -p "${config_dir}"
mkdir -p "${bin_dir}"

if [[ ! -f "${compose_file}" ]]; then
  cat <<'EOF' > "${compose_file}"
services:
  windows:
    image: dockurr/windows
    container_name: winapps-windows
    environment:
      - VERSION=win11
      - RAM_SIZE=8G
      - CPU_CORES=4
      - DISK_SIZE=64G
      - USERNAME=winapps
      - PASSWORD=winapps
    volumes:
      - winapps-data:/storage
    devices:
      - /dev/kvm
    ports:
      - "3389:3389/tcp"
    restart: unless-stopped

volumes:
  winapps-data:
EOF
fi

if [[ ! -f "${env_file}" ]]; then
  cat <<'EOF' > "${env_file}"
# Optional overrides for dockurr/windows environment variables.
# Example: VERSION=win10 or RAM_SIZE=12G
EOF
fi

if [[ ! -f "${winapps_conf}" ]]; then
  cat <<'EOF' > "${winapps_conf}"
##################################
#   WINAPPS CONFIGURATION FILE   #
##################################

RDP_USER="winapps"
RDP_PASS="winapps"
RDP_DOMAIN=""
RDP_IP="127.0.0.1"
WAFLAVOR="manual"
RDP_SCALE="100"
REMOVABLE_MEDIA="/run/media"
RDP_FLAGS="/cert:tofu /sound /microphone +home-drive"
RDP_FLAGS_NON_WINDOWS=""
RDP_FLAGS_WINDOWS=""
DEBUG="false"
AUTOPAUSE="off"
AUTOPAUSE_TIME="300"
FREERDP_COMMAND=""
PORT_TIMEOUT="5"
EOF
else
  if rg -q '^RDP_PORT=' "${winapps_conf}" 2>/dev/null; then
    rg -v '^RDP_PORT=' "${winapps_conf}" > "${winapps_conf}.tmp"
    mv "${winapps_conf}.tmp" "${winapps_conf}"
  fi
  if ! rg -q '^WAFLAVOR=' "${winapps_conf}" 2>/dev/null; then
    printf '\nWAFLAVOR="manual"\n' >> "${winapps_conf}"
  fi
fi

if command -v git >/dev/null 2>&1; then
  if [[ ! -d "${repo_dir}/.git" ]]; then
    git clone --depth 1 "${repo_url}" "${repo_dir}"
  else
    if git -C "${repo_dir}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
      if git -C "${repo_dir}" diff --quiet; then
        git -C "${repo_dir}" pull --ff-only || true
      else
        echo "WinApps repo has local changes; skip git pull."
      fi
    fi
  fi

  if [[ -f "${repo_dir}/bin/winapps" ]]; then
    chmod +x "${repo_dir}/bin/winapps"
    ln -sf "${repo_dir}/bin/winapps" "${bin_dir}/winapps"
  fi

  if [[ ! -d "${launcher_repo_dir}/.git" ]]; then
    git clone --depth 1 "${launcher_repo_url}" "${launcher_repo_dir}"
  else
    if git -C "${launcher_repo_dir}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
      if git -C "${launcher_repo_dir}" diff --quiet; then
        git -C "${launcher_repo_dir}" pull --ff-only || true
      else
        echo "WinApps Launcher repo has local changes; skip git pull."
      fi
    fi
  fi

  if [[ -f "${launcher_repo_dir}/bin/winapps-launcher" ]]; then
    chmod +x "${launcher_repo_dir}/bin/winapps-launcher"
    ln -sf "${launcher_repo_dir}/bin/winapps-launcher" "${bin_dir}/winapps-launcher"
  fi
else
  echo "git not found; skip WinApps repo setup."
fi

if command -v docker >/dev/null 2>&1; then
  if docker info >/dev/null 2>&1; then
    if docker compose version >/dev/null 2>&1; then
      compose_cmd=(docker compose)
    elif command -v docker-compose >/dev/null 2>&1; then
      compose_cmd=(docker-compose)
    else
      echo "Docker Compose not found; skip image pull."
      exit 0
    fi

    "${compose_cmd[@]}" -f "${compose_file}" --env-file "${env_file}" pull
    "${compose_cmd[@]}" -f "${compose_file}" --env-file "${env_file}" up -d
  else
    echo "Docker is installed but not running; skip image pull."
  fi
else
  echo "Docker not found; skip image pull."
fi

if [[ "$(id -u)" -eq 0 ]]; then
  chown -R "${target_user}:${target_user}" "${config_dir}" "${repo_dir}" "${launcher_repo_dir}" "${bin_dir}" 2>/dev/null || true
fi

if [[ -f "${winapps_conf}" ]]; then
  chmod 600 "${winapps_conf}" 2>/dev/null || true
fi
