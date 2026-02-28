#!/usr/bin/env bash
# Nvidia post-install setup
# Configures kernel parameters and mkinitcpio for proper Nvidia DRM/Wayland support.
# Run after installing the nvidia-open-dkms module.

set -euo pipefail

echo "==> Configuring Nvidia for Wayland (DRM modesetting)..."

# ── 1. Kernel parameters ─────────────────────────────────────────────────────
# Add nvidia_drm.modeset=1 and nvidia_drm.fbdev=1 to GRUB cmdline if not present.
GRUB_CFG="/etc/default/grub"

if ! grep -q "nvidia_drm.modeset=1" "$GRUB_CFG"; then
    sudo sed -i 's/\(GRUB_CMDLINE_LINUX_DEFAULT="[^"]*\)"/\1 nvidia_drm.modeset=1 nvidia_drm.fbdev=1"/' "$GRUB_CFG"
    echo "  -> Added nvidia_drm.modeset=1 nvidia_drm.fbdev=1 to GRUB_CMDLINE_LINUX_DEFAULT"
else
    echo "  -> nvidia_drm.modeset already set, skipping"
fi

# ── 2. mkinitcpio modules ─────────────────────────────────────────────────────
# Ensure nvidia modules are listed in MODULES so they load early (needed for DRM).
MKINIT="/etc/mkinitcpio.conf"
NVIDIA_MODULES="nvidia nvidia_modeset nvidia_uvm nvidia_drm"

current_modules=$(grep '^MODULES=' "$MKINIT" | sed 's/MODULES=(\(.*\))/\1/')
needs_update=false
for mod in $NVIDIA_MODULES; do
    if ! echo "$current_modules" | grep -qw "$mod"; then
        current_modules="$current_modules $mod"
        needs_update=true
    fi
done

if $needs_update; then
    # Strip leading/trailing whitespace
    current_modules=$(echo "$current_modules" | xargs)
    sudo sed -i "s/^MODULES=(.*)/MODULES=($current_modules)/" "$MKINIT"
    echo "  -> Updated mkinitcpio MODULES: ($current_modules)"
else
    echo "  -> Nvidia modules already in mkinitcpio, skipping"
fi

# ── 3. Rebuild GRUB and initramfs ─────────────────────────────────────────────
echo "==> Rebuilding GRUB config..."
sudo grub-mkconfig -o /boot/grub/grub.cfg

echo "==> Rebuilding initramfs..."
sudo mkinitcpio -P

echo ""
echo "✓ Nvidia setup complete. Reboot to activate DRM modesetting."
echo ""
echo "After reboot, verify with:"
echo "  cat /sys/module/nvidia_drm/parameters/modeset  # should print Y"
echo "  nvidia-smi                                      # should show GPU info"
