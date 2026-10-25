#!/usr/bin/env bash
set -euo pipefail

gateway_user="${TARGET_USER:-${SUDO_USER:-$USER}}"
[[ "$gateway_user" != root ]] || { echo 'Set TARGET_USER to the gateway owner.' >&2; exit 1; }
gateway_home="$(getent passwd "$gateway_user" | cut -d: -f6)"
gateway_uid="$(id -u "$gateway_user")"
module_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ "$(id -u)" -eq 0 ]]; then
  exec sudo -H -u "$gateway_user" env \
    TARGET_USER="$gateway_user" \
    XDG_RUNTIME_DIR="/run/user/$gateway_uid" \
    DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$gateway_uid/bus" \
    bash "$0"
fi

umask 077
version=8.0.42
case "$(uname -m)" in
  x86_64) architecture=amd64 ;;
  aarch64) architecture=aarch64 ;;
  *) echo 'Unsupported CLIProxyAPI architecture.' >&2; exit 1 ;;
esac
install_dir="$gateway_home/.local/share/cliproxyapi/$version"
config_dir="$gateway_home/.config/cliproxyapi"
binary="$install_dir/cli-proxy-api"
if [[ ! -x "$binary" ]]; then
  mkdir -p "$gateway_home/.local/share/cliproxyapi"
  staging="$(mktemp -d "$gateway_home/.local/share/cliproxyapi/.download-XXXXXX")"
  trap 'rm -rf "$staging"' EXIT
  archive="CLIProxyAPI_${version}_linux_${architecture}.tar.gz"
  release="https://github.com/router-for-me/CLIProxyAPI/releases/download/v$version"
  curl --fail --location --retry 3 "$release/$archive" -o "$staging/$archive"
  curl --fail --location --retry 3 "$release/checksums.txt" -o "$staging/checksums.txt"
  (cd "$staging"; awk -v archive="$archive" '$2 == archive || $2 == "*" archive' checksums.txt > selected-checksum; test -s selected-checksum; sha256sum -c selected-checksum)
  mkdir -p "$install_dir"
  tar -xzf "$staging/$archive" -C "$install_dir" cli-proxy-api
fi

tailnet_ip="$(tailscale ip -4)"
[[ "$tailnet_ip" =~ ^100\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo 'Join Tailscale before enabling CLIProxyAPI.' >&2; exit 1; }
install -d -m 700 "$config_dir" "$config_dir/auth"
python "$module_root/scripts/initialize-config.py" "$config_dir" "$tailnet_ip"
install -d "$gateway_home/.local/bin" "$gateway_home/.config/systemd/user"
binary_changed=false
if [[ "$(readlink "$gateway_home/.local/bin/cli-proxy-api" || true)" != "$binary" ]]; then
  binary_changed=true
fi
ln -sfn "$binary" "$gateway_home/.local/bin/cli-proxy-api"
for launcher in claude-proxy codex-proxy; do
  install -m 700 "$module_root/scripts/$launcher" "$gateway_home/.local/bin/$launcher"
done
service="$gateway_home/.config/systemd/user/cliproxyapi.service"
service_changed=false
if ! cmp -s "$module_root/cliproxyapi.service" "$service"; then
  install -m 600 "$module_root/cliproxyapi.service" "$service"
  service_changed=true
fi
systemctl --user daemon-reload
systemctl --user enable --now cliproxyapi.service
if [[ "$service_changed" == true || "$binary_changed" == true ]]; then
  systemctl --user restart cliproxyapi.service
fi
echo "CLIProxyAPI enabled on $tailnet_ip:8317; private credentials: $config_dir/credentials.json"
if [[ "$(loginctl show-user "$gateway_user" -p Linger --value)" != yes ]]; then
  echo "Enable boot persistence once: sudo loginctl enable-linger $gateway_user"
fi
