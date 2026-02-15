# Auth VPS Setup

Setup guide for the `auth` host — a headless Hetzner VPS running the auth/networking stack (Traefik, Authelia, Pi-hole, OpenLDAP, Vaultwarden, Bluesky PDS).

## Prerequisites

- Arch Linux installed on the VPS (or CachyOS)
- Root SSH access
- Your public SSH key

## 1. Create User & Sudo

```bash
# As root on the VPS
useradd -m -G wheel -s /bin/bash dylan
passwd dylan

# Wheel group sudo — NOPASSWD for convenience on personal VPS
# NOTE: all sudoers.d files MUST be 0440 or sudo silently ignores them
echo '%wheel ALL=(ALL:ALL) NOPASSWD: ALL' > /etc/sudoers.d/wheel
chmod 0440 /etc/sudoers.d/wheel
```

## 2. SSH Keys & Hardening

```bash
# As root — set up SSH keys
mkdir -p /home/dylan/.ssh
echo 'YOUR_PUBLIC_KEY' > /home/dylan/.ssh/authorized_keys
chmod 700 /home/dylan/.ssh
chmod 600 /home/dylan/.ssh/authorized_keys
chown -R dylan:dylan /home/dylan/.ssh

# Harden SSH — disable password auth, root login
cat > /etc/ssh/sshd_config.d/10-hardened.conf << 'EOF'
PasswordAuthentication no
PermitRootLogin no
PubkeyAuthentication yes
MaxAuthTries 10
EOF
systemctl restart sshd
```

Test SSH from your machine before closing the root session:

```bash
ssh dylan@<VPS_IP>
```

## 3. Install Base Tooling

```bash
# As dylan (over SSH)
sudo pacman -Syu --needed --noconfirm git base-devel fzf nvim

# Install paru
git clone --depth 1 https://aur.archlinux.org/paru.git /tmp/paru
cd /tmp/paru && makepkg -si --noconfirm
cd ~ && rm -rf /tmp/paru

# Install dcli
paru -S --needed --noconfirm dcli-arch-git
```

## 4. Clone & Configure

```bash
git clone https://github.com/PaysanCorrezien/arch-config ~/.config/arch-config
cd ~/.config/arch-config
echo 'host: auth' > config.yaml
```

## 5. Run dcli sync

```bash
dcli sync
```

This installs all packages (base.yaml + auth.yaml modules), deploys dotfiles (zsh, tmux, neovim, ssh config), configures UFW firewall, fail2ban, sysctl hardening, and enables docker + fail2ban services.

## 6. Post-sync

```bash
# Docker
sudo systemctl enable --now docker
sudo usermod -aG docker dylan
newgrp docker

# Tailscale
sudo systemctl enable --now tailscaled
sudo tailscale up --ssh

# Change shell to zsh
chsh -s /bin/zsh

# Open ports for auth stack (if UFW enabled by SSH module)
sudo ufw allow 80/tcp comment 'HTTP'
sudo ufw allow 443/tcp comment 'HTTPS'
sudo ufw allow 53/tcp comment 'DNS-TCP'
sudo ufw allow 53/udp comment 'DNS-UDP'
```

## 7. Deploy Auth Stack

```bash
# Clone and set up the docker compose structure
mkdir -p ~/docker/compose
# Copy your compose file, .env, and compose-manager.sh to ~/docker/compose/
# Copy service data dirs to ~/docker/ (traefik, authelia, pihole, etc.)

cd ~/docker/compose
docker compose -f auth-compose.yml up -d
```

## Security Hardening (applied by SSH module)

The SSH module automatically configures:
- **UFW firewall** — deny incoming by default, allow SSH
- **fail2ban** — bans IPs after 3 failed SSH attempts for 24h
- **sysctl hardening** — disables ICMP redirects, source routing, enables SYN cookies, martian logging
- **SSH hardening** — key-only auth, no root login, no TCP/agent forwarding, verbose logging

## Gotchas

- `sudoers.d` files **must** be `chmod 0440` or sudo silently ignores them
- VPS is stock Arch (not CachyOS) — all `cachyos-*` packages are excluded
- `iptables-nft` conflicts with existing `iptables` — excluded in host config
- `systemd-resolved` stub listener conflicts with Pi-hole on port 53 — disable with:
  ```bash
  sudo mkdir -p /etc/systemd/resolved.conf.d
  echo -e '[Resolve]\nDNSStubListener=no' | sudo tee /etc/systemd/resolved.conf.d/no-stub.conf
  sudo systemctl restart systemd-resolved
  ```
- Pi-hole v6 serves web UI at `/admin/` (root returns 403)
- Watchtower needs `DOCKER_API_VERSION=1.44` in compose env for newer Docker engines

## Quick Reference (Full Setup)

Single block to copy-paste after steps 1-2 (user + SSH) are done as root:

```bash
# Install tooling
sudo pacman -Syu --needed --noconfirm git base-devel fzf nvim
git clone --depth 1 https://aur.archlinux.org/paru.git /tmp/paru && cd /tmp/paru && makepkg -si --noconfirm && cd ~ && rm -rf /tmp/paru
paru -S --needed --noconfirm dcli-arch-git

# Clone and sync
git clone https://github.com/PaysanCorrezien/arch-config ~/.config/arch-config
cd ~/.config/arch-config
echo "host: auth" > config.yaml
dcli sync

# Post-sync services
sudo systemctl enable --now docker
sudo usermod -aG docker $USER
sudo systemctl enable --now tailscaled
sudo tailscale up --ssh
chsh -s /bin/zsh

# Open auth stack ports
sudo ufw allow 80/tcp comment 'HTTP'
sudo ufw allow 443/tcp comment 'HTTPS'
sudo ufw allow 53/tcp comment 'DNS-TCP'
sudo ufw allow 53/udp comment 'DNS-UDP'

# Disable systemd-resolved stub (for Pi-hole)
sudo mkdir -p /etc/systemd/resolved.conf.d
echo -e '[Resolve]\nDNSStubListener=no' | sudo tee /etc/systemd/resolved.conf.d/no-stub.conf
sudo systemctl restart systemd-resolved
```
