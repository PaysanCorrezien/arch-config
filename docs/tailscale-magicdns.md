# Tailscale MagicDNS Configuration on Arch Linux

## Problem

On Arch Linux, Tailscale MagicDNS fails to work properly due to conflicts between:
- **NetworkManager** (manages network connections and DNS)
- **systemd-resolved** (systemd's DNS resolver)
- **Tailscale** (needs to inject its MagicDNS server at 100.100.100.100)

### Symptoms

- Health check warning: "systemd-resolved and NetworkManager are wired together incorrectly"
- Health check error: "Tailscale failed to set the DNS configuration"
- Error: "setLinkDNS: Could not activate remote peer 'org.freedesktop.resolve1'"
- MagicDNS hostnames (e.g., `homebot`) fail to resolve
- `/etc/resolv.conf` contains router DNS instead of Tailscale MagicDNS (100.100.100.100)

## Root Cause

1. NetworkManager creates a symlink: `/etc/resolv.conf` → `/run/NetworkManager/resolv.conf`
2. NetworkManager tries to use systemd-resolved (127.0.0.53)
3. Tailscale tries to configure DNS via systemd-resolved's D-Bus interface
4. When systemd-resolved is disabled, Tailscale fails but NetworkManager keeps overwriting resolv.conf

## Solution

### Step 1: Disable systemd-resolved completely

```bash
# Stop and disable systemd-resolved AND its socket activation
sudo systemctl disable --now systemd-resolved.service
sudo systemctl disable --now systemd-resolved.socket
sudo systemctl mask systemd-resolved.service
```

### Step 2: Configure NetworkManager to not manage resolv.conf

```bash
# Tell NetworkManager to ignore Tailscale interface
echo '[keyfile]
unmanaged-devices=interface-name:tailscale0' | sudo tee /etc/NetworkManager/conf.d/tailscale.conf

# Tell NetworkManager not to manage resolv.conf
echo '[main]
dns=default
rc-manager=unmanaged' | sudo tee /etc/NetworkManager/conf.d/dns.conf
```

### Step 3: Remove the NetworkManager symlink

```bash
# Remove the NetworkManager-managed resolv.conf symlink
sudo rm /etc/resolv.conf
```

### Step 4: Restart NetworkManager

```bash
sudo systemctl restart NetworkManager
```

### Step 5: Restart Tailscale daemon and reconnect

```bash
# Restart the daemon so it re-detects DNS configuration
sudo systemctl restart tailscaled

# Reconnect with DNS and routes enabled
sudo tailscale up --accept-dns --accept-routes --ssh
```

### Step 6: Verify

```bash
# Should show: nameserver 100.100.100.100
cat /etc/resolv.conf

# Test MagicDNS resolution
ping homebot

# Check Tailscale status (should have no DNS errors)
sudo tailscale status
```

## How It Works

After this configuration:

1. Tailscale manages `/etc/resolv.conf` directly (no systemd-resolved, no NetworkManager)
2. `/etc/resolv.conf` contains `nameserver 100.100.100.100` (Tailscale MagicDNS)
3. MagicDNS (100.100.100.100) forwards queries to your custom DNS server (e.g., 100.65.207.73 on vmi3085488)
4. Your custom DNS server logs queries and forwards to upstream resolvers
5. MagicDNS hostnames (*.tail66a3d.ts.net) resolve correctly

## Troubleshooting

### MagicDNS still not working after following steps

Check if tailscaled detected the correct DNS manager:
```bash
journalctl -u tailscaled --since "5 min ago" | grep -i "dns manager"
```

If it still tries to use systemd-resolved, restart tailscaled daemon:
```bash
sudo systemctl restart tailscaled
sudo tailscale up --accept-dns --accept-routes --ssh
```

### Custom DNS server (vmi3085488) offline

If your custom DNS server is offline, Tailscale will show DNS timeouts:
```bash
# Check if DNS server is online
tailscale status | grep vmi3085488

# Restart it if needed
ssh vmi3085488 'sudo systemctl restart tailscaled'
```

### NetworkManager keeps recreating the symlink

Make sure `rc-manager=unmanaged` is set in the NetworkManager config:
```bash
cat /etc/NetworkManager/conf.d/dns.conf
# Should show: rc-manager=unmanaged
```

## References

- [Tailscale GitHub Issue #1376 - Magic DNS not working in Arch Linux](https://github.com/tailscale/tailscale/issues/1376)
- [Tailscale Blog: The Sisyphean Task Of DNS Client Config on Linux](https://tailscale.com/blog/sisyphean-dns-client-linux)
- [Tailscale Docs: systemd-resolved and NetworkManager](https://tailscale.com/s/resolved-nm)

## Date

Fixed: 2026-02-15
