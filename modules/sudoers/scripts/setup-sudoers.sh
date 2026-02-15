#!/usr/bin/env bash
set -euo pipefail

# Get the current user (the one who ran dcli, not root)
user_name="${SUDO_USER:-${USER}}"

if [ "${user_name}" = "root" ]; then
  echo "Error: Cannot determine non-root user"
  exit 1
fi

sudoers_file="/etc/sudoers.d/99-${user_name}-nopasswd"

echo "Configuring passwordless sudo for user: ${user_name}"

# Create sudoers.d entry
sudo tee "${sudoers_file}" >/dev/null <<EOF
# Allow ${user_name} to run all commands without password
# Created by dcli sudoers module
${user_name} ALL=(ALL:ALL) NOPASSWD: ALL
EOF

# Set correct permissions (sudoers files must be 0440)
sudo chmod 0440 "${sudoers_file}"

# Validate the sudoers file
if sudo visudo -c -f "${sudoers_file}" >/dev/null 2>&1; then
  echo "✓ Sudoers configuration created successfully: ${sudoers_file}"
  echo "✓ User '${user_name}' can now run sudo commands without password"
else
  echo "✗ Error: Invalid sudoers syntax, removing file"
  sudo rm -f "${sudoers_file}"
  exit 1
fi
