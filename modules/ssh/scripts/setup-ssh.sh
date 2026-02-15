#!/bin/bash
# Setup secure SSH server with key-based authentication
# Configures SSH, UFW firewall, fail2ban, sysctl hardening, and enables services

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
CONFIG_DIR="$MODULE_DIR/config"

# 1. Install SSH configurations
echo "[1/6] Installing SSH configurations..."
for conf in 10-secure-remote-access.conf 20-extra-hardening.conf; do
    if [ -f "$CONFIG_DIR/$conf" ]; then
        sudo cp "$CONFIG_DIR/$conf" "/etc/ssh/sshd_config.d/$conf"
        sudo chmod 644 "/etc/ssh/sshd_config.d/$conf"
        echo "  + $conf"
    fi
done

# 2. Setup UFW firewall
echo ""
echo "[2/6] Configuring UFW firewall..."
if command -v ufw &> /dev/null; then
    sudo ufw default deny incoming 2>/dev/null || true
    sudo ufw default allow outgoing 2>/dev/null || true
    sudo ufw allow 22/tcp comment 'SSH'
    # Enable UFW if not already active
    if ! sudo ufw status | grep -q "Status: active"; then
        echo "y" | sudo ufw enable
    fi
    echo "  + UFW active with SSH allowed"
else
    echo "  - UFW not installed, skipping"
fi

# 3. Setup fail2ban
echo ""
echo "[3/6] Configuring fail2ban..."
if command -v fail2ban-client &> /dev/null; then
    if [ -f "$CONFIG_DIR/fail2ban-sshd.conf" ]; then
        sudo cp "$CONFIG_DIR/fail2ban-sshd.conf" /etc/fail2ban/jail.local
        sudo systemctl enable --now fail2ban
        echo "  + fail2ban configured and enabled"
    fi
else
    echo "  - fail2ban not installed, skipping"
fi

# 4. Apply sysctl hardening
echo ""
echo "[4/6] Applying kernel/network hardening..."
if [ -f "$CONFIG_DIR/99-sysctl-hardening.conf" ]; then
    sudo cp "$CONFIG_DIR/99-sysctl-hardening.conf" /etc/sysctl.d/99-security.conf
    sudo sysctl --system > /dev/null 2>&1
    echo "  + sysctl hardening applied"
fi

# 5. Enable SSH service
echo ""
echo "[5/6] Enabling SSH service..."
sudo systemctl enable sshd
echo "  + SSH service enabled at boot"

# 6. Start/Restart SSH service
echo ""
echo "[6/6] Starting SSH service..."
if systemctl is-active --quiet sshd; then
    sudo systemctl restart sshd
    echo "  + SSH service restarted"
else
    sudo systemctl start sshd
    echo "  + SSH service started"
fi

# Verification
echo ""
echo "=== Setup Complete ==="
echo ""
echo "SSH Configuration:"
echo "  Key-based auth: ENABLED"
echo "  Password auth:  DISABLED"
echo "  Root login:     DISABLED"
echo "  TcpForwarding:  DISABLED"
echo "  LogLevel:       VERBOSE"

echo ""
echo "Firewall:"
if command -v ufw &> /dev/null; then
    sudo ufw status | head -10
fi

echo ""
echo "fail2ban:"
if command -v fail2ban-client &> /dev/null; then
    sudo fail2ban-client status sshd 2>/dev/null || echo "  Not running"
fi

echo ""
echo "IMPORTANT:"
echo "  1. Password auth is DISABLED — only SSH keys work"
echo "  2. Ensure your public key is in ~/.ssh/authorized_keys"
echo "  3. Test SSH from another terminal before closing this session"
echo ""
echo "Test: ssh $(whoami)@$(hostname)"
