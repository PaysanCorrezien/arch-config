#!/bin/bash
# Resilient DNS for client hosts. DNS-serving hosts must not enable this module.
#
# Tailscale deliberately does not own the host's global DNS here.  dnsmasq
# handles public DNS and forwards only Tailscale names to Quad100, preserving
# TLS SNI because callers still use the MagicDNS hostname.

set -euo pipefail

DNSMASQ_DROP_IN="/etc/dnsmasq.d/arch-config-tailscale.conf"
NETWORKMANAGER_DROP_IN="/etc/NetworkManager/conf.d/90-dcli-local-dns.conf"

configure_network_manager() {
    if ! command -v nmcli >/dev/null 2>&1; then
        return
    fi

    sudo install -d -m 0755 /etc/NetworkManager/conf.d
    sudo tee "${NETWORKMANAGER_DROP_IN}" >/dev/null <<'EOF'
# Managed by arch-config/modules/tailscale-client-dns.
# openresolv owns /etc/resolv.conf and points it at the local dnsmasq.
[main]
dns=default
rc-manager=unmanaged
EOF

    # Reloading makes NetworkManager stop replacing resolv.conf.  A fallback
    # restart is needed by older NetworkManager releases that do not reload
    # this setting.
    sudo systemctl reload NetworkManager 2>/dev/null || sudo systemctl restart NetworkManager
}

configure_dnsmasq() {

    sudo install -d -m 0755 /etc/dnsmasq.d
    if ! grep -Eq '^[[:space:]]*conf-dir=/etc/dnsmasq\.d([/,]|$)' /etc/dnsmasq.conf 2>/dev/null; then
        printf '\n# Managed by arch-config: load module-owned DNS configuration.\nconf-dir=/etc/dnsmasq.d/,*.conf\n' |
            sudo tee -a /etc/dnsmasq.conf >/dev/null
    fi

    {
        cat <<'EOF'
# Managed by arch-config/modules/tailscale-client-dns.
listen-address=127.0.0.1,::1
bind-interfaces
no-resolv
server=1.1.1.1
server=8.8.8.8
server=/ts.net/100.100.100.100
EOF
    } | sudo tee "${DNSMASQ_DROP_IN}" >/dev/null

    sudo dnsmasq --test
    sudo systemctl enable --now dnsmasq
    sudo systemctl restart dnsmasq
}

configure_resolvconf() {
    # systemd-resolved owns 127.0.0.53 and makes NetworkManager replace
    # resolv.conf with its stub.  That bypasses this module's dnsmasq and is
    # the source of MagicDNS failures on Arch clients.
    sudo systemctl disable --now systemd-resolved.service 2>/dev/null || true
    sudo systemctl disable --now systemd-resolved.socket 2>/dev/null || true
    sudo systemctl mask systemd-resolved.service 2>/dev/null || true

    if grep -Eq '^[[:space:]]*name_servers=' /etc/resolvconf.conf 2>/dev/null; then
        sudo sed -i 's|^[[:space:]]*name_servers=.*|name_servers="127.0.0.1"|' /etc/resolvconf.conf
    else
        printf '\n# Managed by arch-config/modules/tailscale-client-dns.\nname_servers="127.0.0.1"\n' |
            sudo tee -a /etc/resolvconf.conf >/dev/null
    fi
    sudo resolvconf -u
}

configure_network_manager
configure_dnsmasq
sudo tailscale set --accept-dns=false
configure_resolvconf

echo "✓ Local DNS configured; .ts.net is forwarded to Tailscale MagicDNS"
