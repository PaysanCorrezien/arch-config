# SSH Module

Secure SSH server configuration for remote access with key-based authentication only.

## Features

- **Key-based authentication only** - Password authentication disabled
- **Root login disabled** - Enhanced security
- **UFW firewall rules** - Automatic SSH port configuration
- **Service management** - Auto-enable and start SSH service
- **Security hardening** - Max auth tries, login grace time, etc.

## What This Module Does

1. Installs secure SSH configuration to `/etc/ssh/sshd_config.d/10-secure-remote-access.conf`
2. Adds UFW firewall rule for SSH (port 22/tcp)
3. Enables SSH service at boot
4. Starts the SSH service

## Security Configuration

- PasswordAuthentication: **no**
- PubkeyAuthentication: **yes**
- PermitRootLogin: **no**
- MaxAuthTries: **3**
- LoginGraceTime: **30s**
- X11Forwarding: **no**

## Prerequisites

1. OpenSSH server must be installed:
   ```bash
   sudo pacman -S openssh
   ```

2. You must have an SSH key pair and add your public key to `~/.ssh/authorized_keys`:
   ```bash
   # Generate key (if you don't have one)
   ssh-keygen -t ed25519 -C "your_email@example.com"

   # Add public key to authorized_keys
   cat ~/.ssh/id_ed25519.pub >> ~/.ssh/authorized_keys
   chmod 600 ~/.ssh/authorized_keys
   ```

## Installation

Run the setup script:
```bash
./modules/ssh/scripts/setup-ssh.sh
```

## Testing

After setup, test SSH connection:
```bash
# From another terminal on the same machine
ssh localhost

# From a remote machine
ssh username@your-hostname-or-ip
```

⚠️ **IMPORTANT**: Test your SSH connection from another terminal BEFORE closing your current session to ensure you don't lock yourself out!

## Troubleshooting

### Cannot connect with key

1. Check authorized_keys permissions:
   ```bash
   chmod 700 ~/.ssh
   chmod 600 ~/.ssh/authorized_keys
   ```

2. Check SSH service status:
   ```bash
   sudo systemctl status sshd
   ```

3. Check SSH logs:
   ```bash
   sudo journalctl -u sshd -n 50
   ```

### Firewall blocking connection

1. Check UFW status:
   ```bash
   sudo ufw status verbose
   ```

2. Ensure SSH rule exists:
   ```bash
   sudo ufw allow 22/tcp
   ```

## Customization

To modify SSH settings, edit:
- `config/10-secure-remote-access.conf` - SSH daemon configuration
- `scripts/setup-ssh.sh` - Setup script

After changes, reinstall:
```bash
./modules/ssh/scripts/setup-ssh.sh
```
