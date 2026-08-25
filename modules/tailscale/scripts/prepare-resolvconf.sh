#!/usr/bin/env bash
# Switch from Arch's systemd-backed resolvconf shim before dcli installs
# openresolv for Tailscale. Idempotent and intentionally narrow.
set -euo pipefail

if pacman -Q systemd-resolvconf >/dev/null 2>&1; then
  sudo pacman -Rdd --noconfirm systemd-resolvconf
fi
