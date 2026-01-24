#!/usr/bin/env bash
# Post-install setup script for Rust toolchain

set -euo pipefail

echo "=== Rust Toolchain Setup ==="
echo

# Determine target user (handle sudo context)
target_user="${SUDO_USER:-$USER}"
if [ -n "${target_user}" ] && [ "${target_user}" != "root" ]; then
  user_home="$(getent passwd "${target_user}" | cut -d: -f6)"
else
  user_home="$HOME"
fi

# Run rustup commands as the target user, not as root
run_as_user() {
  if [ "$(id -u)" -eq 0 ] && [ -n "${SUDO_USER:-}" ]; then
    sudo -u "$SUDO_USER" "$@"
  else
    "$@"
  fi
}

# Check if rustup is available
if ! command -v rustup &>/dev/null; then
  echo "Error: rustup not found. Please install rustup first."
  exit 1
fi

# Check if a default toolchain is already configured
echo "-> Checking Rust toolchain status..."
if run_as_user rustup default 2>/dev/null | grep -q "stable"; then
  echo "✓ Stable toolchain already configured"
else
  echo "-> Installing stable Rust toolchain..."
  run_as_user rustup default stable
  echo "✓ Stable toolchain installed and set as default"
fi

# Show installed toolchain info
echo
echo "-> Installed toolchains:"
run_as_user rustup show

echo
echo "=== Rust Setup Complete! ==="
echo
