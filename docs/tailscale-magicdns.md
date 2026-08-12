# Resilient Tailscale and MagicDNS on Arch Linux

## Problem

On Arch Linux, DNS can fail completely when Tailscale owns `/etc/resolv.conf` and the
tailnet's global resolver or exit node becomes unavailable. MagicDNS also has to coexist
with several competing DNS managers:

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
- Public sites stop resolving when the tailnet DNS server is down

## Root Cause

`systemd-resolvconf` (the default Arch package providing `/usr/bin/resolvconf`) is just a symlink to `resolvectl`. It requires `systemd-resolved` to be running. When systemd-resolved is masked/disabled (needed for Pi-hole, or to avoid DNS conflicts), Tailscale calls `resolvconf` which fails silently — DNS config is never updated.

Tailscale's DNS backend priority: systemd-resolved > NetworkManager > **resolvconf** > direct.

## Solution: local DNS with conditional MagicDNS

Use `openresolv` to point the host at a local `dnsmasq` cache. Public queries go to
independent public resolvers. Only the current tailnet's `*.ts.net` suffix is forwarded to
Tailscale's Quad100 resolver. The Tailscale client is configured with
`--accept-dns=false`, so a broken tailnet resolver cannot take over all host DNS.

The `tailscale-client-dns` setup script handles this automatically on opted-in client hosts.
For manual setup:

The client resolver is a separate `tailscale-client-dns` module enabled by the client host
manifests. DNS-serving hosts such as the `auth` DNS/Pi-hole VPS do not enable it and keep
their existing DNS-server configuration, even if a `dnsmasq` binary happens to exist.

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

### Step 4: Configure the local resolver

```bash
sudo pacman -S --needed dnsmasq
# The setup hook writes /etc/dnsmasq.d/arch-config-tailscale.conf dynamically
# and configures openresolv to use nameserver 127.0.0.1.
sudo systemctl enable --now dnsmasq
sudo resolvconf -u
```

### Step 5: Start Tailscale without global DNS ownership

```bash
sudo systemctl enable --now tailscaled
sudo tailscale up --accept-dns=false
```

Re-run the module hook after first authentication so it can discover the tailnet suffix
and add conditional MagicDNS forwarding.

### Step 6: Verify

```bash
# Should show: nameserver 127.0.0.1 (managed by resolvconf)
cat /etc/resolv.conf

# Test public DNS and a fully-qualified MagicDNS name
getent ahostsv4 example.com
getent ahostsv4 homebot.<your-tailnet>.ts.net

# Check Tailscale status (should have no DNS errors)
tailscale status
```

## How It Works

After this configuration:

1. **openresolv** manages `/etc/resolv.conf` and points it to `127.0.0.1`
2. **dnsmasq** resolves public names through independent upstreams
3. Only the tailnet's DNS suffix is forwarded to MagicDNS (`100.100.100.100`)
4. Tailscale remains connected but does not own global host DNS
5. NetworkManager doesn't interfere (`rc-manager=unmanaged`, `tailscale0` unmanaged)

If `tailscaled`, an exit node, or the custom tailnet resolver goes down, public DNS keeps
working. Fully-qualified MagicDNS names recover automatically when Tailscale returns.

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

### Tailnet DNS server offline

Confirm that ordinary DNS still works, then repair the tailnet resolver separately:
```bash
getent ahostsv4 example.com
systemctl status dnsmasq tailscaled
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
Updated: 2026-08-12 — public DNS no longer depends on Tailscale availability
