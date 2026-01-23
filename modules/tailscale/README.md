# Tailscale Module

Tailscale VPN and secure mesh networking with Tailscale SSH support.

## Features

- **Secure VPN Mesh Network** - WireGuard-based encrypted connectivity
- **Tailscale SSH** - Secure SSH access without exposing ports
- **Zero-Trust Networking** - Identity-based access control
- **No Firewall Configuration Required** - Works behind NAT and firewalls
- **ACL-based Security** - Centralized access control policies
- **Automatic Service Management** - Auto-enable and start Tailscale daemon

## What This Module Does

1. Installs the Tailscale package
2. Enables and starts the `tailscaled` service
3. Optionally configures Tailscale SSH for secure remote access
4. Guides you through authentication with your Tailscale account

## What is Tailscale?

Tailscale creates a secure, private network between your devices using WireGuard. It's like a VPN, but:
- **Easier**: No complex configuration, just authenticate and connect
- **Faster**: Direct peer-to-peer connections when possible
- **More Secure**: End-to-end encrypted, identity-based access
- **Works Anywhere**: Traverses NAT and firewalls automatically

## What is Tailscale SSH?

Tailscale SSH is a feature that allows SSH access over your Tailscale network:
- **No Exposed Ports**: SSH access without opening port 22 publicly
- **No Key Management**: Uses Tailscale authentication instead of SSH keys
- **Centralized Access Control**: Manage SSH access via Tailscale ACLs
- **Audit Logging**: See who accessed what in the Tailscale admin console
- **MFA Support**: Leverage Tailscale's multi-factor authentication

### Tailscale SSH vs Traditional SSH

| Feature | Traditional SSH | Tailscale SSH |
|---------|----------------|---------------|
| Port Exposure | Requires port 22 open | No ports exposed |
| Authentication | SSH keys/passwords | Tailscale identity |
| Firewall Rules | Requires UFW rules | Not needed |
| Access Control | Per-machine config | Centralized ACLs |
| MFA Support | Requires additional setup | Built-in via Tailscale |
| Key Management | Manual key distribution | Automatic |

## Installation

The module will be installed when you run:
```bash
dcli sync
```

After package installation, run the setup script:
```bash
./modules/tailscale/scripts/setup-tailscale.sh
```

## Initial Setup

1. **Run Setup Script**: The script will enable the service and guide you through authentication
   ```bash
   ./modules/tailscale/scripts/setup-tailscale.sh
   ```

2. **Authenticate**: Choose how to authenticate:
   - Standard: `sudo tailscale up`
   - With SSH: `sudo tailscale up --ssh`

3. **Complete Authentication**: Follow the URL to authenticate in your browser

## Enabling Tailscale SSH

### During Setup
The setup script will ask if you want to enable Tailscale SSH. Choose 'y' to enable.

### After Setup
Enable Tailscale SSH anytime with:
```bash
sudo tailscale up --ssh
```

### Accessing via Tailscale SSH

Once enabled, you can SSH to any machine in your Tailscale network:
```bash
# By machine name
ssh machine-name

# By Tailscale IP
ssh 100.x.x.x

# From outside the Tailscale network (if ACLs allow)
ssh user@machine-name.your-tailnet.ts.net
```

## Security Configuration

### Access Control Lists (ACLs)

Tailscale ACLs control who can access what. Configure at:
https://login.tailscale.com/admin/acls

Example ACL for SSH:
```json
{
  "acls": [
    {
      "action": "accept",
      "src": ["user@example.com"],
      "dst": ["tag:servers:22"]
    }
  ],
  "ssh": [
    {
      "action": "accept",
      "src": ["user@example.com"],
      "dst": ["tag:servers"],
      "users": ["root", "dylan"]
    }
  ]
}
```

### Security Best Practices

1. **Enable MFA**: Add multi-factor authentication to your Tailscale account
   - Go to: https://login.tailscale.com/admin/settings/account
   - Enable two-factor authentication

2. **Use ACLs**: Restrict which devices can access which services
   - Default policy: deny all, explicitly allow needed access
   - Use tags to group devices (e.g., tag:server, tag:laptop)

3. **Key Expiry**: Enable automatic key expiry for inactive devices
   - Go to: https://login.tailscale.com/admin/settings/keys
   - Set device key expiry (e.g., 180 days)

4. **Regular Audits**: Review connected devices regularly
   - Check: https://login.tailscale.com/admin/machines
   - Remove devices you no longer use

5. **Use Tailscale SSH**: Prefer Tailscale SSH over traditional SSH
   - No exposed ports = reduced attack surface
   - Centralized access control via ACLs
   - Automatic audit logging

6. **Disable Public SSH**: If using Tailscale SSH exclusively, disable traditional SSH or restrict it to local network only

## Configuration

### Basic Commands

```bash
# Check status
sudo tailscale status

# View your Tailscale IP
sudo tailscale ip

# Enable SSH
sudo tailscale up --ssh

# Disconnect
sudo tailscale down

# Reconnect
sudo tailscale up

# Test connectivity
sudo tailscale ping <machine-name>

# Check network conditions
sudo tailscale netcheck
```

### Advanced Options

```bash
# Accept routes advertised by other nodes
sudo tailscale up --accept-routes

# Advertise routes to other nodes
sudo tailscale up --advertise-routes=192.168.1.0/24

# Use as exit node (route all traffic through Tailscale)
sudo tailscale up --exit-node=<node-name>

# Advertise as exit node
sudo tailscale up --advertise-exit-node

# Enable SSH with specific options
sudo tailscale up --ssh --accept-routes
```

## Firewall Considerations

### UFW Rules Not Required

Tailscale creates its own secure network interface and doesn't require UFW rules:
- Tailscale traffic is encrypted and authenticated
- The Tailscale daemon manages its own networking
- No public ports need to be opened

### Disabling Traditional SSH (Optional)

If using Tailscale SSH exclusively, you can disable traditional SSH:

```bash
# Disable SSH service
sudo systemctl disable sshd
sudo systemctl stop sshd

# Remove UFW rule
sudo ufw delete allow 22/tcp
```

**WARNING**: Only do this if:
1. Tailscale SSH is working and tested
2. You have console access to the machine
3. You won't need SSH access if Tailscale is down

## Troubleshooting

### Cannot Connect to Tailscale

1. Check service status:
   ```bash
   sudo systemctl status tailscaled
   ```

2. Check authentication:
   ```bash
   sudo tailscale status
   ```

3. Re-authenticate if needed:
   ```bash
   sudo tailscale up
   ```

### Tailscale SSH Not Working

1. Verify SSH is enabled:
   ```bash
   sudo tailscale status | grep -i ssh
   ```

2. Enable if not active:
   ```bash
   sudo tailscale up --ssh
   ```

3. Check ACLs allow SSH access:
   - Visit: https://login.tailscale.com/admin/acls
   - Ensure your user has SSH access to target machine

4. Check Tailscale logs:
   ```bash
   sudo journalctl -u tailscaled -n 50
   ```

### Network Issues

1. Check network conditions:
   ```bash
   sudo tailscale netcheck
   ```

2. Test connectivity to specific machine:
   ```bash
   sudo tailscale ping <machine-name>
   ```

3. Verify routing:
   ```bash
   ip route | grep tailscale
   ```

## Integration with Other Modules

### SSH Module Compatibility

This module works alongside the traditional SSH module:
- **SSH module**: Public SSH access (requires firewall rules)
- **Tailscale module**: Private Tailscale SSH (no firewall rules needed)

You can use both simultaneously:
- Tailscale SSH for your own devices
- Traditional SSH for specific authorized users

Or disable traditional SSH and use only Tailscale SSH for maximum security.

## Resources

- **Admin Console**: https://login.tailscale.com/admin
- **Documentation**: https://tailscale.com/kb/
- **ACL Documentation**: https://tailscale.com/kb/1018/acls/
- **SSH Documentation**: https://tailscale.com/kb/1193/tailscale-ssh/
- **Exit Nodes**: https://tailscale.com/kb/1103/exit-nodes/
- **Subnet Routers**: https://tailscale.com/kb/1019/subnets/

## Additional Features

### Exit Nodes
Use another Tailscale device as a VPN exit node:
```bash
sudo tailscale up --exit-node=<node-name>
```

### Subnet Routing
Share access to your local network with other Tailscale devices:
```bash
sudo tailscale up --advertise-routes=192.168.1.0/24
```

### MagicDNS
Tailscale automatically provides DNS for your network:
- Access machines by name: `ssh machine-name`
- No need to remember IP addresses
- Automatically configured

### HTTPS Certificates
Get free HTTPS certificates for your Tailscale machines:
- Enables `https://machine-name.your-tailnet.ts.net`
- Automatic renewal
- No port forwarding required

## Customization

To modify Tailscale settings:
- Edit `scripts/setup-tailscale.sh` for setup behavior
- Configure ACLs in Tailscale admin console
- Adjust `tailscale up` flags for runtime options

## Uninstalling

To remove Tailscale:
```bash
# Disconnect from Tailscale
sudo tailscale down

# Stop and disable service
sudo systemctl stop tailscaled
sudo systemctl disable tailscaled

# Remove package (using dcli or manually)
sudo pacman -Rs tailscale
```
