#!/usr/bin/env bash
# Post-install setup script for user profile picture

set -euo pipefail

echo "=== User Profile Setup ==="
echo

target_user="${SUDO_USER:-$USER}"
if [ -n "${target_user}" ] && [ "${target_user}" != "root" ]; then
  user_home="$(getent passwd "${target_user}" | cut -d: -f6)"
else
  user_home="$HOME"
fi

# Verify the profile picture exists
echo "→ Checking profile picture..."
if [ -f "${user_home}/.face" ]; then
  echo "✓ Profile picture is configured at ${user_home}/.face"

  # Show file info
  file_type="$(file -b --mime-type "${user_home}/.face")"
  file_size="$(du -h "${user_home}/.face" | cut -f1)"
  echo "  Type: ${file_type}"
  echo "  Size: ${file_size}"
else
  echo "✗ Profile picture not found at ${user_home}/.face"
  echo "  The dotfile sync should have created this symlink/file."
  exit 1
fi

echo
echo "=== Profile Setup Complete! ==="
echo
echo "Your profile picture is now configured for:"
echo "  - Display managers (GDM, SDDM, LightDM, etc.)"
echo "  - Desktop environments"
echo "  - User account settings"
echo
