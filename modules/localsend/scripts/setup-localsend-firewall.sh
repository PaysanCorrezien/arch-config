#!/bin/bash
# Setup UFW firewall rules for LocalSend
# LocalSend uses port 53317 for both TCP and UDP.  UFW denies inbound traffic
# by default, so explicitly permit the current local LAN only.

set -e

echo "Setting up UFW firewall rules for LocalSend..."

# Check if UFW is installed
if ! command -v ufw &> /dev/null; then
    echo "Warning: UFW is not installed. Skipping firewall configuration."
    exit 0
fi

# Do not open LocalSend on every interface.  In particular, it should not be
# exposed on a public network or Tailscale.  Prefer the ordinary default-route
# interface and ignore a Tailscale exit node if one is present.
UPLINK=$(ip -4 route show default | awk '$5 != "tailscale0" { print $5; exit }')
if [[ -z "$UPLINK" ]]; then
    echo "Warning: no IPv4 LAN uplink found. Skipping LocalSend UFW rules."
    exit 0
fi

LAN_CIDR=$(ip -4 -o addr show dev "$UPLINK" scope global | awk '{ print $4; exit }')
if [[ -z "$LAN_CIDR" ]]; then
    echo "Warning: no IPv4 LAN subnet found on $UPLINK. Skipping LocalSend UFW rules."
    exit 0
fi

for PROTO in tcp udp; do
    echo "Allowing LocalSend $PROTO from $LAN_CIDR on $UPLINK..."
    sudo ufw allow in on "$UPLINK" from "$LAN_CIDR" to any port 53317 proto "$PROTO" comment 'LocalSend LAN'
done

echo "LocalSend firewall rules added successfully!"
echo ""
echo "UFW Status:"
sudo ufw status verbose | grep -E "(53317|Status:)"
