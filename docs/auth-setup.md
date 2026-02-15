# Auth VPS Setup

Setup guide for the `auth` host — a headless Hetzner VPS running the auth/networking stack (Traefik, Authelia, Pi-hole, OpenLDAP, Vaultwarden, Bluesky PDS).

## Prerequisites

- Arch Linux installed on the VPS (or CachyOS)
- Root SSH access
- Your public SSH key

## 1. Create User & SSH Keys

```bash
# As root on the VPS
useradd -m -G wheel -s /bin/bash dylan
passwd dylan

# Allow wheel group sudo (no editor needed)
echo '%wheel ALL=(ALL:ALL) ALL' > /etc/sudoers.d/wheel

# Set up SSH keys
mkdir -p /home/dylan/.ssh
echo 'YOUR_PUBLIC_KEY' > /home/dylan/.ssh/authorized_keys
chmod 700 /home/dylan/.ssh
chmod 600 /home/dylan/.ssh/authorized_keys
chown -R dylan:dylan /home/dylan/.ssh
```

## 2. Harden SSH

```bash
# Disable password auth, root login, allow multiple keys
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
# As dylan
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

cat > config.yaml << 'EOF'
host: auth
EOF
```

## 5. Run dcli sync

```bash
dcli sync
```

This installs all packages from `base.yaml` + `auth.yaml` modules, deploys dotfiles (zsh, tmux, neovim, ssh config), and enables the docker service.

## 6. Post-sync

```bash
# Start docker
sudo systemctl enable --now docker
sudo usermod -aG docker dylan
newgrp docker

# Tailscale
sudo systemctl enable --now tailscaled
sudo tailscale up --ssh

# Change shell to zsh
chsh -s /bin/zsh
```

## 7. Deploy Auth Stack

Clone your docker-compose stack and bring it up:

```bash
# Example — adjust to your actual repo/path
git clone <your-auth-stack-repo> ~/auth-stack
cd ~/auth-stack
docker compose up -d
```

## Quick Reference (Full Setup)

Single block to copy-paste after initial SSH + user setup:

```bash
# Install tooling
sudo pacman -Syu --needed --noconfirm git base-devel fzf
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
```
