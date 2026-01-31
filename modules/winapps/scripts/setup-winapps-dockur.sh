#!/usr/bin/env bash
set -euo pipefail

echo "==> Setting up WinApps with dockurr/windows Docker container"

target_user="${SUDO_USER:-${USER}}"
target_home="${HOME}"
if [[ -n "${SUDO_USER:-}" ]] && command -v getent >/dev/null 2>&1; then
  target_home="$(getent passwd "${SUDO_USER}" | cut -d: -f6)"
fi

config_dir="${target_home}/.config/winapps"
compose_file="${config_dir}/docker-compose.yml"
env_file="${config_dir}/.env"
winapps_conf="${config_dir}/winapps.conf"
bin_dir="${target_home}/.local/bin"
winapps_repo_dir="${bin_dir}/winapps-src"

mkdir -p "${config_dir}"
mkdir -p "${bin_dir}"

echo "==> Creating Docker Compose configuration"

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

echo "==> Creating WinApps configuration file"
if [[ ! -f "${winapps_conf}" ]]; then
  cat <<'EOF' > "${winapps_conf}"
##################################
#   WINAPPS CONFIGURATION FILE   #
##################################

RDP_USER="winapps"
RDP_PASS="winapps"
RDP_DOMAIN=""
RDP_IP="127.0.0.1"
WAFLAVOR="docker"
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
  echo "    Created: ${winapps_conf}"
else
  echo "    Already exists: ${winapps_conf}"
  # Update WAFLAVOR to docker (replace any existing value)
  if grep -q '^WAFLAVOR=' "${winapps_conf}" 2>/dev/null; then
    sed -i 's/^WAFLAVOR=.*/WAFLAVOR="docker"/' "${winapps_conf}"
    echo "    Updated WAFLAVOR to docker"
  else
    printf '\nWAFLAVOR="docker"\n' >> "${winapps_conf}"
    echo "    Added WAFLAVOR=docker"
  fi
fi

echo "==> Starting Docker container"

if command -v docker >/dev/null 2>&1; then
  if docker info >/dev/null 2>&1; then
    if docker compose version >/dev/null 2>&1; then
      compose_cmd=(docker compose)
    elif command -v docker-compose >/dev/null 2>&1; then
      compose_cmd=(docker-compose)
    else
      echo "ERROR: Docker Compose not found"
      exit 1
    fi

    echo "    Pulling dockurr/windows image (this may take a while)..."
    "${compose_cmd[@]}" -f "${compose_file}" --env-file "${env_file}" pull
    echo "    Starting container..."
    "${compose_cmd[@]}" -f "${compose_file}" --env-file "${env_file}" up -d
    echo "    Container started successfully"
  else
    echo "ERROR: Docker is installed but not running"
    echo "Please start Docker and run this script again"
    exit 1
  fi
else
  echo "ERROR: Docker not found"
  exit 1
fi

echo "==> Setting permissions"
if [[ "$(id -u)" -eq 0 ]]; then
  chown -R "${target_user}:${target_user}" "${config_dir}" "${bin_dir}" 2>/dev/null || true
fi

if [[ -f "${winapps_conf}" ]]; then
  chmod 600 "${winapps_conf}" 2>/dev/null || true
fi

echo ""
echo "==> Installing WinApps application integrations"
echo ""

# Clean up any existing repo with wrong ownership
if [[ -d "${winapps_repo_dir}" ]]; then
  if [[ "$(id -u)" -eq 0 ]]; then
    # Running as root, can remove directly
    rm -rf "${winapps_repo_dir}"
  elif [[ ! -O "${winapps_repo_dir}" ]]; then
    # Directory exists but not owned by current user, try to remove
    echo "Removing existing winapps-src with incorrect ownership..."
    rm -rf "${winapps_repo_dir}" 2>/dev/null || {
      echo "ERROR: Cannot remove ${winapps_repo_dir} (wrong ownership)"
      echo "Please run: sudo rm -rf ${winapps_repo_dir}"
      exit 1
    }
  fi
fi

# Clone the winapps repo
if [[ ! -d "${winapps_repo_dir}" ]]; then
  echo "Cloning WinApps repository..."
  if [[ "$(id -u)" -eq 0 ]] && [[ -n "${target_user}" ]]; then
    # Running as root, clone as target user
    su - "${target_user}" -c "git clone --depth 1 https://github.com/winapps-org/winapps.git '${winapps_repo_dir}'"
  else
    # Running as regular user
    git clone --depth 1 https://github.com/winapps-org/winapps.git "${winapps_repo_dir}"
  fi
fi

# Ensure correct ownership
if [[ "$(id -u)" -eq 0 ]] && [[ -d "${winapps_repo_dir}" ]]; then
  chown -R "${target_user}:${target_user}" "${winapps_repo_dir}"
fi

# Install winapps command-line tool
if [[ -x "${winapps_repo_dir}/setup.sh" ]]; then
  echo "Setting up WinApps command-line tool..."

  # Remove any conflicting symlinks from manual installation
  if [[ -L "${bin_dir}/winapps" ]]; then
    rm -f "${bin_dir}/winapps"
  fi

  # Create symlink to winapps binary
  if [[ -f "${winapps_repo_dir}/bin/winapps" ]]; then
    ln -sf "${winapps_repo_dir}/bin/winapps" "${bin_dir}/winapps"
    chmod +x "${winapps_repo_dir}/bin/winapps"
    echo "    Installed winapps command to ${bin_dir}/winapps"
  fi

  # Copy application integrations to user directory
  user_appdata="${target_home}/.local/share/winapps"
  mkdir -p "${user_appdata}"

  if [[ -d "${winapps_repo_dir}/apps" ]]; then
    cp -r "${winapps_repo_dir}/apps" "${user_appdata}/" 2>/dev/null || true
    echo "    Copied app definitions to ${user_appdata}/apps"
  fi

  # Ensure correct ownership
  if [[ "$(id -u)" -eq 0 ]]; then
    chown -R "${target_user}:${target_user}" "${user_appdata}" "${bin_dir}/winapps"
  fi

  echo ""
  echo "==> WinApps infrastructure setup complete!"
  echo ""
  echo "Next steps to install Windows applications:"
  echo ""
  echo "  1. Wait for Windows to fully boot (~5-15 minutes on first start)"
  echo "     Check status: docker logs -f winapps-windows"
  echo ""
  echo "  2. Test RDP connection:"
  echo "     winapps check"
  echo ""
  echo "  3. Install application integrations (run in a GUI terminal):"
  echo "     cd ~/.local/bin/winapps-src && ./setup.sh --user"
  echo ""
  echo "  4. Or use the launcher GUI:"
  echo "     winapps-launcher  # Install yad first: paru -S yad"
  echo ""
  echo "Configuration: ${winapps_conf}"
  echo "Docker Compose: ${compose_file}"
  echo "Container: winapps-windows (docker ps | grep winapps)"
  echo ""
  echo "Note: The full setup requires a GUI session to test RDP connection."
  echo "      Run the setup.sh installer manually when logged into a desktop."
else
  echo "ERROR: WinApps setup.sh not found at ${winapps_repo_dir}/setup.sh"
  exit 1
fi
