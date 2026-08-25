#!/usr/bin/env bash
# Start KRDP only once this host owns a Tailscale IPv4 address.  krdpserver
# itself does not read a listen-address setting from krdpserverrc.
set -euo pipefail

tailnet_ip="$(/usr/bin/tailscale ip -4 2>/dev/null | head -n1 || true)"
if [[ -z "${tailnet_ip}" ]]; then
    echo "KRDP is waiting for Tailscale authentication and an IPv4 address." >&2
    exit 75
fi

exec /usr/bin/krdpserver --plasma --address "${tailnet_ip}"
