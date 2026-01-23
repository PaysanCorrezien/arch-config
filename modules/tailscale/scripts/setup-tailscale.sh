#!/bin/bash
# Setup Tailscale VPN with Tailscale SSH
# Configures Tailscale daemon and enables secure mesh networking

set -e

echo "=== Tailscale VPN Setup ==="
echo ""

# Check if Tailscale is installed
if ! command -v tailscale &> /dev/null; then
    echo "Error: Tailscale is not installed."
    echo "Install with: sudo pacman -S tailscale"
    exit 1
fi

# 1. Enable Tailscale service
echo "[1/5] Enabling Tailscale service..."
sudo systemctl enable tailscaled
echo "  ✓ Tailscale service enabled at boot"

# 2. Start Tailscale service
echo ""
echo "[2/5] Starting Tailscale service..."
if systemctl is-active --quiet tailscaled; then
    echo "  ✓ Tailscale service already running"
else
    sudo systemctl start tailscaled
    echo "  ✓ Tailscale service started"
fi

# 3. Check authentication status
echo ""
echo "[3/6] Checking Tailscale authentication status..."
if sudo tailscale status &> /dev/null; then
    echo "  ✓ Tailscale is authenticated"
    AUTHENTICATED=true
else
    echo "  ℹ Tailscale is not yet authenticated"
    AUTHENTICATED=false
fi

# 4. Configure UFW for Tailscale-only ports (optional)
echo ""
echo "[4/6] Configuring UFW for Tailscale-only ports..."
if command -v ufw &> /dev/null; then
    if sudo ufw status | grep -q "3000:3010/tcp.*tailscale0"; then
        echo "  ✓ UFW rule already present for tailscale0 (3000-3010/tcp)"
    else
        if sudo ufw allow in on tailscale0 to any port 3000:3010 proto tcp comment 'Tailscale ports 3000-3010'; then
            echo "  ✓ UFW rule added for tailscale0 (3000-3010/tcp)"
        else
            echo "  ⚠ Unable to add UFW rule for tailscale0. Add it manually after 'tailscale up'."
        fi
    fi
else
    echo "  ✗ Warning: UFW is not installed. Skipping firewall configuration."
fi

# 5. Configure Tailscale SSH (optional, user prompt)
echo ""
echo "[5/6] Tailscale SSH Configuration..."
echo ""
echo "Tailscale SSH allows secure SSH access over your Tailscale network without"
echo "exposing ports publicly. It uses Tailscale authentication and ACLs."
echo ""
echo "Would you like to enable Tailscale SSH? (y/N)"
read -r ENABLE_SSH

if [[ "$ENABLE_SSH" =~ ^[Yy]$ ]]; then
    if [ "$AUTHENTICATED" = true ]; then
        echo "  Enabling Tailscale SSH..."
        sudo tailscale up --ssh
        echo "  ✓ Tailscale SSH enabled"
        SSH_ENABLED=true
    else
        echo "  ⚠ Cannot enable SSH before authentication. Will enable after auth."
        SSH_ENABLED=false
        ENABLE_SSH_AFTER_AUTH=true
    fi
else
    echo "  Skipping Tailscale SSH configuration"
    SSH_ENABLED=false
    ENABLE_SSH_AFTER_AUTH=false
fi

# 6. Authentication flow
echo ""
echo "[6/6] Authentication..."
if [ "$AUTHENTICATED" = false ]; then
    echo ""
    echo "You need to authenticate this machine with your Tailscale account."
    echo "This will open a browser window for authentication."
    echo ""
    echo "Options:"
    echo "  1. Standard auth:  tailscale up"
    echo "  2. With SSH:       tailscale up --ssh"
    echo "  3. Skip for now"
    echo ""
    echo "Choose an option (1-3): "
    read -r AUTH_CHOICE

    case $AUTH_CHOICE in
        1)
            echo "  Starting Tailscale authentication..."
            sudo tailscale up
            echo "  ✓ Authentication initiated"
            ;;
        2)
            echo "  Starting Tailscale authentication with SSH..."
            sudo tailscale up --ssh
            echo "  ✓ Authentication initiated with SSH enabled"
            SSH_ENABLED=true
            ;;
        3)
            echo "  Skipping authentication. Run 'sudo tailscale up' manually later."
            ;;
        *)
            echo "  Invalid choice. Skipping authentication."
            ;;
    esac
fi

# Verification
echo ""
echo "=== Setup Complete ==="
echo ""
echo "Tailscale Service Status:"
systemctl status tailscaled --no-pager -l | head -n 5

echo ""
echo "Tailscale Status:"
sudo tailscale status 2>/dev/null || echo "  Not authenticated yet"

echo ""
echo "Configuration Summary:"
echo "  • Tailscale daemon: ENABLED"
echo "  • Auto-start at boot: YES"
if [ "$SSH_ENABLED" = true ]; then
    echo "  • Tailscale SSH: ENABLED"
else
    echo "  • Tailscale SSH: DISABLED"
fi

echo ""
echo "Security Features:"
echo "  ✓ End-to-end encrypted mesh VPN"
echo "  ✓ No ports exposed to public internet"
echo "  ✓ Identity-based access control"
echo "  ✓ WireGuard protocol for performance"

if [ "$SSH_ENABLED" = true ]; then
    echo "  ✓ Tailscale SSH for secure remote access"
    echo ""
    echo "SSH Access:"
    echo "  • Access this machine via: ssh <machine-name>"
    echo "  • No passwords or keys needed (uses Tailscale auth)"
    echo "  • Configure ACLs at: https://login.tailscale.com/admin/acls"
fi

echo ""
echo "Next Steps:"
if [ "$AUTHENTICATED" = false ]; then
    echo "  1. Authenticate with: sudo tailscale up"
    if [ "$ENABLE_SSH_AFTER_AUTH" = true ]; then
        echo "     Or with SSH:       sudo tailscale up --ssh"
    fi
fi
echo "  • Check status:      sudo tailscale status"
echo "  • View IP address:   sudo tailscale ip"
echo "  • Admin console:     https://login.tailscale.com/admin/machines"
echo "  • Configure ACLs:    https://login.tailscale.com/admin/acls"

echo ""
echo "Useful Commands:"
echo "  • sudo tailscale up --ssh          # Enable SSH access"
echo "  • sudo tailscale down               # Disconnect from Tailscale"
echo "  • sudo tailscale status             # Show connection status"
echo "  • sudo tailscale ping <machine>     # Test connectivity"
echo "  • sudo tailscale netcheck           # Check network conditions"

echo ""
echo "Security Recommendations:"
echo "  1. Configure ACLs to restrict access between devices"
echo "  2. Enable MFA on your Tailscale account"
echo "  3. Regularly review connected devices in admin console"
echo "  4. Use Tailscale SSH instead of exposing port 22 publicly"
echo "  5. Consider enabling key expiry for additional security"
echo ""
