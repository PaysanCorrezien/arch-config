# Tailscale MagicDNS Configuration on Arch Linux

## Problem

On Arch Linux, Tailscale MagicDNS fails to work properly due to conflicts between:
- **NetworkManager** (manages network connections and DNS)
- **systemd-resolved** (systemd's DNS resolver)
- **systemd-resolvconf** (wrapper around resolvectl, broken without systemd-resolved)
- **Tailscale** (needs to inject its MagicDNS server at 100.100.100.100)

### Symptoms

- Health check warning: "systemd-resolved and NetworkManager are wired together incorrectly"
- Health check error: "Tailscale failed to set the DNS configuration"
- Error: "Failed to resolve interface 'tailscale': Aucun périphérique de ce type"
- Error: "setLinkDNS: Could not activate remote peer 'org.freedesktop.resolve1'"
- Error: "resolvconf: signature mismatch: /etc/resolv.conf"
- MagicDNS hostnames (e.g., `homebot`) fail to resolve
- `/etc/resolv.conf` contains router DNS instead of Tailscale MagicDNS (100.100.100.100)

## Root Cause

`systemd-resolvconf` (the default Arch package providing `/usr/bin/resolvconf`) is just a symlink to `resolvectl`. It requires `systemd-resolved` to be running. When systemd-resolved is masked/disabled (needed for Pi-hole, or to avoid DNS conflicts), Tailscale calls `resolvconf` which fails silently — DNS config is never updated.

Tailscale's DNS backend priority: systemd-resolved > NetworkManager > **resolvconf** > direct.

## Solution: Use openresolv

Replace `systemd-resolvconf` with `openresolv`, which manages `/etc/resolv.conf` directly and supports an "exclusive" mode that Tailscale leverages.

The Tailscale setup script (`modules/tailscale/scripts/setup-tailscale.sh`) handles this automatically. For manual setup:

### Step 1: Replace systemd-resolvconf with openresolv

```bash
sudo pacman -Rdd --noconfirm systemd-resolvconf
sudo pacman -S --noconfirm openresolv
```

### Step 2: Disable systemd-resolved

```bash
sudo systemctl disable --now systemd-resolved.service
sudo systemctl disable --now systemd-resolved.socket
sudo systemctl mask systemd-resolved.service
```

### Step 3: Configure NetworkManager to not manage resolv.conf

```bash
# Tell NetworkManager to ignore Tailscale interface
echo '[keyfile]
unmanaged-devices=interface-name:tailscale0' | sudo tee /etc/NetworkManager/conf.d/tailscale.conf

# Tell NetworkManager not to manage resolv.conf
echo '[main]
dns=default
rc-manager=unmanaged' | sudo tee /etc/NetworkManager/conf.d/dns.conf

sudo systemctl restart NetworkManager
```

### Step 4: Restart Tailscale and update resolvconf

```bash
sudo systemctl restart tailscaled
sudo tailscale up --accept-dns --accept-routes --ssh
sudo resolvconf -u
```

### Step 5: Verify

```bash
# Should show: nameserver 100.100.100.100 (managed by resolvconf)
cat /etc/resolv.conf

# Test MagicDNS resolution
ping homebot

# Check Tailscale status (should have no DNS errors)
tailscale status
```

## How It Works

After this configuration:

1. **openresolv** manages `/etc/resolv.conf` directly (no systemd-resolved dependency)
2. Tailscale uses openresolv's exclusive mode to set `nameserver 100.100.100.100`
3. MagicDNS (100.100.100.100) resolves Tailscale hostnames and forwards other queries upstream
4. NetworkManager doesn't interfere (`rc-manager=unmanaged`, `tailscale0` unmanaged)

## Troubleshooting

### MagicDNS still not working after following steps

Check which DNS manager tailscaled detected:
```bash
journalctl -u tailscaled --since "5 min ago" | grep -i "dns manager"
```

If it still tries to use systemd-resolved, restart tailscaled:
```bash
sudo systemctl restart tailscaled
sudo resolvconf -u
```

### "signature mismatch" error

This means `/etc/resolv.conf` was written by something other than openresolv. Fix with:
```bash
sudo resolvconf -u
```

### Custom DNS server (vmi3085488) offline

If your custom DNS server is offline, Tailscale will show DNS timeouts:
```bash
tailscale status | grep vmi3085488
ssh vmi3085488 'sudo systemctl restart tailscaled'
```

### NetworkManager keeps recreating the symlink

Make sure `rc-manager=unmanaged` is set:
```bash
cat /etc/NetworkManager/conf.d/dns.conf
# Should show: rc-manager=unmanaged
```

## References

- [Tailscale Docs: Configuring Linux DNS](https://tailscale.com/kb/1188/linux-dns)
- [Tailscale Blog: The Sisyphean Task Of DNS Client Config on Linux](https://tailscale.com/blog/sisyphean-dns-client-linux)
- [Tailscale Docs: Why is resolv.conf being overwritten?](https://tailscale.com/kb/1235/resolv-conf)
- [Tailscale GitHub Issue #1376 - Magic DNS not working in Arch Linux](https://github.com/tailscale/tailscale/issues/1376)

## Date

Fixed: 2026-02-15
Updated: 2026-03-16 — replaced systemd-resolvconf workaround with openresolv
