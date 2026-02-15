#!/usr/bin/env bash
set -euo pipefail

repo_url="https://github.com/mahaveergurjar/sddm.git"
repo_branch="noctalia"
theme_name="noctalia"
install_dir="/usr/share/sddm/themes/${theme_name}"
config_dir="/etc/sddm.conf.d"
config_file="${config_dir}/10-noctalia-theme.conf"
# Safer default for broad GPU/multi-monitor compatibility.
# Override with ARCH_CONFIG_SDDM_DISPLAY_SERVER=wayland when desired.
display_server="${ARCH_CONFIG_SDDM_DISPLAY_SERVER:-x11}"

tmp_dir="$(mktemp -d)"
cleanup() {
  rm -rf "${tmp_dir}"
}
trap cleanup EXIT

git clone --depth 1 --branch "${repo_branch}" "${repo_url}" "${tmp_dir}/noctalia"

sudo install -d "${install_dir}"
sudo cp -a "${tmp_dir}/noctalia/." "${install_dir}"

# Apply our patched Main.qml (fixes empty username bug)
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
module_dir="$(dirname "${script_dir}")"
if [ -f "${module_dir}/theme/Main.qml" ]; then
  sudo cp "${module_dir}/theme/Main.qml" "${install_dir}/Main.qml"
  echo "Applied patched Main.qml"
fi

sudo install -d "${config_dir}"
if [ "${display_server}" = "wayland" ]; then
sudo tee "${config_file}" >/dev/null <<EOF_CONF
[Theme]
Current=${theme_name}

[General]
DisplayServer=wayland
InputMethod=

[Wayland]
CompositorCommand=weston --shell=kiosk
EnableHiDPI=true
EOF_CONF
else
sudo tee "${config_file}" >/dev/null <<EOF_CONF
[Theme]
Current=${theme_name}

[General]
DisplayServer=x11
InputMethod=
EOF_CONF
fi

# Enable SDDM service (disables any existing display manager)
sudo systemctl enable sddm.service

user_name="${SUDO_USER:-${USER}}"
user_home="$(getent passwd "${user_name}" | cut -d: -f6)"
if [ -n "${user_home}" ] && [ -f "${user_home}/.face" ]; then
  sudo install -d /usr/share/sddm/faces
  sudo install -m 0644 "${user_home}/.face" "/usr/share/sddm/faces/${user_name}.face.icon"
fi
if [ -n "${user_home}" ] && [ -f "${user_home}/.face.icon" ]; then
  sudo install -d /usr/share/sddm/faces
  sudo install -m 0644 "${user_home}/.face.icon" "/usr/share/sddm/faces/${user_name}.face.icon"
fi

echo "Installed Noctalia SDDM theme to ${install_dir} and set Current=${theme_name}."
