#!/bin/bash
# Setup Tailscale VPN with Tailscale SSH
# Configures DNS (openresolv), Tailscale daemon, and enables secure mesh networking

set -e

STEPS=7
echo "=== Tailscale VPN Setup ==="
echo ""

# Check if Tailscale is installed
if ! command -v tailscale &> /dev/null; then
    echo "Error: Tailscale is not installed."
    echo "Install with: sudo pacman -S tailscale"
    exit 1
fi

# 1. DNS backend: ensure openresolv is used instead of systemd-resolvconf
echo "[1/$STEPS] Configuring DNS backend (openresolv)..."
if pacman -Qi systemd-resolvconf &> /dev/null; then
    echo "  ⚠ systemd-resolvconf detected — replacing with openresolv"
    echo "  (systemd-resolvconf requires systemd-resolved which conflicts with Tailscale MagicDNS)"
    sudo pacman -Rdd --noconfirm systemd-resolvconf
    sudo pacman -S --noconfirm openresolv
    echo "  ✓ Replaced systemd-resolvconf with openresolv"
elif pacman -Qi openresolv &> /dev/null; then
    echo "  ✓ openresolv already installed"
else
    echo "  Installing openresolv..."
    sudo pacman -S --noconfirm openresolv
    echo "  ✓ openresolv installed"
fi

# 2. Disable systemd-resolved (conflicts with Tailscale MagicDNS and Pi-hole)
echo ""
echo "[2/$STEPS] Disabling systemd-resolved..."
if systemctl is-active --quiet systemd-resolved 2>/dev/null; then
    sudo systemctl disable --now systemd-resolved.service
    sudo systemctl disable --now systemd-resolved.socket 2>/dev/null || true
    sudo systemctl mask systemd-resolved.service
    echo "  ✓ systemd-resolved stopped and masked"
elif systemctl is-enabled --quiet systemd-resolved 2>/dev/null; then
    sudo systemctl disable systemd-resolved.service
    sudo systemctl mask systemd-resolved.service
    echo "  ✓ systemd-resolved disabled and masked"
else
    echo "  ✓ systemd-resolved already disabled/masked"
fi

# 3. Configure NetworkManager to not interfere with DNS
echo ""
echo "[3/$STEPS] Configuring NetworkManager..."
if command -v nmcli &> /dev/null; then
    # Tell NetworkManager to ignore tailscale0 interface
    TAILSCALE_CONF="/etc/NetworkManager/conf.d/tailscale.conf"
    if [ ! -f "$TAILSCALE_CONF" ]; then
        echo '[keyfile]
unmanaged-devices=interface-name:tailscale0' | sudo tee "$TAILSCALE_CONF" > /dev/null
        echo "  ✓ NetworkManager configured to ignore tailscale0"
    else
        echo "  ✓ tailscale0 already unmanaged"
    fi

    # Tell NetworkManager not to manage resolv.conf
    DNS_CONF="/etc/NetworkManager/conf.d/dns.conf"
    if [ ! -f "$DNS_CONF" ] || ! grep -q "rc-manager=unmanaged" "$DNS_CONF" 2>/dev/null; then
        echo '[main]
dns=default
rc-manager=unmanaged' | sudo tee "$DNS_CONF" > /dev/null
        echo "  ✓ NetworkManager configured: rc-manager=unmanaged"
        sudo systemctl restart NetworkManager
        echo "  ✓ NetworkManager restarted"
    else
        echo "  ✓ NetworkManager DNS config already correct"
    fi
else
    echo "  ℹ NetworkManager not installed, skipping"
fi

# 4. Enable and start Tailscale service
echo ""
echo "[4/$STEPS] Enabling Tailscale service..."
sudo systemctl enable tailscaled
if systemctl is-active --quiet tailscaled; then
    echo "  ✓ Tailscale service already running"
else
    sudo systemctl start tailscaled
    echo "  ✓ Tailscale service started"
fi

# 5. Check authentication status
echo ""
echo "[5/$STEPS] Checking Tailscale authentication status..."
if sudo tailscale status &> /dev/null; then
    echo "  ✓ Tailscale is authenticated"
    AUTHENTICATED=true

    # Update resolvconf now that tailscale is up
    sudo resolvconf -u 2>/dev/null || true
else
    echo "  ℹ Tailscale is not yet authenticated"
    AUTHENTICATED=false
fi

# 6. Configure Tailscale SSH (optional, user prompt)
echo ""
echo "[6/$STEPS] Tailscale SSH Configuration..."
echo ""
echo "Tailscale SSH allows secure SSH access over your Tailscale network without"
echo "exposing ports publicly. It uses Tailscale authentication and ACLs."
echo ""
echo "Would you like to enable Tailscale SSH? (y/N)"
read -r ENABLE_SSH

if [[ "$ENABLE_SSH" =~ ^[Yy]$ ]]; then
    if [ "$AUTHENTICATED" = true ]; then
        echo "  Enabling Tailscale SSH..."
        sudo tailscale set --ssh
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

# 7. Authentication flow
echo ""
echo "[7/$STEPS] Authentication..."
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
            sudo tailscale up
            sudo tailscale set --ssh
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

    # After auth, update resolvconf so Tailscale MagicDNS takes effect
    if [ "$AUTH_CHOICE" != "3" ]; then
        sudo resolvconf -u 2>/dev/null || true
    fi
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
echo "DNS Configuration:"
echo "  resolv.conf: $(head -n1 /etc/resolv.conf 2>/dev/null || echo 'not found')"
if grep -q "100.100.100.100" /etc/resolv.conf 2>/dev/null; then
    echo "  ✓ MagicDNS active (100.100.100.100)"
else
    echo "  ⚠ MagicDNS not yet configured (authenticate first)"
fi

echo ""
echo "Configuration Summary:"
echo "  • DNS backend: openresolv"
echo "  • systemd-resolved: MASKED"
echo "  • Tailscale daemon: ENABLED"
echo "  • Auto-start at boot: YES"
if [ "$SSH_ENABLED" = true ]; then
    echo "  • Tailscale SSH: ENABLED"
else
    echo "  • Tailscale SSH: DISABLED"
fi

if [ "$SSH_ENABLED" = true ]; then
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
echo ""
