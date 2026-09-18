#!/usr/bin/env bash
# Start KRDP only once this host owns a Tailscale IPv4 address.  krdpserver
# itself does not read a listen-address setting from krdpserverrc.  A
# persistent virtual output keeps KWin and KRDP usable after boot when no
# physical monitor or MST chain is attached.
set -euo pipefail

tailnet_ip="$(/usr/bin/tailscale ip -4 2>/dev/null | head -n1 || true)"
if [[ -z "${tailnet_ip}" ]]; then
    echo "KRDP is waiting for Tailscale authentication and an IPv4 address." >&2
    exit 75
fi

# KRDP 6.7 can mis-map click/button input on a 2560x1440 virtual output.
# Keep the unattended default at the 1080p mode that its Plasma input path
# handles reliably; an explicit systemd environment override can opt in to a
# different mode once that upstream issue is fixed.
virtual_monitor="${KRDP_VIRTUAL_MONITOR:-1920x1080@1}"

exec /usr/bin/krdpserver \
    --plasma \
    --address "${tailnet_ip}" \
    --virtual-monitor "${virtual_monitor}"
