#!/bin/bash
# Resilient DNS for client hosts. DNS-serving hosts must not enable this module.

set -euo pipefail

DNSMASQ_DROP_IN="/etc/dnsmasq.d/arch-config-tailscale.conf"

magic_dns_suffix() {
    sudo tailscale status --json 2>/dev/null |
        sed -n 's/^[[:space:]]*"MagicDNSSuffix": "\([^"]*\)".*/\1/p; t done; b; :done q'
}

configure_dnsmasq() {
    local suffix="${1:-}"

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
EOF
        if [[ -n "${suffix}" ]]; then
            printf 'server=/%s/100.100.100.100\n' "${suffix}"
        fi
    } | sudo tee "${DNSMASQ_DROP_IN}" >/dev/null

    sudo dnsmasq --test
    sudo systemctl enable --now dnsmasq
    sudo systemctl restart dnsmasq

    if grep -Eq '^[[:space:]]*name_servers=' /etc/resolvconf.conf 2>/dev/null; then
        sudo sed -i 's|^[[:space:]]*name_servers=.*|name_servers="127.0.0.1"|' /etc/resolvconf.conf
    else
        printf '\n# Managed by arch-config/modules/tailscale-client-dns.\nname_servers="127.0.0.1"\n' |
            sudo tee -a /etc/resolvconf.conf >/dev/null
    fi
    sudo resolvconf -u
}

configure_dnsmasq ""
if sudo tailscale status &>/dev/null; then
    sudo tailscale set --accept-dns=false
    configure_dnsmasq "$(magic_dns_suffix)"
fi

echo "✓ Resilient public DNS configured; Tailscale only handles its MagicDNS suffix"
