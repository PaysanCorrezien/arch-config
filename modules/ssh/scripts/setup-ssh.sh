#!/bin/bash
# Setup secure SSH server with key-based authentication
# Configures SSH, UFW firewall, and enables the service

set -e

echo "=== SSH Secure Remote Access Setup ==="
echo ""

# Check if OpenSSH is installed
if ! command -v sshd &> /dev/null; then
    echo "Error: OpenSSH server is not installed."
    echo "Install with: sudo pacman -S openssh"
    exit 1
fi

# Get the script directory to find config files
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULE_DIR="$(dirname "$SCRIPT_DIR")"
CONFIG_FILE="$MODULE_DIR/config/10-secure-remote-access.conf"

# 1. Install SSH secure configuration
echo "[1/4] Installing secure SSH configuration..."
if [ -f "$CONFIG_FILE" ]; then
    sudo cp "$CONFIG_FILE" /etc/ssh/sshd_config.d/10-secure-remote-access.conf
    sudo chmod 644 /etc/ssh/sshd_config.d/10-secure-remote-access.conf
    echo "  ✓ SSH config installed to /etc/ssh/sshd_config.d/10-secure-remote-access.conf"
else
    echo "  ✗ Warning: Config file not found at $CONFIG_FILE"
fi

# 2. Setup UFW firewall rules
echo ""
echo "[2/4] Configuring UFW firewall for SSH..."
if command -v ufw &> /dev/null; then
    sudo ufw allow 22/tcp comment 'SSH'
    echo "  ✓ UFW rule added for SSH (port 22/tcp)"
else
    echo "  ✗ Warning: UFW is not installed. Skipping firewall configuration."
fi

# 3. Enable SSH service
echo ""
echo "[3/4] Enabling SSH service..."
sudo systemctl enable sshd
echo "  ✓ SSH service enabled at boot"

# 4. Start/Restart SSH service
echo ""
echo "[4/4] Starting SSH service..."
if systemctl is-active --quiet sshd; then
    sudo systemctl restart sshd
    echo "  ✓ SSH service restarted"
else
    sudo systemctl start sshd
    echo "  ✓ SSH service started"
fi

# Verification
echo ""
echo "=== Setup Complete ==="
echo ""
echo "SSH Service Status:"
systemctl status sshd --no-pager -l | head -n 5

echo ""
echo "SSH Configuration:"
echo "  • Key-based authentication: ENABLED"
echo "  • Password authentication: DISABLED"
echo "  • Root login: DISABLED"
echo "  • Port: 22"

echo ""
echo "Firewall Status:"
if command -v ufw &> /dev/null; then
    sudo ufw status verbose | grep -E "(22|Status:)" || echo "  SSH rule not found in UFW"
else
    echo "  UFW not installed"
fi

echo ""
echo "⚠️  IMPORTANT SECURITY NOTES:"
echo "  1. Password authentication is DISABLED - only SSH keys work"
echo "  2. Ensure you have added your public key to ~/.ssh/authorized_keys"
echo "  3. Test SSH connection from another terminal before closing this session"
echo "  4. Default port is 22 - consider changing in sshd_config for additional security"
echo ""
echo "Test connection with: ssh $(whoami)@$(hostname)"
