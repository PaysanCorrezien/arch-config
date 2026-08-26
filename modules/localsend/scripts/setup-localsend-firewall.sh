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

# LocalSend defaults to asking for each transfer (and may only auto-save from
# favourite devices).  On this workstation it is the shared intake point, so
# receive all LAN transfers without a modal prompt that can be hidden behind
# the fullscreen Windows handoff.  Keep the LocalSend-generated identity in
# place; only update these non-secret preference keys.
PREFERENCES="${XDG_DATA_HOME:-$HOME/.local/share}/org.localsend.localsend_app/shared_preferences.json"
if [[ -f "$PREFERENCES" ]]; then
    TMP_PREFERENCES=$(mktemp "${PREFERENCES}.tmp.XXXXXX")
    # LocalSend 1.17 stores Quick Save as a bool; newer releases migrate the
    # same preference to the string value "on".  Preserve the application's
    # own preference-schema version and write the representation it expects.
    jq '
      if (.["flutter.ls_version"] // 1) >= 3 then
        .["flutter.ls_quick_save"] = "on"
        | del(.["flutter.ls_quick_save_from_favorites"])
      else
        .["flutter.ls_quick_save"] = true
        | .["flutter.ls_quick_save_from_favorites"] = false
      end
    ' "$PREFERENCES" > "$TMP_PREFERENCES"
    chmod --reference="$PREFERENCES" "$TMP_PREFERENCES"
    mv "$TMP_PREFERENCES" "$PREFERENCES"
    echo "Configured LocalSend to accept all incoming transfers automatically."
else
    echo "LocalSend preferences do not exist yet; start LocalSend once, then rerun this hook."
fi

echo "LocalSend firewall rules added successfully!"
echo ""
echo "UFW Status:"
sudo ufw status verbose | grep -E "(53317|Status:)"
